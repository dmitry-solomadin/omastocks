#!/usr/bin/env python3
"""Charts for the Stock view from one long-lived helper, a JSON line each way.

The window keeps this process running so a chart skips Python's start-up and
reuses Yahoo's HTTPS connection: about 80 ms instead of 230. It holds no lock
and saves nothing. Each request, {"id", "symbol", "range"}, is a fresh
download, answered by {"id", "chart"}; a failure is an error in the chart."""

import json
import sys

import yahoo_http
from stocks import chart, symbol


def answer(line):
    identity, ticker, period = None, "", ""
    try:
        request = json.loads(line)
        identity = request.get("id")
        ticker, period = str(request.get("symbol", "")), str(request.get("range", ""))
        return json.dumps({"id": identity, "chart": chart(symbol(ticker), period)}, allow_nan=False)
    except Exception as error:
        # One bad request never ends the helper.
        failed = {"symbol": ticker, "range": period, "points": [], "error": str(error), "stale": True}
        return json.dumps({"id": identity, "chart": failed})


def serve(lines, output):
    yahoo_http.persistent = yahoo_http.KeepAlive()
    # Ends when the window closes stdin, or when the shell that started it is gone.
    for line in iter(lines.readline, ""):
        if line.strip():
            output.write(answer(line) + "\n")
            output.flush()


if __name__ == "__main__":
    serve(sys.stdin, sys.stdout)
