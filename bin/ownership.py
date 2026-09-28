"""Institutional and insider ownership and short interest from Yahoo's quote summary."""
from datetime import datetime, timezone
import urllib.parse

from market_bulk import raw
from yahoo_http import authenticated


MODULES = "defaultKeyStatistics,majorHoldersBreakdown,institutionOwnership"


def percent(row, key):
    value = raw(row, key)
    return value * 100 if value is not None else None


def day(row, key):
    stamp = raw(row, key)
    return datetime.fromtimestamp(stamp, timezone.utc).date().isoformat() if stamp is not None else ""


def others(institutions, insiders, short, outstanding):
    """Percent held by everyone else, mostly individual investors, or None.

    Shorted shares have two owners (the lender and the buyer), so all long
    positions add up to shares outstanding plus shares short. Scaling reported
    holdings by that total removes the double count; without it, heavily
    shorted stocks can show institutions above 100%.
    """
    if institutions is None or insiders is None:
        return None
    scale = 1 + (short / outstanding if short and outstanding else 0)
    value = 100 - (institutions + insiders) / scale
    return value if value >= 0 else None


def parse_ownership(document, ticker):
    summary = document.get("quoteSummary") or {}
    results = summary.get("result") or []
    if not results or not isinstance(results[0], dict):
        raise ValueError(((summary.get("error") or {}).get("description")) or "Ownership data is unavailable.")
    result = results[0]
    stats = result.get("defaultKeyStatistics") or {}
    holders = result.get("majorHoldersBreakdown") or {}
    institutions = []
    for row in (result.get("institutionOwnership") or {}).get("ownershipList") or []:
        name = row.get("organization") if isinstance(row, dict) else None
        if isinstance(name, str) and name.strip():
            institutions.append({"name": name.strip(), "percent": percent(row, "pctHeld"), "date": day(row, "reportDate")})
    institutions_percent, insiders_percent = percent(holders, "institutionsPercentHeld"), percent(holders, "insidersPercentHeld")
    return {
        "symbol": ticker, "source": "Yahoo Finance", "ownershipSchema": 2,
        "institutionsPercent": institutions_percent,
        "institutionsFloatPercent": percent(holders, "institutionsFloatPercentHeld"),
        "institutionsCount": raw(holders, "institutionsCount"),
        "insidersPercent": insiders_percent,
        "othersPercent": others(institutions_percent, insiders_percent, raw(stats, "sharesShort"), raw(stats, "sharesOutstanding")),
        "shortPercentFloat": percent(stats, "shortPercentOfFloat"), "shortShares": raw(stats, "sharesShort"),
        "shortPriorShares": raw(stats, "sharesShortPriorMonth"), "shortRatio": raw(stats, "shortRatio"),
        "shortDate": day(stats, "dateShortInterest"),
        "holders": institutions[:5],
    }


def ownership(ticker, request=authenticated):
    document = request("/v10/finance/quoteSummary/" + urllib.parse.quote(ticker, safe=""), modules=MODULES)
    return parse_ownership(document, ticker)
