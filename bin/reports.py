"""What the agent's HTML reports share: checked sources and points, the page itself, and copies saved for sharing."""
from datetime import datetime
import html
from pathlib import Path
import re
import subprocess
import urllib.parse

import ai_jobs
from stocks import number, read_json, symbol


escape = html.escape


def text(value, limit, what):
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise ValueError(f"The agent returned an invalid {what}. Retry to regenerate.")
    return " ".join(value.split())


def sources(document, limit=20):
    """The agent's sources in listed order, and the number each ID becomes."""
    rows = document.get("sources")
    if not isinstance(rows, list) or not 1 <= len(rows) <= limit:
        raise ValueError("The report needs supporting sources. Retry to regenerate.")
    clean, numbers = [], {}
    for source in rows:
        if (not isinstance(source, dict) or not isinstance(source.get("id"), str) or not isinstance(source.get("url"), str)
                or not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", source["id"]) or source["id"] in numbers
                or not ai_jobs.valid_url(source["url"])):
            raise ValueError("The agent returned an invalid or duplicate source. Retry to regenerate.")
        numbers[source["id"]] = len(clean) + 1
        clean.append({"title": text(source.get("title"), 500, "source title"), "url": source["url"]})
    return clean, numbers


def references(row, numbers, what):
    cited = row.get("sources") if isinstance(row, dict) else None
    if not isinstance(cited, list) or any(reference not in numbers for reference in cited):
        raise ValueError(f"A {what} cites a source the agent did not list. Retry to regenerate.")
    return sorted({numbers[reference] for reference in cited})


def points(rows, numbers, what, low, high):
    """Headed, sourced points: a case's arguments or the day's drivers."""
    if not isinstance(rows, list) or not low <= len(rows) <= high:
        raise ValueError(f"The agent returned too few or too many {what}s. Retry to regenerate.")
    return [{"title": text(row.get("title") if isinstance(row, dict) else None, 200, what),
             "detail": text(row.get("detail") if isinstance(row, dict) else None, 1500, what),
             "sources": references(row, numbers, what)} for row in rows]


def watch(document):
    items = document.get("watch")
    if not isinstance(items, list) or len(items) > 6:
        raise ValueError("The agent returned an invalid list of things to watch. Retry to regenerate.")
    return [text(item, 400, "item to watch") for item in items]


def money(value, currency):
    value = number(value)
    if value is None:
        return ""
    for size, suffix in ((1e12, "T"), (1e9, "B"), (1e6, "M")):
        if abs(value) >= size:
            return f"{value / size:,.2f}{suffix} {currency}".strip()
    return f"{value:,.2f} {currency}".strip()


def host(url):
    return re.sub(r"^www[.]", "", urllib.parse.urlsplit(url).hostname or "")


def cites(numbers):
    links = ", ".join('<a href="#source-%d">%d</a>' % (number, number) for number in numbers)
    return "<sup>" + links + "</sup>" if links else ""


def stats(rows):
    details = "".join(f"<div><dt>{escape(label)}</dt><dd{' class=' + tone if tone else ''}>{escape(value)}</dd></div>"
                      for label, value, tone in rows)
    return f'<dl class="stats">{details}</dl>' if details else ""


STYLE = """
:root{--bg:#f7f6f3;--card:#fff;--fg:#1c1c1e;--muted:#6a6a70;--line:#e4e2dc;--link:#2f62c9;--up:#2e7d32;--down:#c62828}
@media (prefers-color-scheme:dark){:root{--bg:#111113;--card:#19191c;--fg:#ececef;--muted:#9c9ca4;--line:#2b2b30;--link:#86adff;--up:#4caf50;--down:#ef5350}}
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
.stats dd.up{color:var(--up)}.stats dd.down{color:var(--down)}
.summary{margin:32px 0;font-size:19px;line-height:1.55;max-width:820px}
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
@media (max-width:760px){main{padding:32px 16px 48px}.summary{font-size:17px}}
@media print{:root{--bg:#fff;--card:#fff}main{padding:0}}
"""


def page(result, title, eyebrow, heading, header, body, style=""):
    """A whole report: one file, inline CSS, no scripts and nothing fetched. `heading`, `header` and `body` are HTML."""
    generated = datetime.fromtimestamp(result.get("generated") or 0).astimezone()
    items = "".join(f"<li>{escape(item)}</li>" for item in result.get("watch") or [])
    links = "".join(
        f'<li id="source-{index}"><a href="{escape(source["url"])}" target="_blank" rel="noopener noreferrer">{escape(source["title"])}</a>'
        f" · {escape(host(source['url']))}</li>" for index, source in enumerate(result.get("sources") or [], 1))
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<meta name="referrer" content="no-referrer">
<meta name="color-scheme" content="light dark">
<title>{escape(title)} · {generated.strftime('%-d %b %Y')}</title>
<style>{STYLE}{style}</style>
</head>
<body>
<main>
<header>
<p class="eyebrow">{escape(eyebrow)} · {generated.strftime('%-d %B %Y')}</p>
<h1>{heading}</h1>
{header}
</header>
{body}
{f'<section class="more watch"><h2>What to watch</h2><ul>{items}</ul></section>' if items else ''}
<section class="more sources"><h2>Sources</h2><ol>{links}</ol></section>
<footer>Researched by {escape(result.get('agent') or 'an AI agent')} for Omarchy Stocks on {generated.strftime('%-d %B %Y at %H:%M %Z')}.
Prices are from that time. AI-generated from public sources and may contain mistakes; not investment advice.</footer>
</main>
</body>
</html>
"""


def publish(path, result, render):
    """Called under the job lock: the report's HTML page sits beside its result."""
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


def export(task, subject, preference, render, name):
    """Save a copy of the report where it can be shared, never replacing another file.
    `name` turns the saved result into a file name without its extension."""
    subject = symbol(subject)
    try:
        result = read_json(ai_jobs.directory(task, subject, preference) / "result.json", {})
        if result.get("symbol") != subject or result.get("version") != task.version:
            raise ValueError("There is no report to save yet.")
        page, stem, folder = render(result), name(result), downloads()
        for index in range(1, 100):
            path = folder / (stem + (f"-{index}" if index > 1 else "") + ".html")
            if path.exists() and path.read_text(errors="replace") != page:
                continue
            path.write_text(page)
            shown = "~/" + str(path.relative_to(Path.home())) if path.is_relative_to(Path.home()) else str(path)
            return {"symbol": subject, "preference": preference, "generated": result["generated"], "file": str(path), "shown": shown}
        raise ValueError("Could not choose a file name in " + str(folder) + ".")
    except (ValueError, OSError) as error:
        return {"symbol": subject, "preference": preference, "error": str(error)}


def main(task, script, arguments, render, name):
    """A report feature's actions: the shared job actions, plus `export`."""
    if arguments[:1] == ["export"] and len(arguments) >= 3:
        return export(task, arguments[1], arguments[2], render, name)
    return ai_jobs.main(task, script, arguments)
