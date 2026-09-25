import sys
from pathlib import Path
import unittest
import urllib.error
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import yahoo_http


class RetryTests(unittest.TestCase):
    def setUp(self):
        self.reserve = patch("yahoo_http.reserve").start()
        self.sleep = patch("yahoo_http.time.sleep").start()
        self.throttled = patch("yahoo_http.throttled").start()
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


if __name__ == "__main__":
    unittest.main()
