"""The long-lived data helper: a JSON line each way over one reused connection."""
import http.client
import http.cookiejar
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
import data_server
import market_bulk
import stocks
import yahoo_http

AWAKE = yahoo_http.awake  # the real clock, before tests replace it

CHART = {"chart": {"result": [{"meta": {"regularMarketPrice": 105, "chartPreviousClose": 100, "regularMarketTime": 30},
                                "timestamp": [10, 30], "indicators": {"quote": [{"close": [101, 105]}]}}]}}


class Response(io.BytesIO):
    def __init__(self, status=200, body=b"{}", cookie=None):
        super().__init__(body)
        self.status, self.reason, self.headers = status, "Reason", http.client.HTTPMessage()
        if cookie:
            self.headers["Set-Cookie"] = cookie

    def info(self):
        return self.headers


def cookie(name, value):
    return http.cookiejar.Cookie(0, name, value, None, False, ".yahoo.com", True, True, "/", True, True,
                                 None, False, None, None, {})


class Connection:
    """http.client.HTTPSConnection stand-in: scripted failures and responses."""
    made, failures, responses = [], [], []

    def __init__(self, host, timeout):
        self.host, self.timeout, self.targets, self.closed = host, timeout, [], False
        Connection.made.append(self)

    def request(self, method, target, body=None, headers=None):
        self.targets.append(target)
        self.headers = headers
        if Connection.failures:
            raise Connection.failures.pop(0)

    def getresponse(self):
        return Connection.responses.pop(0) if Connection.responses else Response()

    def close(self):
        self.closed = True


class KeepAliveTests(unittest.TestCase):
    def setUp(self):
        Connection.made, Connection.failures, Connection.responses = [], [], []
        patch.object(yahoo_http.KeepAlive, "connect", Connection).start()
        self.clock = patch.object(yahoo_http, "awake", return_value=1000).start()
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

    def test_the_idle_clock_counts_time_asleep(self):
        with patch.object(yahoo_http.time, "clock_gettime", return_value=5) as clock:
            self.assertEqual(AWAKE(), 5)
        clock.assert_called_once_with(yahoo_http.time.CLOCK_BOOTTIME)

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


class SessionTests(unittest.TestCase):
    """Quote requests carry Yahoo's session cookies over the kept connection."""

    def setUp(self):
        Connection.made, Connection.failures, Connection.responses = [], [], []
        patch.object(yahoo_http.KeepAlive, "connect", Connection).start()
        self.addCleanup(patch.stopall)
        self.jar = http.cookiejar.LWPCookieJar()
        self.jar.set_cookie(cookie("A3", "session"))

    def test_cookies_are_sent_and_new_ones_kept_even_from_errors(self):
        transport = yahoo_http.WithCookies(yahoo_http.KeepAlive(), self.jar)
        Connection.responses = [Response(200, b"{}", cookie="B=rotated; Domain=.yahoo.com; Path=/; Secure")]
        request = urllib.request.Request("https://query1.finance.yahoo.com/v7/finance/quote?symbols=TSLA")
        with transport.open(request):
            pass
        self.assertIn("A3=session", Connection.made[0].headers["Cookie"])
        self.assertEqual(Connection.made[0].headers["User-agent"], "Mozilla/5.0")
        self.assertIn("B", {item.name for item in self.jar})
        Connection.responses = [Response(401, b"", cookie="C=late; Domain=.yahoo.com; Path=/; Secure")]
        with self.assertRaises(urllib.error.HTTPError):
            transport.open(urllib.request.Request("https://query1.finance.yahoo.com/v7/finance/quote?symbols=TSLA"))
        self.assertIn("C", {item.name for item in self.jar})

    def test_signed_in_requests_reuse_the_helpers_connection(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        patch.dict(os.environ, {"STOCKS_STATE_DIR": temporary.name}).start()
        directory = Path(temporary.name) / "yahoo"
        directory.mkdir()
        self.jar.save(str(directory / "cookies.txt"), ignore_discard=True)
        (directory / "session.json").write_text(json.dumps({"crumb": "abc", "expires": 4102444800}))
        patch.object(yahoo_http, "persistent", yahoo_http.KeepAlive()).start()
        Connection.responses = [Response(200, b'{"quoteResponse": {"result": []}}') for _ in range(2)]
        for _ in range(2):
            self.assertEqual(yahoo_http.authenticated("/v7/finance/quote", symbols="TSLA"), {"quoteResponse": {"result": []}})
        self.assertEqual(len(Connection.made), 1)
        self.assertIn("crumb=abc", Connection.made[0].targets[0])
        self.assertIn("A3=session", Connection.made[0].headers["Cookie"])


class ServerTests(unittest.TestCase):
    def setUp(self):
        # serve() sets both for the process; restore them for other tests.
        patch.object(yahoo_http, "persistent", None).start()
        patch.object(yahoo_http, "priority", False).start()
        self.fetch = patch.object(stocks, "fetch", return_value=CHART).start()
        self.addCleanup(patch.stopall)

    def serve(self, *lines):
        output = io.StringIO()
        data_server.serve(io.StringIO("".join(line + "\n" for line in lines)), output)
        return [json.loads(line) for line in output.getvalue().splitlines()]

    def test_each_request_gets_one_reply_with_its_id_and_bad_ones_never_end_it(self):
        chart = lambda identity, ticker, period: json.dumps({"id": identity, "action": "chart", "symbol": ticker, "range": period})
        replies = self.serve(chart(1, "aapl", "1D"), "not json", "", chart(3, "BAD SYMBOL", "1D"),
                             chart(4, "AAPL", "9Y"), json.dumps([1]), chart(6, "MSFT", "1W"))
        self.assertEqual([reply["id"] for reply in replies], [1, None, 3, 4, None, 6])
        self.assertEqual((replies[0]["chart"]["symbol"], replies[0]["chart"]["points"]), ("AAPL", [[10, 101], [30, 105]]))
        self.assertIn("fetched", replies[0]["chart"])
        for reply, error in zip(replies[1:5], ["Expecting value", "valid stock symbol", "Unknown chart range", "JSON object"]):
            self.assertIn(error, reply["chart"]["error"])
            self.assertEqual(reply["chart"]["points"], [])
        self.assertEqual(replies[5]["chart"]["range"], "1W")
        self.assertEqual(self.fetch.call_count, 2)
        self.assertIsInstance(yahoo_http.persistent, yahoo_http.KeepAlive)
        self.assertTrue(yahoo_http.priority)

    def test_failed_download_is_an_error_reply(self):
        self.fetch.side_effect = ValueError("offline")
        reply = self.serve(json.dumps({"id": 7, "action": "chart", "symbol": "AAPL", "range": "1D"}))[0]
        self.assertEqual((reply["id"], reply["chart"]["error"], reply["chart"]["stale"]), (7, "offline", True))

    def test_searches_share_the_helper_and_its_connection(self):
        self.fetch.return_value = {"quotes": [{"symbol": "NVDA", "longname": "NVIDIA Corporation", "quoteType": "EQUITY", "exchDisp": "NASDAQ"}]}
        replies = self.serve(json.dumps({"id": 1, "action": "search", "query": "nvidia"}),
                             json.dumps({"id": 2, "action": "chart", "symbol": "NVDA", "range": "1D"}))
        self.assertEqual(replies[0]["search"]["query"], "nvidia")
        self.assertIn("NVDA", [row["symbol"] for row in replies[0]["search"]["results"]])
        self.assertEqual(self.fetch.call_args_list[0].args[0], "/v1/finance/search")
        self.assertEqual(replies[1]["id"], 2)

    def test_failed_search_is_an_error_reply(self):
        self.fetch.side_effect = ValueError("offline")
        reply = self.serve(json.dumps({"id": 3, "action": "search", "query": "nvidia"}))[0]
        self.assertEqual((reply["id"], reply["search"]["error"], reply["search"]["query"]), (3, "offline", "nvidia"))
        with patch.object(data_server, "search", side_effect=RuntimeError("broken")):
            reply = self.serve(json.dumps({"id": 4, "action": "search", "query": "x"}))[0]
        self.assertEqual((reply["id"], reply["search"]["results"], reply["search"]["error"]), (4, [], "broken"))
        reply = self.serve(json.dumps({"id": 5, "action": "delete"}))[0]
        self.assertEqual(reply["chart"]["error"], "Unknown request.")

    def test_quotes_are_saved_like_the_one_shot_quote(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        patch.dict(os.environ, {"STOCKS_STATE_DIR": temporary.name}).start()
        row = {"symbol": "TSLA", "price": 250, "name": "Tesla, Inc.", "marketState": "REGULAR", "updated": 999}
        with patch.object(market_bulk, "quotes", return_value={"rows": {"TSLA": row}}) as request:
            replies = self.serve(json.dumps({"id": 1, "action": "quote", "symbol": "tsla"}),
                                 json.dumps({"id": 2, "action": "quote", "symbol": "BAD SYMBOL"}))
        request.assert_called_once_with(["TSLA"])
        self.assertEqual((replies[0]["id"], replies[0]["quote"]["price"], replies[0]["quote"]["marketState"]), (1, 250, "REGULAR"))
        self.assertIn("TSLA:quote", json.loads((Path(temporary.name) / "cache.json").read_text()))
        self.assertEqual(replies[1]["id"], 2)
        self.assertIn("valid stock symbol", replies[1]["error"])

    def test_process_answers_line_by_line_and_exits_when_stdin_closes(self):
        script = Path(__file__).parents[1] / "bin/data_server.py"
        result = subprocess.run([sys.executable, str(script)], input=json.dumps({"id": 1, "action": "chart", "symbol": "BAD SYMBOL", "range": "1D"}) + "\n",
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["id"], 1)


if __name__ == "__main__":
    unittest.main()
