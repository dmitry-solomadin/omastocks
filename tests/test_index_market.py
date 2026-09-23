import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import index_market
import research


def group():
    return {"id": "sp500", "name": "S&P 500", "source": "https://www.tradingview.com/symbols/SP-SPX/components/",
            "retrievedAt": "2026-09-22T00:00:00+00:00", "members": [
                {"symbol": "BRK-B", "name": "Berkshire", "providerSymbol": "NYSE:BRK.B"},
                {"symbol": "AAA", "name": "Alpha", "providerSymbol": "NASDAQ:AAA"}]}


def quote(identifier="NYSE:BRK.B", change=-2, cap=500, ytd=0):
    return {"s": identifier, "d": [identifier.split(":")[1], "Company", 100, change, cap, ytd, "USD"]}


class IndexMarket(unittest.TestCase):
    def test_bulk_values_preserve_percentage_units_zeros_and_missing_members(self):
        result = index_market.parse({"totalCount": 1, "data": [quote()]}, group())
        first, missing = result["rows"]
        self.assertEqual(first["symbol"], "BRK-B")
        self.assertEqual(first["percent"], -2)
        self.assertEqual(first["ytd"], 0)
        self.assertEqual(first["marketCap"], 500)
        self.assertIsNone(missing["marketCap"])
        self.assertIsNone(missing["percent"])
        self.assertEqual(result["coverage"], 1)

    def test_one_request_for_two_thousand_saved_exchange_qualified_listings(self):
        saved = group()
        saved["members"] = [{"symbol": f"S{i}", "name": f"Stock {i}", "providerSymbol": f"NASDAQ:S{i}"} for i in range(2000)]
        fetch = Mock(return_value={"totalCount": 2000, "data": [quote(row["providerSymbol"]) for row in saved["members"]]})
        with patch.object(index_market, "presets", return_value=[saved]):
            result = index_market.index("sp500", fetch)
        self.assertEqual(len(result["rows"]), 2000)
        self.assertEqual(fetch.call_count, 1)
        self.assertEqual(fetch.call_args.args[0]["symbols"]["tickers"], [row["providerSymbol"] for row in saved["members"]])
        self.assertEqual(fetch.call_args.args[0]["range"], [0, 2000])

    def test_truncated_duplicate_unrequested_and_misaligned_responses_are_rejected(self):
        malformed = quote(); malformed["d"][0] = "OTHER"
        for document in [{"totalCount": 2, "data": [quote()]}, {"totalCount": 0, "data": []},
                         {"totalCount": 2, "data": [quote(), quote()]},
                         {"totalCount": 1, "data": [quote("NASDAQ:UNREQUESTED")]},
                         {"totalCount": 1, "data": [malformed]},
                         {"totalCount": 1, "data": [{"s": "NYSE:BRK.B", "d": []}]}]:
            with self.subTest(document=document), self.assertRaises(ValueError):
                index_market.parse(document, group())

    def test_invalid_caps_and_returns_remain_missing(self):
        result = index_market.parse({"totalCount": 1, "data": [quote(change=True, cap=-1, ytd="NaN")]}, group())
        self.assertIsNone(result["rows"][0]["marketCap"])
        self.assertIsNone(result["rows"][0]["percent"])
        self.assertIsNone(result["rows"][0]["ytd"])

    def test_local_catalog_includes_all_three_unique_complete_snapshots(self):
        groups = index_market.presets()
        self.assertEqual([g["id"] for g in groups], ["sp500", "nasdaq100", "russell2000"])
        for saved in groups:
            self.assertEqual(saved["count"], len(saved["members"]))
            self.assertEqual(saved["count"], len({row["symbol"] for row in saved["members"]}))
            self.assertEqual(saved["count"], len({row["providerSymbol"] for row in saved["members"]}))
        self.assertGreater(groups[-1]["count"], 1800)

    def test_catalog_upgrade_and_index_failure_keep_saved_snapshot(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"STOCKS_STATE_DIR": directory}):
            with patch.object(research, "load", return_value={"sectors": []}):
                research.main(["sectors", "ALL"])
            catalog = research.main(["sectors", "ALL"])["sectors"]
            self.assertEqual(len(catalog), 13)
            self.assertNotIn("russell2000", [row["value"] for row in catalog])
            saved = index_market.parse({"totalCount": 1, "data": [quote()]}, group())
            with patch.object(research, "load", return_value=saved) as load:
                original = research.main(["market-index", "SP500"])
                self.assertEqual(research.main(["market-index", "SP500"]), original)
                self.assertEqual(load.call_count, 1)
                load.side_effect = ValueError("Incomplete response")
                failed = research.main(["market-index", "SP500", "--force"])
                self.assertEqual(failed["rows"], saved["rows"])
                self.assertTrue(failed["stale"])


if __name__ == "__main__":
    unittest.main()
