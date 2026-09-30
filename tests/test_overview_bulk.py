import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bin"))
from overview import bulk


class BulkOverviewTests(unittest.TestCase):
    def test_batches_and_maps_history_by_symbol(self):
        calls = []
        tickers = [f"S{i}" for i in range(45)]

        def request(endpoint, **parameters):
            calls.append(parameters)
            self.assertEqual(endpoint, "/v7/finance/spark")
            return {"spark": {"result": [
                {"symbol": symbol, "response": [{"symbol": symbol}]}
                for symbol in reversed(parameters["symbols"].split(","))]}}

        def performance(document, symbol):
            self.assertEqual(document["chart"]["result"][0]["symbol"], symbol)
            return {"symbol": symbol}

        with patch("overview.performance", side_effect=performance):
            result = bulk(tickers, request)
        self.assertEqual(set(result["rows"]), set(tickers))
        self.assertEqual([len(call["symbols"].split(",")) for call in calls], [20, 20, 5])
        self.assertTrue(all(call["range"] == "2y" and call["interval"] == "1d" for call in calls))

    def test_missing_symbol_rejects_incomplete_cache(self):
        with self.assertRaises(ValueError):
            bulk(["AMD"], lambda *args, **kwargs: {"spark": {"result": []}})


if __name__ == "__main__":
    unittest.main()
