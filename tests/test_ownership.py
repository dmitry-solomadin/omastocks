from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import ownership


def summary(**modules):
    return {"quoteSummary": {"result": [modules], "error": None}}


class Ownership(unittest.TestCase):
    def test_ownership_scales_fractions_and_keeps_top_institutions(self):
        document = summary(
            defaultKeyStatistics={"shortPercentOfFloat": {"raw": .0246}, "sharesShort": {"raw": 39975696},
                                  "sharesShortPriorMonth": {"raw": 40065798}, "shortRatio": {"raw": 2.23},
                                  "sharesOutstanding": {"raw": 1632475042},
                                  "dateShortInterest": {"raw": 1789430400}},
            majorHoldersBreakdown={"institutionsPercentHeld": {"raw": .754}, "institutionsFloatPercentHeld": {"raw": .757},
                                   "institutionsCount": {"raw": 5112}, "insidersPercentHeld": {"raw": 0}},
            institutionOwnership={"ownershipList": [
                {"organization": " Holder %d " % index, "pctHeld": {"raw": .01}, "reportDate": {"raw": 1782777600}}
                for index in range(7)] + [{"organization": ""}]})
        request = Mock(return_value=document)
        result = ownership.ownership("AMD", request)
        self.assertEqual(request.call_args.args[0], "/v10/finance/quoteSummary/AMD")
        self.assertAlmostEqual(result["shortPercentFloat"], 2.46)
        self.assertEqual((result["shortShares"], result["shortRatio"], result["shortDate"]), (39975696, 2.23, "2026-09-15"))
        self.assertAlmostEqual(result["institutionsPercent"], 75.4)
        self.assertEqual(result["institutionsCount"], 5112)
        # Zero is a value, not a missing field.
        self.assertEqual(result["insidersPercent"], 0)
        self.assertEqual(result["holders"], [{"name": "Holder %d" % index, "percent": 1, "date": "2026-06-30"} for index in range(5)])
        self.assertAlmostEqual(result["othersPercent"], 100 - 75.4 / (1 + 39975696 / 1632475042))

    def test_others_undo_the_short_sale_double_count(self):
        # ELF: 98.76% institutions and 2.85% insiders, with 7.15% of shares short.
        self.assertAlmostEqual(ownership.others(98.76, 2.85, 7.15, 100), 5.17, places=2)
        # Without short interest the plain remainder is used.
        self.assertAlmostEqual(ownership.others(51.45, 1.45, None, None), 47.1)
        self.assertIsNone(ownership.others(98.76, 2.85, None, 100))
        self.assertIsNone(ownership.others(None, 2.85, 7.15, 100))

    def test_fund_without_holder_breakdown_stays_empty(self):
        result = ownership.parse_ownership(summary(defaultKeyStatistics={"shortPercentOfFloat": {}, "sharesShort": {}}), "SPY")
        self.assertIsNone(result["shortPercentFloat"])
        self.assertIsNone(result["institutionsPercent"])
        self.assertIsNone(result["insidersPercent"])
        self.assertIsNone(result["othersPercent"])
        self.assertEqual(result["holders"], [])

    def test_provider_error_is_a_failure(self):
        document = {"quoteSummary": {"result": None, "error": {"description": "No fundamentals data found"}}}
        with self.assertRaisesRegex(ValueError, "No fundamentals data found"):
            ownership.parse_ownership(document, "ZZZZ")
        with self.assertRaises(ValueError):
            ownership.parse_ownership({}, "ZZZZ")


if __name__ == "__main__":
    unittest.main()
