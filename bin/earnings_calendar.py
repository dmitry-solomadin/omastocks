"""Watchlist earnings agenda, with explicit provider estimates."""
import concurrent.futures
import re
from stocks import number


def calendar(ticker, request, parse):
    if not re.fullmatch(r"[A-Z][A-Z0-9.-]*", ticker):
        return {"symbol": ticker, "next": None, "events": [], "notice": "Earnings coverage is available for supported US stocks."}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        upcoming = pool.submit(request, "/api/analyst/" + ticker + "/earnings-date")
        history = pool.submit(request, "/api/company/" + ticker + "/earnings-surprise")
        errors, documents = [], []
        for label, future in zip(("Upcoming earnings", "Historical earnings"), (upcoming, history)):
            try:
                documents.append(future.result())
            except Exception as error:
                documents.append({})
                errors.append(label + ": " + str(error))
    if not any(documents):
        raise ValueError("; ".join(errors))
    result = parse(*documents)
    text = documents[0].get("reportText") or ""
    if result["next"]:
        match = re.search(r"consensus EPS forecast for the quarter is\s+\$(-?\d+(?:\.\d+)?)", text, re.I)
        result["next"].update(forecast=number(match[1]) if match else None, currency="USD" if match else "")
        result["next"]["timing"] = ("Before market open" if re.search(r"before (?:the )?market open", text, re.I)
                                    else "After market close" if re.search(r"after (?:the )?market close", text, re.I) else "")
    return {"symbol": ticker, **result, "notice": "; ".join(errors)}
