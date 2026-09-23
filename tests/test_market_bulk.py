from datetime import date, datetime, timezone
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import calendar_bulk
import market_bulk
import research
import stocks
import yahoo_http


def page(rows, total=None):
    return {"finance": {"result": [{"total": len(rows) if total is None else total, "documents": [{
        "columns": [{"id": key} for key in calendar_bulk.FIELDS], "rows": rows}]}], "error": None}}


class BulkData(unittest.TestCase):
    def test_sector_matches_static_members_and_scales_fractional_changes(self):
        group = {"id": "technology", "name": "Technology", "source": "url", "members": [
            {"symbol": "AAA", "name": "Alpha"}, {"symbol": "MISS", "name": None}]}
        request = Mock(return_value={"data": {"key": "technology", "topCompanies": [
            {"symbol": "AAA", "regMarketChangePercent": {"raw": -.02}, "ytdReturn": {"raw": 0}},
            {"symbol": "EXTRA", "regMarketChangePercent": {"raw": .3}}]}})
        with patch.object(market_bulk, "presets", return_value=[group]):
            result = market_bulk.sector("technology", request)
        self.assertEqual(request.call_count, 1)
        self.assertEqual([r["symbol"] for r in result["rows"]], ["AAA", "MISS"])
        self.assertEqual(result["rows"][0]["percent"], -2)
        self.assertEqual(result["rows"][0]["ytd"], 0)
        self.assertIsNone(result["rows"][1]["percent"])
        self.assertEqual(result["coverage"], 1)

    def test_sector_identity_failure_does_not_become_empty_success(self):
        with self.assertRaises(ValueError):
            market_bulk.sector("technology", Mock(return_value={"data": {"key": "energy", "topCompanies": []}}))

    def test_quotes_use_one_request_and_preserve_zero_missing_and_currency_units(self):
        request = Mock(return_value={"quoteResponse": {"result": [
            {"symbol": "AAA.L", "regularMarketPrice": 1234, "regularMarketChange": -23, "regularMarketChangePercent": 0, "marketCap": 5000000, "currency": "GBp"},
            {"symbol": "ZERO", "regularMarketPrice": 0, "regularMarketChangePercent": None},
            {"symbol": "UNREQUESTED", "regularMarketPrice": 99}]}})
        rows = market_bulk.quotes(["AAA.L", "ZERO", "MISS"], request)["rows"]
        self.assertEqual(request.call_count, 1)
        self.assertEqual(rows["AAA.L"]["price"], 12.34)
        self.assertEqual(rows["AAA.L"]["currency"], "GBP")
        self.assertEqual(rows["AAA.L"]["percent"], 0)
        self.assertEqual(rows["AAA.L"]["change"], -.23)
        self.assertEqual(rows["AAA.L"]["marketCap"], 5000000)
        self.assertEqual(rows["ZERO"]["price"], 0)
        self.assertIsNone(rows["MISS"]["price"])
        self.assertNotIn("UNREQUESTED", rows)

    def test_session_state_is_provider_supplied_and_unknown_is_not_closed(self):
        for state, expected in [("REGULAR", "REGULAR"), ("CLOSED", "CLOSED"), ("PRE", "PRE"), ("POST", "POST"), (None, ""), ("UNKNOWN", "")]:
            result = market_bulk.parse_quotes({"quoteResponse": {"result": [{"symbol": "^SPX", "marketState": state}]}}, ["^SPX"])
            self.assertEqual(result["rows"]["^SPX"]["marketState"], expected)

    def test_calendar_paginates_and_keeps_eps_zeros_negative_values_and_timing(self):
        request = Mock(side_effect=[page([["AAA", "2026-08-01T20:00:00Z", "TAS", -.2, -.1]], 3),
                                   page([["AAA", "2026-11-01T20:00:00Z", "AMC", 0, None],
                                         ["BBB", "2026-12-01T00:00:00Z", "TNS", None, None]], 3)])
        result = calendar_bulk.calendar(["AAA", "BBB"], request, date(2026, 9, 22))
        self.assertEqual(request.call_count, 2)
        self.assertEqual(request.call_args_list[1].kwargs["body"]["offset"], 1)
        self.assertEqual(result["rows"]["AAA"]["next"]["forecast"], 0)
        self.assertEqual(result["rows"]["AAA"]["next"]["timing"], "After market close")
        self.assertEqual(result["rows"]["BBB"]["next"]["timing"], "")
        self.assertEqual(result["rows"]["AAA"]["events"][0]["eps"], -.1)
        self.assertEqual(result["rows"]["AAA"]["next"]["currency"], "")

    def test_incomplete_or_changing_calendar_is_failure(self):
        for pages in ([page([], 1)], [page([["AAA", "2026-11-01", "AMC", 0, None]], 2), page([], 3)]):
            with self.subTest(pages=pages), self.assertRaises(ValueError):
                calendar_bulk.calendar(["AAA"], Mock(side_effect=pages), date(2026, 9, 22))

    def test_calendar_uses_column_ids_not_position_or_labels(self):
        doc = page([["AAA", "2026-11-01T20:00:00Z", "BMO", 0, None]])
        table = doc["finance"]["result"][0]["documents"][0]
        table["columns"].reverse(); table["rows"][0].reverse()
        rows, _ = calendar_bulk.parse_page(doc)
        self.assertEqual(rows[0]["ticker"], "AAA")
        self.assertEqual(rows[0]["epsestimate"], 0)

    def test_calendar_deduplicates_and_rejects_conflicts(self):
        event = {"ticker": "AAA", "startdatetime": "2026-11-01T20:00:00Z", "epsestimate": 1, "epsactual": None}
        rows = calendar_bulk.summarize([event, event], ["AAA", "MISS"], date(2026, 9, 22))
        self.assertEqual(rows["AAA"]["next"]["forecast"], 1)
        self.assertIsNone(rows["MISS"]["next"])
        with self.assertRaises(ValueError):
            calendar_bulk.summarize([event, {**event, "epsestimate": 2}], ["AAA"], date(2026, 9, 22))


class BulkCaching(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        context = patch.dict(os.environ, {"STOCKS_STATE_DIR": self.temp.name})
        context.start(); self.addCleanup(context.stop)

    def test_semantic_symbol_set_shares_cache_and_manual_refresh_bypasses_it(self):
        with patch.object(research, "load", return_value={"quotesSchema": 3, "rows": {"AAA": {"price": 1}}}) as load:
            research.main(["quotes", "BBB,AAA,AAA"])
            research.main(["quotes", "AAA,BBB"])
            self.assertEqual(load.call_count, 1)
            research.main(["quotes", "BBB,AAA", "--force"])
            self.assertEqual(load.call_count, 2)

    def test_failed_bulk_refresh_retains_all_saved_rows_and_force_retries(self):
        with patch.object(research, "load", return_value={"quotesSchema": 3, "rows": {"AAA": {"price": 1}, "BBB": {"price": 2}}}) as load:
            research.main(["quotes", "AAA,BBB"])
            load.side_effect = ValueError("Unavailable")
            result = research.main(["quotes", "AAA,BBB", "--force"])
            self.assertEqual(len(result["rows"]), 2)
            self.assertTrue(result["stale"])
            research.main(["quotes", "AAA,BBB"])
            self.assertEqual(load.call_count, 2)
            research.main(["quotes", "AAA,BBB", "--force"])
            self.assertEqual(load.call_count, 3)

    def test_history_baselines_refresh_on_exchange_date_rollover_not_five_minutes(self):
        result = {"overviewSchema": 2, "baselineDay": "2026-09-22", "timezone": "UTC"}
        with patch.object(research, "datetime") as clock, patch.object(research, "load", return_value=result) as load:
            clock.now.return_value = datetime(2026, 9, 22, tzinfo=timezone.utc)
            research.main(["overview", "AAA"])
            research.main(["overview", "AAA"])
            research.main(["overview", "AAA", "--keep-baselines", "--force"])
            self.assertEqual(load.call_count, 1)
            clock.now.return_value = datetime(2026, 9, 23, tzinfo=timezone.utc)
            research.main(["overview", "AAA"])
            self.assertEqual(load.call_count, 2)

    def test_429_is_shared_across_authenticated_and_chart_requests_even_for_force(self):
        error = urllib.error.HTTPError("https://query1.finance.yahoo.com", 429, "Limited", {"Retry-After": "600"}, None)
        with patch.object(yahoo_http.time, "time", return_value=1000), patch.object(yahoo_http.urllib.request, "urlopen", side_effect=error) as request:
            with self.assertRaises(ValueError): stocks.fetch("/v8/finance/chart/AAA")
            state = stocks.read_json(self.directory / "yahoo/traffic.json", {})
            self.assertGreaterEqual(state["retryAfter"], 1600)
            with self.assertRaises(ValueError): yahoo_http.authenticated("/v7/finance/quote", symbols="AAA")
            result = research.main(["compare", "AAA", "1D", "--force"])
            self.assertIn("rate limiting", result["error"])
            self.assertEqual(request.call_count, 1)

    def test_retry_after_http_date_and_exponential_backoff(self):
        with patch.object(yahoo_http.time, "time", return_value=1000):
            yahoo_http.throttled({"Retry-After": "Thu, 01 Jan 1970 00:30:00 GMT"})
            state = stocks.read_json(self.directory / "yahoo/traffic.json", {})
            self.assertEqual(state["retryAfter"], 1800)
            yahoo_http.throttled({})
            self.assertEqual(stocks.read_json(self.directory / "yahoo/traffic.json", {})["retryAfter"], 1800)
        with patch.object(yahoo_http.time, "time", return_value=1801):
            yahoo_http.throttled({})
            self.assertEqual(stocks.read_json(self.directory / "yahoo/traffic.json", {})["retryAfter"], 2281)


if __name__ == "__main__":
    unittest.main()
