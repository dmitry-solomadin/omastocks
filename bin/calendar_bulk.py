"""Symbol-filtered Yahoo earnings pages; bounded pagination, no per-stock fan-out."""
from datetime import date, datetime, timedelta
from stocks import number
from yahoo_http import authenticated

FIELDS = ["ticker", "startdatetime", "startdatetimetype", "epsestimate", "epsactual"]


def query(operator, *operands):
    return {"operator": operator, "operands": list(operands)}


def parse_page(document):
    finance = document.get("finance") or {}
    results = finance.get("result") or []
    if finance.get("error") or len(results) != 1:
        raise ValueError("Yahoo earnings calendar is unavailable.")
    result = results[0]
    documents = result.get("documents") or []
    if len(documents) != 1 or not isinstance(result.get("total"), int) or result["total"] < 0:
        raise ValueError("Incomplete earnings calendar response.")
    columns = [column.get("id") for column in documents[0].get("columns", [])]
    if not set(FIELDS).issubset(columns) or len(columns) != len(set(columns)):
        raise ValueError("Unexpected earnings calendar columns.")
    rows = documents[0].get("rows")
    if not isinstance(rows, list) or any(not isinstance(row, list) or len(row) != len(columns) for row in rows):
        raise ValueError("Incomplete earnings calendar rows.")
    return [dict(zip(columns, row)) for row in rows], result["total"]


def summarize(records, tickers, today):
    rows = {ticker: {"symbol": ticker, "next": None, "events": [], "source": "Yahoo Finance",
                     "notice": "EPS reporting currency is not supplied by Yahoo's bulk calendar."} for ticker in tickers}
    seen = {}
    for record in records:
        ticker = record.get("ticker")
        if ticker not in rows:
            continue
        try:
            day = datetime.fromisoformat(record["startdatetime"].replace("Z", "+00:00")).date().isoformat()
        except (ValueError, TypeError, KeyError, AttributeError):
            continue
        event = {"date": day, "forecast": number(record.get("epsestimate")), "eps": number(record.get("epsactual")),
                 "currency": "", "timing": {"BMO": "Before market open", "AMC": "After market close"}.get(record.get("startdatetimetype"), "")}
        key = (ticker, day)
        # Conflicting duplicate events must not silently choose an EPS value.
        if key in seen and seen[key] != event:
            raise ValueError("Yahoo returned conflicting earnings events.")
        seen[key] = event
    for (ticker, day), event in sorted(seen.items()):
        if day >= today.isoformat() and event["eps"] is None:
            if rows[ticker]["next"] is None:
                rows[ticker]["next"] = event
        elif day <= today.isoformat() and event["eps"] is not None:
            rows[ticker]["events"].append(event)
    return rows


def records(tickers, start, end, request=authenticated):
    """Every earnings record for tickers between two dates, with bounded pagination."""
    body = {"sortType": "ASC", "entityIdType": "sp_earnings", "sortField": "startdatetime",
            "includeFields": FIELDS, "size": 100, "offset": 0,
            "query": query("AND", query("OR", *(query("EQ", "ticker", ticker) for ticker in tickers)),
                           query("GTE", "startdatetime", start.isoformat()), query("LTE", "startdatetime", end.isoformat()),
                           query("OR", query("EQ", "eventtype", "EAD"), query("EQ", "eventtype", "ERA")))}
    found, expected = [], None
    for _ in range(10):
        page, total = parse_page(request("/v1/finance/visualization", body=body, lang="en-US", region="US"))
        if expected is not None and expected != total:
            raise ValueError("Earnings calendar changed during pagination. Try refreshing.")
        expected = total
        found.extend(page)
        if len(found) == total:
            return found
        if not page or len(found) > total:
            break
        body = {**body, "offset": len(found)}
    raise ValueError("Incomplete earnings calendar; saved data retained.")


def calendar(tickers, request=authenticated, today=None):
    today = today or date.today()
    end = today + timedelta(days=365)
    found = records(tickers, today - timedelta(days=180), end, request)
    return {"rows": summarize(found, tickers, today), "source": "Yahoo Finance", "through": end.isoformat()}


def history(ticker, years=5, request=authenticated, today=None):
    """Reported earnings for one ticker over the past years, oldest first."""
    today = today or date.today()
    found = records([ticker], today - timedelta(days=366 * years + 31), today, request)
    return summarize(found, [ticker], today)[ticker]["events"]
