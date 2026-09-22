import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("stocks", Path(__file__).parents[1] / "bin/stocks.py")
stocks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stocks)

SAMPLE = {"chart": {"result": [{
    "meta": {"regularMarketPrice": 105, "chartPreviousClose": 100, "currency": "USD",
             "regularMarketTime": 30, "regularMarketDayHigh": 106, "fiftyTwoWeekHigh": 120},
    "timestamp": [10, 20, 30, 40],
    "indicators": {"quote": [{"close": [101, None, 105, float("nan")], "open": [100, None, 104]}]},
}]}}


class ChartTests(unittest.TestCase):
    def test_volume_preserves_timestamp_alignment_and_missing_values(self):
        data = copy.deepcopy(SAMPLE)
        data["chart"]["result"][0]["indicators"]["quote"][0]["volume"] = [100, 200, None, 400]
        result = stocks.parse_chart(data, "AAPL", "1D")
        self.assertEqual(result["volumes"], [100, None])
        self.assertEqual(len(result["dates"]), len(result["points"]))

    def test_dividends_use_quote_currency_units(self):
        data = copy.deepcopy(SAMPLE)
        source = data["chart"]["result"][0]
        source["meta"]["currency"] = "GBp"
        source["events"] = {"dividends": {"10": {"date": 10, "amount": 25}},
                            "splits": {"30": {"date": 30, "splitRatio": "4:1"}}}
        result = stocks.parse_chart(data, "HSBA.L", "1Y")
        self.assertEqual(result["events"][0]["amount"], .25)
        self.assertEqual(result["events"][1]["ratio"], "4:1")

    def test_null_bars_are_removed_without_shifting_timestamps(self):
        result = stocks.parse_chart(SAMPLE, "AAPL", "1D")
        self.assertEqual(result["points"], [(10, 101), (30, 105)])
        self.assertEqual(result["percent"], 5)
        self.assertEqual(result["previous"], 100)
        json.dumps(result, allow_nan=False)

    def test_historical_baseline_is_not_presented_as_daily_change(self):
        result = stocks.parse_chart(SAMPLE, "AAPL", "1Y")
        self.assertIsNone(result["change"])
        self.assertIsNone(result["previous"])

    def test_pence_quotes_and_history_have_the_same_units(self):
        data = copy.deepcopy(SAMPLE)
        data["chart"]["result"][0]["meta"]["currency"] = "GBp"
        result = stocks.parse_chart(data, "HSBA.L", "1D")
        self.assertEqual(result["currency"], "GBP")
        self.assertEqual(result["price"], 1.05)
        self.assertEqual(result["points"][-1][1], 1.05)
        self.assertEqual(result["yearHigh"], 1.2)
        self.assertAlmostEqual(result["percent"], 5)

    def test_absent_previous_close_is_not_zero_change(self):
        data = copy.deepcopy(SAMPLE)
        del data["chart"]["result"][0]["meta"]["chartPreviousClose"]
        result = stocks.parse_chart(data, "AAPL", "1D")
        self.assertIsNone(result["change"])
        self.assertIsNone(result["percent"])

    def test_regular_session_uses_provider_hours_including_early_close(self):
        data = copy.deepcopy(SAMPLE)
        data["chart"]["result"][0]["meta"]["currentTradingPeriod"] = {
            "pre": {"start": 1, "end": 10},
            "regular": {"start": 10, "end": 50},
            "post": {"start": 50, "end": 100},
        }
        result = stocks.parse_chart(data, "AAPL", "1D")
        self.assertEqual((result["sessionStart"], result["sessionEnd"]), (10, 50))
        historical = stocks.parse_chart(data, "AAPL", "1M")
        self.assertIsNone(historical["sessionStart"])
        self.assertIsNone(historical["sessionEnd"])

    def test_missing_or_invalid_session_does_not_invent_market_hours(self):
        for regular in ({}, {"start": 20, "end": 10}, {"start": 10, "end": float("inf")}):
            with self.subTest(regular=regular):
                data = copy.deepcopy(SAMPLE)
                data["chart"]["result"][0]["meta"]["currentTradingPeriod"] = {"regular": regular}
                result = stocks.parse_chart(data, "AAPL", "1D")
                self.assertIsNone(result["sessionStart"])
                self.assertIsNone(result["sessionEnd"])


class StateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.repository = stocks.Repository(self.path)

    def test_empty_watchlist_survives_restart(self):
        for ticker, _ in stocks.SEED:
            self.repository.mutate("remove", ticker)
        self.assertEqual(stocks.Repository(self.path).snapshot()["entries"], [])

    def test_remove_then_undo_restores_favorite(self):
        self.repository.mutate("remove", "AAPL")
        self.assertFalse(any(entry["symbol"] == "AAPL" for entry in self.repository.snapshot()["entries"]))
        self.repository.mutate("add", "AAPL", "Apple", True)
        restored = stocks.Repository(self.path).snapshot()["entries"][-1]
        self.assertEqual((restored["symbol"], restored["favorite"]), ("AAPL", True))

    def test_move_persists_order_and_preserves_stock_metadata(self):
        original = copy.deepcopy(self.repository.state["entries"])
        self.repository.move("AMZN", "MSFT")
        reopened = stocks.Repository(self.path)
        self.assertEqual([entry["symbol"] for entry in reopened.state["entries"]],
                         ["AAPL", "AMZN", "MSFT", "NVDA", "GOOGL"])
        self.assertEqual(sorted(reopened.state["entries"], key=lambda entry: entry["symbol"]),
                         sorted(original, key=lambda entry: entry["symbol"]))
        reopened.move("AAPL")
        self.assertEqual([entry["symbol"] for entry in stocks.Repository(self.path).state["entries"]],
                         ["AMZN", "MSFT", "NVDA", "GOOGL", "AAPL"])

    def test_moves_use_symbols_after_other_watchlist_edits(self):
        self.repository.mutate("remove", "MSFT")
        self.repository.mutate("add", "AMD", "AMD")
        self.repository.move("AMD", "NVDA")
        self.repository.move("AAPL", "AMD")
        self.assertEqual([entry["symbol"] for entry in self.repository.state["entries"]],
                         ["AAPL", "AMD", "NVDA", "GOOGL", "AMZN"])

    def test_stale_move_or_self_drop_does_not_damage_watchlist(self):
        self.repository.move("AMZN", "AAPL")
        original = self.repository.state_path.read_text()
        self.repository.move("AAPL", "AAPL")
        for ticker, before in [("UNKNOWN", "AAPL"), ("AAPL", "UNKNOWN")]:
            with self.subTest(ticker=ticker, before=before):
                with self.assertRaisesRegex(ValueError, "watchlist changed"):
                    self.repository.move(ticker, before)
                self.assertEqual(self.repository.state_path.read_text(), original)

    def test_corrupt_watchlist_is_not_overwritten(self):
        original = "{not valid json"
        (self.path / "watchlist.json").write_text(original)
        with self.assertRaisesRegex(ValueError, "left untouched"):
            stocks.Repository(self.path)
        self.assertEqual((self.path / "watchlist.json").read_text(), original)

    @patch.object(stocks, "fetch", return_value=SAMPLE)
    def test_failed_refresh_keeps_price_and_timestamp_then_recovers(self, request):
        initial = self.repository.chart("AAPL", "1D")
        request.side_effect = ValueError("offline")
        failed = self.repository.chart("AAPL", "1D", force=True)
        self.assertEqual(failed["price"], initial["price"])
        self.assertEqual(failed["fetched"], initial["fetched"])
        self.assertTrue(failed["stale"])
        with patch.object(stocks.time, "time", return_value=failed["retryAfter"] + 1):
            request.side_effect = None
            recovered = self.repository.chart("AAPL", "1D", force=True)
        self.assertFalse(recovered["stale"])
        self.assertEqual(recovered["error"], "")

    @patch.object(stocks, "fetch", return_value=SAMPLE)
    def test_fresh_cache_prevents_duplicate_requests(self, request):
        self.repository.chart("AAPL", "1D")
        self.repository.chart("AAPL", "1D")
        request.assert_called_once()

    @patch.object(stocks, "fetch", side_effect=ValueError("rate limiting"))
    def test_failed_symbol_backs_off_even_on_force(self, request):
        self.repository.chart("AAPL", "1D")
        self.repository.chart("AAPL", "1D", force=True)
        request.assert_called_once()


if __name__ == "__main__":
    unittest.main()
