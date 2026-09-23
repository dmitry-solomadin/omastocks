import sys
from pathlib import Path
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
from calendar_revenue import enrich


class CalendarRevenue(unittest.TestCase):
    def report(self):
        return {"rows": {"AMD": {"next": {"date": "2026-11-03"}, "events": [{"date": "2026-08-04"}]}}}

    def document(self, estimate=100):
        return {"totalCount": 1, "data": [{"s": "NASDAQ:AMD", "d": [110, estimate, 130, 1785874740, 1793707200, "USD", "stock"]}]}

    def test_one_bulk_request_attaches_only_matching_periods(self):
        fetch = Mock(return_value=self.document())
        report = enrich(self.report(), fetch)
        self.assertEqual(fetch.call_count, 1)
        self.assertEqual(report["rows"]["AMD"]["next"]["revenueForecast"], 130)
        self.assertEqual(report["rows"]["AMD"]["events"][0]["revenue"], 110)
        self.assertEqual(report["rows"]["AMD"]["events"][0]["revenueCurrency"], "USD")
        report = self.report()
        report["rows"]["AMD"]["next"]["date"] = "2026-11-04"
        report["rows"]["AMD"]["events"][0]["date"] = "2026-08-05"
        enrich(report, fetch)
        self.assertNotIn("revenueForecast", report["rows"]["AMD"]["next"])
        self.assertNotIn("revenue", report["rows"]["AMD"]["events"][0])

    def test_zero_missing_ambiguous_and_failed_responses(self):
        for estimate in (0, None):
            report = enrich(self.report(), Mock(return_value=self.document(estimate)))
            self.assertEqual(report["rows"]["AMD"]["events"][0]["revenueForecast"], estimate)
        document = self.document()
        document["data"].append({**document["data"][0], "s": "NYSE:AMD"})
        document["totalCount"] = 2
        report = enrich(self.report(), Mock(return_value=document))
        self.assertNotIn("revenue", report["rows"]["AMD"]["events"][0])
        report = enrich(self.report(), Mock(side_effect=OSError("offline")))
        self.assertIn("revenueNotice", report)
        self.assertEqual(report["rows"]["AMD"]["next"]["date"], "2026-11-03")
