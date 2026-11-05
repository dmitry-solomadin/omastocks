from datetime import date, datetime, timezone
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error
from zoneinfo import ZoneInfo

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

    def test_extended_hours_prices_use_quote_units_and_missing_fields_are_none(self):
        rows = market_bulk.parse_quotes({"quoteResponse": {"result": [
            {"symbol": "HSBA.L", "currency": "GBp", "regularMarketPrice": 1516.4, "regularMarketTime": 1000,
             "hasPrePostMarketData": True, "preMarketPrice": 1520, "preMarketChange": 3.6,
             "preMarketChangePercent": 0.2374, "preMarketTime": 900,
             "postMarketPrice": 1510, "postMarketChange": -6.4, "postMarketChangePercent": -0.422, "postMarketTime": 1100},
            {"symbol": "AAPL", "currency": "USD", "regularMarketPrice": 338.4, "hasPrePostMarketData": False}]}},
            ["HSBA.L", "AAPL"])["rows"]
        pence = rows["HSBA.L"]
        expected = {"prePrice": 15.2, "preChange": .036, "prePercent": .2374, "preUpdated": 900,
                    "postPrice": 15.1, "postChange": -.064, "postPercent": -.422, "postUpdated": 1100}
        for field, value in expected.items():
            self.assertAlmostEqual(pence[field], value, msg=field)
        self.assertIs(pence["extendedData"], True)
        self.assertIs(rows["AAPL"]["extendedData"], False)
        for field in ("prePrice", "preChange", "prePercent", "preUpdated", "postPrice", "postChange", "postPercent", "postUpdated"):
            self.assertIsNone(rows["AAPL"][field], field)
        missing = market_bulk.parse_quotes({"quoteResponse": {"result": [{"symbol": "AAPL"}]}}, ["AAPL"])["rows"]["AAPL"]
        self.assertIsNone(missing["extendedData"])

    def test_session_state_is_provider_supplied_and_unknown_is_not_closed(self):
        for state, expected in [("REGULAR", "REGULAR"), ("CLOSED", "CLOSED"), ("PRE", "PRE"), ("POST", "POST"), (None, ""), ("UNKNOWN", "")]:
            result = market_bulk.parse_quotes({"quoteResponse": {"result": [{"symbol": "^SPX", "marketState": state}]}}, ["^SPX"])
            self.assertEqual(result["rows"]["^SPX"]["marketState"], expected)

    def futures_quotes(self, state, updated, price=26689.5, bars=None, spark=None):
        """Quotes for ^SPX and NQ=F, with `bars` as NQ=F's (stamp, close) spark rows."""
        calls = []

        def request(path, **parameters):
            calls.append((path, parameters))
            if path == "/v7/finance/quote":
                return {"quoteResponse": {"result": [
                    {"symbol": "^SPX", "regularMarketPrice": 7353.73, "marketState": state, "regularMarketTime": updated},
                    {"symbol": "NQ=F", "regularMarketPrice": price, "regularMarketChangePercent": -6.57, "marketState": "REGULAR"}]}}
            if isinstance(spark, Exception):
                raise spark
            if spark is not None:
                return spark
            return {"spark": {"result": [{"symbol": "NQ=F", "response": [{
                "timestamp": [stamp for stamp, _ in bars], "indicators": {"quote": [{"close": [value for _, value in bars]}]}}]}]}}
        return market_bulk.quotes(["^SPX", "NQ=F"], request)["rows"], calls

    def eastern(self, *moment):
        return datetime(*moment, tzinfo=ZoneInfo("America/New_York")).timestamp()

    def test_futures_change_runs_from_the_bar_ending_at_the_cash_close(self):
        bars = [(self.eastern(2026, 11, 5, 15, 50), 27000.0), (self.eastern(2026, 11, 5, 15, 55), 26746.5),
                (self.eastern(2026, 11, 5, 16, 0), 26686.25), (self.eastern(2026, 11, 5, 16, 35), 26689.5)]
        rows, calls = self.futures_quotes("POST", self.eastern(2026, 11, 5, 16, 34), bars=bars)
        self.assertAlmostEqual(rows["NQ=F"]["sinceClose"], (26689.5 / 26746.5 - 1) * 100)
        self.assertEqual(rows["NQ=F"]["percent"], -6.57, "Yahoo's own change stays for everything else")
        self.assertNotIn("sinceClose", rows["^SPX"])
        self.assertEqual(calls[1][1], {"symbols": "NQ=F", "range": "2d", "interval": "5m"})

    def test_overnight_and_weekend_keep_the_last_close(self):
        bars = [(self.eastern(2026, 11, 6, 15, 55), 100.0), (self.eastern(2026, 11, 6, 16, 55), 101.0),
                (self.eastern(2026, 11, 8, 18, 0), 102.0), (self.eastern(2026, 11, 9, 8, 0), 110.0)]
        # A Monday morning: the index last traded on Friday afternoon.
        rows, _ = self.futures_quotes("PRE", self.eastern(2026, 11, 6, 16, 20), price=110.0, bars=bars)
        self.assertAlmostEqual(rows["NQ=F"]["sinceClose"], 10.0)

    def test_a_short_session_ends_at_the_indexs_last_trade(self):
        bars = [(self.eastern(2026, 11, 27, 12, 55), 100.0), (self.eastern(2026, 11, 27, 13, 0), 200.0)]
        rows, _ = self.futures_quotes("CLOSED", self.eastern(2026, 11, 27, 13, 2), price=110.0, bars=bars)
        self.assertAlmostEqual(rows["NQ=F"]["sinceClose"], 10.0)

    def test_a_bar_still_open_at_the_close_or_without_a_price_is_skipped(self):
        bars = [(self.eastern(2026, 11, 5, 15, 50), 100.0), (self.eastern(2026, 11, 5, 15, 55), None),
                (self.eastern(2026, 11, 5, 15, 58), 200.0)]
        rows, _ = self.futures_quotes("POST", self.eastern(2026, 11, 5, 16, 30), price=110.0, bars=bars)
        self.assertAlmostEqual(rows["NQ=F"]["sinceClose"], 10.0)

    def test_the_regular_session_makes_no_extra_request(self):
        rows, calls = self.futures_quotes("REGULAR", self.eastern(2026, 11, 5, 11, 0), bars=[])
        self.assertEqual(len(calls), 1)
        self.assertNotIn("sinceClose", rows["NQ=F"])

    def test_without_a_baseline_the_quotes_survive_unchanged(self):
        after = self.eastern(2026, 11, 5, 16, 30)
        cases = [{"bars": [(self.eastern(2026, 11, 5, 17, 0), 100.0)]}, {"bars": []}, {"spark": ValueError("Rate limited")},
                 {"spark": OSError("Offline")}, {"spark": {"spark": {"error": "bad"}}}, {"spark": {}}, {"spark": {"spark": {"result": None}}},
                 {"spark": {"spark": {"result": [{"symbol": "NQ=F", "response": []}]}}},
                 {"spark": {"spark": {"result": [{"symbol": "NQ=F", "response": [{"timestamp": None, "indicators": {}}]}]}}}]
        for case in cases:
            rows, _ = self.futures_quotes("POST", after, **case)
            self.assertNotIn("sinceClose", rows["NQ=F"], case)
            self.assertEqual(rows["NQ=F"]["percent"], -6.57)

    def test_empty_or_unrelated_quote_response_cannot_replace_saved_prices(self):
        for rows in ([], [{"symbol": "OTHER", "regularMarketPrice": 1}]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                market_bulk.parse_quotes({"quoteResponse": {"result": rows}}, ["AAA"])

    def test_sparks_parse_intraday_closes_and_skip_missing_symbols(self):
        response = [{"meta": {"currency": "GBp", "regularMarketPrice": 250, "chartPreviousClose": 240,
                              "exchangeTimezoneName": "Europe/London",
                              "currentTradingPeriod": {"regular": {"start": 100, "end": 400}}},
                     "timestamp": [100, 200, 300], "indicators": {"quote": [{"close": [240, None, 250]}]}}]
        request = Mock(return_value={"spark": {"result": [
            {"symbol": "AAA.L", "response": response}, {"symbol": "EMPTY", "response": []},
            {"symbol": "OTHER", "response": response}], "error": None}})
        rows = market_bulk.sparks(["AAA.L", "EMPTY", "MISSING"], request)
        self.assertEqual(request.call_args.kwargs["symbols"], "AAA.L,EMPTY,MISSING")
        self.assertEqual(rows, {"AAA.L": {"points": [(100, 2.4), (300, 2.5)], "sessionStart": 100, "sessionEnd": 400}})
        with self.assertRaises(ValueError):
            market_bulk.sparks(["T%d" % index for index in range(21)], request)
        with self.assertRaises(ValueError):
            market_bulk.parse_sparks({"spark": {"result": None, "error": {"code": "Bad Request"}}}, ["AAA"])

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
        with patch.object(research, "load", return_value={"quotesSchema": 4, "rows": {"AAA": {"price": 1}}}) as load:
            research.main(["quotes", "BBB,AAA,AAA"])
            research.main(["quotes", "AAA,BBB"])
            self.assertEqual(load.call_count, 1)
            research.main(["quotes", "BBB,AAA", "--force"])
            self.assertEqual(load.call_count, 2)

    def test_failed_bulk_refresh_retains_all_saved_rows_and_force_retries(self):
        with patch.object(research, "load", return_value={"quotesSchema": 4, "rows": {"AAA": {"price": 1}, "BBB": {"price": 2}}}) as load:
            research.main(["quotes", "AAA,BBB"])
            load.side_effect = ValueError("Unavailable")
            result = research.main(["quotes", "AAA,BBB", "--force"])
            self.assertEqual(len(result["rows"]), 2)
            self.assertTrue(result["stale"])
            research.main(["quotes", "AAA,BBB"])
            self.assertEqual(load.call_count, 2)
            research.main(["quotes", "AAA,BBB", "--force"])
            self.assertEqual(load.call_count, 3)

    def test_failed_refresh_retries_after_cooldown_before_original_ttl(self):
        with patch.object(research.time, "time", return_value=1000) as clock, \
                patch.object(research, "load", return_value={"quotesSchema": 4, "rows": {"AAA": {"price": 1}}}) as load:
            research.main(["quotes", "AAA"])
            load.side_effect = ValueError("offline")
            research.main(["quotes", "AAA", "--force"])
            clock.return_value = 1119
            self.assertTrue(research.main(["quotes", "AAA"])["stale"])
            self.assertEqual(load.call_count, 2)
            load.side_effect = None
            clock.return_value = 1121
            self.assertFalse(research.main(["quotes", "AAA"])["stale"])
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
