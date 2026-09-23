import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLUGIN = "io.github.dmitry-solomadin.omastocks"


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home with spaces"
        self.home.mkdir()
        self.env = {**os.environ, "HOME": str(self.home), "STOCKS_STATE_DIR": str(Path(self.temp.name) / "state")}
        self.env.pop("XDG_DATA_HOME", None)

    def install(self, token="", source=ROOT):
        subprocess.run(["bash", str(source / "install-launcher"), "install", token], env=self.env,
                       cwd=self.home, check=True, capture_output=True, text=True)
        data = Path(self.env.get("XDG_DATA_HOME") or self.home / ".local/share")
        return [(ROOT / "assets/omastocks.desktop", data / "applications" / (PLUGIN + ".desktop")),
                (ROOT / "assets/icon.svg", data / "icons/hicolor/scalable/apps" / (PLUGIN + ".svg"))]

    def test_fresh_install_supports_default_and_custom_data_directories(self):
        for location in ("", str(self.home / "custom data")):
            with self.subTest(location=location):
                self.env["XDG_DATA_HOME"] = location
                for source, destination in self.install():
                    self.assertEqual(destination.read_bytes(), source.read_bytes())
                    self.assertEqual(destination.stat().st_mode & 0o777, 0o644)

    def test_repeated_startup_keeps_unchanged_files_untouched(self):
        files = self.install()
        for _, destination in files:
            os.utime(destination, ns=(1_000_000_000, 1_000_000_000))
        before = [(path.stat().st_ino, path.stat().st_mtime_ns) for _, path in files]
        self.install()
        self.assertEqual(before, [(path.stat().st_ino, path.stat().st_mtime_ns) for _, path in files])

    def test_startup_updates_outdated_launcher_and_icon(self):
        files = self.install()
        for _, destination in files:
            destination.write_text("Old bundled asset")
        for source, destination in self.install():
            self.assertEqual(destination.read_bytes(), source.read_bytes())

    def remove(self, token, script=None, path=None):
        # The service carries this source in memory, independently of the repo.
        subprocess.run(["bash", "-c", script or (ROOT / "install-launcher").read_text(),
                        str(path or ROOT / "install-launcher"), "remove", token],
                       env=self.env, cwd=self.home, check=True, capture_output=True, text=True)

    def test_unload_cleans_only_launcher_assets_and_preserves_user_data(self):
        files = self.install("active")
        state = Path(self.env["STOCKS_STATE_DIR"])
        for name in ("watchlist.json", "cache.json"):
            (state / name).write_text("user data")
        self.remove("active")
        for _, destination in files:
            self.assertFalse(destination.exists())
        for name in ("watchlist.json", "cache.json"):
            self.assertEqual((state / name).read_text(), "user data")
        self.remove("active")  # Repeated cleanup is harmless.

    def test_delayed_old_cleanup_does_not_remove_new_instance_assets(self):
        files = self.install("old")
        self.install("new")
        self.remove("old")
        for source, destination in files:
            self.assertEqual(destination.read_bytes(), source.read_bytes())
        self.remove("new")
        self.assertTrue(all(not path.exists() for _, path in files))

    def test_cleanup_survives_plugin_directory_removal(self):
        plugin = Path(self.temp.name) / "plugin"
        (plugin / "assets").mkdir(parents=True)
        for name in ("icon.svg", "omastocks.desktop"):
            shutil.copyfile(ROOT / "assets" / name, plugin / "assets" / name)
        shutil.copyfile(ROOT / "install-launcher", plugin / "install-launcher")
        script = (plugin / "install-launcher").read_text()
        files = self.install("removed", plugin)
        # Retain test files while simulating the installed path disappearing.
        plugin.rename(plugin.with_name("removed-plugin"))
        self.remove("removed", script, plugin / "install-launcher")
        self.assertTrue(all(not path.exists() for _, path in files))

    def test_manual_repair_preserves_active_service_ownership(self):
        files = self.install("active")
        self.install()
        self.remove("active")
        self.assertTrue(all(not path.exists() for _, path in files))


if __name__ == "__main__":
    unittest.main()
