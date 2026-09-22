"""One trading day's extended sessions, separate from regular-session quotes."""

import time
import urllib.parse

from stocks import fetch, number, parse_chart


def parse_extended(document, ticker, now=None):
    now = time.time() if now is None else now
    results = (document.get("chart") or {}).get("result") or []
    if not results:
        raise ValueError(f"No extended-hours data for {ticker}.")
    meta = results[0].get("meta") or {}
    empty = {"symbol": ticker, "supported": False, "points": [], "sessions": [], "quote": None}
    if meta.get("hasPrePostMarketData") is not True:
        return empty
    periods = meta.get("currentTradingPeriod") or {}
    sessions = []
    for kind, label in (("pre", "Pre-market"), ("regular", "Regular"), ("post", "After-hours")):
        period = periods.get(kind) or {}
        start, end = number(period.get("start")), number(period.get("end"))
        if start is not None and end is not None and end > start:
            sessions.append({"kind": kind, "label": label, "start": start, "end": end})
    regular = next((session for session in sessions if session["kind"] == "regular"), None)
    if not regular:
        return empty
    # Use provider timestamps (including DST and early closes), never fixed US hours.
    sessions = [session for session in sessions if session["kind"] == "regular"
                or session["kind"] == "pre" and session["end"] == regular["start"]
                or session["kind"] == "post" and session["start"] == regular["end"]]
    if len(sessions) == 1:
        return empty
    chart = parse_chart(document, ticker, "1D")
    indices = [index for index, (stamp, _) in enumerate(chart["points"])
               if stamp <= now and any(session["start"] <= stamp < session["end"] for session in sessions)]
    chart.update({key: [chart[key][index] for index in indices] for key in ("points", "dates", "volumes")})
    chart.update(supported=True, sessions=sessions, quote=None,
                 sessionStart=sessions[0]["start"], sessionEnd=sessions[-1]["end"])
    if not chart["points"]:
        return chart
    stamp, value = chart["points"][-1]
    session = next(session for session in sessions if session["start"] <= stamp < session["end"])
    # A pre-market observation is no longer the current quote once regular trading begins.
    if session["kind"] == "regular" or session["kind"] == "pre" and now >= regular["start"]:
        return chart
    regular_time = number(meta.get("regularMarketTime"))
    baseline = chart["price"] if number(meta.get("regularMarketPrice")) is not None else None
    if regular_time is None or regular_time > stamp + 300 or (
            session["kind"] == "pre" and regular_time >= regular["start"] or
            session["kind"] == "post" and regular_time < regular["start"]):
        baseline = None
    change = value - baseline if baseline is not None else None
    chart["quote"] = {"session": session["kind"], "label": session["label"], "price": value,
                      "updated": stamp, "sessionEnd": session["end"], "reference": baseline,
                      "change": change, "percent": change / baseline * 100 if change is not None and baseline else None}
    return chart


def extended(ticker):
    return parse_extended(fetch("/v8/finance/chart/" + urllib.parse.quote(ticker, safe=""),
                                range="1d", interval="5m", includePrePost="true", events="div,splits"), ticker)
