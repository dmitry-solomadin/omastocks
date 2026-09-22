"""Transcript links from Yahoo's symbol-scoped earnings calls page."""

from html.parser import HTMLParser
import re
import urllib.parse
import urllib.request


class CallLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.calls = []
        self.seen = set()
        self.current = None
        self.calls_page = False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get("id") == "tab-earnings-calls" and attrs.get("aria-selected") == "true":
            self.calls_page = True
        if tag != "a":
            return
        self.current = None
        url = urllib.parse.urljoin("https://finance.yahoo.com", attrs.get("href") or "")
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme == "https" and parsed.netloc == "finance.yahoo.com"
                and re.fullmatch(r"/quote/[^/]+/earnings/[^/]+\.html", parsed.path)):
            self.current = {"url": urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, parsed.path, "", "")),
                            "title": attrs.get("title") or attrs.get("aria-label") or "", "text": []}

    def handle_data(self, text):
        if self.current is not None:
            self.current["text"].append(text)

    def handle_endtag(self, tag):
        if tag != "a" or self.current is None:
            return
        call, self.current = self.current, None
        title = " ".join((call["title"] or "".join(call["text"])).split())
        if title and call["url"] not in self.seen:
            self.seen.add(call["url"])
            self.calls.append({"title": title, "url": call["url"]})


def parse_calls(page, ticker):
    parser = CallLinks()
    parser.feed(page)
    # A consent/error page is a failed request, not an empty transcript history.
    if not parser.calls_page:
        raise ValueError("Earnings call links are unavailable from Yahoo Finance. Try refreshing later.")
    return {"symbol": ticker, "calls": parser.calls[:12], "source": "Yahoo Finance"}


def earnings_calls(ticker):
    url = "https://finance.yahoo.com/quote/" + urllib.parse.quote(ticker, safe="") + "/earnings-calls/"
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html"})
    with urllib.request.urlopen(request, timeout=20) as response:
        page = response.read().decode("utf-8")
    return parse_calls(page, ticker)
