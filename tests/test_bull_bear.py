import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import ai_jobs
import ai_runner
import bull_bear
import reports
from stocks import read_json, write_json


AGENT = {"id": "opencode", "name": "OpenCode", "executable": "/usr/bin/opencode"}
JOB = {"symbol": "AMD", "id": "a" * 32, "agent": AGENT}
CONTEXT = {"symbol": "AMD", "name": "Advanced Micro Devices, Inc.", "captured": 100,
           "quote": {"price": 216.42, "percent": -1.84, "currency": "USD", "marketCap": 3.512e11, "yearLow": 76.48, "yearHigh": 267.08},
           "valuation": [{"label": "P/E (TTM)", "value": 124.3}], "sector": "Electronic Technology", "industry": "Semiconductors",
           "nextEarnings": "2026-11-04"}


def point(title, *sources):
    return {"title": title, "detail": title + " explained with specifics.", "sources": list(sources)}


def response():
    return {"summary": "AMD designs CPUs and GPUs. The debate is AI accelerator share.",
            "bull": [point("GPUs ramp", "q3"), point("Server share", "q3", "share")],
            "bear": [point("Valuation"), point("Export controls", "news")],
            "watch": ["Q4 earnings"],
            "sources": [{"id": "q3", "title": "Q3 results", "url": "https://ir.amd.com/q3"},
                        {"id": "share", "title": "Server share", "url": "https://example.com/share"},
                        {"id": "news", "title": "Export curbs", "url": "https://www.reuters.com/amd"}]}


class ValidationTests(unittest.TestCase):
    def test_sources_become_numbers_in_listed_order(self):
        result = bull_bear.validate(response(), JOB, CONTEXT)
        self.assertEqual(result["bull"][1]["sources"], [1, 2])
        self.assertEqual(result["bear"][0]["sources"], [])
        self.assertEqual(result["bear"][1]["sources"], [3])
        self.assertEqual([source["title"] for source in result["sources"]], ["Q3 results", "Server share", "Export curbs"])
        self.assertEqual(result["snapshot"]["quote"]["price"], 216.42)

    def test_invented_sources_bad_links_and_thin_cases_are_rejected(self):
        documents = []
        for change in (lambda document: document["bull"][0]["sources"].append("invented"),
                       lambda document: document["sources"][0].update(url="javascript:alert(1)"),
                       lambda document: document["sources"].append(dict(document["sources"][0])),
                       lambda document: document["bear"].pop(),
                       lambda document: document.update(summary=" "),
                       lambda document: document.update(watch="Q4")):
            document = response()
            change(document)
            documents.append(document)
        for document in documents:
            with self.subTest(document=document), self.assertRaises(ValueError):
                bull_bear.validate(document, JOB, CONTEXT)

    def test_prompt_is_short_and_carries_the_schema(self):
        text = bull_bear.prompt(JOB, CONTEXT)
        self.assertIn("Advanced Micro Devices, Inc. (AMD)", text)
        self.assertIn('"bear"', text)
        self.assertLessEqual(len(text.strip().split("\n")), 10)


class ReportTests(unittest.TestCase):
    def test_report_is_self_contained_and_escapes_agent_text(self):
        document = response()
        document["bull"][0]["title"] = "<script>alert(1)</script>"
        document["sources"][0]["title"] = '"><img src=x onerror=alert(1)>'
        page = bull_bear.render(bull_bear.validate(document, JOB, CONTEXT))
        self.assertIn("default-src 'none'", page)
        self.assertNotIn("<script", page)
        self.assertNotIn("<img", page)
        self.assertIn("&lt;script&gt;", page)
        self.assertIn('<a href="#source-2">2</a>', page)
        self.assertIn('id="source-3"', page)
        self.assertIn("reuters.com", page)
        self.assertIn("124.3", page)
        self.assertIn("351.20B USD", page)


class JobTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(os.environ, {"STOCKS_STATE_DIR": self.temp.name})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.path = ai_jobs.directory(bull_bear.TASK, "AMD", "default")

    def test_worker_saves_result_and_html_report_and_notifies_by_name(self):
        write_json(self.path / "job.json", {**JOB, "state": "running", "notifyRequested": True})
        with patch.object(ai_jobs.signal, "signal"), patch.object(ai_jobs.signal, "alarm"), \
             patch.object(bull_bear, "context", return_value=CONTEXT), patch.object(ai_runner, "run", return_value=response()) as run, \
             patch.object(ai_jobs.subprocess, "run") as notify:
            ai_jobs.worker(bull_bear.TASK, "AMD", "default", JOB["id"])
        self.assertEqual(run.call_args.kwargs["title"], "Stocks · Bull & bear case")
        result = read_json(self.path / "result.json", {})
        self.assertEqual(read_json(self.path / "job.json", {})["state"], "complete")
        self.assertEqual(result["html"], str(self.path / "report.html"))
        self.assertIn("GPUs ramp", (self.path / "report.html").read_text())
        self.assertIn("AMD · Bull & bear ready", notify.call_args.args[0])
        self.assertEqual(bull_bear.main(["status", "AMD", "default"])["bull"][0]["title"], "GPUs ramp")

    def test_existing_report_is_reused_however_old_until_refresh(self):
        write_json(self.path / "result.json", {**bull_bear.validate(response(), {**JOB, "agent": {**AGENT, "id": "opencode"}}, CONTEXT), "generated": 0})
        with patch.object(ai_runner, "resolve", return_value=AGENT), patch.object(ai_jobs, "process_identity", return_value="boot:1"), \
             patch.object(ai_jobs.subprocess, "Popen", return_value=Mock(pid=12345)) as launch:
            reply = bull_bear.main(["start", "AMD", "default"])
            self.assertFalse(reply["pending"])
            self.assertFalse(reply["stale"])
            launch.assert_not_called()
            bull_bear.main(["start", "AMD", "default", "--force"])
            launch.assert_called_once()

    def test_export_saves_a_named_copy_without_replacing_other_files(self):
        downloads = Path(self.temp.name) / "Downloads"
        downloads.mkdir()
        self.assertIn("no report", bull_bear.main(["export", "AMD", "default"])["error"])
        result = {**bull_bear.validate(response(), JOB, CONTEXT), "generated": 1791849600}
        write_json(self.path / "result.json", result)
        with patch.object(reports, "downloads", return_value=downloads):
            first = bull_bear.main(["export", "AMD", "default"])
            self.assertEqual(Path(first["file"]).name, "AMD-bull-bear-" + bull_bear.datetime.fromtimestamp(1791849600).date().isoformat() + ".html")
            self.assertEqual(bull_bear.main(["export", "AMD", "default"])["file"], first["file"])
            Path(first["file"]).write_text("someone else's file")
            second = bull_bear.main(["export", "AMD", "default"])
            self.assertTrue(second["file"].endswith("-2.html"))
            self.assertEqual(Path(first["file"]).read_text(), "someone else's file")
            self.assertEqual(second["generated"], 1791849600)


if __name__ == "__main__":
    unittest.main()
