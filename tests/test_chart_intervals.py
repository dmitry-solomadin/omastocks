from datetime import datetime
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import stocks
import extended
import research


def stamp(day, hour, minute=30):
    return int(datetime(2026, 9, day, hour, minute, tzinfo=ZoneInfo("America/New_York")).timestamp())


def document(day=25, end=16, hours=range(9, 16)):
    return {"chart": {"result": [{
        "meta": {"currency": "USD", "exchangeTimezoneName": "America/New_York",
                 "regularMarketPrice": 107, "currentTradingPeriod": {"regular": {"start": stamp(day, 9), "end": stamp(day, end, 0)}},
                 "tradingPeriods": [[{"start": stamp(day, 9), "end": stamp(day, end, 0)}]]},
        "timestamp": [stamp(day, hour) for hour in hours],
        "indicators": {"quote": [{"close": list(range(100, 100 + len(hours))), "volume": [10] * len(hours)}]}
    }]}}


class ChartIntervals(unittest.TestCase):
    def test_day_closing_marker_keeps_price_but_omits_volume(self):
        data = document()
        source = data["chart"]["result"][0]
        source["timestamp"].append(stamp(25, 16, 0))
        source["indicators"]["quote"][0]["close"].append(108)
        source["indicators"]["quote"][0]["volume"].append(0)
        source["indicators"]["quote"][0]["volume"][-2] = 0
        result = stocks.parse_chart(data, "AMD", "1D")
        self.assertEqual(result["points"][-1], (stamp(25, 16, 0), 108))
        self.assertIsNone(result["volumes"][-1])
        self.assertEqual(result["volumes"][-2], 0, "Real zero-volume candles remain reportable")
        source["indicators"]["quote"][0]["volume"][-1] = 50
        self.assertEqual(stocks.parse_chart(data, "AMD", "1D")["volumes"][-1], 50)

    def test_day_live_quote_keeps_its_price_and_time_without_volume(self):
        data = document(hours=range(9, 14))
        source = data["chart"]["result"][0]
        source["meta"]["regularMarketTime"] = stamp(25, 13, 41)
        source["timestamp"].append(stamp(25, 13, 41))
        source["indicators"]["quote"][0]["close"].append(108)
        source["indicators"]["quote"][0]["volume"].append(0)
        result = stocks.parse_chart(data, "AMD", "1D")
        self.assertEqual(result["points"][-2:], [(stamp(25, 13), 104), (stamp(25, 13, 41), 108)])
        self.assertEqual(result["volumes"][-2:], [10, None])
        # Found by its quote time, not only at today's session end.
        source["meta"]["currentTradingPeriod"]["regular"] = {"start": stamp(26, 9), "end": stamp(26, 16, 0)}
        self.assertIsNone(stocks.parse_chart(data, "AMD", "1D")["volumes"][-1])

    def test_week_bar_takes_the_trailing_quote_price_and_keeps_its_volume(self):
        def week(quote, hours=range(9, 16)):
            data = document(hours=hours)
            source = data["chart"]["result"][0]
            source["meta"]["regularMarketTime"] = quote
            source["timestamp"].append(quote)
            source["indicators"]["quote"][0]["close"].append(108)
            source["indicators"]["quote"][0]["volume"].append(0)
            return data
        # Live price during the 13:30 bar, and the closing price after 15:30's.
        for hours, quote, bar in ((range(9, 14), stamp(25, 13, 41), stamp(25, 13)),
                                  (range(9, 16), stamp(25, 16, 0), stamp(25, 15))):
            with self.subTest(quote=quote):
                result = stocks.parse_chart(week(quote, hours), "AMD", "1W")
                self.assertEqual(result["points"][-1], (bar, 108))
                self.assertEqual(len(result["points"]), len(hours))
                self.assertEqual(result["volumes"][-1], 10)
                self.assertEqual(len(result["dates"]), len(hours))
        # A quote past its bar, before the next bar arrives, has no volume of its own.
        result = stocks.parse_chart(week(stamp(25, 14, 5), range(9, 14)), "AMD", "1W")
        self.assertEqual(result["points"][-1], (stamp(25, 14, 5), 108))
        self.assertIsNone(result["volumes"][-1])
        # A real zero-volume bar is not a quote.
        data = document()
        data["chart"]["result"][0]["indicators"]["quote"][0]["volume"][-1] = 0
        self.assertEqual(stocks.parse_chart(data, "AMD", "1W")["volumes"][-1], 0)

    def test_month_has_three_samples_per_full_session_with_volume_totals(self):
        data = document()
        result = stocks.parse_chart(data, "AMD", "1M")
        self.assertEqual([point[1] for point in result["points"]], [102, 104, 106])
        self.assertEqual([point[0] for point in result["points"]], [stamp(25, 11), stamp(25, 13), stamp(25, 15)])
        self.assertEqual(result["volumes"], [30, 20, 20])
        self.assertEqual(result["dates"], ["2026-09-25"] * 3)
        # An unfinished morning cannot shift existing groups into new slots.
        partial = stocks.parse_chart(document(hours=range(9, 11)), "AMD", "1M")
        self.assertEqual(partial["points"], [(stamp(25, 10), 101)])

    def test_early_close_uses_its_own_session_and_keeps_the_closing_quote(self):
        data = document(end=13, hours=range(9, 13))
        row = data["chart"]["result"][0]
        row["timestamp"].append(stamp(25, 13, 0))
        row["indicators"]["quote"][0]["close"].append(105)
        row["indicators"]["quote"][0]["volume"].append(0)
        result = stocks.parse_chart(data, "AMD", "1M")
        self.assertEqual([point[1] for point in result["points"]], [101, 102, 105])
        self.assertEqual(result["volumes"], [20, 10, 10])
        self.assertEqual(len(result["points"]), 3)

    def test_sessions_do_not_mix_days_or_invent_missing_volume(self):
        data = document(day=24)
        row = data["chart"]["result"][0]
        next_day = document(day=25)["chart"]["result"][0]
        row["meta"]["tradingPeriods"] += next_day["meta"]["tradingPeriods"]
        row["timestamp"] += next_day["timestamp"]
        for field in ("close", "volume"):
            row["indicators"]["quote"][0][field] += next_day["indicators"]["quote"][0][field]
        row["indicators"]["quote"][0]["volume"][0] = None
        result = stocks.parse_chart(data, "AMD", "1M")
        self.assertEqual(result["dates"], ["2026-09-24"] * 3 + ["2026-09-25"] * 3)
        self.assertEqual(result["volumes"], [None, 20, 20, 30, 20, 20])

    def test_new_intervals_invalidate_old_chart_cache_and_apply_to_comparison(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(stocks, "fetch", return_value=document()) as request:
            repo = stocks.Repository(Path(directory))
            repo.cache["AMD:1D"] = {"schema": 2, "fetched": stocks.time.time(), "price": 123}
            result = repo.chart("AMD", "1D")
            self.assertEqual(request.call_args.kwargs["interval"], "1m")
            self.assertEqual(result["schema"], stocks.CHART_SCHEMA)
            repo.chart("AMD", "1M")
            self.assertEqual(request.call_args.kwargs["interval"], "1h")
        with patch.object(research, "fetch", return_value=document()) as request:
            result = research.load("compare", "AMD", "1M")
            self.assertEqual(request.call_args.kwargs["interval"], "1h")
            self.assertEqual(len(result["points"]), 3)
        with patch.object(extended, "fetch", return_value=document()) as request:
            extended.extended("AMD")
            self.assertEqual(request.call_args.kwargs["interval"], "1m")


if __name__ == "__main__":
    unittest.main()
