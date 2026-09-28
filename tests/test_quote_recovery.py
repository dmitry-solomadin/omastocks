"""Bulk quote recovery across offline startup, partial replies and rate limits."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import market_bulk
import stocks


def reply(tickers):
    return {"rows": {ticker: {"symbol": ticker, "price": 123, "percent": 2, "updated": 999}
                     for ticker in tickers}}


class QuoteRecovery(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.repo = stocks.Repository(self.path)
        clock = patch.object(stocks.time, "time", return_value=1000)
        self.clock = clock.start()
        self.addCleanup(clock.stop)
        request = patch.object(market_bulk, "quotes", side_effect=reply)
        self.request = request.start()
        self.addCleanup(request.stop)
        sparks = patch.object(market_bulk, "sparks", side_effect=lambda tickers: {})
        self.sparks = sparks.start()
        self.addCleanup(sparks.stop)

    def test_refresh_combines_active_list_and_other_list_favorites_without_charts(self):
        self.repo.watchlist("create", name="Other")
        self.repo.mutate("add", "AMD", favorite=True)
        self.repo.mutate("add", "AAPL", favorite=True)
        self.repo.watchlist("select", "default")
        with patch.object(self.repo, "chart", side_effect=AssertionError("No chart downloads")):
            result = self.repo.snapshot(refresh=True)
        self.request.assert_called_once()
        tickers = self.request.call_args.args[0]
        self.assertEqual(set(tickers), {ticker for ticker, _ in stocks.SEED} | {"AMD"})
        self.assertEqual(len(tickers), 6)
        self.assertEqual(result["quoteRetryAfter"], 0)
        self.assertTrue(all(row["price"] == 123 and not row["stale"] for row in result["favoriteEntries"]))

    def test_offline_boot_retries_exponentially_persists_and_resets_after_success(self):
        self.repo.cache["AAPL:1D"] = {"price": 100, "fetched": 900, "updated": 800}
        self.request.side_effect = OSError("DNS unavailable")
        for delay in [1, 2, 4, 8, 16, 32, 64, 128, 256, 300, 300]:
            result = self.repo.snapshot(refresh=True, retry_only=True)
            self.assertEqual(result["quoteRetryAfter"], self.clock.return_value + delay)
            apple = next(row for row in result["entries"] if row["symbol"] == "AAPL")
            self.assertEqual((apple["price"], apple["fetched"], apple["updated"]), (100, 900, 800))
            self.assertTrue(apple["stale"])
            calls = self.request.call_count
            self.clock.return_value = result["quoteRetryAfter"] - .1
            self.repo.snapshot(refresh=True, retry_only=True)
            self.assertEqual(self.request.call_count, calls)
            stocks.write_json(self.repo.cache_path, self.repo.cache)
            self.repo = stocks.Repository(self.path)
            self.clock.return_value = result["quoteRetryAfter"]
        self.request.side_effect = reply
        result = self.repo.snapshot(refresh=True, retry_only=True)
        self.assertEqual(result["quoteRetryAfter"], 0)
        self.assertTrue(all(not row["stale"] and not row["error"] for row in result["entries"]))
        self.assertNotIn("failures", self.repo.cache["AAPL:quote"])
        self.request.side_effect = OSError("offline again")
        result = self.repo.snapshot(refresh=True, force=True)
        self.assertEqual(result["quoteRetryAfter"], self.clock.return_value + 1)

    def test_partial_reply_retains_missing_quote_and_retries_only_failed_symbols(self):
        self.repo.snapshot(refresh=True)
        self.clock.return_value += 301
        self.request.side_effect = lambda tickers: reply([ticker for ticker in tickers if ticker != "AAPL"])
        result = self.repo.snapshot(refresh=True)
        self.assertEqual(result["quoteRetryAfter"], 1302)
        apple = next(row for row in result["entries"] if row["symbol"] == "AAPL")
        self.assertEqual(apple["price"], 123)
        self.assertTrue(apple["stale"])
        self.clock.return_value = 1302
        self.request.side_effect = reply
        recovered = self.repo.snapshot(refresh=True, retry_only=True)
        self.assertEqual(self.request.call_args.args[0], ["AAPL"])
        self.assertEqual(recovered["quoteRetryAfter"], 0)

    def test_provider_cooldown_overrides_short_retry_delay(self):
        (self.path / "yahoo").mkdir()
        (self.path / "yahoo/traffic.json").write_text(json.dumps({"retryAfter": 1500}))
        self.request.side_effect = ValueError("rate limiting")
        result = self.repo.snapshot(refresh=True)
        self.assertEqual(result["quoteRetryAfter"], 1500)
        self.clock.return_value = 1499
        self.repo.snapshot(refresh=True, retry_only=True)
        self.request.assert_called_once()

    def test_large_symbol_sets_are_chunked_and_fresh_quotes_are_cached(self):
        tickers = ["T%d" % index for index in range(145)]
        self.repo.refresh_quotes(tickers)
        self.assertEqual([len(call.args[0]) for call in self.request.call_args_list], [70, 70, 5])
        self.repo.refresh_quotes(tickers)
        self.assertEqual(self.request.call_count, 3)

    def test_sparklines_join_rows_in_chunks_and_failures_keep_the_previous_line(self):
        line = {"points": [[900, 1], [960, 2]], "sessionStart": 800, "sessionEnd": 2000}
        self.sparks.side_effect = lambda tickers: {ticker: line for ticker in tickers}
        result = self.repo.snapshot(refresh=True)
        self.assertTrue(all(row["points"] == line["points"] and row["sessionEnd"] == 2000 for row in result["entries"]))
        self.repo.refresh_sparks(["T%d" % index for index in range(45)])
        self.assertEqual([len(call.args[0]) for call in self.sparks.call_args_list[1:]], [20, 20, 5])
        self.clock.return_value += 61
        self.sparks.side_effect = OSError("offline")
        result = self.repo.snapshot(refresh=True)
        self.assertTrue(all(row["points"] == line["points"] for row in result["entries"]))
        calls = self.sparks.call_count
        self.clock.return_value += 60
        self.repo.snapshot(refresh=True)
        self.assertEqual(self.sparks.call_count, calls)

    def test_quote_recovery_retries_do_not_download_sparklines(self):
        self.repo.snapshot(refresh=True, retry_only=True)
        self.sparks.assert_not_called()
        self.repo.snapshot(refresh=True)
        calls = self.sparks.call_count
        self.repo.snapshot(refresh=True)
        self.assertEqual(self.sparks.call_count, calls)
        self.repo.snapshot(refresh=True, force=True)
        self.assertEqual(self.sparks.call_count, calls + 1)


class QuoteAction(unittest.TestCase):
    """The header quote for a stock outside the watchlist comes from the bulk quote."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.path = Path(temp.name)
        (self.path / "watchlist.json").write_text(json.dumps({"entries": [{"symbol": "AAPL", "name": "Apple Inc."}]}))
        for patcher in (patch.dict(os.environ, {"STOCKS_STATE_DIR": temp.name}),
                        patch.object(stocks, "fetch", side_effect=AssertionError("No chart downloads"))):
            patcher.start()
            self.addCleanup(patcher.stop)
        clock = patch.object(stocks.time, "time", return_value=1000)
        self.clock = clock.start()
        self.addCleanup(clock.stop)
        self.row = {"symbol": "TSLA", "price": 250, "name": "Tesla, Inc.", "currency": "USD",
                    "previous": 245, "marketState": "REGULAR", "updated": 999}

    def test_quote_outside_watchlist_is_one_bulk_request_without_a_chart(self):
        with patch.object(market_bulk, "quotes", return_value={"rows": {"TSLA": self.row}}) as request:
            quote = stocks.main(["quote", "TSLA"])["quote"]
        request.assert_called_once_with(["TSLA"])
        self.assertEqual({key: quote[key] for key in ("price", "name", "currency", "previous", "marketState")},
                         {"price": 250, "name": "Tesla, Inc.", "currency": "USD", "previous": 245, "marketState": "REGULAR"})
        self.assertFalse(quote["stale"])

    def test_failed_quote_keeps_the_saved_price_marked_stale(self):
        with patch.object(market_bulk, "quotes", return_value={"rows": {"TSLA": self.row}}):
            stocks.main(["quote", "TSLA"])
        self.clock.return_value += 120
        with patch.object(market_bulk, "quotes", side_effect=OSError("offline")) as request:
            quote = stocks.main(["quote", "TSLA"])["quote"]
        request.assert_called_once_with(["TSLA"])
        self.assertEqual(quote["price"], 250)
        self.assertTrue(quote["stale"])
        self.assertEqual(quote["error"], "offline")


if __name__ == "__main__":
    unittest.main()
