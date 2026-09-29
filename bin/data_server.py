#!/usr/bin/env python3
"""Charts, quotes and search for the window from one long-lived helper, a JSON
line each way.

The window keeps this process running so a request skips Python's start-up and
reuses Yahoo's HTTPS connection: a chart in about 40-150 ms instead of 230.
Charts and search hold no lock and save nothing. A quote, for a stock outside
the watchlist, is the same as `stocks.py quote`: taken and saved under the
watchlist lock. Requests are {"id", "action": "chart", "symbol", "range"},
{"id", "action": "quote", "symbol"}, {"id", "action": "search", "query"} or
{"id", "action": "quotes", "symbols"} (search results' prices, not saved),
answered by {"id", "chart"}, {"id", "quote"}, {"id", "search"} or
{"id", "quotes"}. A failed chart, search or quotes request is an error in its
reply; a failed quote is {"id", "error"}."""

import json
import sys

import stocks
import yahoo_http
from stocks import chart, search, search_quotes, symbol


def answer(line):
    request = {}
    try:
        request = json.loads(line)
        if not isinstance(request, dict):
            raise ValueError("A request is a JSON object.")
        if request.get("action") == "chart":
            result = {"chart": chart(symbol(str(request.get("symbol", ""))), str(request.get("range", "")))}
        elif request.get("action") == "quote":
            result = stocks.main(["quote", str(request.get("symbol", ""))])
        elif request.get("action") == "search":
            result = {"search": search(str(request.get("query", "")))}
        elif request.get("action") == "quotes":
            result = {"quotes": search_quotes([symbol(str(ticker)) for ticker in request.get("symbols") or []])}
        else:
            raise ValueError("Unknown request.")
        return json.dumps({"id": request.get("id"), **result}, allow_nan=False)
    except Exception as error:
        # One bad request never ends the helper.
        request = request if isinstance(request, dict) else {}
        if request.get("action") == "quote":
            failed = {"error": str(error)}
        elif request.get("action") == "search":
            failed = {"search": {"query": str(request.get("query", "")), "results": [], "error": str(error)}}
        elif request.get("action") == "quotes":
            failed = {"quotes": {"rows": [], "error": str(error)}}
        else:
            failed = {"chart": {"symbol": str(request.get("symbol", "")), "range": str(request.get("range", "")),
                                "points": [], "error": str(error), "stale": True}}
        return json.dumps({"id": request.get("id"), **failed})


def serve(lines, output):
    yahoo_http.persistent = yahoo_http.KeepAlive()
    yahoo_http.priority = True
    # Ends when the window closes stdin, or when the shell that started it is gone.
    for line in iter(lines.readline, ""):
        if line.strip():
            output.write(answer(line) + "\n")
            output.flush()


if __name__ == "__main__":
    serve(sys.stdin, sys.stdout)
