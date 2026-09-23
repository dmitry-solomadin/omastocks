"""Market pulse: CNN Fear & Greed and the US economic calendar.

Each loader validates the provider response and raises on anything unexpected,
so the research cache keeps the last good result instead of saving a bad one.
"""
from datetime import datetime, timedelta, timezone
import json
import urllib.parse
import urllib.request
from stocks import number

FEAR_GREED = "https://production.dataviz.cnn.io/index/fearandgreed/graphdata"
CALENDAR = "https://economic-calendar.tradingview.com/events"
BROWSER = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"


def get_json(url, headers, limit=2 * 1024 * 1024):
    req = urllib.request.Request(url, headers={"User-Agent": BROWSER, "Accept": "application/json", **headers})
    with urllib.request.urlopen(req, timeout=12) as response:
        raw = response.read(limit + 1)
    if len(raw) > limit:
        raise ValueError("The provider returned an oversized response.")
    return json.loads(raw)


def sentiment(fetch=get_json):
    """CNN's Fear & Greed index with its recent comparisons."""
    document = fetch(FEAR_GREED, {"Referer": "https://www.cnn.com/"})
    index = document.get("fear_and_greed") if isinstance(document, dict) else None
    score = number(index.get("score")) if isinstance(index, dict) else None
    if score is None or not 0 <= score <= 100 or not isinstance(index.get("rating"), str):
        raise ValueError("CNN returned an unexpected Fear & Greed response.")
    return {"score": score, "rating": index["rating"],
            "previousClose": number(index.get("previous_close")), "previousWeek": number(index.get("previous_1_week")),
            "previousMonth": number(index.get("previous_1_month")), "previousYear": number(index.get("previous_1_year")),
            "updated": index.get("timestamp") or "", "provider": "CNN"}


def economic_calendar(now=None, fetch=get_json):
    """High-importance US releases from yesterday through the next two weeks."""
    now = now or datetime.now(timezone.utc)
    now = now.astimezone(timezone.utc)
    start, end = now - timedelta(days=1), now + timedelta(days=14)
    stamp = lambda moment: moment.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    url = CALENDAR + "?" + urllib.parse.urlencode({"from": stamp(start), "to": stamp(end), "countries": "US"})
    document = fetch(url, {"Origin": "https://www.tradingview.com"})
    result = document.get("result") if isinstance(document, dict) else None
    if not isinstance(result, list):
        raise ValueError("TradingView returned an unexpected economic calendar.")
    events = []
    for event in result:
        if not isinstance(event, dict) or event.get("importance") != 1 or not event.get("title") or not event.get("date"):
            continue
        try:
            moment = datetime.fromisoformat(str(event["date"]).replace("Z", "+00:00"))
            if moment.tzinfo is None or not start <= moment <= end:
                continue
        except ValueError:
            continue
        events.append({"id": str(event.get("id") or ""), "title": str(event["title"]), "time": moment.timestamp(),
                       "period": event.get("period") or "", "actual": number(event.get("actual")),
                       "forecast": number(event.get("forecast")), "previous": number(event.get("previous")),
                       "unit": event.get("unit") or "", "scale": event.get("scale") or "",
                       "source": event.get("source") or ""})
    events.sort(key=lambda event: (event["time"], event["title"]))
    return {"events": events, "provider": "TradingView"}
