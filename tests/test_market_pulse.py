import sys
from datetime import datetime, timezone
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import market_pulse


class Sentiment(unittest.TestCase):
    def test_score_and_comparisons(self):
        result = market_pulse.sentiment(fetch=lambda url, headers: {"fear_and_greed": {
            "score": 36.9, "rating": "fear", "previous_close": 35.2, "previous_1_week": 27.3,
            "previous_1_month": 54.7, "previous_1_year": 56.8, "timestamp": "2026-09-23T15:29:58+00:00"}})
        self.assertEqual((result["score"], result["rating"], result["previousWeek"]), (36.9, "fear", 27.3))

    def test_unexpected_response_is_rejected(self):
        for document in ({}, {"fear_and_greed": []}, {"fear_and_greed": "unavailable"},
                         {"fear_and_greed": {"score": 140, "rating": "greed"}}, {"fear_and_greed": {"score": 50}}):
            with self.assertRaises(ValueError):
                market_pulse.sentiment(fetch=lambda url, headers: document)


class Calendar(unittest.TestCase):
    def test_keeps_high_importance_sorted(self):
        seen = {}

        def fetch(url, headers):
            seen["url"] = url
            return {"result": [
                {"id": "2", "title": "Non Farm Payrolls", "importance": 1, "date": "2026-10-02T12:30:00.000Z",
                 "period": "Sep", "previous": 162, "forecast": None, "actual": None, "scale": "K"},
                {"id": "1", "title": "Fed Barkin Speech", "importance": 0, "date": "2026-09-24T12:00:00.000Z"},
                {"id": "3", "title": "Durable Goods Orders MoM", "importance": 1, "date": "2026-09-25T12:30:00.000Z",
                 "unit": "%", "previous": 1.1, "forecast": -0.4},
                {"id": "4", "title": "Broken date", "importance": 1, "date": "not a date"}]}

        result = market_pulse.economic_calendar(now=datetime(2026, 9, 23, tzinfo=timezone.utc), fetch=fetch)
        self.assertIn("countries=US", seen["url"])
        self.assertEqual([event["id"] for event in result["events"]], ["3", "2"])
        self.assertEqual((result["events"][0]["unit"], result["events"][0]["forecast"]), ("%", -0.4))
        self.assertEqual(result["events"][1]["scale"], "K")

    def test_unexpected_response_is_rejected(self):
        with self.assertRaises(ValueError):
            market_pulse.economic_calendar(fetch=lambda url, headers: {"status": "error"})

    def test_calendar_rejects_ambiguous_times_and_out_of_window_events(self):
        dates = ["2026-09-25T12:30:00", "2026-01-01T12:30:00Z", "2026-12-01T12:30:00Z", "2026-09-25T12:30:00Z"]
        document = {"result": [{"title": "US GDP", "importance": 1, "date": day} for day in dates]}
        result = market_pulse.economic_calendar(datetime(2026, 9, 23, tzinfo=timezone.utc), fetch=lambda *_: document)
        self.assertEqual(len(result["events"]), 1)
        self.assertEqual(result["events"][0]["time"], datetime(2026, 9, 25, 12, 30, tzinfo=timezone.utc).timestamp())


if __name__ == "__main__":
    unittest.main()
