"""Local discovery aliases supplement Yahoo's incomplete autocomplete results."""

import json
from pathlib import Path
import re
import unicodedata


CATALOG = json.loads(Path(__file__).with_suffix(".json").read_text())
BY_SYMBOL = {symbol: row for row in CATALOG for symbol in [row["symbol"], *row.get("alternateSymbols", [])]}


def normalize(value):
    value = unicodedata.normalize("NFKD", value.casefold())
    value = re.sub(r"\bu\.s\.?\b", "us", value)
    value = re.sub(r"\bs\s*&\s*p(?=\W|\d|$)", "sp", value)
    value = re.sub(r"([a-z])([0-9])", r"\1 \2", value)
    value = re.sub(r"([0-9])([a-z])", r"\1 \2", value)
    return " ".join(re.findall(r"[a-z0-9]+", value))


def public_row(row):
    return {key: row[key] for key in ("symbol", "name", "exchange", "type")}


def score(row, query):
    if not query:
        return 0
    if query == normalize(row["symbol"]):
        return 10000
    if query in [normalize(value) for value in row.get("alternateSymbols", [])]:
        return 9500
    name = normalize(row["name"])
    aliases = [normalize(value) for value in row.get("aliases", [])]
    kind = {"ETF": "etf fund", "MUTUALFUND": "mutual fund", "INDEX": "index"}.get(row["type"], "stock equity")
    words = (name + " " + normalize(row["symbol"]) + " " + " ".join(aliases) + " " + kind).split()
    tokens = query.split()
    if not all(any(word == token or len(token) >= 2 and word.startswith(token) for word in words) for token in tokens):
        return 0
    match = 900 if query == name else 800 if query in aliases else 300
    # Benchmark queries prefer the index; explicit fund/provider terms match funds.
    return match + (50 if row["type"] == "INDEX" else 0)


def merge_results(query, remote):
    query = normalize(query)
    if not query:
        return []
    rows = {row["symbol"]: row for row in CATALOG if score(row, query)}
    for row in remote:
        # Canonicalize alternate symbols (e.g. a former fund ticker) before deduping.
        row = BY_SYMBOL.get(row["symbol"], row)
        rows.setdefault(row["symbol"], row)
    def priority(row):
        relevance = score(row, query)
        # Prefer curated listings over alternate-market listings with shorter names,
        # while any exact ticker match still takes precedence.
        return relevance + (1000 if 0 < relevance < 9500 and row["symbol"] in BY_SYMBOL else 0)
    ranked = sorted(rows.values(), key=lambda row: -priority(row))
    return [public_row(row) for row in ranked]
