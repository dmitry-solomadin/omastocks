"""Financial statements and valuation snapshots. Python standard library only."""

import re
import time
import urllib.parse
from datetime import date

from stocks import fetch, number
from tradingview import listings, request


STATEMENTS = {
    "income": ("Income", [
        ("TotalRevenue", "Revenue"), ("CostOfRevenue", "Cost of revenue"),
        ("GrossProfit", "Gross profit"), ("ResearchAndDevelopment", "Research & development"),
        ("SellingGeneralAndAdministration", "Selling & administration"),
        ("OperatingIncome", "Operating income"), ("EBITDA", "EBITDA"),
        ("NetIncome", "Net income"), ("DilutedEPS", "Diluted EPS"),
    ]),
    "balance": ("Balance Sheet", [
        ("CashAndCashEquivalents", "Cash & equivalents"),
        ("CashCashEquivalentsAndShortTermInvestments", "Cash & short-term investments"),
        ("CurrentAssets", "Current assets"), ("TotalAssets", "Total assets"),
        ("CurrentLiabilities", "Current liabilities"),
        ("TotalLiabilitiesNetMinorityInterest", "Total liabilities"),
        ("TotalDebt", "Total debt"), ("NetDebt", "Net debt"),
        ("StockholdersEquity", "Shareholders’ equity"),
    ]),
    "cash": ("Cash Flow", [
        ("OperatingCashFlow", "Operating cash flow"), ("CapitalExpenditure", "Capital expenditure"),
        ("FreeCashFlow", "Free cash flow"), ("InvestingCashFlow", "Investing cash flow"),
        ("FinancingCashFlow", "Financing cash flow"), ("RepurchaseOfCapitalStock", "Share repurchases"),
        ("CashDividendsPaid", "Dividends paid"),
    ]),
}


def parse_statements(document, ticker, frequency):
    if frequency not in ("annual", "quarterly"):
        raise ValueError("Choose annual or quarterly financials.")
    result = (document.get("timeseries") or {})
    if result.get("error"):
        raise ValueError("Financial statements are unavailable. Try again later.")
    fields = {key for _, metrics in STATEMENTS.values() for key, _ in metrics}
    records = {key: {} for key in fields}
    for row in result.get("result") or []:
        for field in fields:
            for cell in row.get(frequency + field) or []:
                if not isinstance(cell, dict):
                    continue
                day = cell.get("asOfDate", "")
                try:
                    date.fromisoformat(day)
                except (TypeError, ValueError):
                    continue
                if cell.get("periodType") != ("3M" if frequency == "quarterly" else "12M"):
                    continue
                value = number((cell.get("reportedValue") or {}).get("raw"))
                currency = cell.get("currencyCode") or ""
                if value is None or not re.fullmatch(r"[A-Z]{3}", currency):
                    continue
                records[field][day] = (value, currency)

    statements = []
    for section, (title, metrics) in STATEMENTS.items():
        dates = sorted({day for key, _ in metrics for day in records[key]}, reverse=True)[:5 if frequency == "quarterly" else 4]
        rows = []
        for key, label in metrics:
            if not records[key]:
                continue
            values = [records[key].get(day, (None, "")) for day in dates]
            rows.append({"key": key, "label": label, "kind": "perShare" if key == "DilutedEPS" else "money",
                         "values": [value for value, _ in values], "currencies": [unit for _, unit in values]})

        def ratio(key, label, numerator, denominator, percent=False):
            values = []
            for day in dates:
                top, unit = records[numerator].get(day, (None, ""))
                bottom, bottom_unit = records[denominator].get(day, (None, ""))
                values.append(top / bottom * (100 if percent else 1)
                              if top is not None and bottom is not None and bottom > 0 and unit == bottom_unit else None)
            if any(value is not None for value in values):
                rows.append({"key": key, "label": label, "kind": "percent" if percent else "ratio", "values": values, "currencies": [""] * len(dates)})

        if section == "income":
            ratio("grossMargin", "Gross margin", "GrossProfit", "TotalRevenue", True)
            ratio("operatingMargin", "Operating margin", "OperatingIncome", "TotalRevenue", True)
            ratio("netMargin", "Net margin", "NetIncome", "TotalRevenue", True)
            growth = []
            for day in dates:
                current, unit = records["TotalRevenue"].get(day, (None, ""))
                previous = next((value for old, value in records["TotalRevenue"].items()
                                 if int(old[:4]) == int(day[:4]) - 1 and old[5:7] == day[5:7]), (None, ""))
                growth.append((current / previous[0] - 1) * 100 if current is not None and previous[0] is not None
                              and previous[0] > 0 and previous[1] == unit else None)
            if any(value is not None for value in growth):
                rows.append({"key": "revenueGrowth", "label": "Revenue growth YoY", "kind": "percent", "values": growth, "currencies": [""] * len(dates)})
        elif section == "balance":
            ratio("currentRatio", "Current ratio", "CurrentAssets", "CurrentLiabilities")
            ratio("debtEquity", "Debt / equity", "TotalDebt", "StockholdersEquity")
        else:
            ratio("fcfMargin", "Free cash flow margin", "FreeCashFlow", "TotalRevenue", True)
        statements.append({"id": section, "title": title, "dates": dates, "rows": rows})
    return {"symbol": ticker, "frequency": frequency, "statements": statements, "source": "Yahoo Finance"}


def statements(ticker, frequency):
    if frequency not in ("annual", "quarterly"):
        raise ValueError("Choose annual or quarterly financials.")
    fields = [frequency + key for _, metrics in STATEMENTS.values() for key, _ in metrics]
    document = fetch("/ws/fundamentals-timeseries/v1/finance/timeseries/" + urllib.parse.quote(ticker, safe=""),
                     symbol=ticker, type=",".join(fields), period1=1483142400, period2=int(time.time()) + 86400)
    return parse_statements(document, ticker, frequency)


VALUATION_FIELDS = ["market_cap_basic", "price_earnings_ttm", "price_sales_current", "price_book_fq",
                    "enterprise_value_ebitda_ttm", "sector", "industry", "currency", "type"]


def parse_valuation(document, ticker):
    matches = [row for row in document.get("data") or []
               if row.get("s") in listings(ticker)
               and len(row.get("d") or []) == len(VALUATION_FIELDS)]
    if len(matches) != 1:
        return {"symbol": ticker, "metrics": [], "source": "TradingView"}
    values = dict(zip(VALUATION_FIELDS, matches[0]["d"]))
    currency = values.get("currency") or ""
    if values.get("type") not in ("stock", "dr") or not re.fullmatch(r"[A-Z]{3}", currency):
        return {"symbol": ticker, "metrics": [], "source": "TradingView"}
    metrics = []
    for key, label, kind in [("market_cap_basic", "Market cap", "money"), ("price_earnings_ttm", "P/E (TTM)", "ratio"),
                              ("price_sales_current", "Price / sales", "ratio"), ("price_book_fq", "Price / book", "ratio"),
                              ("enterprise_value_ebitda_ttm", "EV / EBITDA", "ratio")]:
        value = number(values[key])
        metrics.append({"label": label, "value": value, "kind": kind, "currency": currency if kind == "money" else ""})
    return {"symbol": ticker, "metrics": metrics, "sector": values.get("sector") or "", "industry": values.get("industry") or "", "source": "TradingView"}


def valuation(ticker):
    if not re.fullmatch(r"[A-Z][A-Z0-9.-]*", ticker):
        return {"symbol": ticker, "metrics": [], "source": "TradingView"}
    payload = {"symbols": {"tickers": listings(ticker), "query": {"types": []}},
               "columns": VALUATION_FIELDS}
    return parse_valuation(request(payload), ticker)
