"""One supplemental bulk request, matched to calendar report dates."""
from datetime import datetime
import re
from zoneinfo import ZoneInfo
from index_market import request
from stocks import number

COLUMNS = ["total_revenue_fq", "revenue_forecast_fq", "revenue_forecast_next_fq",
           "earnings_release_date", "earnings_release_next_date", "currency", "type"]


def day(value):
    value = number(value)
    if value is None:
        return None
    try:
        return datetime.fromtimestamp(value, ZoneInfo("America/New_York")).date().isoformat()
    except (ValueError, OverflowError, OSError):
        return None


def attach(report, document, identifiers):
    matches = {}
    for row in document.get("data") or []:
        ticker = identifiers.get(row.get("s"))
        values = row.get("d") or []
        if ticker and len(values) == len(COLUMNS) and values[6] in ("stock", "dr"):
            matches.setdefault(ticker, []).append(values)
    for ticker, candidates in matches.items():
        if len(candidates) != 1:
            continue
        actual, estimate, upcoming, released, next_date, currency, _ = candidates[0]
        if not isinstance(currency, str) or not re.fullmatch(r"[A-Z]{3}", currency):
            continue
        row = report["rows"][ticker]
        for event in row.get("events") or []:
            if event["date"] == day(released):
                event.update(revenue=number(actual), revenueForecast=number(estimate), revenueCurrency=currency)
        if row.get("next") and row["next"]["date"] == day(next_date):
            row["next"].update(revenueForecast=number(upcoming), revenueCurrency=currency)
    return report


def enrich(report, fetch=request):
    identifiers = {exchange + ":" + ticker.replace("-", "."): ticker
                   for ticker in report["rows"] if re.fullmatch(r"[A-Z][A-Z0-9-]*", ticker)
                   for exchange in ("NASDAQ", "NYSE", "AMEX")}
    report["calendarSchema"] = 2
    if not identifiers:
        return report
    try:
        document = fetch({"symbols": {"tickers": list(identifiers), "query": {"types": []}}, "columns": COLUMNS,
                          "range": [0, len(identifiers)]})
        if not isinstance(document.get("data"), list) or document.get("totalCount") != len(document["data"]):
            raise ValueError("Incomplete revenue response.")
        return attach(report, document, identifiers)
    except (OSError, ValueError, TypeError) as error:
        report["revenueNotice"] = "Revenue data unavailable: " + str(error)
        return report
