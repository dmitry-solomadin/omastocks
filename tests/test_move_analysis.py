from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import ai_runner
import move_analysis as analysis
import move_context as context
from stocks import read_json, write_json


AGENT = {"id": "codex", "name": "Codex", "executable": "/usr/bin/codex"}
JOB = {"symbol": "AMD", "id": "a" * 32, "agent": AGENT}
CONTEXT = {"captured": 100, "latestMove": {"kind": "regular", "updated": 100, "date": "2026-10-12", "percent": -2}}


def response():
    return {"symbol": "AMD", "request": JOB["id"], "researchStatus": "complete", "assessment": "inferred",
            "sentences": [{"text": "AMD's decline appears linked to weaker sentiment toward chip suppliers as investors question whether demand will justify ambitious infrastructure spending plans.", "sources": ["news"]}],
            "sources": [{"id": "news", "title": "Chip stocks retreat", "url": "https://example.com/chips",
                         "published": "2026-10-12", "evidence": "Chip suppliers fell alongside concern about AI spending."}]}


class ValidationTests(unittest.TestCase):
    def test_paragraph_preserves_sentence_source_mapping(self):
        result = analysis.validate(response(), JOB, CONTEXT)
        self.assertEqual(result["summary"], response()["sentences"][0]["text"])
        self.assertEqual(result["sentences"][0]["sources"], ["news"])
        self.assertEqual(result["session"], CONTEXT["latestMove"])

    def test_wrong_stock_job_unresearched_and_uncited_results_are_rejected(self):
        for field, value in (("symbol", "META"), ("request", "other"), ("researchStatus", "unavailable"), ("assessment", "certain")):
            with self.subTest(field=field), self.assertRaises(ValueError):
                analysis.validate({**response(), field: value}, JOB, CONTEXT)
        for refs in ([], ["invented"], [{}]):
            document = response()
            document["sentences"][0]["sources"] = refs
            with self.assertRaises(ValueError):
                analysis.validate(document, JOB, CONTEXT)

    def test_bad_links_duplicate_ids_repeated_prices_and_long_output_rejected(self):
        for url in ("file:///etc/passwd", "javascript:alert(1)", "https://user:secret@example.com", "https://example.com/\n"):
            document = response()
            document["sources"][0]["url"] = url
            with self.assertRaises(ValueError):
                analysis.validate(document, JOB, CONTEXT)
        for text in ("AMD fell 5% today.", "First paragraph.\nSecond paragraph.", "word " * 181):
            document = response()
            document["sentences"][0]["text"] = text
            with self.assertRaises(ValueError):
                analysis.validate(document, JOB, CONTEXT)
        document = response()
        document["sources"] *= 2
        with self.assertRaises(ValueError):
            analysis.validate(document, JOB, CONTEXT)


class AdapterTests(unittest.TestCase):
    def test_native_final_output_and_successful_research_required(self):
        streams = {
            "opencode": [{"type": "tool_use", "part": {"tool": "websearch", "state": {"status": "completed"}}},
                         {"type": "text", "part": {"text": json.dumps(response())}},
                         {"type": "step_finish", "part": {"reason": "stop"}}],
            "codex": [{"type": "item.completed", "item": {"type": "web_search", "status": "completed"}},
                      {"type": "item.completed", "item": {"type": "agent_message", "text": json.dumps(response())}},
                      {"type": "turn.completed"}],
            "claude": [{"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "WebSearch", "id": "web1"}]}},
                       {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "web1", "content": "news"}]}},
                       {"type": "result", "subtype": "success", "structured_output": response()}]
        }
        for kind, events in streams.items():
            with self.subTest(kind=kind):
                parser = ai_runner.Output(kind)
                for event in events:
                    parser.feed(event)
                self.assertEqual(parser.result(), response())
                parser.failed = True
                with self.assertRaises(ValueError):
                    parser.result()
                parser.failed, parser.researched = False, False
                with self.assertRaisesRegex(ValueError, "web research"):
                    parser.result()

    def test_failed_web_tool_is_not_evidence(self):
        parser = ai_runner.Output("claude")
        parser.feed({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "WebSearch", "id": "web1"}]}})
        parser.feed({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "web1", "is_error": True}]}})
        self.assertFalse(parser.researched)

    def test_opencode_reconciled_final_message_requires_successful_exit(self):
        parser = ai_runner.Output("opencode")
        parser.feed({"type": "tool_use", "part": {"tool": "webfetch", "state": {"status": "completed"}}})
        parser.feed({"type": "text", "part": {"text": json.dumps(response())}})
        with self.assertRaises(ValueError):
            parser.result()
        self.assertEqual(parser.result(successful_exit=True), response())

    def test_default_agent_resolution_and_no_silent_fallback(self):
        with patch.object(ai_runner.shutil, "which", side_effect=lambda value: "/missing/" + value), \
             patch.object(ai_runner.subprocess, "run", return_value=Mock(stdout="opencode\n")):
            self.assertEqual(ai_runner.resolve("default")["executable"], "/missing/opencode2")
            with self.assertRaisesRegex(ValueError, "Choose Claude"):
                ai_runner.resolve("gemini")

    def test_actual_subprocess_stream_and_timeout(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            events = [{"type": "item.completed", "item": {"type": "web_search", "status": "completed"}},
                      {"type": "item.completed", "item": {"type": "agent_message", "text": json.dumps(response())}},
                      {"type": "turn.completed"}]
            script = "import os,sys; assert os.environ['PWD'] == os.getcwd(); sys.stdin.read(); print(" + repr("\n".join(map(json.dumps, events))) + ")"
            with patch.object(ai_runner, "command", return_value=[sys.executable, "-c", script]):
                self.assertEqual(ai_runner.run(AGENT, "test context", analysis.SCHEMA, path), response())
            with patch.object(ai_runner, "command", return_value=[sys.executable, "-c", "import time; time.sleep(30)"]):
                with self.assertRaisesRegex(ValueError, "timed out"):
                    ai_runner.run(AGENT, "test", analysis.SCHEMA, path, timeout=.1)


class JobTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(os.environ, {"STOCKS_STATE_DIR": self.temp.name})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.path = analysis.directory("AMD", "default")
        self.saved = analysis.validate(response(), JOB, CONTEXT)

    def test_status_never_starts_agent_or_fetches_data(self):
        with patch.object(ai_runner, "resolve") as resolve, patch.object(context, "build") as build:
            self.assertFalse(analysis.main(["status", "AMD", "default"])["pending"])
            resolve.assert_not_called()
            build.assert_not_called()

    def test_exchange_session_open_clears_disk_cache_without_network(self):
        saved = {**self.saved, "asOf": 1000, "generated": 1100}
        write_json(self.path / "result.json", saved)
        write_json(analysis.state_directory() / "cache.json", {"AMD:spark": {"sessionStart": 2000}})
        with patch.object(analysis.time, "time", return_value=1999):
            self.assertEqual(analysis.main(["status", "AMD", "default"])["summary"], saved["summary"])
        with patch.object(analysis.time, "time", return_value=2000), patch.object(ai_runner, "resolve") as resolve:
            self.assertNotIn("summary", analysis.main(["status", "AMD", "default"]))
            resolve.assert_not_called()
        self.assertEqual(read_json(self.path / "result.json", {}), {})

    def test_old_session_is_retained_across_closed_days_and_new_research_survives(self):
        write_json(analysis.state_directory() / "cache.json", {"AMD:spark": {"sessionStart": 1000}})
        with patch.object(analysis.time, "time", return_value=100000):
            self.assertFalse(analysis.expired_session({"asOf": 1100}, "AMD"))
            self.assertFalse(analysis.expired_session({"asOf": 1000}, "AMD"))
            self.assertTrue(analysis.expired_session({"asOf": 900, "generated": 1100}, "AMD"))

    def test_new_regular_trade_expires_premarket_research_without_a_spark(self):
        captured = datetime(2026, 10, 12, 12, tzinfo=timezone.utc).timestamp()
        opened = datetime(2026, 10, 12, 13, 30, tzinfo=timezone.utc).timestamp()
        saved = {"asOf": captured, "session": {"regularDate": "2026-10-09", "date": "2026-10-12", "timezone": "America/New_York"}}
        write_json(analysis.state_directory() / "cache.json", {"AMD:quote": {"updated": opened}})
        with patch.object(analysis.time, "time", return_value=opened):
            self.assertTrue(analysis.expired_session(saved, "AMD"))
            self.assertFalse(analysis.expired_session({**saved, "asOf": opened}, "AMD"))

    def test_background_notification_survives_worker_completion_and_is_sent_once(self):
        write_json(self.path / "job.json", {**JOB, "state": "running", "started": analysis.time.time()})
        with patch.object(analysis, "alive", return_value=True), patch.object(analysis.subprocess, "run") as notify:
            analysis.main(["notify", "AMD", "default", "old-job"])
            self.assertFalse(read_json(self.path / "job.json", {}).get("notifyRequested", False))
            self.assertTrue(analysis.main(["notify", "AMD", "default", JOB["id"]])["notifyRequested"])
            notify.assert_not_called()
            with patch.object(analysis.signal, "signal"), patch.object(analysis.signal, "alarm"), \
                 patch.object(context, "build", return_value=CONTEXT), patch.object(ai_runner, "run", return_value=response()):
                analysis.worker("AMD", "default", JOB["id"])
            self.assertEqual(read_json(self.path / "job.json", {})["state"], "complete")
            self.assertEqual(read_json(self.path / "result.json", {})["request"], JOB["id"])
            analysis.main(["notify", "AMD", "default", JOB["id"]])
            analysis.main(["status", "AMD", "default"])
            notify.assert_called_once()
            self.assertIn("AMD · Analysis ready", notify.call_args.args[0])

    def test_notification_registration_after_completion_and_failure_but_not_cancellation(self):
        for state in ("complete", "failed", "cancelled"):
            with self.subTest(state=state), patch.object(analysis.subprocess, "run") as notify:
                write_json(self.path / "job.json", {**JOB, "state": state})
                analysis.main(["notify", "AMD", "default", JOB["id"]])
                if state == "cancelled":
                    notify.assert_not_called()
                else:
                    notify.assert_called_once()
                    self.assertIn("AMD · Analysis " + ("ready" if state == "complete" else "failed"), notify.call_args.args[0])

    def test_notification_failure_does_not_lose_completed_analysis(self):
        write_json(self.path / "result.json", self.saved)
        write_json(self.path / "job.json", {**JOB, "state": "complete"})
        with patch.object(analysis.subprocess, "run", side_effect=OSError("No notification daemon")):
            result = analysis.main(["notify", "AMD", "default", JOB["id"]])
        self.assertEqual(result["summary"], self.saved["summary"])
        self.assertFalse(read_json(self.path / "job.json", {}).get("notified", False))

    def test_start_deduplicates_and_cancel_only_targets_matching_job(self):
        with patch.object(ai_runner, "resolve", return_value=AGENT), \
             patch.object(analysis.subprocess, "Popen", return_value=Mock(pid=12345)) as launch, \
             patch.object(analysis, "process_identity", return_value="boot:123"), \
             patch.object(analysis.os, "kill") as kill:
            first = analysis.main(["start", "AMD", "default"])
            second = analysis.main(["start", "AMD", "default", "--force"])
            self.assertEqual(first["job"], second["job"])
            self.assertEqual(launch.call_count, 1)
            self.assertTrue(analysis.main(["cancel", "AMD", "default", "old-job"])["pending"])
            kill.assert_not_called()
            self.assertFalse(analysis.main(["cancel", "AMD", "default", first["job"]])["pending"])
            kill.assert_called_once_with(12345, signal.SIGTERM)

    def test_cached_analysis_and_failed_refresh_preserve_previous_result(self):
        write_json(self.path / "result.json", self.saved)
        with patch.object(ai_runner, "resolve", return_value=AGENT), patch.object(analysis.subprocess, "Popen") as launch:
            cached = analysis.main(["start", "AMD", "default"])
            self.assertEqual(cached["summary"], self.saved["summary"])
            launch.assert_not_called()
        with patch.object(ai_runner, "resolve", side_effect=ValueError("Not signed in")):
            failed = analysis.main(["start", "AMD", "default", "--force"])
            self.assertEqual(failed["summary"], self.saved["summary"])
            self.assertEqual(failed["error"], "Not signed in")

    def test_orphan_pid_reuse_never_kills_an_unrelated_process(self):
        write_json(self.path / "job.json", {**JOB, "state": "running", "pid": os.getpid(), "processIdentity": "old-boot:1", "started": 0})
        write_json(self.path / "result.json", self.saved)
        with patch.object(analysis.os, "kill") as kill:
            result = analysis.main(["status", "AMD", "default"])
            self.assertFalse(result["pending"])
            self.assertEqual(result["summary"], self.saved["summary"])
            self.assertIn("stopped", result["error"])
            kill.assert_not_called()

    def test_worker_validation_failure_keeps_saved_result_and_late_worker_cannot_overwrite(self):
        write_json(self.path / "result.json", self.saved)
        write_json(self.path / "job.json", {**JOB, "state": "running"})
        with patch.object(analysis.signal, "signal"), patch.object(analysis.signal, "alarm"), \
             patch.object(context, "build", return_value=CONTEXT), \
             patch.object(ai_runner, "run", return_value={**response(), "symbol": "META"}):
            analysis.worker("AMD", "default", JOB["id"])
        self.assertEqual(read_json(self.path / "result.json", {})["summary"], self.saved["summary"])
        self.assertEqual(read_json(self.path / "job.json", {})["state"], "failed")
        write_json(self.path / "job.json", {**JOB, "id": "b" * 32, "state": "running"})
        self.assertFalse(analysis.update(self.path, JOB["id"], state="complete"))
        self.assertEqual(read_json(self.path / "job.json", {})["id"], "b" * 32)


class ContextTests(unittest.TestCase):
    def test_snapshot_uses_same_session_benchmarks_and_completed_day_volume_only(self):
        stamp = datetime(2026, 10, 12, 18, tzinfo=timezone.utc).timestamp()
        quote = {"symbol": "AMD", "instrumentType": "EQUITY", "price": 110, "previous": 100, "percent": 10,
                 "updated": stamp, "open": 102, "high": 115, "low": 101, "volume": 50, "marketState": "REGULAR"}
        def quotes(symbols):
            if symbols == ["AMD"]:
                return {"rows": {"AMD": quote}}
            return {"rows": {"SPY": {**quote, "updated": stamp - 86400}, "QQQ": {**quote, "percent": 2}}}
        history = [{"date": "2026-10-09", "close": 100, "volume": 100}] * 6
        with patch.object(context.market_bulk, "quotes", side_effect=quotes), \
             patch.object(context.market_bulk, "presets", return_value=[]), \
             patch.object(context, "chart", return_value={"timezone": "America/New_York", "points": [[stamp, 110]]}), \
             patch.object(context, "fetch", return_value={}), patch.object(context, "daily_context", return_value=history), \
             patch.object(context.research, "main", return_value={"articles": []}), \
             patch.object(context, "read_json", return_value={}), patch.object(context.time, "time", return_value=stamp + 10):
            result = context.build("AMD")
            self.assertEqual([row["symbol"] for row in result["benchmarks"]], ["QQQ"])
            self.assertNotIn("volumeVsPriorSessions", result["regularSession"])
            quote["marketState"] = "POST"
            self.assertEqual(context.build("AMD")["regularSession"]["volumeVsPriorSessions"], .5)

    def test_extended_session_must_be_newer_and_match_market_state(self):
        quote = {"price": 100, "previous": 99, "percent": 1, "updated": 1000, "marketState": "POST",
                 "postPrice": 105, "postPercent": 5, "postUpdated": 1200, "prePrice": 90, "preUpdated": 900}
        self.assertEqual(context.latest(quote)["kind"], "after-hours")
        self.assertEqual(context.latest({**quote, "postUpdated": 999})["kind"], "regular")
        self.assertEqual(context.latest({**quote, "marketState": "REGULAR"})["kind"], "regular")

    def test_daily_baseline_excludes_current_session_and_uses_exchange_date(self):
        stamps = [datetime(2026, 10, day, 14, tzinfo=timezone.utc).timestamp() for day in (8, 9, 12)]
        document = {"chart": {"result": [{"meta": {"exchangeTimezoneName": "America/New_York"}, "timestamp": stamps,
                                          "indicators": {"quote": [{"close": [100, 101, 105], "volume": [100, 200, 20]}]}}]}}
        rows = context.daily_context(document, "2026-10-12")
        self.assertEqual([row["date"] for row in rows], ["2026-10-08", "2026-10-09"])
        self.assertAlmostEqual(context.percent(110, 100), 10)
        self.assertIsNone(context.percent(1, 0))
        document["chart"]["result"][0]["meta"]["currency"] = "GBp"
        self.assertEqual(context.daily_context(document, "2026-10-12")[0]["close"], 1)


if __name__ == "__main__":
    unittest.main()
