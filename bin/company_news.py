"""Broaden sparse Yahoo results with one recent, company-scoped RSS search."""
from email.utils import parsedate_to_datetime
import time
import urllib.parse
import urllib.request
from rss_feed import parse_xml


def supplement(ticker, name=""):
    terms = '"' + ticker.replace('"', '') + '"'
    if name:
        terms += ' OR "' + name.replace('"', '') + '"'
    query = '(' + terms + ') (stock OR shares OR earnings OR business) when:7d'
    url = "https://news.google.com/rss/search?" + urllib.parse.urlencode({"q": query, "hl": "en-US", "gl": "US", "ceid": "US:en"})
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=10) as response:
        raw = response.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError("Company news feed is too large.")
    return parse(raw)


def parse(raw, now=None):
    now = time.time() if now is None else now
    rows = []
    document = parse_xml(raw)
    for item in document.findall("channel/item"):
        title, source = (item.findtext("title") or "").strip(), (item.findtext("source") or "").strip()
        if source and title.endswith(" - " + source):
            title = title[:-(len(source) + 3)]
        try:
            published = parsedate_to_datetime(item.findtext("pubDate") or "").timestamp()
        except (ValueError, TypeError, OverflowError):
            continue
        if now - 7 * 86400 <= published <= now + 3600:
            rows.append({"title": title, "link": item.findtext("link"), "publisher": source,
                         "providerPublishTime": published, "type": "STORY"})
    return rows
