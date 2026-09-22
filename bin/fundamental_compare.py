"""Comparable statement snapshots with explicit fiscal dates and currencies."""

import concurrent.futures
from financials import statements, valuation


FIELDS = [("income", "revenueGrowth", "Revenue growth YoY", "percent"),
          ("income", "grossMargin", "Gross margin", "percent"),
          ("income", "operatingMargin", "Operating margin", "percent"),
          ("income", "netMargin", "Net margin", "percent"),
          ("cash", "fcfMargin", "FCF margin", "percent"),
          ("income", "TotalRevenue", "Revenue", "money"),
          ("cash", "FreeCashFlow", "Free cash flow", "money"),
          ("balance", "NetDebt", "Net debt", "money"),
          ("balance", "debtEquity", "Debt / equity", "ratio")]


def summarize(financial, value, ticker, frequency):
    cells = []
    for section, key, label, kind in FIELDS:
        statement = next((row for row in financial.get("statements", []) if row["id"] == section), {})
        dates = statement.get("dates", [])
        row = next((row for row in statement.get("rows", []) if row["key"] == key), {})
        values, currencies = row.get("values", []), row.get("currencies", [])
        # Do not substitute an older populated period for a missing latest value.
        cells.append({"key": key, "label": label, "kind": kind,
                      "value": values[0] if values else None,
                      "currency": currencies[0] if currencies else "", "date": dates[0] if dates else ""})
    for index, row in enumerate(value.get("metrics", [])):
        cells.append({**row, "key": "valuation" + str(index), "date": "Current snapshot"})
    return {"symbol": ticker, "frequency": frequency, "cells": cells,
            "sector": value.get("sector", ""), "industry": value.get("industry", ""),
            "source": "Yahoo Finance / TradingView"}


def fundamentals(ticker, frequency):
    if frequency not in ("annual", "quarterly"):
        raise ValueError("Choose annual or quarterly financials.")
    errors, results = [], []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        tasks = [pool.submit(statements, ticker, frequency), pool.submit(valuation, ticker)]
        for label, task in zip(("Financials", "Valuation"), tasks):
            try:
                results.append(task.result())
            except Exception as error:
                results.append({})
                errors.append(label + ": " + str(error))
    if all(not result for result in results):
        raise ValueError("; ".join(errors))
    return {**summarize(*results, ticker, frequency), "notice": "; ".join(errors)}
