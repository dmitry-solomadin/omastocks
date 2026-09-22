#!/usr/bin/env python3
"""JSON data helper for Omastocks. Python standard library only."""

import concurrent.futures
from datetime import datetime
import fcntl
import json
import math
import os
from pathlib import Path
import re
import signal
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


RANGES = {
    "1D": ("1d", "5m"), "1W": ("5d", "30m"),
    "1M": ("1mo", "1d"), "3M": ("3mo", "1d"),
    "1Y": ("1y", "1d"), "5Y": ("5y", "1wk"),
}
SEED = [("AAPL", "Apple Inc."), ("MSFT", "Microsoft Corporation"),
        ("NVDA", "NVIDIA Corporation"), ("GOOGL", "Alphabet Inc."),
        ("AMZN", "Amazon.com, Inc.")]
BASE = "https://query1.finance.yahoo.com"


def number(value):
    if isinstance(value, bool):
        return None
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (TypeError, ValueError):
        return None


def symbol(value):
    value = value.strip().upper()
    if not re.fullmatch(r"[A-Z0-9^][A-Z0-9.^=\-]{0,29}", value):
        raise ValueError("Enter a valid stock symbol.")
    return value


def read_json(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except (ValueError, OSError) as error:
        raise ValueError(f"Cannot read {path.name}: {error}. File left untouched.") from error


def write_json(path, data):
    descriptor, temporary = tempfile.mkstemp(prefix=".stocks-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump(data, output, allow_nan=False)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def fetch(path, **parameters):
    url = BASE + path + "?" + urllib.parse.urlencode(parameters)
    request = urllib.request.Request(url, headers={"User-Agent": "Omastocks/0.1", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            raw = response.read(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            raise ValueError("Yahoo Finance returned an oversized response.")
        return json.loads(raw)
    except urllib.error.HTTPError as error:
        if error.code == 429:
            raise ValueError("Yahoo Finance is rate limiting requests. Try again in a few minutes.") from error
        if error.code == 404:
            raise ValueError("No market data found for this symbol.") from error
        raise ValueError(f"Yahoo Finance returned HTTP {error.code}.") from error
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise ValueError(f"Could not reach Yahoo Finance: {error}") from error


def parse_chart(document, ticker, period):
    # Yahoo: {chart:{result:[{meta:{...},timestamp:[],indicators:{quote:[{close:[]}]}}]}}.
    results = document.get("chart", {}).get("result") or []
    if not results:
        raise ValueError(f"No chart data for {ticker}.")
    result = results[0]
    meta = result.get("meta") or {}
    raw_currency = meta.get("currency", "")
    currency, scale = {"GBp": ("GBP", .01), "GBX": ("GBP", .01),
                       "ZAc": ("ZAR", .01), "ILA": ("ILS", .01)}.get(raw_currency, (raw_currency, 1))

    def price(value):
        parsed = number(value)
        return parsed * scale if parsed is not None else None

    quotes = (result.get("indicators", {}).get("quote") or [{}])[0]
    points = []
    for stamp, close in zip(result.get("timestamp") or [], quotes.get("close") or []):
        timestamp, value = number(stamp), price(close)
        if timestamp is not None and value is not None:
            points.append([int(timestamp), value])
    points = sorted(dict(points).items())
    try:
        timezone = ZoneInfo(meta.get("exchangeTimezoneName") or "UTC")
    except ZoneInfoNotFoundError:
        timezone = ZoneInfo("UTC")
    dates = [datetime.fromtimestamp(stamp, timezone).date().isoformat() for stamp, _ in points]
    volumes = {}
    for stamp, volume in zip(result.get("timestamp") or [], quotes.get("volume") or []):
        stamp, volume = number(stamp), number(volume)
        if stamp is not None and volume is not None and volume >= 0:
            volumes[int(stamp)] = volume
    events = []
    for category, kind in (("dividends", "dividend"), ("splits", "split")):
        for event in (result.get("events", {}).get(category) or {}).values():
            stamp = number(event.get("date"))
            if stamp is None:
                continue
            events.append({"type": kind, "timestamp": stamp,
                           "date": datetime.fromtimestamp(stamp, timezone).date().isoformat(),
                           "amount": price(event.get("amount")), "ratio": event.get("splitRatio", "")})
    current = price(meta.get("regularMarketPrice"))
    if current is None and points:
        current = points[-1][1]
    if current is None:
        raise ValueError(f"No price available for {ticker}.")
    previous = price(meta.get("chartPreviousClose"))
    if previous is None:
        previous = price(meta.get("previousClose"))
    # Historical chartPreviousClose is the range baseline, not yesterday's close.
    change = current - previous if period == "1D" and previous is not None else None
    opens = [price(value) for value in quotes.get("open") or [] if price(value) is not None]
    regular = (meta.get("currentTradingPeriod") or {}).get("regular") or {}
    session_start, session_end = number(regular.get("start")), number(regular.get("end"))
    if period != "1D" or session_start is None or session_end is None or session_end <= session_start:
        session_start = session_end = None
    return {
        "symbol": ticker, "name": meta.get("longName") or meta.get("shortName") or ticker,
        "currency": currency, "exchange": meta.get("fullExchangeName") or meta.get("exchangeName", ""),
        "price": current, "previous": previous if period == "1D" else None,
        "change": change, "percent": change / previous * 100 if change is not None and previous else None,
        "updated": meta.get("regularMarketTime") or (points[-1][0] if points else 0),
        "open": opens[0] if opens and period == "1D" else None,
        "high": price(meta.get("regularMarketDayHigh")), "low": price(meta.get("regularMarketDayLow")),
        "yearHigh": price(meta.get("fiftyTwoWeekHigh")), "yearLow": price(meta.get("fiftyTwoWeekLow")),
        "volume": number(meta.get("regularMarketVolume")),
        "sessionStart": session_start, "sessionEnd": session_end,
        "points": points, "dates": dates, "volumes": [volumes.get(stamp) for stamp, _ in points],
        "events": events, "timezone": str(timezone), "schema": 2,
        "range": period, "stale": False, "error": "",
    }


class Repository:
    def __init__(self, directory):
        self.directory = directory
        self.state_path = directory / "watchlist.json"
        self.cache_path = directory / "cache.json"
        self.state = read_json(self.state_path, {"entries": [
            {"symbol": ticker, "name": name, "favorite": ticker in ("AAPL", "NVDA")}
            for ticker, name in SEED]})
        if not isinstance(self.state, dict) or not isinstance(self.state.get("entries"), list):
            raise ValueError("Invalid watchlist.json. File left untouched.")
        self.cache = read_json(self.cache_path, {})
        if not isinstance(self.cache, dict):
            raise ValueError("Invalid cache.json. File left untouched.")

    def chart(self, ticker, period, force=False):
        if period not in RANGES:
            raise ValueError("Unknown chart range.")
        key = ticker + ":" + period
        cached = self.cache.get(key, {})
        now = time.time()
        ttl = 60 if period == "1D" else 3600
        if cached.get("schema") == 2 and not force and now - cached.get("fetched", 0) < ttl:
            return cached
        if now < cached.get("retryAfter", 0):
            return cached
        try:
            span, interval = RANGES[period]
            data = fetch("/v8/finance/chart/" + urllib.parse.quote(ticker, safe=""), range=span, interval=interval, events="div,splits")
            row = parse_chart(data, ticker, period)
            row["fetched"] = now
        except (ValueError, TypeError, KeyError, AttributeError, IndexError) as error:
            row = dict(cached) if cached else {"symbol": ticker, "range": period, "points": [], "price": None}
            row.update(stale=True, error=str(error), retryAfter=now + 120)
        self.cache[key] = row
        return row

    def snapshot(self, refresh=False, force=False):
        entries = self.state["entries"]
        if refresh:
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
                list(pool.map(lambda entry: self.chart(entry["symbol"], "1D", force), entries))
        rows = []
        for entry in entries:
            cached = self.cache.get(entry["symbol"] + ":1D", {})
            row = {**entry, **cached, "favorite": entry.get("favorite", False)}
            row["stale"] = cached.get("stale", False) or time.time() - cached.get("fetched", 0) > 600
            rows.append(row)
        return {"entries": rows}

    def mutate(self, action, ticker, name="", favorite=False):
        entries = self.state["entries"]
        existing = next((entry for entry in entries if entry["symbol"] == ticker), None)
        if action == "add" and existing is None:
            if len(entries) >= 60:
                raise ValueError("The watchlist supports up to 60 stocks.")
            entries.append({"symbol": ticker, "name": name or ticker, "favorite": favorite})
        elif action == "remove":
            self.state["entries"] = [entry for entry in entries if entry["symbol"] != ticker]
        elif action == "favorite" and existing:
            existing["favorite"] = not existing.get("favorite", False)
        write_json(self.state_path, self.state)
        return self.snapshot()

    def move(self, ticker, before=""):
        entries = self.state["entries"]
        moving = next((entry for entry in entries if entry["symbol"] == ticker), None)
        if moving is None or (before and not any(entry["symbol"] == before for entry in entries)):
            raise ValueError("The watchlist changed. Try dragging the stock again.")
        if ticker == before:
            return self.snapshot()
        ordered = [entry for entry in entries if entry["symbol"] != ticker]
        index = next((i for i, entry in enumerate(ordered) if entry["symbol"] == before), len(ordered))
        ordered.insert(index, moving)
        self.state["entries"] = ordered
        write_json(self.state_path, self.state)
        return self.snapshot()


def search(query):
    data = fetch("/v1/finance/search", q=query[:100], quotesCount=15, newsCount=0, enableFuzzyQuery="true")
    return {"query": query, "results": [
        {"symbol": row["symbol"], "name": row.get("longname") or row.get("shortname") or row["symbol"],
         "exchange": row.get("exchDisp", ""), "type": row.get("quoteType", "")}
        for row in data.get("quotes", []) if row.get("symbol") and
        row.get("quoteType") in ("EQUITY", "ETF", "INDEX", "MUTUALFUND")
    ]}


def state_directory():
    return Path(os.environ.get("STOCKS_STATE_DIR") or
                Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "omarchy/io.github.dmitry-solomadin.omastocks")


def main(arguments):
    directory = state_directory()
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        repository = Repository(directory)
        action = arguments[0] if arguments else "snapshot"
        if action in ("snapshot", "refresh"):
            result = repository.snapshot(refresh=action == "refresh", force="--force" in arguments)
        elif action == "chart":
            result = {"chart": repository.chart(symbol(arguments[1]), arguments[2], "--force" in arguments)}
        elif action == "quote":
            result = {"quote": repository.chart(symbol(arguments[1]), "1D")}
        elif action == "search":
            result = search(arguments[1])
        elif action == "move":
            result = repository.move(symbol(arguments[1]), symbol(arguments[2]) if len(arguments) > 2 and arguments[2] else "")
        elif action in ("add", "remove", "favorite"):
            result = repository.mutate(action, symbol(arguments[1]), arguments[2] if len(arguments) > 2 else "",
                                       len(arguments) > 3 and arguments[3] == "true")
        else:
            raise ValueError("Use snapshot, refresh, chart SYMBOL RANGE, search QUERY, add, remove, favorite or move SYMBOL [BEFORE].")
        write_json(repository.cache_path, repository.cache)
        return result


if __name__ == "__main__":
    def deadline(_signal, _frame):
        raise TimeoutError("Request timed out. Try refreshing again.")
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(55)
    try:
        print(json.dumps(main(sys.argv[1:]), allow_nan=False))
    except Exception as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
