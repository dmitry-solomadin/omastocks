from datetime import datetime, timezone
import io
from pathlib import Path
import os
import sys
import tempfile
import tracemalloc
import unittest
from unittest import mock
import zipfile

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import margin_debt
import remote_images
import research

TITLES = list(margin_debt.COLUMNS.values())
SPACE = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'


def text(reference, value):
    return f'<c r="{reference}" t="inlineStr"><is><t>{value}</t></is></c>'


def row(index, month, *numbers):
    cells = text(f"A{index}", month)
    for column, value in zip("BCD", numbers):
        if value is not None:
            cells += f'<c r="{column}{index}"><v>{value}</v></c>'
    return f'<row r="{index}">{cells}</row>'


def sheet(rows, titles=TITLES, prologue=""):
    header = "".join(text(f"{column}1", title.replace("'", "&apos;")) for column, title in zip("ABCD", titles))
    body = "".join(row(index + 2, *values) for index, values in enumerate(rows))
    return f'{prologue}<worksheet {SPACE}><sheetData><row r="1">{header}</row>{body}</sheetData></worksheet>'


def archive(content, name=margin_debt.SHEET):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as output:
        output.writestr(name, content)
    return buffer.getvalue()


def month_keys(count, year=2010, month=1):
    keys = []
    for offset in range(count):
        total = year * 12 + month - 1 + offset
        keys.append(f"{total // 12}-{total % 12 + 1:02d}")
    return keys


def history(count=140):
    return [(key, 100.0 + index, 50.0, 25.0) for index, key in enumerate(month_keys(count))]


class SheetTests(unittest.TestCase):
    def test_reads_months_ascending_in_millions_with_optional_credit(self):
        months = month_keys(margin_debt.MIN_MONTHS)
        rows = [(key, 1000 + index, 300, 200) for index, key in enumerate(months)][::-1]
        rows[-1] = (months[0], 1000, 300, None)
        result = margin_debt.parse_sheet(archive(sheet(rows)))
        self.assertEqual(result[0], (months[0], 1000.0, 300.0, None), "Margin credit starts in 2010")
        self.assertEqual(result[-1], (months[-1], 1000.0 + len(months) - 1, 300.0, 200.0))
        self.assertEqual([values[0] for values in result], sorted(months))

    def test_blank_rows_are_skipped(self):
        rows = "".join(row(index + 2, key, 10, 1, 1) for index, key in enumerate(month_keys(margin_debt.MIN_MONTHS)))
        content = sheet([]).replace("</sheetData>", rows + '<row r="900"><c r="A900"/><c r="B900"/></row></sheetData>')
        self.assertEqual(len(margin_debt.parse_sheet(archive(content))), margin_debt.MIN_MONTHS)

    def test_anything_unexpected_is_refused_rather_than_shown(self):
        good = [(key, 10, 1, 1) for key in month_keys(margin_debt.MIN_MONTHS)]
        moved = TITLES[:1] + [TITLES[2], TITLES[1], TITLES[3]]
        cases = {
            "not an archive": b"<html>Just a moment...</html>",
            "empty": b"",
            "no worksheet": archive(sheet(good), "xl/worksheets/other.xml"),
            "columns moved": archive(sheet(good, moved)),
            "not XML": archive("not xml"),
            "no sheet data": archive(f"<worksheet {SPACE}/>"),
            "no rows": archive(sheet([])),
            "too few months": archive(sheet(good[:-1])),
            "a bad month": archive(sheet(good + [("2026-13", 10, 1, 1)])),
            "a date for a month": archive(sheet(good + [("Sep-26", 10, 1, 1)])),
            "a repeated month": archive(sheet(good + [good[0]])),
            "no debt": archive(sheet(good + [("2031-01", None, 1, 1)])),
            "zero debt": archive(sheet(good + [("2031-01", 0, 1, 1)])),
            "negative debt": archive(sheet(good + [("2031-01", -5, 1, 1)])),
            "negative credit": archive(sheet(good + [("2031-01", 5, 1, -1)])),
            "text for a number": archive(sheet(good + [("2031-01", "abc", 1, 1)])),
            "not a number": archive(sheet(good + [("2031-01", "nan", 1, 1)])),
            "infinity": archive(sheet(good + [("2031-01", "inf", 1, 1)])),
        }
        for name, raw in cases.items():
            with self.subTest(name), self.assertRaisesRegex(ValueError, "could not be read"):
                margin_debt.parse_sheet(raw)

    def test_a_document_type_is_refused(self):
        bomb = '<!DOCTYPE lolz [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;">]>'
        with self.assertRaisesRegex(ValueError, "could not be read"):
            margin_debt.parse_sheet(archive(sheet([(key, 10, 1, 1) for key in month_keys(margin_debt.MIN_MONTHS)], prologue=bomb)))

    def test_a_compressed_bomb_is_read_only_to_the_limit(self):
        raw = archive(b"\0" * (64 * 1024 * 1024))
        self.assertLess(len(raw), 1024 * 1024, "It fits the download limit")
        tracemalloc.start()
        try:
            with self.assertRaisesRegex(ValueError, "could not be read"):
                margin_debt.parse_sheet(raw)
            _, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
        self.assertLess(peak, 16 * 1024 * 1024)


class MarketTests(unittest.TestCase):
    def chart(self, stamps, closes, zone="Europe/London"):
        calls = []

        def request(path, **parameters):
            calls.append((path, parameters))
            return {"chart": {"result": [{"meta": {"exchangeTimezoneName": zone}, "timestamp": stamps,
                                          "indicators": {"quote": [{"close": closes}]}}]}}
        return margin_debt.market_closes(request), calls

    def stamp(self, *moment):
        return int(datetime(*moment, tzinfo=timezone.utc).timestamp())

    def test_a_summer_bar_in_london_time_belongs_to_its_own_month(self):
        closes, _ = self.chart([self.stamp(2026, 8, 31, 23), self.stamp(2026, 9, 30, 23), self.stamp(2026, 11, 1)], [76039.0, 75517.0, 76621.0])
        self.assertEqual(closes, {"2026-09": 76039.0, "2026-10": 75517.0, "2026-11": 76621.0})

    def test_a_bar_without_a_close_is_left_out(self):
        closes, _ = self.chart([self.stamp(2026, 1, 1), self.stamp(2026, 2, 1)], [None, 5.0], "UTC")
        self.assertEqual(closes, {"2026-02": 5.0})

    def test_asks_for_monthly_bars_rather_than_a_thinned_range(self):
        _, calls = self.chart([], [])
        self.assertEqual(calls[0][1]["interval"], "1mo")
        self.assertNotIn("range", calls[0][1], "Yahoo returns quarters for a max range")
        self.assertEqual(calls[0][1]["period1"], margin_debt.FIRST_YEAR)


class ReportTests(unittest.TestCase):
    def closes(self, rows, value=1000.0):
        return {values[0]: value for values in rows}

    def test_share_change_and_record(self):
        rows = history()
        rows[100] = (rows[100][0], 500.0, 50.0, 25.0)
        result = margin_debt.report(rows, self.closes(rows))
        latest = result["latest"]
        self.assertEqual(result["since"], "2010-01")
        self.assertEqual(latest["month"], rows[-1][0])
        self.assertEqual(latest["debt"], 239e6)
        self.assertAlmostEqual(latest["share"], 239 / 1000 / 1000 * 100)
        self.assertAlmostEqual(latest["monthChange"], (239 / 238 - 1) * 100)
        self.assertAlmostEqual(latest["yearChange"], (239 / 227 - 1) * 100)
        self.assertEqual(latest["highMonth"], rows[100][0])
        self.assertAlmostEqual(latest["fromHigh"], (239 / 500 - 1) * 100)
        self.assertIsNone(result["months"][0]["change"], "No year before the first")

    def test_a_record_reads_as_zero_from_the_high(self):
        rows = history()
        self.assertEqual(margin_debt.report(rows, self.closes(rows))["latest"]["fromHigh"], 0)

    def test_ranks_leave_out_the_reading_itself(self):
        rows = history()
        latest = margin_debt.report(rows, self.closes(rows))["latest"]
        self.assertEqual(latest["sharePercentile"], 100, "Rising every month: higher than all the others")
        rows = rows[:-1] + [(rows[-1][0], 1.0, 50.0, 25.0)]
        self.assertEqual(margin_debt.report(rows, self.closes(rows))["latest"]["sharePercentile"], 0)

    def test_the_cushion_ranks_only_from_when_margin_credit_is_reported(self):
        rows = [(key, 100.0, 80.0, None) for key in month_keys(100)]
        rows += [(key, 100.0, 30.0, 30.0) for key in month_keys(39, 2018, 5)]
        rows += [("2021-08", 100.0, 10.0, 10.0)]
        latest = margin_debt.report(rows, self.closes(rows))["latest"]
        self.assertEqual(latest["cushionSince"], "2018-05")
        self.assertAlmostEqual(latest["cushion"], 20.0)
        self.assertEqual(latest["cushionPercentile"], 0)
        self.assertAlmostEqual(latest["cushionMedian"], 60.0)

    def test_a_latest_month_without_credit_has_no_cushion(self):
        rows = history()
        rows[-1] = (rows[-1][0], rows[-1][1], 50.0, None)
        latest = margin_debt.report(rows, self.closes(rows))["latest"]
        self.assertIsNone(latest["cushion"])
        self.assertIsNone(latest["cushionPercentile"])

    def test_falling_prices_can_show_high_leverage_while_debt_falls(self):
        # March 2009: the share peaks because the market fell faster than the debt.
        rows = [(key, 200.0, 50.0, 25.0) for key in month_keys(139)] + [("2021-08", 120.0, 50.0, 25.0)]
        closes = self.closes(rows)
        closes["2021-08"] = 300.0
        latest = margin_debt.report(rows, closes)["latest"]
        self.assertEqual((latest["level"], latest["trend"]), ("High", "Deleveraging"))

    def test_level_and_trend_boundaries(self):
        for percentile, expected in ((0, "Low"), (19.9, "Low"), (20, "Below average"), (39.9, "Below average"), (40, "Average"),
                                     (59.9, "Average"), (60, "Above average"), (79.9, "Above average"), (80, "High"), (100, "High"), (None, "")):
            self.assertEqual(margin_debt.level(percentile), expected, percentile)
        for change, expected in ((-41.6, "Deleveraging"), (-10, "Deleveraging"), (-9.9, "Easing"), (-0.1, "Easing"), (0, "Growing"),
                                 (19.9, "Growing"), (20, "Rising fast"), (80, "Rising fast"), (None, "")):
            self.assertEqual(margin_debt.trend(change), expected, change)

    def test_refuses_to_rank_without_enough_market_history(self):
        rows = history()
        with self.assertRaises(ValueError):
            margin_debt.report(rows, {})
        with self.assertRaises(ValueError):
            margin_debt.report(rows, {rows[-1][0]: 1000.0})
        short = {values[0]: 1000.0 for values in rows[-margin_debt.MIN_MONTHS + 1:]}
        with self.assertRaises(ValueError):
            margin_debt.report(rows, short)
        missing_latest = self.closes(rows)
        del missing_latest[rows[-1][0]]
        with self.assertRaises(ValueError):
            margin_debt.report(rows, missing_latest)

    def test_a_year_without_a_prior_month_is_refused(self):
        rows = history()
        del rows[-13]
        with self.assertRaises(ValueError):
            margin_debt.report(rows, self.closes(rows))


class SourceTests(unittest.TestCase):
    def test_downloads_through_the_bounded_https_fetcher(self):
        rows = [(key, 100 + index, 50, 25) for index, key in enumerate(month_keys(140))]
        get = mock.Mock(return_value=archive(sheet(rows)))
        request = mock.Mock(return_value={"chart": {"result": [{"meta": {"exchangeTimezoneName": "UTC"},
            "timestamp": [int(datetime(*map(int, key.split("-")), 15, tzinfo=timezone.utc).timestamp()) for key, *_ in rows],
            "indicators": {"quote": [{"close": [1000.0] * len(rows)}]}}]}})
        result = margin_debt.margin_debt(get, request)
        get.assert_called_once_with(margin_debt.URL, margin_debt.HEADERS)
        self.assertEqual(result["latest"]["month"], rows[-1][0])
        self.assertTrue(margin_debt.URL.startswith("https://www.finra.org/"))
        self.assertIs(margin_debt.download, remote_images.download)

    def test_a_refused_download_is_a_failure(self):
        with self.assertRaises(ValueError):
            margin_debt.margin_debt(mock.Mock(side_effect=ValueError("The picture is too large.")), mock.Mock())

    def test_pictures_keep_their_own_request_headers(self):
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b"body"
        opener = mock.Mock(**{"open.return_value": response})
        with mock.patch.object(remote_images, "OPENER", opener):
            remote_images.download("https://example.org/a.png")
            self.assertEqual(opener.open.call_args[0][0].get_header("Accept"), "image/png,image/jpeg")
            remote_images.download(margin_debt.URL, margin_debt.HEADERS)
            self.assertEqual(opener.open.call_args[0][0].get_header("User-agent"), "Omastocks")


class CacheTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        patcher = mock.patch.dict(os.environ, {"STOCKS_STATE_DIR": folder.name})
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_checks_daily_and_a_failure_keeps_the_last_report(self):
        good = {"marginSchema": 1, "months": [{"month": "2026-09"}], "latest": {"month": "2026-09"}}
        with mock.patch.object(research, "load", return_value=good) as load:
            research.main(["margin-debt", "ALL"])
            research.main(["margin-debt", "ALL"])
            self.assertEqual(load.call_count, 1)
            load.side_effect = ValueError("FINRA's margin statistics could not be read.")
            result = research.main(["margin-debt", "ALL", "--force"])
        self.assertEqual(result["months"], good["months"])
        self.assertTrue(result["stale"])
        self.assertIn("could not be read", result["error"])

    def test_an_older_schema_is_not_reused(self):
        with mock.patch.object(research, "load", return_value={"marginSchema": 0, "months": []}) as load:
            research.main(["margin-debt", "ALL"])
            research.main(["margin-debt", "ALL"])
        self.assertEqual(load.call_count, 2)


if __name__ == "__main__":
    unittest.main()
