"""Nasdaq filings and insider records. No inferred trade classifications."""

import re
from urllib.parse import urlsplit, urljoin, parse_qs
from stocks import number


def safe_link(value, hosts):
    if not isinstance(value, str):
        return ""
    parsed = urlsplit(value)
    return value if parsed.scheme == "https" and parsed.hostname in hosts else ""


def parse_filings(document, ticker, parse_date):
    if str(document.get("symbol", "")).upper() != ticker:
        raise ValueError("Filing data did not match this symbol.")
    if not isinstance(document.get("rows"), list):
        raise ValueError("Filing records are unavailable for this symbol.")
    rows, seen = [], set()
    for row in document["rows"]:
        url = safe_link((row.get("view") or {}).get("htmlLink"), {"app.quotemedia.com", "www.sec.gov", "sec.gov"})
        day = parse_date(row.get("filed"))
        form = str(row.get("formType") or "").strip()
        if not url or not day or not form or url in seen:
            continue
        seen.add(url)
        description = parse_qs(urlsplit(url).query).get("formDescription", [""])[0]
        rows.append({"date": day, "form": form, "description": description,
                     "period": parse_date(row.get("period")), "owner": row.get("reportingOwner") or "", "url": url})
    return {"symbol": ticker, "rows": sorted(rows, key=lambda r: r["date"], reverse=True)[:40], "source": "Nasdaq / QuoteMedia"}


def parse_insiders(document, ticker, parse_date):
    table = (document.get("transactionTable") or {}).get("table") or {}
    if not isinstance(table.get("rows"), list):
        raise ValueError("Insider transactions are unavailable for this symbol.")
    rows = []
    for row in table["rows"]:
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
    return {"symbol": ticker, "rows": sorted(rows, key=lambda r: r["date"], reverse=True)[:30], "source": "Nasdaq"}


def activity(action, ticker, request, parse_date):
    if not re.fullmatch(r"[A-Z][A-Z0-9.-]*", ticker):
        return {"symbol": ticker, "rows": [], "notice": "Coverage is available for supported US-listed companies."}
    endpoint = "sec-filings?limit=40" if action == "filings" else "insider-trades?limit=30"
    document = request("/api/company/" + ticker + "/" + endpoint)
    return (parse_filings if action == "filings" else parse_insiders)(document, ticker, parse_date)
