"""New listings for the exchange banner: NYSE listing ceremonies and Nasdaq's IPO calendar.

SPACs are left out. The app asks for one New York trading day ("2026-03-20");
a month ("2026-03") is handy for reviewing listings from the command line.
"""
import calendar
from datetime import date, datetime
import html
import json
import re
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo


NYSE = "https://www.nyse.com"
EASTERN = ZoneInfo("America/New_York")
TICKER = re.compile(r"\((NYSE(?:\s+American|\s+Arca|\s+Texas)?)\s*:\s*([A-Z][A-Z0-9.\-]*)\)")
# Listing ceremonies; anniversaries and other visits are not new listings.
LISTING = re.compile(r"initial public offering|\bIPO\b|direct listing|(?:its|their) (?:recent )?listing", re.I)


def period_bounds(period):
    if re.fullmatch(r"\d{4}-\d{2}", period or ""):
        year, month = map(int, period.split("-"))
        return date(year, month, 1), date(year, month, calendar.monthrange(year, month)[1])
    try:
        day = date.fromisoformat(period)
    except (TypeError, ValueError):
        raise ValueError("Choose a day (YYYY-MM-DD) or a month (YYYY-MM).") from None
    return day, day


def spac(name, ticker, price=None):
    # Blank-check companies list as $10 units (tickers ending in U).
    return bool(re.search(r"\bacquisition\b|blank check", name or "", re.I)) or (ticker or "").endswith(".U") \
        or (price == 10 and (ticker or "").endswith("U"))


def text(value):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(value or ""))).strip()


def parse_nyse(document):
    rows = []
    for event in document.get("results") or []:
        if not isinstance(event, dict):
            continue
        title, description = text(event.get("title")), text(event.get("description"))
        # The occasion is stated before the bell ringer is named.
        if not LISTING.search(description.split("To honor the occasion")[0]):
            continue
        # Titles occasionally carry a typo (American Water as AMK); prefer the description.
        match = TICKER.search(description) or TICKER.search(title)
        stamp = event.get("startDateTime")
        if not match or not isinstance(stamp, (int, float)):
            continue
        name = re.split(r"\s+\(NYSE|\s+Rings\b", title)[0].strip()
        exchange, ticker = re.sub(r"\s+", " ", match.group(1)), match.group(2)
        if spac(name, ticker):
            continue
        path = event.get("filePath") or ""
        rows.append({"date": datetime.fromtimestamp(stamp / 1000, EASTERN).date().isoformat(), "name": name,
                     "ticker": ticker, "exchange": exchange, "source": "NYSE",
                     "logo": NYSE + urllib.parse.quote(path) if path.startswith("/publicdocs/") else ""})
    return rows


def exchange_name(value):
    value = value or ""
    return "Nasdaq" if value.upper().startswith("NASDAQ") else "NYSE American" if value in ("NYSE MKT", "NYSE American") else value


def parse_nasdaq(data, first, last):
    rows = []
    for row in ((data.get("priced") or {}).get("rows") or []):
        if not isinstance(row, dict):
            continue
        try:
            month, day, year = map(int, (row.get("pricedDate") or "").split("/"))
            listed = date(year, month, day)
        except ValueError:
            continue
        name, ticker = (row.get("companyName") or "").strip(), (row.get("proposedTickerSymbol") or "").strip()
        try:
            price = float(row.get("proposedSharePrice"))
        except (TypeError, ValueError):
            price = None
        if not first <= listed <= last or not name or not ticker or spac(name, ticker, price):
            continue
        rows.append({"date": listed.isoformat(), "name": name, "ticker": ticker,
                     "exchange": exchange_name(row.get("proposedExchange")), "source": "Nasdaq", "logo": ""})
    return rows


def merge(nyse, nasdaq):
    """One entry per listing and day. NYSE's has the ceremony logo."""
    key = lambda row: (row["date"], re.sub(r"[.\-]", "", row["ticker"]))
    seen = {key(row) for row in nyse}
    return sorted(nyse + [row for row in nasdaq if key(row) not in seen], key=lambda row: (row["date"], row["ticker"]))


def favicon(ticker, profile):
    """A site icon for listings without a ceremony logo; empty when unknown."""
    try:
        site = urllib.parse.urlsplit(profile(ticker)).hostname or ""
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        return ""
    site = re.sub(r"^www\.", "", site)
    return "https://www.google.com/s2/favicons?" + urllib.parse.urlencode({"domain": site, "sz": 128}) if site else ""


def website(ticker):
    """The company's website from Yahoo, kept once found: it rarely changes."""
    from stocks import read_json, state_directory, write_json
    from yahoo_http import authenticated
    path = state_directory() / "research" / "ipo-websites.json"
    saved = read_json(path, {})
    if saved.get(ticker):
        return saved[ticker]
    result = authenticated("/v10/finance/quoteSummary/" + urllib.parse.quote(ticker, safe=""), modules="assetProfile")
    site = (result["quoteSummary"]["result"][0].get("assetProfile") or {}).get("website") or ""
    if site:
        path.parent.mkdir(parents=True, exist_ok=True)
        write_json(path, {**read_json(path, {}), ticker: site})
    return site


def nyse_events(first, last):
    query = urllib.parse.urlencode({"filterToken": "", "startDate": first.isoformat(), "endDate": last.isoformat(),
                                    "type": "", "pageNumber": 1, "max": 200, "company": "", "sortOrder": "down"})
    request = urllib.request.Request(NYSE + "/api/events/filter?" + query, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36",
        "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=10) as response:
        raw = response.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError("The NYSE response was too large.")
    return json.loads(raw)


def listings(period, nasdaq, events=nyse_events, profile=website):
    first, last = period_bounds(period)
    # Each source stands alone; the banner only fails when both do.
    failures = 0
    try:
        nyse = parse_nyse(events(first, last))
    except (OSError, ValueError):
        nyse, failures = [], failures + 1
    try:
        # Nasdaq's calendar is monthly; a period never spans two months.
        ipo = parse_nasdaq(nasdaq("/api/ipo/calendar?date=%04d-%02d" % (first.year, first.month)), first, last)
    except (OSError, ValueError):
        ipo, failures = [], failures + 1
    if failures == 2:
        raise ValueError("New listings are unavailable.")
    rows = merge(nyse, ipo)
    for row in rows:
        if not row["logo"]:
            row["logo"] = favicon(row["ticker"], profile)
    return {"period": period, "listings": rows, "ipoSchema": 1}
