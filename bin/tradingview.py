"""Shared, bounded transport for TradingView's bulk screener."""
import json
import urllib.request

ENDPOINT = "https://scanner.tradingview.com/america/scan"


def listings(ticker):
    """Yahoo uses dashes for share classes; TradingView uses dots."""
    return [f"{exchange}:{ticker.replace('-', '.')}" for exchange in ("NASDAQ", "NYSE", "AMEX")]


def request(payload):
    req = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=10) as response:
        raw = response.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024:
        raise ValueError("TradingView returned an oversized response.")
    return json.loads(raw)
