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


def web_url(value):
    if not isinstance(value, str):
        return ""
    parsed = urllib.parse.urlsplit(value)
    return value if parsed.scheme in ("http", "https") and parsed.hostname else ""


def parse_news(document, ticker):
    articles, seen = [], set()
    quote = next((row for row in document.get("quotes") or [] if row.get("symbol") == ticker), {})
    name = re.sub(r"^the\s+", "", str(quote.get("shortname") or quote.get("longname") or ""), flags=re.I)
    stem = name.split()[0].rstrip(",.").casefold() if name.split() else ""
    ticker_pattern = re.compile(r"(?<!\w)" + re.escape(ticker) + r"(?!\w)", re.I)
    for row in document.get("news") or []:
        related = row.get("relatedTickers") or []
        url, title = web_url(row.get("link")), str(row.get("title") or "").strip()
        if not url or not title or ticker not in related or row.get("type") not in (None, "STORY"):
            continue
        identity = row.get("uuid") or url
        if identity in seen:
            continue
        seen.add(identity)
        resolutions = (row.get("thumbnail") or {}).get("resolutions") or []
        images = [image for image in resolutions if web_url(image.get("url"))]
        image = min(images, key=lambda item: abs((number(item.get("width")) or 320) - 320)) if images else {}
        articles.append({"id": identity, "title": title, "url": url, "source": row.get("publisher") or "Publisher",
                         "published": number(row.get("providerPublishTime")), "image": image.get("url", ""),
                         "symbols": related, "primary": bool(ticker_pattern.search(title) or (len(stem) > 3 and stem in title.casefold()))})
    # Company-focused headlines first; broader articles mentioning the ticker follow.
    return {"symbol": ticker, "articles": sorted(articles, key=lambda article: (article["primary"], article["published"] or 0), reverse=True)[:12]}


def nasdaq(path):
    request = urllib.request.Request("https://api.nasdaq.com" + path, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36",
        "Accept": "application/json", "Origin": "https://www.nasdaq.com"})
    with urllib.request.urlopen(request, timeout=10) as response:
        raw = response.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError("The earnings response was too large.")
    document = json.loads(raw)
    if not isinstance(document.get("data"), dict):
        raise ValueError("Earnings dates are unavailable for this symbol.")
    return document["data"]


def date_string(value):
    for pattern in ("%m/%d/%Y", "%b %d, %Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(value).strip(), pattern).date().isoformat()
        except ValueError:
            pass
    return ""


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
        if row.get("s") not in {f"{exchange}:{ticker}" for exchange in ("NASDAQ", "NYSE", "AMEX")}:
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
    payload = {"symbols": {"tickers": [f"{exchange}:{ticker}" for exchange in ("NASDAQ", "NYSE", "AMEX")],
                           "query": {"types": []}},
               "columns": ["total_revenue_fq", "revenue_forecast_fq", "earnings_release_date", "currency", "type"]}
    request = urllib.request.Request("https://scanner.tradingview.com/america/scan",
                                     data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=10) as response:
        raw = response.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        raise ValueError("The revenue response was too large.")
    return parse_revenue(json.loads(raw), ticker)


def attach_revenue(calendar, report):
    if not report:
        return False
    for event in calendar["events"]:
        if event["date"] == report["date"]:
            event.update({key: value for key, value in report.items() if key != "date"})
            return True
    return False


def earnings(ticker):
    if not re.fullmatch(r"[A-Z][A-Z0-9.-]*", ticker):
        return {"symbol": ticker, "next": None, "events": [], "notice": "Earnings coverage is available for supported US stocks.", "earningsSchema": 2}
    encoded = urllib.parse.quote(ticker, safe="")
    values, errors = [{}, {}], []
    paths = [f"/api/analyst/{encoded}/earnings-date", f"/api/company/{encoded}/earnings-surprise"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        revenue_future = pool.submit(revenue, ticker)
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
    return {"symbol": ticker, **calendar, "notice": " ".join(errors), "earningsSchema": 2}


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
    if action == "news":
        return parse_news(fetch("/v1/finance/search", q=ticker, quotesCount=1, newsCount=12), ticker)
    if action == "events":
        return earnings(ticker)
    if action == "financials":
        return statements(ticker, period)
    if action == "valuation":
        return valuation(ticker)
    if action == "averages":
        document = fetch("/v8/finance/chart/" + urllib.parse.quote(ticker, safe=""), range="10y", interval="1d")
        chart = parse_chart(document, ticker, "1Y")
        return {"symbol": ticker, "series": moving_averages(chart["points"], chart["dates"])}
    span, interval = RANGES[period]
    return parse_chart(fetch("/v8/finance/chart/" + urllib.parse.quote(ticker, safe=""), range=span, interval=interval), ticker, period)


def main(arguments):
    action, ticker = arguments[0], symbol(arguments[1])
    if action not in ("news", "events", "averages", "compare", "financials", "valuation"):
        raise ValueError("Unknown research request.")
    period = arguments[2] if action in ("compare", "financials") else ""
    if action == "compare" and period not in RANGES:
        raise ValueError("Unknown chart range.")
    directory = state_directory() / "research"
    directory.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(f"{action}:{ticker}:{period}".encode()).hexdigest()
    path = directory / (key + ".json")
    ttl = {"news": 600, "events": 21600, "averages": 3600, "financials": 86400, "valuation": 3600,
           "compare": 60 if period in ("1D", "1W") else 3600}[action]
    with (directory / (key + ".lock")).open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        saved = read_json(path, {})
        now = time.time()
        current_schema = action != "events" or saved.get("earningsSchema") == 2
        if saved.get("retryAfter", 0) > now or (current_schema and saved.get("fetched", 0) + ttl > now and "--force" not in arguments):
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
