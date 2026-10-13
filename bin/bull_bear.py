#!/usr/bin/env python3
"""On-demand bull and bear case research, saved as a shareable HTML report."""
from datetime import datetime
import hashlib
import json
import time

import ai_jobs
import market_bulk
import reports
import research
from stocks import number, read_json, state_directory


VERSION = 1
TTL = float("inf")  # A report stays until Refresh replaces it
TIMEOUT = 600
POINT = {"type": "object", "additionalProperties": False, "required": ["title", "detail", "sources"], "properties": {
    "title": {"type": "string", "description": "A short headline for the argument."},
    "detail": {"type": "string", "description": "Two or three sentences explaining it, with specifics."},
    "sources": {"type": "array", "items": {"type": "string"}, "description": "IDs of the sources behind it."}}}
SCHEMA = {
    "type": "object", "additionalProperties": False,
    "required": ["summary", "bull", "bear", "watch", "sources"],
    "properties": {
        "summary": {"type": "string", "description": "Two or three sentences: what the company does and what investors debate about it."},
        "bull": {"type": "array", "items": POINT, "description": "3-5 points for the bull case."},
        "bear": {"type": "array", "items": POINT, "description": "3-5 points for the bear case."},
        "watch": {"type": "array", "items": {"type": "string"}, "description": "2-4 upcoming events or numbers that would settle the debate."},
        "sources": {"type": "array", "description": "Sources you read.", "items": {
            "type": "object", "additionalProperties": False, "required": ["id", "title", "url"],
            "properties": {key: {"type": "string"} for key in ("id", "title", "url")}}}
    }
}


def prompt(job, context):
    snapshot = {key: context[key] for key in ("quote", "valuation", "sector", "industry", "nextEarnings")}
    return f"""Do some basic research on {context['name']} ({job['symbol']}) and write the bull case and the bear case for the stock.

Search the web for current information: the business, recent results and guidance, valuation, competition, risks and news.
Give 3-5 points for each side: a short title, two or three sentences of explanation, and the IDs of the sources behind it.
Be specific and balanced, and don't recommend buying or selling.

Today is {datetime.now().astimezone().date().isoformat()}. Snapshot from the Stocks app: {json.dumps(snapshot, ensure_ascii=False)}
Return only JSON matching this schema: {json.dumps(SCHEMA)}
"""


def context(ticker):
    quote = market_bulk.quotes([ticker])["rows"][ticker]
    if number(quote.get("price")) is None:
        raise ValueError("A fresh stock quote is unavailable. Refresh the stock and retry.")
    if quote.get("instrumentType") != "EQUITY":
        raise ValueError("Bull and bear cases are available for company stocks.")
    valuation = research.main(["valuation", ticker])
    # Earnings dates only help the agent pick what to watch; don't fetch them here.
    key = hashlib.sha256(f"events:{ticker}:".encode()).hexdigest()
    earnings = read_json(state_directory() / "research" / (key + ".json"), {})
    return {"symbol": ticker, "name": quote.get("name") or ticker, "captured": time.time(),
            "quote": {key: quote.get(key) for key in ("price", "percent", "currency", "exchange", "marketCap", "yearLow", "yearHigh", "updated")},
            "valuation": [{key: metric.get(key) for key in ("label", "value")} for metric in valuation.get("metrics") or []
                          if metric.get("kind") == "ratio" and number(metric.get("value")) is not None],
            "sector": valuation.get("sector") or "", "industry": valuation.get("industry") or "",
            "nextEarnings": (earnings.get("next") or {}).get("date") or ""}


def validate(document, job, context):
    sources, numbers = reports.sources(document)
    return {"version": VERSION, "symbol": job["symbol"], "request": job["id"], "name": context["name"],
            "summary": reports.text(document.get("summary"), 1500, "summary"),
            "bull": reports.points(document.get("bull"), numbers, "bull point", 2, 6),
            "bear": reports.points(document.get("bear"), numbers, "bear point", 2, 6),
            "watch": reports.watch(document), "sources": sources,
            "snapshot": {key: context[key] for key in ("quote", "valuation", "sector", "industry", "nextEarnings")},
            "generated": time.time(), "asOf": context["captured"], "agent": job["agent"]["name"], "agentId": job["agent"]["id"]}


def stats(result):
    snapshot = result.get("snapshot") or {}
    quote = snapshot.get("quote") or {}
    currency = quote.get("currency") or ""
    rows = []
    if number(quote.get("price")) is not None:
        percent = number(quote.get("percent"))
        rows.append(("Price", reports.money(quote["price"], currency) + (f" ({percent:+.2f}%)" if percent is not None else ""), ""))
    if number(quote.get("marketCap")) is not None:
        rows.append(("Market cap", reports.money(quote["marketCap"], currency), ""))
    for metric in snapshot.get("valuation") or []:
        if metric.get("label") in ("P/E (TTM)", "Price / sales"):
            rows.append((metric["label"], f"{metric['value']:,.1f}", ""))
    if number(quote.get("yearLow")) is not None and number(quote.get("yearHigh")) is not None:
        rows.append(("52-week range", f"{quote['yearLow']:,.2f} – {quote['yearHigh']:,.2f}", ""))
    if snapshot.get("sector"):
        rows.append(("Sector", snapshot["sector"], ""))
    try:
        rows.append(("Next earnings", datetime.fromisoformat(snapshot["nextEarnings"]).strftime("%-d %b %Y") + " (est.)", ""))
    except (KeyError, TypeError, ValueError):
        pass
    return rows


STYLE = """
.cases{display:grid;grid-template-columns:1fr 1fr;gap:20px;align-items:start}
.case{background:var(--card);border:1px solid var(--line);border-top:4px solid var(--tone);border-radius:14px;padding:22px 24px 10px}
.bull{--tone:var(--up)}.bear{--tone:var(--down)}
.case h2{margin:0 0 6px;font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--tone)}
.case ol{margin:0;padding:0;list-style:none}
.case li{padding:16px 0;border-top:1px solid var(--line)}
.case li:first-child{border-top:0}
.case h3{margin:0 0 6px;font-size:17px;line-height:1.35}
.case p{margin:0}
@media (max-width:760px){.cases{grid-template-columns:1fr}}
@media print{.case{break-inside:avoid}}
"""


def render(result):
    escape = reports.escape
    def case(side, title):
        points = "".join(f"<li><h3>{escape(point['title'])}</h3><p>{escape(point['detail'])}{reports.cites(point.get('sources') or [])}</p></li>"
                         for point in result.get(side) or [])
        return f'<section class="case {side}"><h2>{title}</h2><ol>{points}</ol></section>'
    body = (f'<p class="summary">{escape(result.get("summary") or "")}</p>\n'
            f'<div class="cases">\n{case("bull", "▲ Bull case")}\n{case("bear", "▼ Bear case")}\n</div>')
    return reports.page(result, f"{result['symbol']} bull & bear case", "Bull & bear case",
                        f"{escape(result.get('name') or result['symbol'])} <span>{escape(result['symbol'])}</span>",
                        reports.stats(stats(result)), body, STYLE)


def file_name(result):
    return f"{result['symbol']}-bull-bear-{datetime.fromtimestamp(result['generated']).date().isoformat()}"


TASK = ai_jobs.Task(folder="bull-bear", version=VERSION, ttl=TTL, timeout=TIMEOUT,
                    name="Bull & bear", action="Bull & bear", title="Stocks · Bull & bear case",
                    context=lambda ticker: context(ticker), prompt=prompt, schema=SCHEMA, validate=validate,
                    publish=lambda path, result: reports.publish(path, result, render),
                    stage="Researching the bull and bear case", steps=30)


def main(arguments):
    return reports.main(TASK, __file__, arguments, render, file_name)


if __name__ == "__main__":
    ai_jobs.cli(TASK, __file__, main)
