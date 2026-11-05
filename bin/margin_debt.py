"""FINRA's monthly margin debt, against the size of the market and its own history.

FINRA publishes an Excel file and no data feed, about three weeks after each month
ends. Debt alone is nearly always near a record because the market grows, so the
level is read as a share of the Wilshire 5000, whose points roughly equal $1 billion
of market value. Falling prices raise that share, so the year's change reads beside
it: in March 2009 the share was high while debt had fallen by two fifths."""

from datetime import datetime, timezone
import io
import math
import re
import statistics
import time
import zipfile
import zlib
from zoneinfo import ZoneInfo

from remote_images import download
from rss_feed import parse_xml
from stocks import fetch

URL = "https://www.finra.org/sites/default/files/2021-03/margin-statistics.xlsx"
HEADERS = {"User-Agent": "Omastocks", "Accept": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}
SHEET = "xl/worksheets/sheet1.xml"
NAMESPACE = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
# Real sheets are about 70 KB; parse_xml refuses anything over 2 MB.
MAX_SHEET = 2 * 1024 * 1024
MIN_MONTHS = 120
COLUMNS = {"A": "Year-Month", "B": "Debit Balances in Customers' Securities Margin Accounts",
           "C": "Free Credit Balances in Customers' Cash Accounts",
           "D": "Free Credit Balances in Customers' Securities Margin Accounts"}
FIRST_YEAR = int(datetime(1997, 1, 1, tzinfo=timezone.utc).timestamp())
UNREADABLE = "FINRA's margin statistics could not be read."


def amount(text):
    value = float(text)
    if not math.isfinite(value) or value < 0:
        raise ValueError(UNREADABLE)
    return value


def cells(row):
    values = {}
    for cell in row:
        column = re.sub(r"\d", "", cell.get("r") or "")
        if cell.get("t") == "inlineStr":
            values[column] = "".join(part.text or "" for part in cell.iter(NAMESPACE + "t")).strip()
        else:
            values[column] = (cell.findtext(NAMESPACE + "v") or "").strip()
    return values


def parse_sheet(raw):
    """Months ascending as (month, debt, cash credit, margin credit), in $ millions."""
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive, archive.open(SHEET) as member:
            # Bounded here, whatever size the archive declares.
            rows = parse_xml(member.read(MAX_SHEET + 1)).find(NAMESPACE + "sheetData")
        if rows is None or not len(rows) or any(cells(rows[0]).get(key) != title for key, title in COLUMNS.items()):
            raise ValueError(UNREADABLE)
        months = {}
        for row in rows[1:]:
            values = cells(row)
            if not any(values.values()):
                continue
            month = values.get("A", "")
            if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", month) or month in months or not amount(values.get("B") or "0"):
                raise ValueError(UNREADABLE)
            months[month] = (amount(values["B"]), amount(values["C"]) if values.get("C") else None,
                             amount(values["D"]) if values.get("D") else None)
    except (ValueError, KeyError, OSError, EOFError, RuntimeError, NotImplementedError, zipfile.BadZipFile, zlib.error) as error:
        raise ValueError(UNREADABLE) from error
    if len(months) < MIN_MONTHS:
        raise ValueError(UNREADABLE)
    return [(month, *months[month]) for month in sorted(months)]


def market_closes(request=fetch):
    """The Wilshire 5000's close by month. Yahoo thins a `max` range to quarters."""
    result = request("/v8/finance/chart/%5EW5000", period1=FIRST_YEAR, period2=int(time.time()), interval="1mo")["chart"]["result"][0]
    # Bars are stamped at the month's start in the exchange's time: London's summer
    # months would otherwise fall in the month before.
    zone = ZoneInfo(result["meta"]["exchangeTimezoneName"])
    return {datetime.fromtimestamp(stamp, zone).strftime("%Y-%m"): close
            for stamp, close in zip(result["timestamp"], result["indicators"]["quote"][0]["close"]) if close}


def rank(values, value):
    """The share of the other readings below this one, as a percentage."""
    others = list(values)
    others.remove(value)
    return sum(other < value for other in others) / len(others) * 100 if others else None


def level(percentile):
    return ("Low" if percentile < 20 else "Below average" if percentile < 40 else "Average" if percentile < 60
            else "Above average" if percentile < 80 else "High") if percentile is not None else ""


def trend(change):
    return ("Deleveraging" if change <= -10 else "Easing" if change < 0 else "Growing" if change < 20
            else "Rising fast") if change is not None else ""


def report(rows, closes):
    debts = {month: debt for month, debt, _, _ in rows}
    months = []
    for month, debt, _, _ in rows:
        close = closes.get(month)
        before = debts.get(f"{int(month[:4]) - 1}{month[4:]}")
        months.append({"month": month, "debt": debt * 1e6, "share": debt / 1000 / close * 100 if close else None,
                       "change": (debt / before - 1) * 100 if before else None})
    latest, previous = months[-1], months[-2]
    shares = [row["share"] for row in months if row["share"] is not None]
    changes = [row["change"] for row in months if row["change"] is not None]
    high = max(months, key=lambda row: row["debt"])
    # Margin-account credit is reported separately only from February 2010.
    cushions = [(month, ((cash or 0) + credit) / debt * 100) for month, debt, cash, credit in rows if credit is not None]
    cushion = cushions[-1][1] if cushions and cushions[-1][0] == latest["month"] else None
    # A ranking against a short history would look more certain than it is.
    if latest["share"] is None or latest["change"] is None or len(shares) < MIN_MONTHS:
        raise ValueError("Margin debt has no comparison for its latest month.")
    share_rank = rank(shares, latest["share"])
    return {"marginSchema": 1, "source": "FINRA", "since": months[0]["month"], "months": months, "latest": {
        "month": latest["month"], "debt": latest["debt"], "monthChange": (latest["debt"] / previous["debt"] - 1) * 100,
        "highMonth": high["month"], "high": high["debt"], "fromHigh": (latest["debt"] / high["debt"] - 1) * 100,
        "share": latest["share"], "sharePercentile": share_rank, "shareMedian": statistics.median(shares),
        "yearChange": latest["change"], "yearChangePercentile": rank(changes, latest["change"]),
        "cushion": cushion, "cushionPercentile": rank([value for _, value in cushions], cushion) if cushion is not None else None,
        "cushionMedian": statistics.median(value for _, value in cushions) if cushions else None,
        "cushionSince": cushions[0][0] if cushions else "",
        "level": level(share_rank), "trend": trend(latest["change"])}}


def margin_debt(get=download, request=fetch):
    return report(parse_sheet(get(URL, HEADERS)), market_closes(request))
