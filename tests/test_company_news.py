import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import company_news
import research


class CompanyNews(unittest.TestCase):
    def test_supplement_dates_sources_and_relevance(self):
        rows = company_news.parse(b'''<rss><channel>
          <item><title>AMD earnings - Reuters</title><source>Reuters</source><link>https://example.com/amd</link><pubDate>Tue, 22 Sep 2026 12:00:00 GMT</pubDate></item>
          <item><title>Shopify earnings - Reuters</title><source>Reuters</source><link>https://example.com/shop</link><pubDate>Tue, 22 Sep 2026 12:00:00 GMT</pubDate></item>
          <item><title>AMD old news</title><link>https://example.com/old</link><pubDate>Tue, 01 Sep 2026 12:00:00 GMT</pubDate></item>
        </channel></rss>''', now=1790120000)
        self.assertEqual(len(rows), 2)
        result = research.parse_news({"news": rows + [{**rows[0], "link": "https://other.example/duplicate"}]}, "AMD")
        self.assertEqual(len(result["articles"]), 1)
        self.assertEqual(result["articles"][0]["title"], "AMD earnings")

    def test_sparse_results_are_supplemented_and_failure_keeps_yahoo_articles(self):
        row = {"title": "AMD earnings", "link": "https://example.com/amd"}
        with patch.object(research, "fetch", return_value={"news": [row]}), patch.object(company_news, "supplement", return_value=[{**row, "title": "AMD new chips", "link": "https://example.com/new"}]) as extra:
            self.assertEqual(len(research.load("news", "AMD", "")["articles"]), 2)
            extra.assert_called_once()
            extra.side_effect = OSError("offline")
            self.assertEqual(len(research.load("news", "AMD", "")["articles"]), 1)
