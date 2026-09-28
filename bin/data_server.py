#!/usr/bin/env python3
"""Charts and search for the window from one long-lived helper, a JSON line each way.

The window keeps this process running so a request skips Python's start-up and
reuses Yahoo's HTTPS connection: a chart in about 40-150 ms instead of 230. It
holds no lock and saves nothing. Requests are {"id", "action": "chart",
"symbol", "range"} or {"id", "action": "search", "query"}, answered by
{"id", "chart"} or {"id", "search"}; a failure is an error in that reply."""

import json
import sys

import yahoo_http
from stocks import chart, search, symbol


def answer(line):
    request = {}
    try:
        request = json.loads(line)
        if not isinstance(request, dict):
            raise ValueError("A request is a JSON object.")
        if request.get("action") == "chart":
            result = {"chart": chart(symbol(str(request.get("symbol", ""))), str(request.get("range", "")))}
        elif request.get("action") == "search":
            result = {"search": search(str(request.get("query", "")))}
        else:
            raise ValueError("Unknown request.")
        return json.dumps({"id": request.get("id"), **result}, allow_nan=False)
    except Exception as error:
        # One bad request never ends the helper.
        request = request if isinstance(request, dict) else {}
        if request.get("action") == "search":
            failed = {"search": {"query": str(request.get("query", "")), "results": [], "error": str(error)}}
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
