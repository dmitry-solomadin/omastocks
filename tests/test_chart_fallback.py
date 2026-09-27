import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import stocks


def response(points):
    return {"chart": {"result": [{"meta": {
        "regularMarketPrice": 7803, "regularMarketTime": 1790369999,
        "chartPreviousClose": 7750, "currency": "USD", "instrumentType": "FUTURE",
        "exchangeTimezoneName": "America/New_York",
        "currentTradingPeriod": {"regular": {"start": 1790481600, "end": 1790567940}},
    }, "timestamp": [point[0] for point in points],
        "indicators": {"quote": [{"close": [point[1] for point in points]}]}}]}}


class ChartFallback(unittest.TestCase):
    def test_empty_day_fetches_overnight_history_once_and_preserves_daily_baseline(self):
        history = response([(1790287200, 7780), (1790369999, 7803)])
        history["chart"]["result"][0]["meta"]["chartPreviousClose"] = 7700
        with patch.object(stocks.time, "time", return_value=1790530000), patch.object(stocks, "fetch", side_effect=[response([]), history]) as fetch:
            row = stocks.fetch_full_chart("ES=F", "1D")
        self.assertEqual(fetch.call_count, 2)
        query = fetch.call_args.kwargs
        self.assertEqual(query["period1"], 1790369999 - 86400 + 1)
        self.assertEqual(query["period2"], 1790369999 + 1)
        self.assertEqual(query["interval"], "1m")
        self.assertEqual(len(row["points"]), 2)
        self.assertEqual(row["previous"], 7750)
        self.assertEqual(row["change"], 53)
        self.assertEqual(row["sessionStart"], 1790287200)
        self.assertTrue(row["lastSessionFallback"])

    def test_nonempty_day_never_uses_fallback(self):
        with patch.object(stocks, "fetch", return_value=response([(1790369999, 7803)])) as fetch:
            row = stocks.fetch_full_chart("ES=F", "1D")
        self.assertEqual(fetch.call_count, 1)
        self.assertNotIn("lastSessionFallback", row)

    def test_empty_fallback_is_bounded_and_other_ranges_do_not_fallback(self):
        for period, expected in (("1D", 2), ("1W", 1)):
            with self.subTest(period=period), patch.object(stocks.time, "time", return_value=1790530000), patch.object(stocks, "fetch", return_value=response([])) as fetch:
                with self.assertRaisesRegex(ValueError, "No chart candles"):
                    stocks.fetch_full_chart("ES=F", period)
                self.assertEqual(fetch.call_count, expected)
