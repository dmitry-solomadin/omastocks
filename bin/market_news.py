"""Market-wide and macro headlines, rather than a general stock-picking feed."""
from email.utils import parsedate_to_datetime
from datetime import datetime
import urllib.parse
import urllib.request
from rss_feed import parse_xml
import re
import time

QUERY = '("stock market today" OR "stock futures" OR "Wall Street" OR "Federal Reserve" OR "Treasury yields" OR "inflation data" OR "jobs report") when:3d'
URL = "https://news.google.com/rss/search?" + urllib.parse.urlencode({"q": QUERY, "hl": "en-US", "gl": "US", "ceid": "US:en"})
MACRO = re.compile(r"\b(fed(?:'s)? (?:rate|hike|cut|meeting|decision|chair)|treasury yields?|bond yields?|interest rates?|inflation|consumer prices?|CPI|PCE|jobs report|payrolls|unemployment|GDP|recession|central banks?)\b", re.I)
MARKET = re.compile(r"\b(stock markets?|stock futures|stocks|S&P\s*500|Dow|Nasdaq|Wall Street|global markets?)\b", re.I)
MOVEMENT = re.compile(r"\b(today|rise[sd]?|rising|rall(?:y|ies)|fall[sd]?|falling|slid(?:e|es|ing)|drop[sd]?|gain[sd]?|losses|higher|lower|record|sell.?off|close[sd]?|open[sd]?|tumble[sd]?|surge[sd]?|flat|mixed|edge[sd]?|hold[sd]?|tick[sd]?|futures)\b", re.I)
PICKS = re.compile(r"\b(stock picks?|stocks? to (?:buy|watch)|buy (?:this|these)|outperform(?:ing|s)?|price targets?|dividend stocks?|prediction|motley fool|cash management stocks?|retirees|retirement|could benefit|stocks investors|GPU futures)\b", re.I)
SOURCES = {"ap news", "reuters", "cnbc", "bloomberg", "bloomberg.com", "yahoo finance", "wsj", "the wall street journal", "financial times", "bbc", "bbc news", "the guardian", "marketwatch", "investing.com", "barron's", "investor's business daily", "cnn", "cnn business"}


def relevant(title):
    if PICKS.search(title):
        return False
    if MACRO.search(title) or re.search(r"\bfederal reserve\b.{0,35}\b(rate|tightening|easing|hike|cut|raises|cuts)\b", title, re.I):
        return True
    if re.search(r"\bstock (?:market today|futures)\b|\bmarkets wrap\b", title, re.I):
        return True
    # The index/market must be the subject of the move, rather than a passing
    # 'Wall Street' reference in an individual-company headline.
    return any(MOVEMENT.match(title[match.end():].lstrip()) for match in MARKET.finditer(title))


def parse(raw, now=None):
    now = time.time() if now is None else now
    channel = parse_xml(raw).find("channel")
    if channel is None:
        raise ValueError("Market news feed is unavailable.")
    articles, seen = [], set()
    for item in channel.findall("item"):
        title = (item.findtext("title") or "").strip()
        source = (item.findtext("source") or "").strip()
        if source.casefold() not in SOURCES:
            continue
        if source and title.endswith(" - " + source):
            title = title[:-(len(source) + 3)]
        url = (item.findtext("link") or "").strip()
        parsed = urllib.parse.urlsplit(url)
        if not title or parsed.scheme not in ("http", "https") or not parsed.netloc or url in seen:
            continue
        identity = re.sub(r"\W+", " ", title.casefold()).strip()
        if identity in seen or not relevant(title):
            continue
        try:
            published = int(parsedate_to_datetime(item.findtext("pubDate") or "").timestamp())
        except (ValueError, TypeError, OverflowError):
            try:
                date = datetime.fromisoformat((item.findtext("pubDate") or "").replace("Z", "+00:00"))
                published = int(date.timestamp()) if date.tzinfo else None
            except (ValueError, TypeError, OverflowError):
                published = None
        if published is None or published < now - 3 * 86400 or published > now + 3600:
            continue
        seen.add(url)
        seen.add(identity)
        articles.append({"title": title, "url": url, "source": source or "Publisher",
                         "published": published, "image": ""})
    if not channel.findall("item"):
        raise ValueError("Market news feed returned no headlines.")
    articles.sort(key=lambda article: article["published"] or 0, reverse=True)
    return {"articles": articles[:12], "source": URL, "marketNewsSchema": 3}


def news():
    with urllib.request.urlopen(urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"}), timeout=10) as response:
        raw = response.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError("Market news feed is too large.")
    return parse(raw)
