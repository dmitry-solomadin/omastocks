import os
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import research
import social


class SocialTests(unittest.TestCase):
    def test_json_response_has_a_bounded_read(self):
        class Response(io.BytesIO):
            def read(self, size=-1):
                self.requested_size = size
                return super().read(size)

        for payload, valid in [(b'{"messages": []}', True), (b" " * (social.MAX_RESPONSE_BYTES + 1), False)]:
            response = Response(payload)
            with patch.object(social.urllib.request, "urlopen", return_value=response):
                if valid:
                    self.assertEqual(social.get_json("https://api.stocktwits.com/test", "Stocktwits"), {"messages": []})
                else:
                    with self.assertRaises(ValueError):
                        social.get_json("https://api.stocktwits.com/test", "Stocktwits")
            self.assertEqual(response.requested_size, social.MAX_RESPONSE_BYTES + 1)

    def test_posts_deduplicate_sort_and_keep_only_author_sentiment(self):
        base = {"id": 1, "body": "$ACME earnings &amp; outlook", "created_at": "2026-09-21T12:00:00Z",
                "user": {"username": "trader"}, "likes": {"total": 0}, "entities": {"sentiment": {"basic": "Bullish"}}}
        newer = dict(base, id=2, created_at="2026-09-21T13:00:00Z", entities={}, likes={})
        result = social.parse_stocktwits({"symbol": {"symbol": "ACME"}, "messages": [base, newer, base]}, "ACME")
        self.assertEqual([post["id"] for post in result["posts"]], ["2", "1"])
        self.assertIsNone(result["posts"][0]["sentiment"])
        self.assertIsNone(result["posts"][0]["likes"])
        self.assertEqual(result["posts"][1]["likes"], 0)
        self.assertEqual(result["posts"][1]["text"], "$ACME earnings & outlook")
        self.assertEqual(result["posts"][1]["url"], "https://stocktwits.com/trader/message/1")

    def test_bad_posts_and_wrong_symbol_are_not_shown(self):
        base = {"id": 1, "body": "Hello", "created_at": "2026-09-21T12:00:00Z", "user": {"username": "trader"}}
        invalid = [dict(base, id=-1), dict(base, body=""), dict(base, created_at="bad"),
                   dict(base, created_at="2026-09-21T12:00:00"), dict(base, user={"username": "../bad"})]
        self.assertEqual(social.parse_stocktwits({"symbol": {"symbol": "ACME"}, "messages": invalid}, "ACME")["posts"], [])
        with self.assertRaises(ValueError):
            social.parse_stocktwits({"symbol": {"symbol": "OTHER"}, "messages": [base]}, "ACME")
        with self.assertRaises(ValueError):
            social.parse_stocktwits({"response": {"status": 403}}, "ACME")
        result = social.parse_stocktwits({"symbol": {"symbol": "SPX"}, "messages": []}, "^SPX")
        self.assertEqual(result["symbol"], "^SPX")
        self.assertEqual(result["url"], "https://stocktwits.com/symbol/SPX")

    def test_buzz_missing_values_are_not_zero_or_sentiment(self):
        result = social.parse_buzz([{"results": [
            {"ticker": "ACME", "mentions": "0", "upvotes": "12", "rank": 9, "rank_24h_ago": 0},
            {"ticker": "OTHER", "mentions": -1, "upvotes": True, "mentions_24h_ago": "nan"},
            {"ticker": "ACME", "mentions": 3}]}])
        self.assertEqual(len(result["rows"]), 2)
        row = result["rows"][0]
        self.assertEqual(row["mentions"], 0)
        self.assertEqual(row["upvotes"], 12)
        self.assertIsNone(row["previousMentions"])
        self.assertIsNone(row["previousRank"])
        self.assertNotIn("sentiment", row)
        self.assertIsNone(result["rows"][1]["mentions"])
        self.assertIsNone(result["rows"][1]["upvotes"])
        self.assertIsNone(result["rows"][1]["previousMentions"])
        self.assertFalse(any(row["symbol"] == "MISSING" for row in result["rows"]))

    def test_buzz_fetches_beyond_first_page(self):
        def fetch(url, provider):
            if url.endswith("/page/2"):
                return {"results": [{"ticker": "ACME", "mentions": 1}]}
            return {"pages": 2, "results": [{"ticker": "OTHER", "mentions": 5}]}
        with patch.object(social, "get_json", side_effect=fetch) as request:
            result = social.reddit_buzz()
        self.assertEqual([row["symbol"] for row in result["rows"]], ["OTHER", "ACME"])
        self.assertTrue(result["complete"])
        self.assertEqual(request.call_count, 2)

    def test_failed_page_does_not_publish_partial_snapshot(self):
        with patch.object(social, "get_json", side_effect=[{"pages": 2, "results": []}, ValueError("offline")]):
            with self.assertRaisesRegex(ValueError, "offline"):
                social.reddit_buzz()

    def test_global_buzz_cache_shared_across_stocks_and_manual_refresh_recovers(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        with patch.dict(os.environ, {"STOCKS_STATE_DIR": temporary.name}), patch.object(research, "reddit_buzz") as fetch, \
                patch.object(research.time, "time", return_value=100000) as now:
            fetch.return_value = {"symbol": "ALL", "rows": [{"symbol": "ACME", "mentions": 10}]}
            first = research.main(["buzz", "ACME"])
            self.assertEqual(research.main(["buzz", "OTHER"]), first)
            fetch.assert_called_once()
            now.return_value += 1801
            fetch.side_effect = ValueError("offline")
            failed = research.main(["buzz", "ALL"])
            self.assertTrue(failed["stale"])
            self.assertEqual(failed["rows"], first["rows"])
            self.assertEqual(research.main(["buzz", "ACME"]), failed)
            fetch.side_effect = None
            self.assertFalse(research.main(["buzz", "ALL", "--force"])["stale"])
            self.assertEqual(fetch.call_count, 3)

    def test_social_cache_is_per_symbol(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        with patch.dict(os.environ, {"STOCKS_STATE_DIR": temporary.name}), patch.object(research, "stocktwits") as fetch:
            fetch.side_effect = lambda ticker: {"symbol": ticker, "posts": [{"id": ticker}]}
            self.assertEqual(research.main(["social", "ACME"])["posts"], [{"id": "ACME"}])
            self.assertEqual(research.main(["social", "OTHER"])["posts"], [{"id": "OTHER"}])
            self.assertEqual(research.main(["social", "ACME"])["symbol"], "ACME")
            self.assertEqual(fetch.call_count, 2)
