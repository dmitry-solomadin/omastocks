import copy
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
from extended import parse_extended


SAMPLE = {"chart": {"result": [{
    "meta": {"currency": "USD", "regularMarketPrice": 105, "regularMarketTime": 201,
             "chartPreviousClose": 100, "hasPrePostMarketData": True,
             "currentTradingPeriod": {"pre": {"start": 10, "end": 100},
                                      "regular": {"start": 100, "end": 200},
                                      "post": {"start": 200, "end": 300}}},
    "timestamp": [20, 90, 100, 190, 200, 270, 300, 400],
    "indicators": {"quote": [{"close": [102, 103, 104, 105, 106, 107, 108, 109],
                              "volume": [1, 2, 3, 4, 5, 6, 7, 8]}]},
}]}}


class ExtendedTests(unittest.TestCase):
    def test_after_hours_is_separate_and_relative_to_regular_close(self):
        result = parse_extended(SAMPLE, "TEST", now=350)
        self.assertEqual(result["quote"]["session"], "post")
        self.assertEqual(result["quote"]["price"], 107)
        self.assertEqual(result["quote"]["reference"], 105)
        self.assertEqual(result["quote"]["change"], 2)
        self.assertAlmostEqual(result["quote"]["percent"], 2 / 105 * 100)
        self.assertEqual(result["price"], 105)
        self.assertEqual(result["change"], 5)
        self.assertEqual(result["points"][-1], (270, 107))
        self.assertEqual(result["volumes"], [1, 2, 3, 4, 5, 6])

    def test_pre_market_compares_to_prior_regular_close_without_future_samples(self):
        data = copy.deepcopy(SAMPLE)
        data["chart"]["result"][0]["meta"].update(regularMarketTime=-86400, regularMarketPrice=100)
        result = parse_extended(data, "TEST", now=95)
        self.assertEqual(result["quote"]["session"], "pre")
        self.assertEqual(result["quote"]["change"], 3)
        self.assertEqual(result["points"], [(20, 102), (90, 103)])
        self.assertEqual((result["sessionStart"], result["sessionEnd"]), (10, 300))

    def test_regular_session_does_not_mislabel_pre_market_as_current(self):
        self.assertIsNone(parse_extended(SAMPLE, "TEST", now=150)["quote"])
        data = copy.deepcopy(SAMPLE)
        data["chart"]["result"][0]["timestamp"] = [20, 90]
        self.assertIsNone(parse_extended(data, "TEST", now=150)["quote"])

    def test_incorrect_close_timestamp_does_not_invent_extended_change(self):
        for stamp in (None, -86400, 86400):
            data = copy.deepcopy(SAMPLE)
            data["chart"]["result"][0]["meta"]["regularMarketTime"] = stamp
            result = parse_extended(data, "TEST", now=350)
            self.assertEqual(result["quote"]["price"], 107)
            self.assertIsNone(result["quote"]["change"])

    def test_unsupported_or_misaligned_sessions_do_not_supply_quotes(self):
        data = copy.deepcopy(SAMPLE)
        meta = data["chart"]["result"][0]["meta"]
        meta["hasPrePostMarketData"] = False
        self.assertFalse(parse_extended(data, "INDEX", now=350)["supported"])
        meta["hasPrePostMarketData"] = True
        for session in meta["currentTradingPeriod"].values():
            session["start"] += 86400
            session["end"] += 86400
        result = parse_extended(data, "TEST", now=350)
        self.assertEqual(result["points"], [])
        self.assertIsNone(result["quote"])
        meta["currentTradingPeriod"]["regular"]["end"] = 0
        self.assertFalse(parse_extended(data, "TEST", now=350)["supported"])

    def test_early_close_boundaries_and_pence_conversion(self):
        data = copy.deepcopy(SAMPLE)
        meta = data["chart"]["result"][0]["meta"]
        meta["currency"] = "GBp"
        meta["regularMarketTime"] = 150
        meta["currentTradingPeriod"]["regular"]["end"] = 150
        meta["currentTradingPeriod"]["post"]["start"] = 150
        result = parse_extended(data, "TEST", now=195)
        self.assertEqual(result["quote"]["session"], "post")
        self.assertEqual(result["currency"], "GBP")
        self.assertEqual(result["quote"]["price"], 1.05)
        self.assertEqual(result["quote"]["change"], 0)


if __name__ == "__main__":
    unittest.main()
