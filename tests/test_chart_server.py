"""The long-lived chart helper: a JSON line each way over one reused connection."""
import http.client
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import chart_server
import stocks
import yahoo_http

CHART = {"chart": {"result": [{"meta": {"regularMarketPrice": 105, "chartPreviousClose": 100, "regularMarketTime": 30},
                                "timestamp": [10, 30], "indicators": {"quote": [{"close": [101, 105]}]}}]}}


class Response(io.BytesIO):
    def __init__(self, status=200, body=b"{}"):
        super().__init__(body)
        self.status, self.reason, self.headers = status, "Reason", {}


class Connection:
    """http.client.HTTPSConnection stand-in: scripted failures and responses."""
    made, failures, responses = [], [], []

    def __init__(self, host, timeout):
        self.host, self.timeout, self.targets, self.closed = host, timeout, [], False
        Connection.made.append(self)

    def request(self, method, target, body=None, headers=None):
        self.targets.append(target)
        if Connection.failures:
            raise Connection.failures.pop(0)

    def getresponse(self):
        return Connection.responses.pop(0) if Connection.responses else Response()

    def close(self):
        self.closed = True


class KeepAliveTests(unittest.TestCase):
    def setUp(self):
        Connection.made, Connection.failures, Connection.responses = [], [], []
        patch.object(yahoo_http.http.client, "HTTPSConnection", Connection).start()
        self.clock = patch.object(yahoo_http.time, "monotonic", return_value=1000).start()
        self.addCleanup(patch.stopall)
        self.transport = yahoo_http.KeepAlive()

    def open(self, path="/v8/finance/chart/AAPL?range=1d"):
        with self.transport.open(urllib.request.Request("https://query1.finance.yahoo.com" + path), timeout=10) as response:
            return response.read()

    def test_one_connection_serves_consecutive_requests(self):
        self.open()
        self.open("/v8/finance/chart/MSFT?range=5d")
        self.assertEqual(len(Connection.made), 1)
        self.assertEqual(Connection.made[0].targets, ["/v8/finance/chart/AAPL?range=1d", "/v8/finance/chart/MSFT?range=5d"])

    def test_connection_yahoo_closed_is_reopened_silently(self):
        self.open()
        for failure in (http.client.RemoteDisconnected("closed"), BrokenPipeError(), http.client.CannotSendRequest()):
            with self.subTest(failure=failure):
                Connection.failures = [failure]
                self.assertEqual(self.open(), b"{}")
        self.assertEqual(len(Connection.made), 4)
        self.assertTrue(all(connection.closed for connection in Connection.made[:3]))

    def test_failures_on_a_new_connection_are_network_errors_and_are_not_kept(self):
        for failure in (ConnectionRefusedError(), TimeoutError(), http.client.RemoteDisconnected("closed")):
            with self.subTest(failure=failure):
                Connection.failures = [failure]
                with self.assertRaises(urllib.error.URLError):
                    self.open()
        self.assertEqual(len(Connection.made), 3)
        self.assertEqual(self.transport.connections, {})

    def test_a_timeout_is_not_retried_on_a_reused_connection(self):
        self.open()
        Connection.failures = [TimeoutError()]
        with self.assertRaises(urllib.error.URLError):
            self.open()
        self.assertEqual(len(Connection.made), 1)

    def test_idle_connection_is_not_reused(self):
        self.open()
        self.clock.return_value += 61
        self.open()
        self.assertEqual(len(Connection.made), 2)
        self.assertTrue(Connection.made[0].closed)

    def test_http_errors_match_urllib_and_keep_the_connection(self):
        Connection.responses = [Response(404, b"missing")]
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.open()
        self.assertEqual((caught.exception.code, caught.exception.read()), (404, b"missing"))
        self.open()
        self.assertEqual(len(Connection.made), 1)

    def test_yahoo_requests_use_it_with_the_usual_errors(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        patch.dict(os.environ, {"STOCKS_STATE_DIR": temporary.name}).start()
        patch.object(yahoo_http, "persistent", self.transport).start()
        Connection.responses = [Response(200, json.dumps(CHART).encode()), Response(404)]
        self.assertEqual(stocks.fetch("/v8/finance/chart/AAPL")["chart"]["result"][0]["timestamp"], [10, 30])
        with self.assertRaisesRegex(ValueError, "No market data found"):
            stocks.fetch("/v8/finance/chart/NOPE")
        self.assertEqual(len(Connection.made), 1)


class ServerTests(unittest.TestCase):
    def setUp(self):
        # serve() sets both for the process; restore them for other tests.
        patch.object(yahoo_http, "persistent", None).start()
        patch.object(yahoo_http, "priority", False).start()
        self.fetch = patch.object(stocks, "fetch", return_value=CHART).start()
        self.addCleanup(patch.stopall)

    def serve(self, *lines):
        output = io.StringIO()
        chart_server.serve(io.StringIO("".join(line + "\n" for line in lines)), output)
        return [json.loads(line) for line in output.getvalue().splitlines()]

    def test_each_request_gets_one_reply_with_its_id_and_bad_ones_never_end_it(self):
        replies = self.serve(json.dumps({"id": 1, "symbol": "aapl", "range": "1D"}), "not json", "",
                             json.dumps({"id": 3, "symbol": "BAD SYMBOL", "range": "1D"}),
                             json.dumps({"id": 4, "symbol": "AAPL", "range": "9Y"}), json.dumps([1]),
                             json.dumps({"id": 6, "symbol": "MSFT", "range": "1W"}))
        self.assertEqual([reply["id"] for reply in replies], [1, None, 3, 4, None, 6])
        self.assertEqual((replies[0]["chart"]["symbol"], replies[0]["chart"]["points"]), ("AAPL", [[10, 101], [30, 105]]))
        self.assertIn("fetched", replies[0]["chart"])
        for reply, error in zip(replies[1:5], ["Expecting value", "valid stock symbol", "Unknown chart range", "has no attribute"]):
            self.assertIn(error, reply["chart"]["error"])
            self.assertEqual(reply["chart"]["points"], [])
        self.assertEqual(replies[5]["chart"]["range"], "1W")
        self.assertEqual(self.fetch.call_count, 2)
        self.assertIsInstance(yahoo_http.persistent, yahoo_http.KeepAlive)
        self.assertTrue(yahoo_http.priority)

    def test_failed_download_is_an_error_reply(self):
        self.fetch.side_effect = ValueError("offline")
        reply = self.serve(json.dumps({"id": 7, "symbol": "AAPL", "range": "1D"}))[0]
        self.assertEqual((reply["id"], reply["chart"]["error"], reply["chart"]["stale"]), (7, "offline", True))

    def test_process_answers_line_by_line_and_exits_when_stdin_closes(self):
        script = Path(__file__).parents[1] / "bin/chart_server.py"
        result = subprocess.run([sys.executable, str(script)], input=json.dumps({"id": 1, "symbol": "BAD SYMBOL", "range": "1D"}) + "\n",
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["id"], 1)


if __name__ == "__main__":
    unittest.main()
