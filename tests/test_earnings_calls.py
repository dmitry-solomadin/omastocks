import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
from earnings_calls import parse_calls
import research


PAGE = '<a id="tab-earnings-calls" aria-selected="true">Earnings Calls</a>'


class EarningsCallsTests(unittest.TestCase):
    def test_links_keep_provider_order_decode_titles_and_deduplicate(self):
        page = PAGE + '''
            <a href="/quote/ACME.B/earnings/latest.html" title="Q3 FY2026 earnings call transcript">Latest</a>
            <a href="https://finance.yahoo.com/quote/ACME.B/earnings/latest.html?source=other">Duplicate</a>
            <a href="/quote/ACME.B/earnings/older.html"><h3>Q2 &amp; full-year <span>call</span></h3></a>
        '''
        result = parse_calls(page, "ACME.A")
        self.assertEqual(result["symbol"], "ACME.A")
        self.assertEqual([row["title"] for row in result["calls"]],
                         ["Q3 FY2026 earnings call transcript", "Q2 & full-year call"])
        self.assertEqual(result["calls"][0]["url"], "https://finance.yahoo.com/quote/ACME.B/earnings/latest.html")

    def test_only_individual_yahoo_transcripts_are_retained(self):
        page = PAGE + '''
            <a href="/quote/ACME/earnings-calls/">Index</a>
            <a href="/news/story.html">News</a>
            <a href="https://example.org/quote/ACME/earnings/call.html">External</a>
            <a href="javascript:alert(1)">Invalid</a>
            <a href="/quote/ACME/earnings/empty.html"></a>
        '''
        self.assertEqual(parse_calls(page, "ACME")["calls"], [])

    def test_unrecognized_page_is_an_error_not_an_empty_history(self):
        for page in ("", "<h1>Consent required</h1>", '<a id="tab-earnings-calls" aria-selected="false">Calls</a>'):
            with self.subTest(page=page), self.assertRaises(ValueError):
                parse_calls(page, "ACME")
        self.assertEqual(parse_calls(PAGE, "ACME")["calls"], [])

    def test_daily_cache_and_failure_backoff_preserve_transcripts(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        with patch.dict(os.environ, {"STOCKS_STATE_DIR": temporary.name}), \
                patch.object(research, "earnings_calls") as fetch, patch.object(research.time, "time", return_value=100000) as now:
            fetch.return_value = parse_calls(PAGE + '<a href="/quote/ACME/earnings/call.html">Q3 call</a>', "ACME")
            first = research.main(["calls", "ACME"])
            now.return_value += 86399
            self.assertEqual(research.main(["calls", "ACME"]), first)
            fetch.assert_called_once_with("ACME")
            now.return_value += 2
            fetch.side_effect = ValueError("Unavailable")
            failed = research.main(["calls", "ACME"])
            self.assertEqual(failed["calls"], first["calls"])
            self.assertTrue(failed["stale"])
            self.assertEqual(research.main(["calls", "ACME", "--force"]), failed)
            self.assertEqual(fetch.call_count, 2)
