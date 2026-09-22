"""Nasdaq insider transactions and provider-wide three-month aggregates."""

import re
from urllib.parse import urlsplit, urljoin
from stocks import number


def safe_link(value, hosts):
    if not isinstance(value, str):
        return ""
    parsed = urlsplit(value)
    return value if parsed.scheme == "https" and parsed.hostname in hosts else ""


def parse_summary(document):
    def metric(section, label, integer=False):
        matches = [row for row in (document.get(section) or {}).get("rows") or []
                   if isinstance(row, dict) and " ".join(str(row.get("insiderTrade") or "").split()).casefold() == label.casefold()]
        if len(matches) != 1:
            return None
        raw = matches[0].get("months3")
        value = number(raw.replace(",", "").strip() if isinstance(raw, str) else raw)
        return value if value is not None and value >= 0 and (not integer or value.is_integer()) else None

    bought = metric("numberOfSharesTraded", "Number of Shares Bought")
    sold = metric("numberOfSharesTraded", "Number of Shares Sold")
    total = bought + sold if bought is not None and sold is not None else None
    return {"period": "Past 3 months", "boughtShares": bought, "soldShares": sold,
            "buyTrades": metric("numberOfTrades", "Number of Open Market Buys", True),
            "sellTrades": metric("numberOfTrades", "Number of Sells", True),
            "netShares": bought - sold if total is not None else None,
            "buyFraction": bought / total if total is not None and total > 0 else None,
            "asOf": (document.get("numberOfSharesTraded") or {}).get("asOf") or ""}


def parse_insiders(document, ticker, parse_date):
    summary = parse_summary(document)
    table = (document.get("transactionTable") or {}).get("table") or {}
    table_available = isinstance(table.get("rows"), list)
    if not table_available and all(summary[key] is None for key in ("boughtShares", "soldShares", "buyTrades", "sellTrades")):
        raise ValueError("Insider transactions are unavailable for this symbol.")
    rows = []
    for row in table.get("rows") or []:
        day, name = parse_date(row.get("lastDate")), str(row.get("insider") or "").strip()
        if not day or not name:
            continue
        def numeric(key):
            text = str(row.get(key) or "").replace(",", "").replace("$", "")
            value = number(text)
            return value if value is not None and value >= 0 else None
        url = safe_link(urljoin("https://www.nasdaq.com", str(row.get("url") or "")), {"www.nasdaq.com"})
        rows.append({"date": day, "name": name, "role": row.get("relation") or "",
                     "type": row.get("transactionType") or "Unspecified", "ownership": row.get("ownType") or "",
                     "shares": numeric("sharesTraded"), "price": numeric("lastPrice"), "held": numeric("sharesHeld"),
                     "currency": "USD" if str(row.get("lastPrice") or "").startswith("$") else "", "url": url})
    return {"symbol": ticker, "rows": sorted(rows, key=lambda r: r["date"], reverse=True)[:30],
            "summary": summary, "source": "Nasdaq", "insiderSchema": 2,
            "notice": "" if table_available else "Recent transaction details are unavailable."}


def activity(ticker, request, parse_date):
    if not re.fullmatch(r"[A-Z][A-Z0-9.-]*", ticker):
        return {"symbol": ticker, "rows": [], "insiderSchema": 2, "notice": "Coverage is available for supported US-listed companies."}
    document = request("/api/company/" + ticker + "/insider-trades?limit=30")
    return parse_insiders(document, ticker, parse_date)
