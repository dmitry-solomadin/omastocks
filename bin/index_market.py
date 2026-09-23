"""One bulk screener request for a saved index membership, never per-stock history."""
import json
from pathlib import Path
import urllib.request
from stocks import number

COLUMNS = ["name", "description", "close", "change", "market_cap_basic", "Perf.YTD", "currency"]
ENDPOINT = "https://scanner.tradingview.com/america/scan"


def presets():
    return json.loads((Path(__file__).resolve().parents[1] / "data/index-presets.json").read_text())["lists"]


def request(payload):
    req = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=10) as response:
        raw = response.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024:
        raise ValueError("TradingView returned an oversized index response.")
    return json.loads(raw)


def parse(document, group):
    data = document.get("data")
    total = document.get("totalCount")
    if not isinstance(data, list) or not data or type(total) is not int or total != len(data):
        raise ValueError("TradingView returned an incomplete index response. Saved data retained.")
    expected = {row["providerSymbol"] for row in group["members"]}
    quotes = {}
    for row in data:
        identifier, values = row.get("s"), row.get("d")
        if identifier not in expected or identifier in quotes or not isinstance(values, list) or len(values) != len(COLUMNS):
            raise ValueError("TradingView returned unexpected index listings.")
        if values[0] != identifier.split(":", 1)[1]:
            raise ValueError("TradingView returned mismatched index symbols.")
        quotes[identifier] = dict(zip(COLUMNS, values))
    rows = []
    for member in group["members"]:
        quote = quotes.get(member["providerSymbol"], {})
        cap = number(quote.get("market_cap_basic"))
        rows.append({"symbol": member["symbol"], "name": member["name"],
                     "price": number(quote.get("close")), "percent": number(quote.get("change")),
                     "ytd": number(quote.get("Perf.YTD")), "marketCap": cap if cap is not None and cap > 0 else None,
                     "currency": quote.get("currency") or ""})
    return {"group": group["id"], "name": group["name"], "rows": rows,
            "provider": "TradingView", "source": group["source"], "membershipDate": group["retrievedAt"],
            "coverage": sum(row["percent"] is not None for row in rows)}


def index(identity, fetch=request):
    group = next((group for group in presets() if group["id"] == identity), None)
    if not group:
        raise ValueError("Unknown market index.")
    tickers = [row["providerSymbol"] for row in group["members"]]
    if not tickers or len(tickers) > 2500 or len(set(tickers)) != len(tickers):
        raise ValueError("Invalid saved index membership.")
    payload = {"symbols": {"tickers": tickers, "query": {"types": []}},
               "columns": COLUMNS, "range": [0, len(tickers)]}
    return parse(fetch(payload), group)
