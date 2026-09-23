"""Free, public Stocktwits posts and ApeWisdom's aggregate Reddit mentions."""

import concurrent.futures
from datetime import datetime
import html
import json
import re
import urllib.error
import urllib.parse
import urllib.request

MAX_RESPONSE_BYTES = 2 * 1024 * 1024


def get_json(url, provider):
    request = urllib.request.Request(url, headers={"User-Agent": "Omastocks/0.1", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=6) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
        if len(raw) > MAX_RESPONSE_BYTES:
            raise ValueError("Social feed response is too large.")
        return json.loads(raw)
    except urllib.error.HTTPError as error:
        if error.code == 429:
            raise ValueError(f"{provider} is rate limiting requests. Try again later.") from error
        if error.code == 404:
            raise ValueError(f"{provider} has no coverage for this symbol.") from error
        raise ValueError(f"{provider} returned HTTP {error.code}.") from error
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        raise ValueError(f"Could not reach {provider}. Try refreshing later.") from error


def count(value):
    if isinstance(value, bool) or value is None:
        return None
    try:
        number = float(value)
        return int(number) if number >= 0 and number.is_integer() else None
    except (ValueError, TypeError, OverflowError):
        return None


def parse_stocktwits(document, ticker):
    provider_symbol = ticker.lstrip("^")
    if not isinstance(document, dict) or not isinstance(document.get("messages"), list):
        raise ValueError("Stocktwits did not return a post feed.")
    if (document.get("symbol") or {}).get("symbol", "").upper() != provider_symbol:
        raise ValueError("Stocktwits returned a different symbol.")
    posts, seen = [], set()
    for row in document["messages"]:
        if not isinstance(row, dict):
            continue
        identity = count(row.get("id"))
        body = html.unescape(str(row.get("body") or "")).strip()
        user = row.get("user") or {}
        username = str(user.get("username") or "")
        if not identity or identity in seen or not body or not re.fullmatch(r"[A-Za-z0-9_]+", username):
            continue
        try:
            date = datetime.fromisoformat(str(row.get("created_at") or "").replace("Z", "+00:00"))
            if date.tzinfo is None:
                continue
            published = date.timestamp()
            if published <= 0:
                continue
        except (ValueError, OverflowError):
            continue
        sentiment = ((row.get("entities") or {}).get("sentiment") or {}).get("basic")
        seen.add(identity)
        posts.append({"id": str(identity), "text": body, "author": username, "published": published,
                      "url": f"https://stocktwits.com/{username}/message/{identity}",
                      "likes": count((row.get("likes") or {}).get("total")),
                      "sentiment": sentiment if sentiment in ("Bullish", "Bearish") else None})
    return {"symbol": ticker, "posts": sorted(posts, key=lambda row: row["published"], reverse=True)[:20],
            "source": "Stocktwits", "url": "https://stocktwits.com/symbol/" + urllib.parse.quote(provider_symbol, safe="")}


def stocktwits(ticker):
    url = "https://api.stocktwits.com/api/2/streams/symbol/" + urllib.parse.quote(ticker.lstrip("^"), safe="") + ".json"
    return parse_stocktwits(get_json(url, "Stocktwits"), ticker)


def parse_buzz(pages):
    rows, seen = [], set()
    for page in pages:
        if not isinstance(page, dict) or not isinstance(page.get("results"), list):
            raise ValueError("ApeWisdom did not return mention rankings.")
        for row in page["results"]:
            if not isinstance(row, dict):
                continue
            ticker = str(row.get("ticker") or "").upper()
            if not re.fullmatch(r"[A-Z0-9^][A-Z0-9.^=\-]{0,29}", ticker) or ticker in seen:
                continue
            seen.add(ticker)
            rows.append({"symbol": ticker, "mentions": count(row.get("mentions")),
                         "upvotes": count(row.get("upvotes")), "rank": count(row.get("rank")) or None,
                         "previousMentions": count(row.get("mentions_24h_ago")),
                         "previousRank": count(row.get("rank_24h_ago")) or None})
    return {"symbol": "ALL", "rows": rows, "source": "ApeWisdom", "filter": "all-stocks"}


def reddit_buzz():
    url = "https://apewisdom.io/api/v1.0/filter/all-stocks"
    first = get_json(url, "ApeWisdom")
    pages = count(first.get("pages"))
    if not pages or not isinstance(first.get("results"), list):
        raise ValueError("ApeWisdom did not return mention rankings.")
    # Fetch one shared snapshot, rather than scanning the same pages per stock.
    # Bound work to stay within the research worker's deadline if coverage grows.
    last = min(pages, 20)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        remaining = list(pool.map(lambda page: get_json(url + "/page/" + str(page), "ApeWisdom"), range(2, last + 1)))
    return {**parse_buzz([first, *remaining]), "complete": pages <= last}
