import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
from market_news import parse, relevant


class MarketNews(unittest.TestCase):
    def test_deduplication_safe_links_and_missing_dates(self):
        result = parse(b'''<rss><channel>
          <item><title>Undated</title><link>https://example.com/a</link></item>
          <item><title>Duplicate</title><link>https://example.com/a</link></item>
          <item><title>Unsafe</title><link>javascript:alert(1)</link></item>
          <item><title>Stock futures rise &amp; rally - Reuters</title><link>https://example.com/b</link>
            <pubDate>Tue, 22 Sep 2026 12:00:00 GMT</pubDate><source>Reuters</source></item>
          <item><title>Stock futures rise &amp; rally - CNBC</title><link>https://example.com/c</link>
            <pubDate>Tue, 22 Sep 2026 12:00:00 GMT</pubDate><source>CNBC</source></item>
        </channel></rss>''', now=1790120000)["articles"]
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["title"], "Stock futures rise & rally")
        self.assertEqual(result[0]["source"], "Reuters")

    def test_empty_or_wrong_feed_does_not_replace_saved_headlines(self):
        for raw in (b"<html/>", b"<rss><channel/></rss>"):
            with self.assertRaises(ValueError):
                parse(raw)

    def test_yahoo_iso_dates(self):
        article = parse(b'<rss><channel><item><title>Stock market rises</title><source>Reuters</source><link>https://example.com/</link><pubDate>2026-09-21T14:37:00Z</pubDate></item></channel></rss>', now=1790120000)["articles"][0]
        self.assertEqual(article["published"], 1790001420)

    def test_market_focus_excludes_stock_picks_and_generic_wall_street_mentions(self):
        for title in ["Stock futures rise ahead of Fed decision", "Treasury yields fall after inflation data", "Wall Street holds near its record", "Federal Reserve raises key interest rate"]:
            self.assertTrue(relevant(title), title)
        for title in ["Wall Street expects Meta's AI agent to become a revenue engine", "3 stocks to buy as Treasury yields rise", "Is AMD outperforming the S&P 500?", "Shopify shares jump on earnings", "Paramount Shares Tick Up As Wall Street Remains Optimistic", "3 Insurance Stocks That Could Benefit From Higher Treasury Yields", "How Many Retirees Own Their Homes? What Federal Reserve Data Reveals"]:
            self.assertFalse(relevant(title), title)

    def test_old_articles_are_not_used_to_fill_the_feed(self):
        result = parse(b'<rss><channel><item><title>Stock futures rise</title><source>CNBC</source><link>https://example.com/</link><pubDate>2026-01-01T14:37:00Z</pubDate></item></channel></rss>', now=1790120000)
        self.assertEqual(result["articles"], [])
