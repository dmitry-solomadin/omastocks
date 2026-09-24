import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import financials


def fact(day, value, currency="USD", period="3M"):
    return {"asOfDate": day, "periodType": period, "currencyCode": currency, "reportedValue": {"raw": value}}


def parse(fields, frequency="quarterly"):
    return financials.parse_statements({"timeseries": {"result": [
        {frequency + key: values} for key, values in fields.items()
    ]}}, "TEST", frequency)["statements"]


def metric(statement, key):
    return next(row for row in statement["rows"] if row["key"] == key)


class FinancialsTests(unittest.TestCase):
    def test_aligns_fiscal_periods_without_filling_missing_values(self):
        statements = parse({"TotalRevenue": [fact("2026-06-30", 200), fact("2026-03-31", 100)],
                            "NetIncome": [fact("2026-03-31", -10)], "DilutedEPS": [fact("2026-03-31", -.12)]})
        income = statements[0]
        self.assertEqual(income["dates"], ["2026-06-30", "2026-03-31"])
        self.assertEqual(metric(income, "NetIncome")["values"], [None, -10])
        self.assertEqual(metric(income, "DilutedEPS")["kind"], "perShare")
        self.assertEqual(metric(income, "netMargin")["values"], [None, -10])

    def test_preserves_reporting_currency_and_rejects_mixed_currency_ratios(self):
        income = parse({"TotalRevenue": [fact("2026-06-30", 100, "USD")],
                        "NetIncome": [fact("2026-06-30", 30, "GBP")]})[0]
        self.assertEqual(metric(income, "TotalRevenue")["currencies"], ["USD"])
        self.assertEqual(metric(income, "NetIncome")["currencies"], ["GBP"])
        self.assertNotIn("netMargin", [row["key"] for row in income["rows"]])

    def test_rejects_ytd_invalid_dates_missing_units_and_nonfinite_values(self):
        income = parse({"TotalRevenue": [fact("2026-06-30", 1, period="6M"),
                        fact("2026-02-30", 2), fact("2026-03-31", 3, ""),
                        fact("2025-12-31", float("inf")), fact("2025-09-30", 0)]})[0]
        self.assertEqual(income["dates"], ["2025-09-30"])
        self.assertEqual(metric(income, "TotalRevenue")["values"], [0])

    def test_growth_matches_year_ago_quarter_and_negative_equity_has_no_ratio(self):
        statements = parse({"TotalRevenue": [fact("2026-06-30", 150), fact("2026-03-31", 130), fact("2025-06-30", 100)],
                            "TotalDebt": [fact("2026-06-30", 50)], "StockholdersEquity": [fact("2026-06-30", -10)]})
        self.assertEqual(metric(statements[0], "revenueGrowth")["values"], [50, None, None])
        self.assertNotIn("debtEquity", [row["key"] for row in statements[1]["rows"]])

    def test_growth_falls_back_to_aligned_history(self):
        def growth(revenue, history):
            fields = {"TotalRevenue": [fact(day, value) for day, value in revenue]}
            document = {"timeseries": {"result": [{"quarterly" + key: values} for key, values in fields.items()]}}
            income = financials.parse_statements(document, "TEST", "quarterly", history)["statements"][0]
            return next((row["values"] for row in income["rows"] if row["key"] == "revenueGrowth"), None)
        quarters = [("2026-06-30", 150), ("2026-03-31", 130), ("2025-12-31", 120), ("2025-09-30", 110), ("2025-06-30", 100)]
        # History runs one quarter newer than Yahoo and reaches back a year further.
        history = [160, 150, 130, 120, 110, 100, 104, 96, 88]
        self.assertEqual(growth(quarters, history), [50, 25, 25, 25, None])
        # Values that don't line up, or line up twice, are not trusted.
        self.assertEqual(growth(quarters, [150, 131, 120, 110, 100, 104]), [50, None, None, None, None])
        self.assertIsNone(growth(quarters[:2], [150, 130, 150, 130, 104, 96, 110]))
        # A gap in Yahoo's quarters can't be placed in an undated history.
        self.assertEqual(growth([quarters[0], quarters[1], quarters[4]], history), [50, None, None])

    def test_revenue_history_is_empty_when_unavailable(self):
        with patch.object(financials, "request", side_effect=OSError("offline")):
            self.assertEqual(financials.revenue_history("AMD", "quarterly"), [])
        row = {"s": "NASDAQ:AMD", "d": [[3, None, 1]]}
        with patch.object(financials, "request", return_value={"data": [row]}) as fetch:
            self.assertEqual(financials.revenue_history("AMD", "annual"), [3, None, 1])
        self.assertEqual(fetch.call_args.args[0]["columns"], ["total_revenue_fy_h"])
        with patch.object(financials, "request", return_value={"data": [row, dict(row, s="NYSE:AMD")]}):
            self.assertEqual(financials.revenue_history("AMD", "quarterly"), [])

    def test_annual_uses_only_full_year_and_no_statements_is_valid(self):
        income = parse({"TotalRevenue": [fact("2025-09-30", 400, period="12M"), fact("2026-06-30", 100)]}, "annual")[0]
        self.assertEqual(income["dates"], ["2025-09-30"])
        self.assertEqual(metric(income, "TotalRevenue")["values"], [400])
        self.assertTrue(all(not row["rows"] for row in parse({})))
        with self.assertRaises(ValueError):
            financials.statements("AAPL", "trailing")

    def test_valuation_missing_values_and_listing_ambiguity(self):
        row = {"s": "NASDAQ:AAPL", "d": [1230000000000, None, 0, -2, 12, "Technology", "Hardware", "USD", "stock"]}
        result = financials.parse_valuation({"data": [row]}, "AAPL")
        self.assertEqual(result["metrics"][0]["value"], 1230000000000)
        self.assertIsNone(result["metrics"][1]["value"])
        self.assertEqual(result["metrics"][2]["value"], 0)
        self.assertEqual(result["metrics"][0]["currency"], "USD")
        self.assertEqual(financials.parse_valuation({"data": [row, dict(row, s="NYSE:AAPL")]}, "AAPL")["metrics"], [])
        self.assertEqual(financials.parse_valuation({"data": [row]}, "MSFT")["metrics"], [])

    def test_share_class_symbol_is_normalized_in_request_and_response(self):
        document = {"data": [{"s": "NYSE:BRK.B", "d": [1000, 10, 2, 3, 4, "Finance", "Insurance", "USD", "stock"]}]}
        with patch.object(financials, "request", return_value=document) as fetch:
            result = financials.valuation("BRK-B")
        self.assertIn("NYSE:BRK.B", fetch.call_args.args[0]["symbols"]["tickers"])
        self.assertEqual(result["symbol"], "BRK-B")
        self.assertEqual(result["metrics"][0]["value"], 1000)

    def test_research_financials_are_separate_from_valuation(self):
        import research
        with patch.object(research, "statements", return_value={"statements": []}) as statements, \
                patch.object(research, "valuation", side_effect=ValueError("offline")):
            self.assertEqual(research.load("financials", "AAPL", "annual"), {"statements": []})
            statements.assert_called_once_with("AAPL", "annual")


if __name__ == "__main__":
    unittest.main()
