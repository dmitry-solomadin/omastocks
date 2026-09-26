"""Bulk watchlist quote requests and caching."""
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
        self.assertTrue(all(row["price"] == 123 and not row["stale"] for row in result["favoriteEntries"]))

    def test_large_symbol_sets_are_chunked_and_fresh_quotes_are_cached(self):
        tickers = ["T%d" % index for index in range(145)]
        self.repo.refresh_quotes(tickers)
        self.assertEqual([len(call.args[0]) for call in self.request.call_args_list], [70, 70, 5])
        self.repo.refresh_quotes(tickers)
        self.assertEqual(self.request.call_count, 3)


if __name__ == "__main__":
    unittest.main()
