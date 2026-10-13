#!/usr/bin/env python3
"""On-demand brief on the day's US stock market, saved as a shareable HTML report."""
from datetime import datetime
import json
import re
import time
from zoneinfo import ZoneInfo

import ai_jobs
import market_bulk
import reports
import research
from stocks import number


VERSION = 1
TTL = float("inf")  # A brief stays until Refresh, or until the app sees a newer session
TIMEOUT = 600
NEW_YORK = ZoneInfo("America/New_York")
SUBJECT = "MARKET"
INDEXES = [("^SPX", "S&P 500"), ("^IXIC", "Nasdaq"), ("^DJI", "Dow Jones"), ("^RUT", "Russell 2000")]
FUTURES = [("ES=F", "S&P 500 futures"), ("NQ=F", "Nasdaq 100 futures"), ("YM=F", "Dow futures")]
ASSETS = [("^VIX", "VIX"), ("^TNX", "US 10Y yield"), ("DX-Y.NYB", "US dollar index"), ("CL=F", "Crude oil"),
          ("GC=F", "Gold"), ("BTC-USD", "Bitcoin")]
SECTORS = [("XLK", "Technology"), ("XLF", "Financials"), ("XLY", "Consumer cyclical"), ("XLC", "Communication"),
           ("XLV", "Healthcare"), ("XLI", "Industrials"), ("XLP", "Consumer defensive"), ("XLE", "Energy"),
           ("XLB", "Materials"), ("XLRE", "Real estate"), ("XLU", "Utilities")]
PHASES = {"PRE": "before the open", "PREPRE": "before the open", "REGULAR": "during the session",
          "POST": "after the close", "POSTPOST": "after the close", "CLOSED": "while the market was closed"}
POINT = {"type": "object", "additionalProperties": False, "required": ["title", "detail", "sources"], "properties": {
    "title": {"type": "string", "description": "A short headline."},
    "detail": {"type": "string", "description": "Two or three sentences explaining it, with specifics."},
    "sources": {"type": "array", "items": {"type": "string"}, "description": "IDs of the sources behind it."}}}
MOVER = {"type": "object", "additionalProperties": False, "required": ["symbol", "detail", "sources"], "properties": {
    "symbol": {"type": "string", "description": "The stock's US ticker."},
    "detail": {"type": "string", "description": "One or two sentences: how it moved and why."},
    "sources": {"type": "array", "items": {"type": "string"}, "description": "IDs of the sources behind it."}}}
SCHEMA = {
    "type": "object", "additionalProperties": False,
    "required": ["headline", "summary", "drivers", "movers", "watch", "sources"],
    "properties": {
        "headline": {"type": "string", "description": "One line: the day's main market story."},
        "summary": {"type": "string", "description": "Two or three sentences on how the market did and why."},
        "drivers": {"type": "array", "items": POINT, "description": "3-5 things that moved the market."},
        "movers": {"type": "array", "items": MOVER, "description": "Up to 6 stocks with notable moves."},
        "watch": {"type": "array", "items": {"type": "string"}, "description": "2-4 upcoming events or levels to watch."},
        "sources": {"type": "array", "description": "Sources you read.", "items": {
            "type": "object", "additionalProperties": False, "required": ["id", "title", "url"],
            "properties": {key: {"type": "string"} for key in ("id", "title", "url")}}}
    }
}


def prompt(job, context):
    snapshot = {key: context[key] for key in ("marketState", "indexes", "futures", "assets", "sectors", "fearGreed", "economicCalendar", "headlines")}
    return f"""Write a short brief on today's US stock market for the Stocks app.

Search the web for today's market news. Explain how stocks did and why: the indexes, sectors and notable movers, and what drove them (economic data, the Fed, earnings, news).
If the market hasn't opened yet, cover the pre-market setup; if it has closed, cover the session that just ended.
Use the snapshot's numbers, and cite the sources behind each point by ID. The headlines are leads, not sources.

It's {context['newYork']} in New York. Market snapshot from the Stocks app: {json.dumps(snapshot, ensure_ascii=False)}
Return only JSON matching this schema: {json.dumps(SCHEMA)}
"""


def quotes(rows, assets):
    rounded = lambda value, places: round(value, places) if number(value) is not None else None
    return [{"symbol": symbol, "name": name, "price": rounded(row.get("price"), 2), "change": rounded(row.get("change"), 4),
             "percent": rounded(row.get("percent"), 2)}
            for symbol, name in assets for row in [rows.get(symbol) or {}] if number(row.get("price")) is not None]


def context(_subject):
    rows = market_bulk.quotes(sorted({symbol for symbol, _ in INDEXES + FUTURES + ASSETS + SECTORS}))["rows"]
    spx = rows.get("^SPX") or {}
    if number(spx.get("price")) is None or not spx.get("updated"):
        raise ValueError("Market quotes are unavailable. Refresh the Market view and retry.")
    now = datetime.now(NEW_YORK)
    # Cached by the Market view; each is a lead, and a failure leaves it out.
    sentiment = research.main(["sentiment", "ALL"])
    calendar = research.main(["economic-calendar", "ALL"])
    news = research.main(["market-news", "ALL"])
    events = [{key: event.get(key) for key in ("title", "period", "actual", "forecast", "previous", "unit")}
              | {"time": datetime.fromtimestamp(event["time"], NEW_YORK).strftime("%a %-d %b %H:%M")}
              for event in calendar.get("events") or []
              if isinstance(event.get("time"), (int, float)) and 0 <= (datetime.fromtimestamp(event["time"], NEW_YORK).date() - now.date()).days <= 3]
    return {"symbol": SUBJECT, "captured": time.time(), "newYork": now.strftime("%A %-d %B %Y, %H:%M"),
            "marketState": spx.get("marketState") or "", "sessionDate": datetime.fromtimestamp(spx["updated"], NEW_YORK).date().isoformat(),
            "indexes": quotes(rows, INDEXES), "futures": quotes(rows, FUTURES), "assets": quotes(rows, ASSETS),
            "sectors": sorted(quotes(rows, SECTORS), key=lambda row: -(number(row["percent"]) or 0)),
            "fearGreed": {key: sentiment.get(key) for key in ("score", "rating", "previousClose")} if sentiment.get("score") is not None else None,
            "economicCalendar": events[:12],
            "headlines": [{key: row.get(key) for key in ("title", "source")} for row in (news.get("articles") or [])[:12]]}


def validate(document, job, context):
    sources, numbers = reports.sources(document)
    movers = document.get("movers")
    if not isinstance(movers, list) or len(movers) > 8:
        raise ValueError("The agent returned an invalid list of movers. Retry to regenerate.")
    clean_movers = []
    for mover in movers:
        ticker = mover.get("symbol").strip().upper() if isinstance(mover, dict) and isinstance(mover.get("symbol"), str) else ""
        if not re.fullmatch(r"[A-Z][A-Z0-9.-]{0,9}", ticker):
            raise ValueError("The agent returned an invalid mover symbol. Retry to regenerate.")
        clean_movers.append({"symbol": ticker, "detail": reports.text(mover.get("detail"), 800, "mover"),
                             "sources": reports.references(mover, numbers, "mover")})
    return {"version": VERSION, "symbol": SUBJECT, "request": job["id"],
            "headline": reports.text(document.get("headline"), 200, "headline"),
            "summary": reports.text(document.get("summary"), 1500, "summary"),
            "drivers": reports.points(document.get("drivers"), numbers, "driver", 1, 6), "movers": clean_movers,
            "watch": reports.watch(document), "sources": sources,
            "session": {"state": context["marketState"], "date": context["sessionDate"],
                        "phase": PHASES.get(context["marketState"], "")},
            "snapshot": {key: context[key] for key in ("indexes", "assets", "sectors")},
            "generated": time.time(), "asOf": context["captured"], "agent": job["agent"]["name"], "agentId": job["agent"]["id"]}


def reading(row):
    """A quote as the header shows it; yields move in basis points and carry no direction colour."""
    price, change, percent = number(row.get("price")), number(row.get("change")), number(row.get("percent"))
    if row["symbol"] == "^TNX":
        return f"{price:.2f}%" + (f" ({change * 100:+.1f} bp)" if change is not None else ""), ""
    tone = "" if percent is None or row["symbol"] == "^VIX" else "up" if percent > 0 else "down" if percent < 0 else ""
    return f"{price:,.2f}" + (f" ({percent:+.2f}%)" if percent is not None else ""), tone


STYLE = """
.drivers ol{margin:0;padding:0;list-style:none}
.drivers li{padding:16px 0;border-top:1px solid var(--line)}
.drivers li:first-child{border-top:0;padding-top:4px}
.drivers h3{margin:0 0 6px;font-size:17px;line-height:1.35}
.drivers p,.movers p{margin:0}
.movers ul{margin:0;padding:0;list-style:none;display:grid;grid-template-columns:1fr 1fr;gap:12px 28px}
.movers strong{margin-right:6px}
.sectors ul{margin:0;padding:0;list-style:none;display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:6px 28px;font-size:15px}
.sectors li{display:flex;justify-content:space-between;border-bottom:1px solid var(--line);padding:4px 0}
.sectors .up{color:var(--up)}.sectors .down{color:var(--down)}
@media (max-width:760px){.movers ul{grid-template-columns:1fr}}
"""


def render(result):
    escape = reports.escape
    snapshot = result.get("snapshot") or {}
    header = reports.stats([(row["name"], *reading(row)) for row in (snapshot.get("indexes") or []) + (snapshot.get("assets") or [])])
    drivers = "".join(f"<li><h3>{escape(point['title'])}</h3><p>{escape(point['detail'])}{reports.cites(point['sources'])}</p></li>"
                      for point in result.get("drivers") or [])
    movers = "".join(f"<li><p><strong>{escape(mover['symbol'])}</strong>{escape(mover['detail'])}{reports.cites(mover['sources'])}</p></li>"
                     for mover in result.get("movers") or [])
    sectors = "".join(f'<li><span>{escape(row["name"])}</span><span class="{reading(row)[1]}">{number(row["percent"]):+.2f}%</span></li>'
                      for row in snapshot.get("sectors") or [] if number(row.get("percent")) is not None)
    body = (f'<p class="summary">{escape(result.get("summary") or "")}</p>\n'
            f'<section class="more drivers"><h2>What moved markets</h2><ol>{drivers}</ol></section>\n'
            + (f'<section class="more movers"><h2>Notable movers</h2><ul>{movers}</ul></section>\n' if movers else "")
            + (f'<section class="more sectors"><h2>Sectors</h2><ul>{sectors}</ul></section>' if sectors else ""))
    phase = (result.get("session") or {}).get("phase")
    return reports.page(result, "US market brief", "US market brief" + (" · written " + phase if phase else ""),
                        escape(result.get("headline") or ""), header, body, STYLE)


def file_name(result):
    return f"market-brief-{datetime.fromtimestamp(result['generated']).strftime('%Y-%m-%d-%H%M')}"


TASK = ai_jobs.Task(folder="market-brief", version=VERSION, ttl=TTL, timeout=TIMEOUT,
                    name="Market brief", action="Market brief", title="Stocks · Market brief",
                    context=lambda subject: context(subject), prompt=prompt, schema=SCHEMA, validate=validate,
                    publish=lambda path, result: reports.publish(path, result, render),
                    stage="Researching today's market", steps=30)


def main(arguments):
    return reports.main(TASK, __file__, arguments, render, file_name)


if __name__ == "__main__":
    ai_jobs.cli(TASK, __file__, main)
