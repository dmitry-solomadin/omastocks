import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import release_link


class ReleaseLink(unittest.TestCase):
    def test_unwraps_google_redirect(self):
        seen = {}

        def fetch(url):
            seen["url"] = url
            return "https://www.google.com/url?q=https://ir.example.com/news/q2-results&sa=U"

        result = release_link.resolve("AMD", "2026-08-04", fetch=fetch)
        self.assertEqual(result["url"], "https://ir.example.com/news/q2-results")
        self.assertIn("btnI=1", seen["url"])
        self.assertIn("AMD+earnings+release+2026-08-04", seen["url"])

    def test_accepts_direct_redirect(self):
        result = release_link.resolve("AAPL", "2026-07-30", fetch=lambda url: "https://www.apple.com/newsroom/q3/")
        self.assertEqual(result["url"], "https://www.apple.com/newsroom/q3/")

    def test_rejects_google_pages_and_bad_input(self):
        for redirect in ("", "https://www.google.com/search?q=AMD", "https://www.google.com/url?q=javascript:alert(1)"):
            with self.assertRaises(ValueError):
                release_link.resolve("AMD", "2026-08-04", fetch=lambda url, redirect=redirect: redirect)
        with self.assertRaises(ValueError):
            release_link.resolve("AMD", "04/08/2026", fetch=lambda url: "https://ir.example.com/")


if __name__ == "__main__":
    unittest.main()
