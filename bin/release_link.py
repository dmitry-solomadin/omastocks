"""Resolve an earnings release link without Google's redirect notice.

Google's "I'm Feeling Lucky" (btnI) answers with a redirect through
google.com/url, which browsers sometimes stop at with a "Redirect notice"
page. Reading the destination from that redirect here lets the app open the
release directly.
"""
import re
import urllib.error
import urllib.parse
import urllib.request

BROWSER = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def query(ticker, date):
    return f"{ticker} earnings release {date} investor relations"


def lucky_url(ticker, date):
    return "https://www.google.com/search?" + urllib.parse.urlencode({"btnI": "1", "q": query(ticker, date)})


def location(url):
    """The Location of a redirect response, without following it."""
    request = urllib.request.Request(url, headers={"User-Agent": BROWSER, "Accept-Language": "en-US,en;q=0.9"})
    try:
        urllib.request.build_opener(_NoRedirect).open(request, timeout=10)
    except urllib.error.HTTPError as error:
        if error.code in (301, 302, 303, 307, 308):
            return error.headers.get("Location") or ""
        raise
    return ""


def destination(redirect):
    """The final URL inside a google.com/url redirect (or a direct one)."""
    parts = urllib.parse.urlsplit(redirect)
    if parts.netloc.endswith("google.com") and parts.path == "/url":
        redirect = (urllib.parse.parse_qs(parts.query).get("q") or [""])[0]
    target = urllib.parse.urlsplit(redirect)
    if target.scheme not in ("http", "https") or not target.netloc or target.netloc.endswith("google.com"):
        raise ValueError("Google did not return a direct result for this earnings release.")
    return redirect


def resolve(ticker, date, fetch=location):
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
        raise ValueError("Invalid report date.")
    return {"url": destination(fetch(lucky_url(ticker, date))), "query": query(ticker, date), "provider": "Google"}
