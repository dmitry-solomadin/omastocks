import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import stocks
import research
import overview
import fundamental_compare
import company_activity
import earnings_calendar


class Watchlists(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)

    def test_legacy_migration_preserves_order_metadata_and_empty_lists(self):
        for entries in ([], [{"symbol":"ELF", "favorite":True, "name":"ELF", "custom":"keep"}, {"symbol":"AMD"}]):
            with self.subTest(entries=entries):
                stocks.write_json(self.path / "watchlist.json", {"entries":entries,"custom":"keep"})
                repo = stocks.Repository(self.path)
                self.assertEqual(repo.state["entries"], entries)
                self.assertEqual(repo.snapshot()["activeWatchlist"], "default")
                repo.watchlist("rename", "default", "Original")
                reopened = stocks.Repository(self.path)
                self.assertEqual(reopened.state["entries"], entries)
                self.assertEqual(reopened.state["custom"], "keep")

    def test_memberships_order_favorites_and_removal_are_independent(self):
        repo = stocks.Repository(self.path)
        original = copy.deepcopy(repo.state["entries"])
        new = repo.watchlist("create", name="Technology")["activeWatchlist"]
        repo.mutate("add", "AMD")
        repo.mutate("add", "AAPL")
        self.assertTrue(repo.state["entries"][-1]["favorite"])
        repo.move("AAPL", "AMD")
        self.assertEqual([r["symbol"] for r in repo.state["watchlists"][0]["entries"]], [r["symbol"] for r in original])
        repo.mutate("favorite", "AAPL")
        self.assertFalse(any(r["symbol"] == "AAPL" for r in repo.snapshot()["favoriteEntries"]))
        repo.mutate("favorite", "AAPL")
        repo.mutate("remove", "AAPL")
        self.assertTrue(any(r["symbol"] == "AAPL" for r in repo.snapshot()["favoriteEntries"]))
        repo.watchlist("remove", new)
        self.assertEqual(repo.state["entries"], original)
        self.assertEqual(stocks.Repository(self.path).snapshot()["activeWatchlist"], "default")

    def test_queued_mutation_targets_its_original_list(self):
        repo = stocks.Repository(self.path)
        repo.watchlist("create", name="Other")
        repo.mutate("add", "ELF", list_id="default")
        self.assertEqual(repo.state["entries"], [])
        repo.watchlist("select", "default")
        self.assertEqual(repo.state["entries"][-1]["symbol"], "ELF")
        with self.assertRaises(ValueError):
            repo.mutate("add", "NVDA", list_id="gone")

    def test_invalid_changes_and_malformed_lists_preserve_file(self):
        repo = stocks.Repository(self.path)
        repo.watchlist("rename", "default", "Watchlist")
        original = repo.state_path.read_text()
        for args in [("remove", "default", ""), ("create", "", "watchLIST"), ("create", "", " "), ("select", "missing", "")]:
            with self.assertRaises(ValueError):
                repo.watchlist(*args)
            self.assertEqual(repo.state_path.read_text(), original)
        broken = {"entries":[],"watchlists":[],"activeWatchlist":"nope"}
        stocks.write_json(repo.state_path, broken)
        with self.assertRaises(ValueError):
            stocks.Repository(self.path)
        self.assertEqual(json.loads(repo.state_path.read_text()), broken)


class ResearchFeatures(unittest.TestCase):
    def test_price_returns_use_preceding_close_and_require_sufficient_history(self):
        chart = {"price":120, "timezone":"UTC", "updated":1,
                 "dates":["2025-09-22","2025-12-31","2026-08-21","2026-09-15","2026-09-22"],
                 "points":[[1,60],[2,80],[3,100],[4,110],[5,120]],"currency":"USD"}
        with patch.object(overview,"parse_chart",return_value=chart), patch.object(overview,"datetime") as clock:
            clock.now.return_value = datetime(2026,9,22,tzinfo=timezone.utc)
            result = overview.performance({},"TEST")
            self.assertEqual(result["baselines"]["1M"], "2026-08-21")
            self.assertAlmostEqual(result["returns"]["1M"],20)
            self.assertEqual(result["returns"]["YTD"],50)
            self.assertEqual(result["returns"]["1Y"],100)
            chart["dates"] = chart["dates"][2:]; chart["points"] = chart["points"][2:]
            result = overview.performance({},"IPO")
            self.assertIsNone(result["returns"]["1Y"])
            self.assertIsNone(result["returns"]["YTD"])

    def test_comparison_keeps_latest_missing_cells_currency_and_period(self):
        report = {"statements":[{"id":"income","dates":["2026-06-30","2025-06-30"],"rows":[
            {"key":"TotalRevenue","values":[None,10],"currencies":["","EUR"]},
            {"key":"operatingMargin","values":[0,5],"currencies":["",""]}]}]}
        result = fundamental_compare.summarize(report,{},"TEST","quarterly")
        revenue = next(c for c in result["cells"] if c["key"]=="TotalRevenue")
        self.assertIsNone(revenue["value"])
        self.assertEqual(revenue["date"],"2026-06-30")
        self.assertEqual(next(c for c in result["cells"] if c["key"]=="operatingMargin")["value"],0)

    def test_filings_validate_dates_links_identity_and_deduplicate(self):
        good = {"filed":"09/21/2026","period":"06/30/2026","formType":"10-Q", "view":{"htmlLink":"https://app.quotemedia.com/data/downloadFiling?ref=1&formDescription=Quarterly+report"}}
        doc = {"symbol":"TEST","rows":[good,good,{**good,"filed":"bad"},{**good,"view":{"htmlLink":"javascript:alert(1)"}}]}
        result = company_activity.parse_filings(doc,"TEST",research.date_string)
        self.assertEqual(len(result["rows"]),1)
        self.assertEqual(result["rows"][0]["description"],"Quarterly report")
        with self.assertRaises(ValueError): company_activity.parse_filings(doc,"OTHER",research.date_string)
        with self.assertRaises(ValueError): company_activity.parse_filings({"symbol":"TEST"},"TEST",research.date_string)

    def test_insiders_preserve_transaction_types_missing_prices_and_zero(self):
        source = {"lastDate":"9/21/2026","insider":"PERSON","transactionType":"Option Execute", "sharesTraded":"1,234", "lastPrice":"", "sharesHeld":"0"}
        doc = {"transactionTable":{"table":{"rows":[source,{**source,"lastPrice":"$0.00","transactionType":"Disposition (Non Open Market)"}]}}}
        rows = company_activity.parse_insiders(doc,"TEST",research.date_string)["rows"]
        self.assertEqual(rows[0]["shares"],1234)
        self.assertIsNone(rows[0]["price"])
        self.assertEqual(rows[0]["held"],0)
        self.assertEqual(rows[1]["price"],0)
        self.assertEqual(rows[1]["type"],"Disposition (Non Open Market)")
        with self.assertRaises(ValueError): company_activity.parse_insiders({},"TEST",research.date_string)

    def test_calendar_does_not_invent_timing_and_retains_negative_forecasts(self):
        def request(path):
            return {"reportText":"Estimated to report 10/29/2026. The consensus EPS forecast for the quarter is $-0.12."} if "earnings-date" in path else {}
        def parse(a,b): return research.parse_earnings(a,b,today="2026-09-22")
        report = earnings_calendar.calendar("TEST",request,parse)
        self.assertEqual(report["next"]["forecast"],-.12)
        self.assertEqual(report["next"]["timing"],"")
        self.assertTrue(report["next"]["estimated"])

    def test_new_research_caches_keep_saved_results_and_manual_refresh_bypasses_backoff(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(research,"state_directory",return_value=Path(directory)):
            for action in ["overview","calendar","fundamentals","filings","insiders"]:
                args = [action,"TEST"] + (["annual"] if action=="fundamentals" else [])
                with patch.object(research,"load",return_value={"symbol":"TEST","sentinel":action}) as load:
                    saved = research.main(args)
                    self.assertEqual(research.main(args),saved)
                    load.side_effect = ValueError("offline")
                    failed = research.main(args+["--force"])
                    self.assertEqual(failed["sentinel"],action)
                    self.assertTrue(failed["stale"])
                    research.main(args)
                    self.assertEqual(load.call_count,2)
                    load.side_effect = None
                    self.assertFalse(research.main(args+["--force"])["stale"])
                    self.assertEqual(load.call_count,3)
