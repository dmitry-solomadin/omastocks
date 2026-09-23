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

    def test_sort_persists_per_list_without_changing_memberships_or_custom_order(self):
        repo = stocks.Repository(self.path)
        original = copy.deepcopy(repo.state["entries"])
        repo.watchlist("sort", "default", "marketCap")
        other = repo.watchlist("create", name="Other")["activeWatchlist"]
        repo.watchlist("sort", other, "name")
        reopened = stocks.Repository(self.path)
        self.assertEqual(reopened.state["watchlists"][0]["entries"], original)
        sorts = {row["id"]: row["sort"] for row in reopened.snapshot()["watchlists"]}
        self.assertEqual(sorts, {"default": "marketCap", other: "name"})
        reopened.watchlist("sort", "default", "custom")
        reopened.watchlist("select", "default")
        self.assertEqual(reopened.state["entries"], original)
        before = repo.state_path.read_bytes()
        with self.assertRaises(ValueError): reopened.watchlist("sort", "default", "invalid")
        self.assertEqual(repo.state_path.read_bytes(), before)


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

    def summary_document(self, bought="97,699", sold="201,847", buys="10", sells="11"):
        return {"numberOfSharesTraded":{"rows":[
            {"insiderTrade":"Number of Shares Bought","months3":bought,"months12":"999,999"},
            {"insiderTrade":"Number of Shares Sold","months3":sold,"months12":"0"}]},
            "numberOfTrades":{"rows":[{"insiderTrade":"Number of Open Market Buys","months3":buys},
                                       {"insiderTrade":"Number of Sells","months3":sells}]}}

    def test_insider_summary_uses_provider_totals_not_visible_transactions(self):
        document = self.summary_document()
        # The recent-page sample is a purchase but the complete summary is net selling.
        document["transactionTable"] = {"table":{"rows":[{"lastDate":"9/21/2026","insider":"PERSON","transactionType":"Buy","sharesTraded":"5"}]}}
        report = company_activity.parse_insiders(document,"TEST",research.date_string)
        summary = report["summary"]
        self.assertEqual(summary["netShares"],-104148)
        self.assertAlmostEqual(summary["buyFraction"],97699 / 299546)
        self.assertEqual((summary["buyTrades"],summary["sellTrades"]),(10,11))
        self.assertEqual(len(report["rows"]),1)

    def test_insider_summary_distinguishes_missing_zero_and_balanced(self):
        for bought,sold,net,fraction in [("0","0",0,None),("100","0",100,1),("0","100",-100,0),
                                         ("100","100",0,.5),("N/A","100",None,None),(None,"100",None,None),
                                         ("-2","100",None,None),(True,"100",None,None),("inf","100",None,None)]:
            with self.subTest(bought=bought,sold=sold):
                summary = company_activity.parse_summary(self.summary_document(bought,sold))
                self.assertEqual(summary["netShares"],net)
                self.assertEqual(summary["buyFraction"],fraction)
        summary = company_activity.parse_summary(self.summary_document(buys="1.5",sells="—"))
        self.assertIsNone(summary["buyTrades"])
        self.assertIsNone(summary["sellTrades"])

    def test_insider_summary_survives_missing_details_without_fabricating_transactions(self):
        report = company_activity.parse_insiders(self.summary_document(),"TEST",research.date_string)
        self.assertEqual(report["rows"],[])
        self.assertEqual(report["summary"]["netShares"],-104148)
        self.assertIn("unavailable",report["notice"])
        report = company_activity.parse_insiders({"transactionTable":{"table":{"rows":[]}}},"TEST",research.date_string)
        self.assertIsNone(report["summary"]["netShares"])

    def test_old_insider_cache_is_refreshed_and_removed_filings_action_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(research,"state_directory",return_value=Path(directory)):
            with patch.object(research,"load",return_value={"symbol":"TEST","rows":[]}) as load:
                research.main(["insiders","TEST"])
                load.return_value = {"symbol":"TEST","rows":[],"insiderSchema":2,"summary":{"netShares":123}}
                result = research.main(["insiders","TEST"])
                self.assertEqual(result["summary"]["netShares"],123)
                research.main(["insiders","TEST"])
                self.assertEqual(load.call_count,2)
            with self.assertRaises(ValueError): research.main(["filings","TEST"])

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
            for action in ["overview","calendar","fundamentals","insiders"]:
                args = [action,"TEST"] + (["annual"] if action=="fundamentals" else [])
                with patch.object(research,"load",return_value={"symbol":"TEST","sentinel":action,"insiderSchema":2,
                    "overviewSchema":2,"baselineDay":datetime.now(timezone.utc).date().isoformat(),"timezone":"UTC"}) as load:
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
