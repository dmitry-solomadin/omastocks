#!/usr/bin/env python3
"""Independent market research requests; never locks the watchlist."""

import concurrent.futures
from datetime import datetime
import fcntl
import hashlib
import json
import re
import signal
import sys
import time
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

from stocks import RANGES, fetch, number, parse_chart, read_json, state_directory, symbol, write_json
from financials import statements, valuation
from extended import extended
from earnings_calls import earnings_calls
from social import stocktwits, reddit_buzz
from tradingview import listings, request as scan


CACHE_TTLS = {
    "news": 600, "social": 300, "buzz": 1800, "events": 21600, "calls": 86400,
    "averages": 3600, "financials": 86400, "valuation": 3600, "extended": 60, "analysts": 86400,
    "sectors": 86400, "sector": 900, "market-index": 900, "market-news": 600,
    "sentiment": 1800, "economic-calendar": 900, "quotes": 300, "calendar-bulk": 21600,
    "calendar": 21600, "overview": 86400, "fundamentals": 3600, "insiders": 3600, "compare": 3600,
    # A past quarter's release does not move.
    "release": 2592000,
}
CACHE_SCHEMAS = {
    "events": ("earningsSchema", 3), "sectors": ("catalogSchema", 4),
    "market-news": ("marketNewsSchema", 3), "quotes": ("quotesSchema", 3),
    "calendar-bulk": ("calendarSchema", 2), "news": ("newsSchema", 6),
    "insiders": ("insiderSchema", 2), "overview": ("overviewSchema", 2),
    "financials": ("financialsSchema", 2),
}


def web_url(value):
    if not isinstance(value, str):
        return ""
    parsed = urllib.parse.urlsplit(value)
    return value if parsed.scheme in ("http", "https") and parsed.hostname else ""


def parse_news(document, ticker):
    articles, seen = [], set()
    quote = next((row for row in document.get("quotes") or [] if row.get("symbol") == ticker), {})
    name = re.sub(r"^the\s+", "", str(quote.get("shortname") or quote.get("longname") or ""), flags=re.I)
    name = re.sub(r",?\s+(?:incorporated|inc|corporation|corp|limited|ltd|plc|class\s+\w)\b.*$", "", name, flags=re.I).strip(" ,.")
    stem = name.split()[0].rstrip(",.").casefold() if name.split() else ""
    generic = {"advanced", "american", "international", "national", "global", "united", "first", "general", "bank"}
    names = [name] if len(name) > 3 else []
    if len(stem) > 3 and stem not in generic:
        names.append(stem)
    ticker_pattern = re.compile(r"(?<!\w)" + re.escape(ticker) + r"(?!\w)" if len(ticker) > 2 else r"(?:\$|\()" + re.escape(ticker) + r"(?!\w)")
    for row in document.get("news") or []:
        related = row.get("relatedTickers") or []
        url, title = web_url(row.get("link")), str(row.get("title") or "").strip()
        primary = bool(ticker_pattern.search(title) or any(re.search(r"(?<!\w)" + re.escape(alias) + r"(?!\w)", title, re.I) for alias in names))
        # Yahoo tags can include unrelated tickers (even on single-company
        # stories). Require a headline mention, not merely a provider tag.
        if not primary:
            continue
        if not url or not title or row.get("type") not in (None, "STORY"):
            continue
        identity = row.get("uuid") or url
        headline = re.sub(r"\W+", " ", title.casefold()).strip()
        if identity in seen or url in seen or headline in seen:
            continue
        seen.add(identity)
        seen.add(url)
        seen.add(headline)
        resolutions = (row.get("thumbnail") or {}).get("resolutions") or []
        images = [image for image in resolutions if web_url(image.get("url"))]
        image = min(images, key=lambda item: abs((number(item.get("width")) or 320) - 320)) if images else {}
        articles.append({"id": identity, "title": title, "url": url, "source": row.get("publisher") or "Publisher",
                         "published": number(row.get("providerPublishTime")), "image": image.get("url", ""),
                           "symbols": related, "primary": primary})
    return {"symbol": ticker, "newsSchema": 6,
            "articles": sorted(articles, key=lambda article: (article["primary"], article["published"] or 0), reverse=True)[:20]}


def nasdaq(path):
    request = urllib.request.Request("https://api.nasdaq.com" + path, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36",
        "Accept": "application/json", "Origin": "https://www.nasdaq.com"})
    with urllib.request.urlopen(request, timeout=10) as response:
        raw = response.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError("The Nasdaq response was too large.")
    document = json.loads(raw)
    if not isinstance(document.get("data"), dict):
        raise ValueError("Nasdaq data is unavailable for this symbol.")
    return document["data"]


def date_string(value):
    for pattern in ("%m/%d/%Y", "%b %d, %Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(value).strip(), pattern).date().isoformat()
        except ValueError:
            pass
    return ""


def parse_analysts(document, ticker):
    if str(document.get("symbol") or "").upper() != ticker:
        raise ValueError("Analyst data did not match the requested symbol.")

    def count(value):
        value = number(value)
        return int(value) if value is not None and value >= 0 and value.is_integer() else None

    def target(value):
        value = number(value)
        return value if value is not None and value > 0 else None

    def recommendations(row):
        counts = {key: count(row.get(key)) for key in ("buy", "hold", "sell")}
        counts["total"] = sum(counts.values()) if all(value is not None for value in counts.values()) else None
        return counts

    overview = document.get("consensusOverview") or {}
    summary = {**recommendations(overview), "low": target(overview.get("lowPriceTarget")),
               "average": target(overview.get("priceTarget")), "high": target(overview.get("highPriceTarget"))}
    history = {}
    for row in document.get("historicalConsensus") or []:
        details = row.get("z") or {}
        day = date_string(details.get("date"))
        if not day:
            continue
        history[day] = {"date": day, "average": target(row.get("y")), **recommendations(details)}
    # These are US-listing, USD targets. Do not infer currency from a Yahoo quote.
    return {"symbol": ticker, "currency": "USD", "source": "Nasdaq / TipRanks",
            "summary": summary, "history": sorted(history.values(), key=lambda row: row["date"], reverse=True)[:24]}


def parse_earnings(upcoming, history, today=None):
    today = today or datetime.now(ZoneInfo("America/New_York")).date().isoformat()
    text = upcoming.get("reportText") or ""
    dates = re.findall(r"\b\d{1,2}/\d{1,2}/\d{4}\b", text)
    if not dates:
        dates = re.findall(r"[A-Z][a-z]{2} \d{1,2}, \d{4}", upcoming.get("announcement") or "")
    next_date = date_string(dates[0]) if dates else ""
    # Nasdaq describes these as algorithm-derived estimates; never imply confirmation.
    next_event = {"type": "earnings", "date": next_date, "estimated": True} if next_date >= today else None
    events = []
    for row in (history.get("earningsSurpriseTable") or {}).get("rows") or []:
        date = date_string(row.get("dateReported"))
        if date:
            events.append({"type": "earnings", "date": date, "estimated": False,
                           "eps": number(row.get("eps")), "forecast": number(row.get("consensusForecast"))})
    return {"next": next_event, "events": sorted(events, key=lambda event: event["date"]), "source": "Nasdaq / Zacks"}


def parse_revenue(document, ticker):
    matches = []
    for row in document.get("data") or []:
        if row.get("s") not in listings(ticker):
            continue
        values = row.get("d") or []
        if len(values) != 5:
            continue
        actual, estimate, released, currency, kind = values
        released = number(released)
        if released is None or kind not in ("stock", "dr") or not isinstance(currency, str) or not re.fullmatch(r"[A-Z]{3}", currency):
            continue
        actual, estimate = number(actual), number(estimate)
        if actual is None and estimate is None:
            continue
        matches.append({"date": datetime.fromtimestamp(released, ZoneInfo("America/New_York")).date().isoformat(),
                        "revenue": actual, "revenueForecast": estimate, "revenueCurrency": currency,
                        "revenueSource": "TradingView"})
    # Do not guess between conflicting listings of the same symbol.
    return matches[0] if len(matches) == 1 else None


def revenue(ticker):
    payload = {"symbols": {"tickers": listings(ticker), "query": {"types": []}},
               "columns": ["total_revenue_fq", "revenue_forecast_fq", "earnings_release_date", "currency", "type"]}
    return parse_revenue(scan(payload), ticker)


def attach_revenue(calendar, report):
    if not report:
        return False
    for event in calendar["events"]:
        if event["date"] == report["date"]:
            event.update({key: value for key, value in report.items() if key != "date"})
            return True
    return False


def merge_history(calendar, older):
    """Add older reported quarters (Yahoo) to Nasdaq's recent ones for long charts.

    Nasdaq entries win; a Yahoo date within three days of one is the same report
    (providers can disagree by a day around after-close releases)."""
    known = [datetime.fromisoformat(event["date"]) for event in calendar["events"]]
    for event in older:
        day = datetime.fromisoformat(event["date"])
        if all(abs((day - other).days) > 3 for other in known):
            calendar["events"].append({"type": "earnings", "date": event["date"], "estimated": False,
                                       "eps": event.get("eps"), "forecast": event.get("forecast")})
            known.append(day)
    calendar["events"].sort(key=lambda event: event["date"])
    return calendar


def earnings(ticker):
    if not re.fullmatch(r"[A-Z][A-Z0-9.-]*", ticker):
        return {"symbol": ticker, "next": None, "events": [], "notice": "Earnings coverage is available for supported US stocks.", "earningsSchema": 3}
    encoded = urllib.parse.quote(ticker, safe="")
    values, errors = [{}, {}], []
    paths = [f"/api/analyst/{encoded}/earnings-date", f"/api/company/{encoded}/earnings-surprise"]
    from calendar_bulk import history
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        revenue_future = pool.submit(revenue, ticker)
        history_future = pool.submit(history, ticker)
        for index, future in enumerate([pool.submit(nasdaq, path) for path in paths]):
            try:
                values[index] = future.result()
            except Exception:
                errors.append("Upcoming earnings unavailable." if index == 0 else "Historical earnings unavailable.")
        if len(errors) == 2:
            raise ValueError("Earnings dates are unavailable for this symbol. Try again later.")
        calendar = parse_earnings(*values)
        try:
            matched = attach_revenue(calendar, revenue_future.result())
        except Exception:
            matched = False
        if not matched:
            errors.append("Revenue figures are unavailable for the reported quarter.")
        # Older quarters only extend long charts; without them the recent ones still stand.
        try:
            merge_history(calendar, history_future.result())
        except Exception:
            errors.append("Older earnings history unavailable.")
    return {"symbol": ticker, **calendar, "notice": " ".join(errors), "earningsSchema": 3}


def moving_averages(points, dates, windows=(20, 50, 200)):
    series = []
    for window in windows:
        total, values, days = 0.0, [], []
        for index, (stamp, price) in enumerate(points):
            total += price
            if index >= window:
                total -= points[index - window][1]
            if index >= window - 1:
                values.append([stamp, total / window])
                days.append(dates[index])
        series.append({"window": window, "points": values, "dates": days})
    return series


def load(action, ticker, period):
    if action == "sectors":
        from market_bulk import presets
        from index_market import presets as indexes
        return {"catalogSchema": 4, "sectors":
                [{"value": group["id"], "label": group["name"], "kind": "index"} for group in indexes() if group["id"] != "russell2000"]
                + [{"value": group["id"], "label": group["name"], "kind": "sector"} for group in presets()]}
    if action == "market-index":
        from index_market import index
        return index(ticker.lower())
    if action in ("sentiment", "economic-calendar"):
        import market_pulse
        return {"sentiment": market_pulse.sentiment, "economic-calendar": market_pulse.economic_calendar}[action]()
    if action == "release":
        from release_link import resolve
        return resolve(ticker, period)
    if action == "market-news":
        from market_news import news
        return news()
    if action == "sector":
        from market_bulk import sector
        return sector(ticker.lower())
    if action == "quotes":
        from market_bulk import quotes
        return quotes(ticker.split(","))
    if action == "calendar-bulk":
        from calendar_bulk import calendar
        from calendar_revenue import enrich
        return enrich(calendar(ticker.split(",")))
    if action == "calendar":
        from earnings_calendar import calendar
        return calendar(ticker, nasdaq, parse_earnings)
    if action == "overview":
        from overview import overview
        return overview(ticker)
    if action == "fundamentals":
        from fundamental_compare import fundamentals
        return fundamentals(ticker, period)
    if action == "insiders":
        from company_activity import activity
        return activity(ticker, nasdaq, date_string)
    if action == "social":
        return stocktwits(ticker)
    if action == "buzz":
        return reddit_buzz()
    if action == "news":
        document = fetch("/v1/finance/search", q=ticker, quotesCount=1, newsCount=12)
        result = parse_news(document, ticker)
        if len(result["articles"]) < 12:
            from company_news import supplement
            quote = next((row for row in document.get("quotes") or [] if row.get("symbol") == ticker), {})
            try:
                extra = supplement(ticker, quote.get("shortname") or quote.get("longname") or "")
                result = parse_news({**document, "news": (document.get("news") or []) + extra}, ticker)
            except (OSError, ValueError) as error:
                if not result["articles"]:
                    raise ValueError("Company news is temporarily unavailable.") from error
        return result
    if action == "events":
        return earnings(ticker)
    if action == "calls":
        return earnings_calls(ticker)
    if action == "financials":
        return statements(ticker, period)
    if action == "valuation":
        return valuation(ticker)
    if action == "extended":
        return extended(ticker)
    if action == "analysts":
        if not re.fullmatch(r"[A-Z][A-Z0-9.-]*", ticker):
            return {"symbol": ticker, "summary": {}, "history": [], "currency": "USD", "source": "Nasdaq / TipRanks"}
        return parse_analysts(nasdaq("/api/analyst/" + urllib.parse.quote(ticker, safe="") + "/targetprice"), ticker)
    if action == "averages":
        document = fetch("/v8/finance/chart/" + urllib.parse.quote(ticker, safe=""), range="10y", interval="1d")
        chart = parse_chart(document, ticker, "1Y")
        return {"symbol": ticker, "series": moving_averages(chart["points"], chart["dates"])}
    span, interval = RANGES[period]
    return parse_chart(fetch("/v8/finance/chart/" + urllib.parse.quote(ticker, safe=""), range=span, interval=interval), ticker, period)


def main(arguments):
    action = arguments[0]
    if action in ("quotes", "calendar-bulk"):
        from market_bulk import symbols
        ticker = ",".join(symbols(arguments[1]))
    else:
        ticker = symbol(arguments[1])
    if action not in CACHE_TTLS:
        raise ValueError("Unknown research request.")
    if action == "buzz":
        ticker = "ALL"
    period = arguments[2] if action in ("compare", "financials", "fundamentals", "release") else ""
    if action == "compare" and period not in RANGES:
        raise ValueError("Unknown chart range.")
    directory = state_directory() / "research"
    directory.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(f"{action}:{ticker}:{period}".encode()).hexdigest()
    path = directory / (key + ".json")
    ttl = 60 if action == "compare" and period in ("1D", "1W") else CACHE_TTLS[action]
    with (directory / (key + ".lock")).open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        saved = read_json(path, {})
        now = time.time()
        schema = CACHE_SCHEMAS.get(action)
        current_schema = schema is None or saved.get(schema[0]) == schema[1]
        if action == "overview" and current_schema:
            current_schema = saved.get("baselineDay") == datetime.now(ZoneInfo(saved.get("timezone", "UTC"))).date().isoformat()
        # Overview refreshes live prices in bulk. Successful historical baselines
        # have a separate daily lifecycle; failed baseline downloads still retry.
        fresh = bool(saved.get("fetched")) and current_schema and not saved.get("stale", False) and saved["fetched"] + ttl > now
        fixed_baselines = action == "overview" and "--keep-baselines" in arguments and fresh
        if fixed_baselines or ("--force" not in arguments and (saved.get("retryAfter", 0) > now or fresh)):
            return saved
        try:
            result = {**load(action, ticker, period), "fetched": now, "stale": False, "error": ""}
        except Exception as error:
            result = {**saved, "symbol": ticker, "stale": True, "error": str(error), "retryAfter": now + 120}
        write_json(path, result)
        return result


if __name__ == "__main__":
    signal.signal(signal.SIGALRM, lambda *_: sys.exit(1))
    signal.alarm(40)
    try:
        print(json.dumps(main(sys.argv[1:]), allow_nan=False))
    except Exception as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
