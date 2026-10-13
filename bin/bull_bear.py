#!/usr/bin/env python3
"""On-demand bull and bear case research, saved as a shareable HTML report."""
from datetime import datetime
import hashlib
import html
import json
from pathlib import Path
import re
import subprocess
import time
import urllib.parse

import ai_jobs
import market_bulk
import research
from stocks import number, read_json, state_directory, symbol


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


def text(value, limit, what):
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise ValueError(f"The agent returned an invalid {what}. Retry to regenerate.")
    return " ".join(value.split())


def validate(document, job, context):
    sources = document.get("sources")
    if not isinstance(sources, list) or not 1 <= len(sources) <= 20:
        raise ValueError("The report needs supporting sources. Retry to regenerate.")
    clean_sources, numbers = [], {}
    for source in sources:
        if (not isinstance(source, dict) or not isinstance(source.get("id"), str) or not isinstance(source.get("url"), str)
                or not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", source["id"]) or source["id"] in numbers
                or not ai_jobs.valid_url(source["url"])):
            raise ValueError("The agent returned an invalid or duplicate source. Retry to regenerate.")
        numbers[source["id"]] = len(clean_sources) + 1
        clean_sources.append({"title": text(source.get("title"), 500, "source title"), "url": source["url"]})
    cases = {}
    for side in ("bull", "bear"):
        points = document.get(side)
        if not isinstance(points, list) or not 2 <= len(points) <= 6:
            raise ValueError(f"The agent returned an incomplete {side} case. Retry to regenerate.")
        cases[side] = []
        for point in points:
            references = point.get("sources") if isinstance(point, dict) else None
            if not isinstance(references, list) or any(reference not in numbers for reference in references):
                raise ValueError(f"A {side} point cites a source the agent did not list. Retry to regenerate.")
            cases[side].append({"title": text(point.get("title"), 200, side + " point"),
                                "detail": text(point.get("detail"), 1500, side + " point"),
                                "sources": sorted({numbers[reference] for reference in references})})
    watch = document.get("watch")
    if not isinstance(watch, list) or len(watch) > 6:
        raise ValueError("The agent returned an invalid list of things to watch. Retry to regenerate.")
    return {"version": VERSION, "symbol": job["symbol"], "request": job["id"], "name": context["name"],
            "summary": text(document.get("summary"), 1500, "summary"), **cases,
            "watch": [text(item, 400, "item to watch") for item in watch], "sources": clean_sources,
            "snapshot": {key: context[key] for key in ("quote", "valuation", "sector", "industry", "nextEarnings")},
            "generated": time.time(), "asOf": context["captured"], "agent": job["agent"]["name"], "agentId": job["agent"]["id"]}


def money(value, currency):
    value = number(value)
    if value is None:
        return ""
    for size, suffix in ((1e12, "T"), (1e9, "B"), (1e6, "M")):
        if abs(value) >= size:
            return f"{value / size:,.2f}{suffix} {currency}".strip()
    return f"{value:,.2f} {currency}".strip()


def stats(result):
    snapshot = result.get("snapshot") or {}
    quote = snapshot.get("quote") or {}
    currency = quote.get("currency") or ""
    rows = []
    if number(quote.get("price")) is not None:
        percent = number(quote.get("percent"))
        rows.append(("Price", money(quote["price"], currency) + (f" ({percent:+.2f}%)" if percent is not None else "")))
    if number(quote.get("marketCap")) is not None:
        rows.append(("Market cap", money(quote["marketCap"], currency)))
    for metric in snapshot.get("valuation") or []:
        if metric.get("label") in ("P/E (TTM)", "Price / sales"):
            rows.append((metric["label"], f"{metric['value']:,.1f}"))
    if number(quote.get("yearLow")) is not None and number(quote.get("yearHigh")) is not None:
        rows.append(("52-week range", f"{quote['yearLow']:,.2f} – {quote['yearHigh']:,.2f}"))
    if snapshot.get("sector"):
        rows.append(("Sector", snapshot["sector"]))
    try:
        rows.append(("Next earnings", datetime.fromisoformat(snapshot["nextEarnings"]).strftime("%-d %b %Y") + " (est.)"))
    except (KeyError, TypeError, ValueError):
        pass
    return rows


STYLE = """
:root{--bg:#f7f6f3;--card:#fff;--fg:#1c1c1e;--muted:#6a6a70;--line:#e4e2dc;--link:#2f62c9;--bull:#2e7d32;--bear:#c62828}
@media (prefers-color-scheme:dark){:root{--bg:#111113;--card:#19191c;--fg:#ececef;--muted:#9c9ca4;--line:#2b2b30;--link:#86adff;--bull:#4caf50;--bear:#ef5350}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased}
main{max-width:1080px;margin:0 auto;padding:56px 24px 64px}
a{color:var(--link)}
.eyebrow{margin:0;font-size:12px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:var(--muted)}
h1{margin:10px 0 0;font-size:clamp(30px,5vw,44px);line-height:1.1;letter-spacing:-.01em}
h1 span{color:var(--muted);font-weight:500}
.stats{display:flex;flex-wrap:wrap;gap:14px 36px;margin:28px 0 0;padding:18px 0;border-block:1px solid var(--line)}
.stats dt{font-size:12px;color:var(--muted)}
.stats dd{margin:2px 0 0;font-weight:600;font-variant-numeric:tabular-nums}
.summary{margin:32px 0;font-size:19px;line-height:1.55;max-width:820px}
.cases{display:grid;grid-template-columns:1fr 1fr;gap:20px;align-items:start}
.case{background:var(--card);border:1px solid var(--line);border-top:4px solid var(--tone);border-radius:14px;padding:22px 24px 10px}
.bull{--tone:var(--bull)}.bear{--tone:var(--bear)}
.case h2{margin:0 0 6px;font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--tone)}
.case ol{margin:0;padding:0;list-style:none}
.case li{padding:16px 0;border-top:1px solid var(--line)}
.case li:first-child{border-top:0}
.case h3{margin:0 0 6px;font-size:17px;line-height:1.35}
.case p{margin:0}
sup{margin-left:2px;font-size:11px;font-weight:600}
sup a{text-decoration:none}
section.more{margin-top:40px}
section.more h2{margin:0 0 10px;font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted)}
.watch ul{margin:0;padding-left:20px}
.watch li{margin:4px 0}
.sources ol{margin:0;padding-left:26px;font-size:14px;color:var(--muted)}
.sources li{margin:4px 0;overflow-wrap:anywhere}
.sources a{color:var(--fg)}
footer{margin-top:48px;padding-top:18px;border-top:1px solid var(--line);font-size:13px;color:var(--muted)}
@media (max-width:760px){main{padding:32px 16px 48px}.cases{grid-template-columns:1fr}.summary{font-size:17px}}
@media print{:root{--bg:#fff;--card:#fff}main{padding:0}.case{break-inside:avoid}}
"""


def render(result):
    escape = html.escape
    sources = result.get("sources") or []
    generated = datetime.fromtimestamp(result.get("generated") or 0).astimezone()
    def case(side, title):
        def cites(numbers):
            links = ", ".join('<a href="#source-%d">%d</a>' % (number, number) for number in numbers)
            return "<sup>" + links + "</sup>" if links else ""
        points = "".join(f"<li><h3>{escape(point['title'])}</h3><p>{escape(point['detail'])}{cites(point.get('sources') or [])}</p></li>"
                         for point in result.get(side) or [])
        return f'<section class="case {side}"><h2>{title}</h2><ol>{points}</ol></section>'
    watch = "".join(f"<li>{escape(item)}</li>" for item in result.get("watch") or [])
    links = "".join(
        f'<li id="source-{index}"><a href="{escape(source["url"])}" target="_blank" rel="noopener noreferrer">{escape(source["title"])}</a>'
        f' · {escape(re.sub(r"^www[.]", "", urllib.parse.urlsplit(source["url"]).hostname or ""))}</li>'
        for index, source in enumerate(sources, 1))
    details = "".join(f"<div><dt>{escape(label)}</dt><dd>{escape(value)}</dd></div>" for label, value in stats(result))
    title = f"{result['symbol']} bull & bear case"
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<meta name="referrer" content="no-referrer">
<meta name="color-scheme" content="light dark">
<title>{escape(title)} · {generated.strftime('%-d %b %Y')}</title>
<style>{STYLE}</style>
</head>
<body>
<main>
<header>
<p class="eyebrow">Bull &amp; bear case · {generated.strftime('%-d %B %Y')}</p>
<h1>{escape(result.get('name') or result['symbol'])} <span>{escape(result['symbol'])}</span></h1>
{f'<dl class="stats">{details}</dl>' if details else ''}
</header>
<p class="summary">{escape(result.get('summary') or '')}</p>
<div class="cases">
{case('bull', '▲ Bull case')}
{case('bear', '▼ Bear case')}
</div>
{f'<section class="more watch"><h2>What to watch</h2><ul>{watch}</ul></section>' if watch else ''}
<section class="more sources"><h2>Sources</h2><ol>{links}</ol></section>
<footer>Researched by {escape(result.get('agent') or 'an AI agent')} for Omarchy Stocks on {generated.strftime('%-d %B %Y at %H:%M %Z')}.
Prices are from that time. AI-generated from public sources and may contain mistakes; not investment advice.</footer>
</main>
</body>
</html>
"""


def publish(path, result):
    (path / "report.html").write_text(render(result))
    result["html"] = str(path / "report.html")


def downloads():
    try:
        folder = Path(subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, check=True, timeout=5).stdout.strip())
    except (OSError, subprocess.SubprocessError):
        folder = Path()
    # xdg-user-dir answers with the home folder when no download folder is set.
    if not folder.is_absolute() or folder == Path.home():
        folder = Path.home() / "Downloads"
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def export(ticker, preference):
    """Save a copy of the report where it can be shared, never replacing another file."""
    ticker = symbol(ticker)
    result = read_json(ai_jobs.directory(TASK, ticker, preference) / "result.json", {})
    if result.get("symbol") != ticker or result.get("version") != VERSION:
        raise ValueError("There is no report to save yet.")
    page = render(result)
    stem = f"{ticker}-bull-bear-{datetime.fromtimestamp(result['generated']).date().isoformat()}"
    folder = downloads()
    for index in range(1, 100):
        path = folder / (stem + (f"-{index}" if index > 1 else "") + ".html")
        if path.exists() and path.read_text(errors="replace") != page:
            continue
        path.write_text(page)
        shown = "~/" + str(path.relative_to(Path.home())) if path.is_relative_to(Path.home()) else str(path)
        return {"symbol": ticker, "preference": preference, "generated": result["generated"], "file": str(path), "shown": shown}
    raise ValueError("Could not choose a file name in " + str(folder) + ".")


TASK = ai_jobs.Task(folder="bull-bear", version=VERSION, ttl=TTL, timeout=TIMEOUT,
                    name="Bull & bear", action="Bull & bear", title="Stocks · Bull & bear case",
                    context=lambda ticker: context(ticker), prompt=prompt, schema=SCHEMA, validate=validate,
                    publish=publish, stage="Researching the bull and bear case", steps=30)


def main(arguments):
    if arguments[:1] == ["export"] and len(arguments) >= 3:
        try:
            return export(*arguments[1:3])
        except (ValueError, OSError) as error:
            return {"symbol": symbol(arguments[1]), "preference": arguments[2], "error": str(error)}
    return ai_jobs.main(TASK, __file__, arguments)


if __name__ == "__main__":
    ai_jobs.cli(TASK, __file__, main)
