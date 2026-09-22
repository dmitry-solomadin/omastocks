import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import research


class ResearchTests(unittest.TestCase):
    def test_news_is_relevant_deduplicated_and_safe_to_open(self):
        row = {"uuid": "one", "title": "Apple earnings", "publisher": "Publisher",
               "link": "https://example.org/story", "providerPublishTime": 100, "relatedTickers": ["AAPL"],
               "thumbnail": {"resolutions": [{"url": "https://example.org/image", "width": 320}]}}
        result = research.parse_news({"news": [row, row, dict(row, uuid="other", relatedTickers=["MSFT"]),
                                                dict(row, uuid="unsafe", link="file:///etc/passwd")]}, "AAPL")
        self.assertEqual(len(result["articles"]), 1)
        self.assertEqual(result["articles"][0]["image"], "https://example.org/image")

    def test_missing_thumbnail_is_supported(self):
        result = research.parse_news({"news": [{"title": "Headline", "link": "https://example.org", "relatedTickers": ["ELF"]}]}, "ELF")
        self.assertEqual(result["articles"][0]["image"], "")

    def test_company_headlines_rank_above_broad_related_coverage(self):
        base = {"link": "https://example.org/story", "relatedTickers": ["AAPL", "AMD"]}
        result = research.parse_news({"quotes": [{"symbol": "AAPL", "shortname": "Apple Inc."}], "news": [
            dict(base, uuid="broad", title="Why AMD is rising", providerPublishTime=200),
            dict(base, uuid="focused", title="Apple announces earnings", providerPublishTime=100),
        ]}, "AAPL")
        self.assertEqual([article["id"] for article in result["articles"]], ["focused", "broad"])

    def test_earnings_estimates_and_reported_dates_are_distinct(self):
        upcoming = {"reportText": "Estimated to report earnings on 10/29/2026."}
        history = {"earningsSurpriseTable": {"rows": [{"dateReported": "7/30/2026", "eps": 1.91, "consensusForecast": "1.88"}]}}
        result = research.parse_earnings(upcoming, history, "2026-09-21")
        self.assertEqual(result["next"], {"date": "2026-10-29", "type": "earnings", "estimated": True})
        self.assertEqual(result["events"][0]["date"], "2026-07-30")
        self.assertFalse(result["events"][0]["estimated"])
        self.assertIsNone(research.parse_earnings(upcoming, history, "2026-11-01")["next"])
        self.assertIsNone(research.parse_earnings({}, {}, "2026-09-21")["next"])

    def test_averages_require_full_warmup_history(self):
        points = [[index * 86400, index + 1] for index in range(220)]
        dates = [str(index) for index in range(220)]
        series = research.moving_averages(points, dates)
        sma200 = series[2]
        self.assertEqual(len(sma200["points"]), 21)
        self.assertEqual(sma200["points"][0], [199 * 86400, 100.5])
        self.assertEqual(sma200["points"][-1], [219 * 86400, 120.5])
        self.assertEqual(research.moving_averages(points[:10], dates[:10])[0]["points"], [])

    def test_revenue_matches_release_date_without_rescaling_amounts(self):
        document = {"data": [{"s": "NASDAQ:AAPL", "d": [109417000000, 109038899874, 1785443580, "USD", "stock"]}]}
        report = research.parse_revenue(document, "AAPL")
        self.assertEqual(report["date"], "2026-07-30")
        self.assertEqual(report["revenue"], 109417000000)
        self.assertEqual(report["revenueForecast"], 109038899874)
        self.assertEqual(report["revenueCurrency"], "USD")
        calendar = {"events": [{"date": "2026-04-30"}, {"date": "2026-07-30", "eps": 1.91}]}
        self.assertTrue(research.attach_revenue(calendar, report))
        self.assertNotIn("revenue", calendar["events"][0])
        self.assertEqual(calendar["events"][1]["eps"], 1.91)
        self.assertFalse(research.attach_revenue({"events": [{"date": "2026-08-01"}]}, report))

    def test_revenue_missing_estimate_is_not_zero_and_ambiguous_listings_are_rejected(self):
        row = {"s": "NYSE:ELF", "d": [0, None, 1785960300, "USD", "stock"]}
        report = research.parse_revenue({"data": [row]}, "ELF")
        self.assertEqual(report["revenue"], 0)
        self.assertIsNone(report["revenueForecast"])
        self.assertIsNone(research.parse_revenue({"data": [row]}, "AAPL"))
        self.assertIsNone(research.parse_revenue({"data": [row, dict(row, s="NASDAQ:ELF")]}, "ELF"))
        self.assertIsNone(research.parse_revenue({"data": [dict(row, d=[1, 2, None, "USD", "stock"])]}, "ELF"))

    def test_revenue_failure_does_not_discard_eps(self):
        history = {"earningsSurpriseTable": {"rows": [{"dateReported": "7/30/2026", "eps": 1.91, "consensusForecast": "1.88"}]}}
        with patch.object(research, "nasdaq", return_value=history), patch.object(research, "revenue", side_effect=ValueError("offline")):
            result = research.earnings("AAPL")
        self.assertEqual(result["events"][0]["eps"], 1.91)
        self.assertNotIn("revenue", result["events"][0])
        self.assertIn("Revenue", result["notice"])
        self.assertEqual(result["earningsSchema"], 2)

    def test_failed_news_refresh_retains_cache_and_backs_off(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        with patch.dict(os.environ, {"STOCKS_STATE_DIR": temporary.name}), patch.object(research, "load") as load:
            load.return_value = {"symbol": "AAPL", "articles": [{"title": "Saved headline"}]}
            first = research.main(["news", "AAPL"])
            self.assertEqual(research.main(["news", "AAPL"]), first)
            load.assert_called_once()
            load.side_effect = ValueError("offline")
            failed = research.main(["news", "AAPL", "--force"])
            self.assertEqual(failed["articles"], first["articles"])
            self.assertTrue(failed["stale"])
            self.assertEqual(research.main(["news", "AAPL", "--force"]), failed)
            self.assertEqual(load.call_count, 2)
            self.assertFalse((Path(temporary.name) / "watchlist.json").exists())
            json.dumps(failed, allow_nan=False)


if __name__ == "__main__":
    unittest.main()
