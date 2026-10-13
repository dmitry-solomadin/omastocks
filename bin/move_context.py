"""A bounded, fresh latest-session snapshot, independent of the displayed chart."""
from datetime import datetime
import hashlib
import time
from zoneinfo import ZoneInfo

import market_bulk
import research
from stocks import chart, fetch, number, quote_units, read_json, state_directory


SECTOR_ETFS = {"technology": "XLK", "communication-services": "XLC", "consumer-cyclical": "XLY",
               "consumer-defensive": "XLP", "financial-services": "XLF", "healthcare": "XLV",
               "industrials": "XLI", "energy": "XLE", "utilities": "XLU", "real-estate": "XLRE",
               "basic-materials": "XLB"}


def percent(value, baseline):
    value, baseline = number(value), number(baseline)
    return (value / baseline - 1) * 100 if value is not None and baseline is not None and baseline > 0 else None


def latest(quote):
    regular = {"kind": "regular", "price": quote.get("price"), "percent": quote.get("percent"),
               "updated": quote.get("updated"), "baseline": quote.get("previous")}
    state = quote.get("marketState")
    key = "pre" if state in ("PRE", "PREPRE") else "post" if state in ("POST", "POSTPOST", "CLOSED") else ""
    if key and number(quote.get(key + "Price")) is not None and (number(quote.get(key + "Updated")) or 0) > (number(quote.get("updated")) or 0):
        return {"kind": "pre-market" if key == "pre" else "after-hours", "price": quote[key + "Price"],
                "percent": quote.get(key + "Percent"), "updated": quote[key + "Updated"], "baseline": quote.get("price")}
    return regular


def daily_context(document, session_date):
    result = ((document.get("chart") or {}).get("result") or [{}])[0]
    timezone = ZoneInfo((result.get("meta") or {}).get("exchangeTimezoneName") or "UTC")
    _, scale = quote_units((result.get("meta") or {}).get("currency", ""))
    values = ((result.get("indicators") or {}).get("quote") or [{}])[0]
    rows = []
    for stamp, close, volume in zip(result.get("timestamp") or [], values.get("close") or [], values.get("volume") or []):
        day = datetime.fromtimestamp(stamp, timezone).date().isoformat()
        close = number(close)
        if day < session_date and close is not None:
            rows.append({"date": day, "close": close * scale, "volume": number(volume)})
    return rows[-22:]


def build(ticker):
    now = time.time()
    missing = []
    quote = market_bulk.quotes([ticker])["rows"][ticker]
    if number(quote.get("price")) is None or not quote.get("updated"):
        raise ValueError("A fresh stock quote is unavailable. Refresh the stock and retry.")
    if quote.get("instrumentType") not in ("EQUITY", "ETF"):
        raise ValueError("Latest-move analysis is available for stocks and ETFs.")
    intraday = chart(ticker, "1D")
    timezone = ZoneInfo(intraday.get("timezone") or "UTC")
    move = latest(quote)
    if now - move["updated"] > 7 * 86400:
        raise ValueError("The latest available trade is over a week old. There is no recent move to explain.")
    session_date = datetime.fromtimestamp(move["updated"], timezone).date().isoformat()
    move["date"] = session_date
    move["asOf"] = datetime.fromtimestamp(move["updated"], timezone).isoformat()
    move["timezone"] = str(timezone)
    move["state"] = quote.get("marketState") or "unknown"
    regular = {key: quote.get(key) for key in ("price", "percent", "previous", "open", "high", "low", "volume", "updated")}
    regular["openingGapPercent"] = percent(quote.get("open"), quote.get("previous"))
    regular["fromHighPercent"] = percent(quote.get("price"), quote.get("high"))
    regular["fromLowPercent"] = percent(quote.get("price"), quote.get("low"))
    regular_day = datetime.fromtimestamp(quote["updated"], timezone).date().isoformat()
    move["regularDate"] = regular_day
    try:
        history = daily_context(fetch("/v8/finance/chart/" + ticker, range="3mo", interval="1d"), regular_day)
    except (ValueError, OSError, KeyError, TypeError):
        history = []
        missing.append("Recent daily history unavailable.")
    for count, key in ((5, "fiveSessionPercent"), (20, "twentySessionPercent")):
        regular[key] = percent(quote["price"], history[-count]["close"]) if len(history) >= count else None
    # A live partial session must not be compared with a whole day's volume.
    if quote.get("marketState") in ("POST", "POSTPOST", "CLOSED") and len(history) >= 5:
        volumes = [row["volume"] for row in history[-20:]]
        if all(value is not None and value > 0 for value in volumes) and number(quote.get("volume")) is not None:
            regular["volumeVsPriorSessions"] = quote["volume"] / (sum(volumes) / len(volumes))
            regular["volumeComparisonSessions"] = len(volumes)
    points = [point for point in intraday.get("points") or []
              if datetime.fromtimestamp(point[0], timezone).date().isoformat() == regular_day]
    if points:
        # A few time anchors, not an entire chart or the user's selected range.
        regular["intradaySamples"] = [points[index] for index in sorted({0, len(points) // 3, 2 * len(points) // 3, len(points) - 1})]
    else:
        missing.append("Intraday shape unavailable.")
    sector = next((group for group in market_bulk.presets() if any(row["symbol"] == ticker for row in group["members"])), {})
    benchmarks = []
    if str(timezone) == "America/New_York":
        symbols = ["SPY", "QQQ"]
        if sector.get("id") in SECTOR_ETFS:
            symbols.append(SECTOR_ETFS[sector["id"]])
        try:
            for symbol, row in market_bulk.quotes(symbols)["rows"].items():
                comparison = latest(row)
                stamp = number(comparison.get("updated"))
                if stamp and comparison["kind"] == move["kind"] and datetime.fromtimestamp(stamp, timezone).date().isoformat() == session_date and abs(stamp - move["updated"]) <= 1800:
                    benchmarks.append({"symbol": symbol, **comparison})
        except (ValueError, OSError):
            missing.append("Benchmark comparison unavailable.")
    if not benchmarks:
        missing.append("No time-aligned market/sector comparison. Do not assert relative performance.")
    news = research.main(["news", ticker])
    if news.get("stale") or news.get("error"):
        missing.append("Company headline feed is stale or unavailable; use fresh web research.")
    # Earnings help query selection; don't fan out into every financial panel.
    key = hashlib.sha256(f"events:{ticker}:".encode()).hexdigest()
    earnings = read_json(state_directory() / "research" / (key + ".json"), {})
    return {"symbol": ticker, "name": quote.get("name") or ticker, "currency": quote.get("currency"),
            "captured": now, "latestMove": move, "regularSession": regular,
            "sector": sector.get("name"), "benchmarks": benchmarks,
            "headlines": [{key: row.get(key) for key in ("title", "url", "source", "published")}
                          for row in (news.get("articles") or [])[:12]],
            "earnings": {"fetched": earnings.get("fetched"), "next": earnings.get("next"),
                         "recent": (earnings.get("events") or [])[-2:]},
            "missing": missing, "quoteSource": "https://finance.yahoo.com/quote/" + ticker + "/",
            "scope": "Latest quoted session, including newer pre-/post-market trading. Independent of the displayed chart. Headlines are leads, not article contents."}
