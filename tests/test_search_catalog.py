from collections import Counter
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import stocks
from search_catalog import CATALOG, merge_results


def symbols(query, remote=()):
    return [row["symbol"] for row in merge_results(query, remote)]


class SearchCatalogTests(unittest.TestCase):
    def test_catalog_coverage_and_unique_symbols(self):
        self.assertEqual(Counter(row["type"] for row in CATALOG), {"INDEX": 21, "ETF": 28, "MUTUALFUND": 7})
        self.assertEqual(len(set(row["symbol"] for row in CATALOG)), len(CATALOG))
        for row in CATALOG:
            self.assertEqual(symbols(row["symbol"])[0], row["symbol"])

    def test_nasdaq_discovery_without_yahoo_results(self):
        result = symbols("nasdaq")
        self.assertEqual(set(result[:2]), {"^IXIC", "^NDX"})
        self.assertTrue({"QQQ", "QQQM"}.issubset(result))
        for query in ("nasdaq100", "Nasdaq-100", "nasdaq 100"):
            self.assertEqual(symbols(query), ["^NDX", "QQQ", "QQQM"])
        self.assertEqual(symbols("nasdaq etf"), ["QQQ", "QQQM"])

    def test_spx_and_punctuation_variants(self):
        for query in ("SPX", "^spx", "sp500", "S&P500", "S&P 500"):
            result = symbols(query)
            self.assertEqual(result[0], "^SPX")
            self.assertTrue({"VOO", "SPY", "IVV", "SPYM", "VFIAX", "FXAIX", "SWPPX"}.issubset(result))
        self.assertEqual(symbols("vanguard sp500"), ["VOO", "VFIAX"])
        self.assertEqual(symbols("sp500 mutual fund"), ["VFIAX", "FXAIX", "SWPPX"])

    def test_provider_scope_and_common_aliases(self):
        self.assertEqual(symbols("dow"), ["^DJI", "DIA"])
        self.assertEqual(symbols("footsie"), ["^FTSE"])
        self.assertEqual(symbols("fear index"), ["^VIX"])
        self.assertEqual(symbols("vanguard total stock market"), ["VTI", "VTSAX"])
        self.assertEqual(symbols("fidelity sp500"), ["FXAIX"])
        self.assertEqual(symbols("nasdaq madeupword"), [])
        self.assertEqual(symbols(""), [])

    def test_remote_exact_ticker_wins_and_known_duplicates_use_catalog(self):
        remote = [{"symbol": "NASDAQ", "name": "Example exact ticker", "type": "EQUITY", "exchange": "Example"},
                  {"symbol": "QQQM", "name": "Provider name", "type": "ETF", "exchange": "NASDAQ"}]
        result = merge_results("nasdaq", remote)
        self.assertEqual(result[0]["symbol"], "NASDAQ")
        self.assertEqual([r["symbol"] for r in result].count("QQQM"), 1)
        self.assertEqual(next(r["name"] for r in result if r["symbol"] == "QQQM"), "Invesco NASDAQ 100 ETF")

    def test_alternate_symbols_return_canonical_instrument(self):
        remote = [{"symbol": "^GSPC", "name": "S&P 500", "type": "INDEX", "exchange": "SNP"},
                  {"symbol": "^SPX", "name": "S&P 500", "type": "INDEX", "exchange": "SNP"}]
        result = symbols("sp500", remote)
        self.assertEqual(result.count("^SPX"), 1)
        self.assertNotIn("^GSPC", result)
        self.assertEqual(symbols("splg"), ["SPYM"])

    def test_curated_listing_precedes_remote_shorter_name_but_not_exact_ticker(self):
        remote = [{"symbol": "VOOCO.CL", "name": "Vanguard S&P 500", "type": "ETF", "exchange": "Santiago"}]
        self.assertEqual(symbols("vanguard sp500", remote), ["VOO", "VFIAX", "VOOCO.CL"])
        self.assertEqual(symbols("VOOCO.CL", remote), ["VOOCO.CL"])

    @patch.object(stocks, "fetch", side_effect=ValueError("Offline"))
    def test_provider_failure_keeps_local_matches_and_reports_error(self, fetch):
        result = stocks.search("nasdaq 100")
        self.assertEqual([row["symbol"] for row in result["results"]], ["^NDX", "QQQ", "QQQM"])
        self.assertEqual(result["error"], "Offline")
        self.assertEqual(result["query"], "nasdaq 100")

    @patch.object(stocks, "fetch", return_value={"quotes": [
        {"symbol": "AAPL", "longname": "Apple Inc.", "quoteType": "EQUITY", "exchDisp": "NASDAQ"},
        {"symbol": "FUT=F", "quoteType": "FUTURE"}]})
    def test_regular_stock_search_and_type_filter_are_preserved(self, fetch):
        result = stocks.search("apple")
        self.assertEqual([row["symbol"] for row in result["results"]], ["AAPL"])
        self.assertEqual(result["error"], "")
