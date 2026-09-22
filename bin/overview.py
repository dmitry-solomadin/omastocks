"""Watchlist price returns, independent of chart selection and daily quotes."""

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo
from stocks import fetch, parse_chart
from urllib.parse import quote


def performance(document, ticker):
    chart = parse_chart(document, ticker, "1Y")
    today = datetime.now(ZoneInfo(chart["timezone"])).date()
    current = chart["price"]
    samples = [(date.fromisoformat(day), point[1]) for day, point in zip(chart["dates"], chart["points"])]
    def month_before(day):
        month = day.month - 1 or 12
        year = day.year - (day.month == 1)
        for offset in range(4):
            try:
                return date(year, month, day.day - offset)
            except ValueError:
                pass
    targets = {"1W": today - timedelta(days=7), "1M": month_before(today),
               "YTD": date(today.year, 1, 1) - timedelta(days=1),
               "1Y": today.replace(year=today.year - 1, day=28) if today.month == 2 and today.day == 29
                     else today.replace(year=today.year - 1)}
    returns, baselines = {}, {}
    for period, target in targets.items():
        # Holidays use the preceding close. Never substitute the next session.
        earlier = [(day, value) for day, value in samples if day <= target]
        baseline = earlier[-1] if earlier else None
        valid = baseline and (target - baseline[0]).days <= 7 and baseline[1] > 0
        returns[period] = (current / baseline[1] - 1) * 100 if valid else None
        baselines[period] = baseline[0].isoformat() if valid else None
    return {"symbol": ticker, "returns": returns, "baselines": baselines,
            "asOf": chart["updated"], "currency": chart["currency"], "source": "Yahoo Finance"}


def overview(ticker):
    return performance(fetch("/v8/finance/chart/" + quote(ticker, safe=""), range="2y", interval="1d"), ticker)
