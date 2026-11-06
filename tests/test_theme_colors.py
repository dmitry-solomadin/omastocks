from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ThemeColorTests(unittest.TestCase):
    """QtQuick has its own Color since Qt 6.12, and it hides the shell's whatever the import order."""

    def sources(self, *suffixes):
        return {
            path.relative_to(ROOT / "qml").as_posix(): path.read_text()
            for path in (ROOT / "qml").rglob("*")
            if path.suffix in suffixes
        }

    def test_theme_colors_are_read_through_the_named_import(self):
        found = {}
        for name, source in self.sources(".qml", ".js").items():
            for number, line in enumerate(source.splitlines(), 1):
                if re.search(r"(?<![\w.])Color\s*[.\[]", line):
                    found.setdefault(name, []).append(number)
        self.assertEqual(found, {}, "A bare Color is undefined on Qt 6.12, so use Commons.Color")

    def test_files_reading_commons_import_it_by_name(self):
        missing = [
            name
            for name, source in self.sources(".qml").items()
            if re.search(r"(?<![\w.])Commons\.", source)
            and not re.search(r"^import qs\.Commons as Commons$", source, re.MULTILINE)
        ]
        self.assertEqual(missing, [], "Commons.Color needs: import qs.Commons as Commons")


if __name__ == "__main__":
    unittest.main()
