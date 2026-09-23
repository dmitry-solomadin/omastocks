import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import brief
from stocks import write_json


class BriefTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.env = patch.dict(os.environ, {"STOCKS_STATE_DIR": self.temp.name})
        self.env.start()
        self.addCleanup(self.env.stop)
        write_json(self.directory / "cache.json", {
            "AMD:1D": {"symbol": "AMD", "name": "Advanced Micro Devices", "price": 100, "currency": "USD", "points": [[1, 100]], "fetched": 100},
            "NVDA:1D": {"symbol": "NVDA", "price": 200}})

    def response(self, job):
        return {"symbol": "AMD", "request": job["id"], "sections": [
            {"heading": heading, "points": [{"text": "Snapshot quote is 100 USD.", "sources": ["quote"]}]} for heading in brief.HEADINGS]}

    def test_context_is_selected_stock_only_and_excludes_chart_arrays(self):
        context = brief.snapshot("AMD")
        text = json.dumps(context)
        self.assertNotIn("NVDA", text)
        self.assertNotIn("points", text)
        self.assertNotIn(str(self.directory), text)
        self.assertEqual(context["sources"][0]["data"]["price"], 100)

    def test_explicit_start_poll_validation_and_cache_reuse(self):
        with patch.object(brief.shutil, "which", return_value="/usr/bin/tool"), \
             patch.object(brief.subprocess, "run", return_value=Mock(stdout="claude\n")), \
             patch.object(brief.subprocess, "Popen") as launch:
            self.assertFalse(brief.main(["status", "AMD"])["pending"])
            launch.assert_not_called()
            self.assertTrue(brief.main(["start", "AMD"])["pending"])
            self.assertTrue(brief.main(["start", "AMD"])["pending"])
            self.assertEqual(launch.call_count, 1)
            self.assertEqual(launch.call_args.args[0][:3], ["omarchy", "agent", "prompt"])
            root = self.directory / "briefs"
            active = root / (hashlib.sha256(b"AMD").hexdigest() + "-active.json")
            job = json.loads(active.read_text())
            output = root / job["id"] / "result.json"
            output.write_text('{"symbol":')
            self.assertTrue(brief.main(["status", "AMD"])["pending"])
            write_json(output, self.response(job))
            result = brief.main(["status", "AMD"])
            self.assertFalse(result["pending"])
            self.assertEqual(len(result["sections"]), 4)
            self.assertFalse(brief.main(["start", "AMD"])["pending"])
            self.assertEqual(launch.call_count, 1)
            self.assertTrue(brief.main(["start", "AMD", "--force"])["pending"])
            self.assertEqual(launch.call_count, 2)

    def test_rejects_wrong_request_and_invented_source_ids(self):
        job = {"symbol": "AMD", "id": "a" * 32, "snapshot": brief.snapshot("AMD"), "started": 100, "agent": "claude", "fingerprint": "test"}
        good = self.response(job)
        for field, value in [("symbol", "NVDA"), ("request", "b" * 32)]:
            with self.assertRaises(ValueError):
                brief.validate({**good, field: value}, job)
        bad = copy.deepcopy(good)
        bad["sections"][0]["points"][0]["sources"] = ["invented"]
        with self.assertRaises(ValueError):
            brief.validate(bad, job)

    def test_missing_default_does_not_launch_or_install(self):
        with patch.object(brief.shutil, "which", return_value="/usr/bin/tool"), \
             patch.object(brief.subprocess, "run", return_value=Mock(stdout="")), \
             patch.object(brief.subprocess, "Popen") as launch:
            with self.assertRaisesRegex(ValueError, "Choose your agent"):
                brief.main(["start", "AMD"])
            launch.assert_not_called()

    def test_v2_resolution_is_local_to_the_handoff(self):
        original = os.environ.get("PATH")
        with patch.object(brief.shutil, "which", side_effect=lambda name: "/usr/bin/opencode2" if name == "opencode2" else "/usr/bin/" + name), \
             patch.object(brief.subprocess, "run", return_value=Mock(stdout="opencode\n")), \
             patch.object(brief.subprocess, "Popen") as launch:
            result = brief.main(["start", "AMD"])
            self.assertEqual(result["agent"], "OpenCode V2")
            path = Path(launch.call_args.kwargs["env"]["PATH"].split(os.pathsep)[0]) / "opencode"
            self.assertTrue(path.is_symlink())
            self.assertEqual(os.readlink(path), "/usr/bin/opencode2")
            self.assertEqual(os.environ.get("PATH"), original)

    def test_timeout_preserves_previous_brief_and_does_not_relaunch(self):
        with patch.object(brief.shutil, "which", return_value="/usr/bin/tool"), \
             patch.object(brief.subprocess, "run", return_value=Mock(stdout="claude\n")), \
             patch.object(brief.subprocess, "Popen") as launch:
            brief.main(["start", "AMD"])
            root = self.directory / "briefs"
            key = hashlib.sha256(b"AMD").hexdigest()
            active = root / (key + "-active.json")
            job = json.loads(active.read_text())
            saved = brief.validate(self.response(job), job)
            write_json(root / (key + ".json"), saved)
            job["started"] = 0
            write_json(active, job)
            result = brief.main(["status", "AMD"])
            self.assertFalse(result["pending"])
            self.assertEqual(result["sections"], saved["sections"])
            self.assertIn("five minutes", result["error"])
            self.assertEqual(launch.call_count, 1)
