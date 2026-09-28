import gzip
import json
import os
import sys
from pathlib import Path
import tempfile
import unittest
import urllib.error
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import stocks
import yahoo_http


class RetryTests(unittest.TestCase):
    def setUp(self):
        self.reserve = patch("yahoo_http.reserve").start()
        self.sleep = patch("yahoo_http.time.sleep").start()
        self.throttled = patch("yahoo_http.throttled").start()
        self.outage = patch("yahoo_http.outage").start()
        self.addCleanup(patch.stopall)
        self.opener = MagicMock()
        self.response = MagicMock()
        self.response.__enter__.return_value.read.return_value = b'{"ok": true}'

    def test_recovers_from_dns_failure_and_timeout(self):
        self.opener.open.side_effect = [urllib.error.URLError("Temporary failure in name resolution"),
                                        TimeoutError(), self.response]
        self.assertEqual(yahoo_http.read("https://example.test", self.opener), b'{"ok": true}')
        self.assertEqual(self.reserve.call_count, 3)
        self.assertEqual([call.args[0] for call in self.sleep.call_args_list], [1, 2])

    def test_persistent_network_failure_is_bounded(self):
        self.opener.open.side_effect = urllib.error.URLError("offline")
        with self.assertRaises(urllib.error.URLError):
            yahoo_http.read("https://example.test", self.opener)
        self.assertEqual(self.opener.open.call_count, 3)
        self.assertEqual(self.sleep.call_count, 2)
        self.outage.assert_called_once_with(True)

    def test_transient_server_error_recovers(self):
        self.opener.open.side_effect = [urllib.error.HTTPError("", 503, "Unavailable", {}, None), self.response]
        self.assertEqual(yahoo_http.read("https://example.test", self.opener), b'{"ok": true}')
        self.assertEqual(self.reserve.call_count, 2)

    def test_permanent_http_errors_are_not_retried(self):
        for code in (401, 404, 429):
            with self.subTest(code=code):
                self.opener.open.reset_mock()
                self.opener.open.side_effect = urllib.error.HTTPError("", code, "error", {}, None)
                with self.assertRaises(ValueError if code == 429 else urllib.error.HTTPError):
                    yahoo_http.read("https://example.test", self.opener)
                self.assertEqual(self.opener.open.call_count, 1)
        self.sleep.assert_not_called()
        self.throttled.assert_called_once_with({})

    def test_shared_cooldown_stops_retry(self):
        self.opener.open.side_effect = urllib.error.URLError("offline")
        self.reserve.side_effect = [None, ValueError("rate limiting")]
        with self.assertRaisesRegex(ValueError, "rate limiting"):
            yahoo_http.read("https://example.test", self.opener)
        self.assertEqual(self.opener.open.call_count, 1)



class CompressionTests(unittest.TestCase):
    def setUp(self):
        patch("yahoo_http.reserve", return_value={}).start()
        self.addCleanup(patch.stopall)
        self.opener = MagicMock()

    def reply(self, body, encoding="gzip"):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = body
        response.__enter__.return_value.headers = {"Content-Encoding": encoding} if encoding else {}
        self.opener.open.return_value = response

    def test_requests_ask_for_gzip_and_replies_are_unpacked(self):
        request = urllib.request.Request("https://query1.finance.yahoo.com/v8/finance/chart/AAPL")
        self.reply(gzip.compress(b'{"ok": true}'))
        self.assertEqual(yahoo_http.read(request, self.opener), b'{"ok": true}')
        self.assertEqual(request.get_header("Accept-encoding"), "gzip")
        self.reply(b'{"plain": true}', encoding=None)
        self.assertEqual(yahoo_http.read(request, self.opener), b'{"plain": true}')

    def test_oversized_or_damaged_replies_are_errors(self):
        request = urllib.request.Request("https://query1.finance.yahoo.com/v8/finance/chart/AAPL")
        self.reply(gzip.compress(b" " * (yahoo_http.LIMIT + 10)))
        with self.assertRaisesRegex(ValueError, "oversized"):
            yahoo_http.read(request, self.opener)
        self.reply(b"not gzip at all")
        with self.assertRaisesRegex(ValueError, "damaged"):
            yahoo_http.read(request, self.opener)


class PacingTests(unittest.TestCase):
    """Requests keep 0.25 s apart; the chart on screen goes first."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        patch.dict(os.environ, {"STOCKS_STATE_DIR": temporary.name}).start()
        patch("yahoo_http.time.time", return_value=1000).start()
        self.sleep = patch("yahoo_http.time.sleep").start()
        self.addCleanup(patch.stopall)
        self.traffic = Path(temporary.name) / "yahoo/traffic.json"

    def next_turn(self):
        return json.loads(self.traffic.read_text())["next"]

    def test_each_request_claims_the_turn_after_the_last(self):
        for wait in (0, .25, .5):
            yahoo_http.reserve()
            self.assertAlmostEqual(self.sleep.call_args.args[0], wait)
        self.assertAlmostEqual(self.next_turn(), 1000.75)

    def test_the_chart_goes_at_once_and_later_requests_wait_after_it(self):
        yahoo_http.reserve()
        yahoo_http.reserve()
        with patch.object(yahoo_http, "priority", True):
            yahoo_http.reserve()
        self.assertEqual(self.sleep.call_args.args[0], 0)
        self.assertAlmostEqual(self.next_turn(), 1000.75)
        yahoo_http.reserve()
        self.assertAlmostEqual(self.sleep.call_args.args[0], .75)

    def test_the_rate_limit_cooldown_holds_the_chart_too(self):
        self.traffic.parent.mkdir(parents=True)
        self.traffic.write_text(json.dumps({"retryAfter": 2000}))
        with patch.object(yahoo_http, "priority", True), self.assertRaisesRegex(ValueError, "rate limiting"):
            yahoo_http.reserve()


class OutageTests(unittest.TestCase):
    """traffic.json records an outage from the app's own requests, not health checks."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.traffic = Path(temporary.name) / "yahoo/traffic.json"
        self.clock = patch("yahoo_http.time.time", return_value=1000).start()
        patch("yahoo_http.time.sleep").start()
        patch.dict(os.environ, {"STOCKS_STATE_DIR": temporary.name}).start()
        self.writes = patch.object(stocks, "write_json", wraps=stocks.write_json).start()
        self.request = patch("yahoo_http.urllib.request.urlopen").start()
        self.addCleanup(patch.stopall)
        self.response = MagicMock()
        self.response.__enter__.return_value.read.return_value = b"{}"

    def state(self):
        return json.loads(self.traffic.read_text())

    def fetch(self, reply):
        self.request.side_effect = [reply] * 3
        try:
            stocks.fetch("/v8/finance/chart/AAPL")
        except ValueError:
            pass

    def test_success_writes_only_the_pacing_reservation(self):
        self.fetch(self.response)
        self.assertNotIn("outage", self.state())
        self.assertEqual(self.writes.call_count, 1)

    def test_three_failed_requests_record_one_outage_then_a_reply_clears_it(self):
        for now in (1000, 1010, 1020):
            self.clock.return_value = now
            self.fetch(urllib.error.URLError("offline"))
        self.assertEqual(self.state()["outage"], {"since": 1000, "failures": 3})
        self.fetch(self.response)
        self.assertNotIn("outage", self.state())

    def test_server_errors_are_an_outage_but_other_replies_prove_yahoo_is_reachable(self):
        self.fetch(urllib.error.HTTPError("", 503, "Unavailable", {}, None))
        self.assertEqual(self.state()["outage"]["failures"], 1)
        self.fetch(urllib.error.HTTPError("", 404, "Not found", {}, None))
        self.assertNotIn("outage", self.state())
        self.fetch(urllib.error.HTTPError("", 404, "Not found", {}, None))
        self.assertNotIn("outage", self.state())

    def test_rate_limit_sets_the_cooldown_without_an_outage(self):
        self.fetch(urllib.error.HTTPError("", 429, "Limited", {}, None))
        self.assertGreater(self.state()["retryAfter"], 1000)
        self.assertNotIn("outage", self.state())

    def test_request_held_back_by_the_cooldown_leaves_the_outage_alone(self):
        self.traffic.parent.mkdir(parents=True)
        saved = {"retryAfter": 2000, "outage": {"since": 900, "failures": 2}}
        self.traffic.write_text(json.dumps(saved))
        self.fetch(urllib.error.URLError("offline"))
        self.request.assert_not_called()
        self.assertEqual(self.state(), saved)


if __name__ == "__main__":
    unittest.main()
