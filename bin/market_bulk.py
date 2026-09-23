"""Bulk sector snapshots and quotes. Never expand sectors into chart requests."""
import json
from pathlib import Path
from stocks import number, quote_units, symbol
from yahoo_http import authenticated


def presets():
    return json.loads((Path(__file__).resolve().parents[1] / "data/yahoo-sector-presets.json").read_text())["lists"]


def symbols(value):
    result = sorted({symbol(item) for item in value.split(",") if item})
    if not result or len(result) > 70:
        raise ValueError("Choose between 1 and 70 symbols.")
    return result


def raw(row, key):
    value = row.get(key)
    return number(value.get("raw")) if isinstance(value, dict) else None


def sector(slug, request=authenticated):
    group = next((group for group in presets() if group["id"] == slug), None)
    if not group:
        raise ValueError("Unknown market sector.")
    data = request("/v1/finance/sectors/" + slug).get("data") or {}
    if data.get("key") != slug or not isinstance(data.get("topCompanies"), list) or not data["topCompanies"]:
        raise ValueError("Yahoo returned an incomplete sector response.")
    quotes = {}
    for row in data["topCompanies"]:
        ticker = row.get("symbol")
        if ticker in quotes:
            raise ValueError("Yahoo returned duplicate sector symbols.")
        quotes[ticker] = row
    rows = []
    for member in group["members"]:
        quote = quotes.get(member["symbol"], {})
        change, ytd = raw(quote, "regMarketChangePercent"), raw(quote, "ytdReturn")
        rows.append({**member, "name": member.get("name") or quote.get("name") or member["symbol"],
                     "price": raw(quote, "lastPrice"), "percent": change * 100 if change is not None else None,
                     "ytd": ytd * 100 if ytd is not None else None, "marketCap": raw(quote, "marketCap")})
    return {"sector": slug, "name": group["name"], "rows": rows, "source": group["source"],
            "coverage": sum(row["percent"] is not None for row in rows)}


def parse_quotes(document, tickers):
    response = document.get("quoteResponse") or {}
    if response.get("error") or not isinstance(response.get("result"), list):
        raise ValueError("Yahoo returned an invalid bulk quote response.")
    rows = {}
    for quote in response["result"]:
        ticker = quote.get("symbol")
        if ticker not in tickers:
            continue
        if ticker in rows:
            raise ValueError("Yahoo returned duplicate quotes.")
        currency, scale = quote_units(quote.get("currency", ""))
        price = number(quote.get("regularMarketPrice"))
        change = number(quote.get("regularMarketChange"))
        rows[ticker] = {"symbol": ticker, "price": price * scale if price is not None else None,
                        "change": change * scale if change is not None else None, "marketCap": number(quote.get("marketCap")),
                        "percent": number(quote.get("regularMarketChangePercent")),
                        "currency": currency, "updated": number(quote.get("regularMarketTime")),
                        "marketState": quote.get("marketState") if quote.get("marketState") in ("REGULAR", "PRE", "PREPRE", "POST", "POSTPOST", "CLOSED") else ""}
    if not rows:
        raise ValueError("Yahoo returned no quotes for the requested symbols.")
    for ticker in tickers:
        rows.setdefault(ticker, {"symbol": ticker, "price": None, "percent": None, "error": "Bulk quote unavailable"})
    return {"rows": rows, "source": "Yahoo Finance", "quotesSchema": 3}


def quotes(tickers, request=authenticated):
    return parse_quotes(request("/v7/finance/quote", symbols=",".join(tickers)), tickers)
