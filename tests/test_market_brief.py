from datetime import datetime
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import ai_jobs
import ai_runner
import market_brief as brief
from stocks import read_json, write_json


AGENT = {"id": "opencode", "name": "OpenCode", "executable": "/usr/bin/opencode"}
JOB = {"symbol": "MARKET", "id": "a" * 32, "agent": AGENT}
CONTEXT = {"symbol": "MARKET", "captured": 100, "newYork": "Monday 12 October 2026, 16:30", "marketState": "POST", "sessionDate": "2026-10-12",
           "indexes": [{"symbol": "^SPX", "name": "S&P 500", "price": 7807.24, "change": -4.3, "percent": -0.06}],
           "futures": [], "assets": [{"symbol": "^TNX", "name": "US 10Y yield", "price": 5.24, "change": -0.004, "percent": -0.08},
                                     {"symbol": "^VIX", "name": "VIX", "price": 15.21, "change": 0.37, "percent": 2.49}],
           "sectors": [{"symbol": "XLE", "name": "Energy", "price": 90, "change": 1, "percent": 1.2},
                       {"symbol": "XLK", "name": "Technology", "price": 250, "change": -2, "percent": -0.8}],
           "fearGreed": None, "economicCalendar": [], "headlines": []}


def response():
    return {"headline": "Dow climbs as chip stocks drag the Nasdaq",
            "summary": "Stocks were mixed. Memory-chip makers fell while energy rose.",
            "drivers": [{"title": "Memory chips slide", "detail": "Micron fell after a downgrade.", "sources": ["mu"]},
                        {"title": "Oil lifts energy", "detail": "Crude rose on supply worries.", "sources": ["oil", "mu"]}],
            "movers": [{"symbol": "mu", "detail": "Fell on a downgrade.", "sources": ["mu"]}],
            "watch": ["CPI on Wednesday"],
            "sources": [{"id": "mu", "title": "Micron downgraded", "url": "https://example.com/mu"},
                        {"id": "oil", "title": "Oil climbs", "url": "https://www.reuters.com/oil"}]}


class ValidationTests(unittest.TestCase):
    def test_brief_keeps_its_session_and_numbers_sources(self):
        result = brief.validate(response(), JOB, CONTEXT)
        self.assertEqual(result["symbol"], "MARKET")
        self.assertEqual(result["drivers"][1]["sources"], [1, 2])
        self.assertEqual(result["movers"], [{"symbol": "MU", "detail": "Fell on a downgrade.", "sources": [1]}])
        self.assertEqual(result["session"], {"state": "POST", "date": "2026-10-12", "phase": "after the close"})

    def test_bad_movers_invented_sources_and_missing_drivers_are_rejected(self):
        for change in (lambda document: document["movers"][0].update(symbol="<b>MU"),
                       lambda document: document["movers"][0]["sources"].append("invented"),
                       lambda document: document.update(drivers=[]),
                       lambda document: document.update(headline=""),
                       lambda document: document["sources"][1].update(url="file:///etc/passwd")):
            document = response()
            change(document)
            with self.subTest(document=document), self.assertRaises(ValueError):
                brief.validate(document, JOB, CONTEXT)

    def test_prompt_is_short_and_carries_the_time_and_schema(self):
        text = brief.prompt(JOB, CONTEXT)
        self.assertIn("Monday 12 October 2026, 16:30 in New York", text)
        self.assertIn('"movers"', text)
        self.assertLessEqual(len(text.strip().split("\n")), 10)


class ReportTests(unittest.TestCase):
    def test_page_shows_the_snapshot_and_escapes_agent_text(self):
        document = response()
        document["headline"] = "<script>alert(1)</script>"
        page = brief.render(brief.validate(document, JOB, CONTEXT))
        self.assertIn("default-src 'none'", page)
        self.assertNotIn("<script", page)
        self.assertIn("<h1>&lt;script&gt;", page)
        self.assertIn('<dd class=down>7,807.24 (-0.06%)</dd>', page)
        self.assertIn("<dd>5.24% (-0.4 bp)</dd>", page, "Yields move in basis points, without a direction colour")
        self.assertIn("<dd>15.21 (+2.49%)</dd>", page, "A rising VIX is not coloured as a gain")
        self.assertIn('<span class="up">+1.20%</span>', page)
        self.assertIn("written after the close", page)
        self.assertIn('<a href="#source-1">1</a>, <a href="#source-2">2</a>', page)

    def test_context_snapshot_from_cached_market_data(self):
        stamp = datetime(2026, 10, 12, 20, 0).timestamp()
        rows = {"^SPX": {"price": 7807.237, "change": -4.29980, "percent": -0.055044, "updated": stamp, "marketState": "POST"},
                "XLE": {"price": 90, "percent": 1.2}, "XLK": {"price": 250, "percent": -0.8}}
        leads = {"sentiment": {"score": 45.7, "rating": "neutral", "previousClose": 45},
                 "economic-calendar": {"events": [{"title": "CPI", "time": stamp + 2 * 86400, "forecast": .2}]},
                 "market-news": {"articles": [{"title": "Stocks mixed", "source": "Reuters", "url": "https://x"}]}}
        with patch.object(brief.market_bulk, "quotes", return_value={"rows": rows}), \
             patch.object(brief.research, "main", side_effect=lambda arguments: leads[arguments[0]]):
            context = brief.context("MARKET")
        self.assertEqual(context["indexes"], [{"symbol": "^SPX", "name": "S&P 500", "price": 7807.24, "change": -4.2998, "percent": -0.06}])
        self.assertEqual([row["symbol"] for row in context["sectors"]], ["XLE", "XLK"])
        self.assertEqual(context["economicCalendar"][0]["title"], "CPI")
        self.assertEqual(context["headlines"], [{"title": "Stocks mixed", "source": "Reuters"}])
        self.assertEqual(context["marketState"], "POST")
        with patch.object(brief.market_bulk, "quotes", return_value={"rows": {}}), self.assertRaisesRegex(ValueError, "unavailable"):
            brief.context("MARKET")


class JobTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(os.environ, {"STOCKS_STATE_DIR": self.temp.name})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.path = ai_jobs.directory(brief.TASK, "MARKET", "default")

    def test_worker_saves_brief_and_page_and_exports_a_dated_copy(self):
        write_json(self.path / "job.json", {**JOB, "state": "running"})
        with patch.object(ai_jobs.signal, "signal"), patch.object(ai_jobs.signal, "alarm"), \
             patch.object(brief, "context", return_value=CONTEXT), patch.object(ai_runner, "run", return_value=response()) as run:
            ai_jobs.worker(brief.TASK, "MARKET", "default", JOB["id"])
        self.assertEqual(run.call_args.kwargs["title"], "Stocks · Market brief")
        self.assertEqual(read_json(self.path / "job.json", {})["state"], "complete")
        self.assertIn("Memory chips slide", (self.path / "report.html").read_text())
        self.assertEqual(brief.main(["status", "MARKET", "default"])["headline"], response()["headline"])
        downloads = Path(self.temp.name) / "Downloads"
        downloads.mkdir()
        with patch.object(brief.reports, "downloads", return_value=downloads):
            saved = brief.main(["export", "MARKET", "default"])
        self.assertRegex(Path(saved["file"]).name, r"^market-brief-\d{4}-\d{2}-\d{2}-\d{4}\.html$")


if __name__ == "__main__":
    unittest.main()
