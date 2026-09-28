from datetime import date
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
import ipos


def event(title, description, stamp=1774013160000, path="/publicdocs/nyse/events/images/X-1920-logo-pos-alpha.png"):
    return {"title": title, "description": "<p>" + description + "</p>", "startDateTime": stamp, "filePath": path}


def priced(name, ticker, day, exchange="NASDAQ Global Select", price="20.00"):
    return {"companyName": name, "proposedTickerSymbol": ticker, "pricedDate": day,
            "proposedExchange": exchange, "proposedSharePrice": price}


class Listings(unittest.TestCase):
    def test_nyse_keeps_listing_ceremonies_only(self):
        rows = ipos.parse_nyse({"results": [
            event("Janus Living (NYSE: JAN) Rings The Opening Bell&#0174;",
                  "The New York Stock Exchange welcomes Janus Living (NYSE: JAN) to the podium to celebrate its Initial Public "
                  "Offering. To honor the occasion, the CEO will ring The Opening Bell&#0174;."),
            event("MDA Space Ltd (NYSE: MDA) Rings The Opening Bell&#0174;",
                  "The New York Stock Exchange welcomes MDA Space Ltd (NYSE: MDA) to the podium in celebration of its listing. "
                  "To honor the occasion, the CEO will ring The Opening Bell&#0174;."),
            event("Guardian Metal Resources PLC (NYSE American: GMTL) Rings The Closing Bell",
                  "The New York Stock Exchange welcomes Guardian Metal Resources PLC (NYSE American: GMTL) to celebrate its listing."),
            event("AT&amp;T (NYSE: T) Rings The Opening Bell&#0174;",
                  "The New York Stock Exchange welcomes AT&amp;T (NYSE: T) in celebration of its 150th anniversary."),
            event("ServiceNow (NYSE: NOW) Rings The Opening Bell&#0174;",
                  "The New York Stock Exchange welcomes ServiceNow (NYSE: NOW) to the podium. To honor the occasion, "
                  "the CEO will ring The Opening Bell&#0174; to celebrate its listing anniversary."),
            event("Kensington Capital Acquisition Corp. VI (NYSE: KCAC.U) Rings The Opening Bell&#0174;",
                  "The New York Stock Exchange welcomes Kensington Capital Acquisition Corp. VI (NYSE: KCAC.U) to celebrate its listing."),
            event("Ireland Day Rings The Opening Bell&#0174;", "The New York Stock Exchange welcomes Ireland Day to celebrate its listing."),
        ]})
        self.assertEqual([(row["ticker"], row["exchange"], row["name"]) for row in rows],
                         [("JAN", "NYSE", "Janus Living"), ("MDA", "NYSE", "MDA Space Ltd"),
                          ("GMTL", "NYSE American", "Guardian Metal Resources PLC")])
        self.assertEqual(rows[0]["date"], "2026-03-20")
        self.assertEqual(rows[0]["logo"], "https://www.nyse.com/publicdocs/nyse/events/images/X-1920-logo-pos-alpha.png")

    def test_description_ticker_wins_over_a_title_typo(self):
        rows = ipos.parse_nyse({"results": [event(
            "American Water (NYSE: AMK) Rings The Closing Bell&#0174;",
            "The New York Stock Exchange welcomes American Water (NYSE: AWK) to celebrate its listing.", path="")]})
        self.assertEqual((rows[0]["ticker"], rows[0]["logo"]), ("AWK", ""))

    def test_nasdaq_keeps_priced_non_spac_ipos_in_the_period(self):
        data = {"priced": {"rows": [
            priced("MiniMed Group, Inc.", "MMED", "3/06/2026"),
            priced("Freecast, Inc.", "CAST", "3/10/2026", "NASDAQ Global", None),
            priced("Guardian Metal Resources PLC", "GMTL", "3/20/2026", "NYSE MKT", "13.50"),
            priced("GalaxyEdge Acquisition Corp", "GLEDU", "3/04/2026", "NYSE", "10.00"),
            priced("Pono Capital Four, Inc.", "PONOU", "3/13/2026", "NASDAQ Global", "10.00"),
            priced("Orion180 Insurance Group Inc.", "OIG", "4/01/2026"),
            priced("Broken", "BRK", "soon"),
        ]}}
        rows = ipos.parse_nasdaq(data, date(2026, 3, 1), date(2026, 3, 31))
        self.assertEqual([(row["ticker"], row["exchange"], row["date"]) for row in rows],
                         [("MMED", "Nasdaq", "2026-03-06"), ("CAST", "Nasdaq", "2026-03-10"), ("GMTL", "NYSE American", "2026-03-20")])

    def test_listings_merge_sources_and_find_icons_for_nasdaq_ipos(self):
        nyse = {"results": [event("Janus Living (NYSE: JAN) Rings The Opening Bell",
                                  "The New York Stock Exchange welcomes Janus Living (NYSE: JAN) to celebrate its Initial Public Offering.")]}
        calendar = {"priced": {"rows": [priced("Janus Living, Inc.", "JAN", "3/20/2026", "NYSE"),
                                        priced("PayPay Corp", "PAYP", "3/20/2026", price="16.00")]}}
        nasdaq, events = Mock(return_value=calendar), Mock(return_value=nyse)
        result = ipos.listings("2026-03-20", nasdaq, events, lambda ticker: "https://www.paypay.ne.jp/about")
        nasdaq.assert_called_once_with("/api/ipo/calendar?date=2026-03")
        self.assertEqual(events.call_args.args, (date(2026, 3, 20), date(2026, 3, 20)))
        self.assertEqual([(row["ticker"], row["source"]) for row in result["listings"]], [("JAN", "NYSE"), ("PAYP", "Nasdaq")])
        self.assertEqual(result["listings"][1]["logo"], "https://www.google.com/s2/favicons?domain=paypay.ne.jp&sz=128")

    def test_one_failing_source_still_shows_the_other(self):
        failing = Mock(side_effect=OSError("offline"))
        calendar = {"priced": {"rows": [priced("Swarmer, Inc", "SWMR", "3/17/2026", price="5.00")]}}
        result = ipos.listings("2026-03", Mock(return_value=calendar), failing, Mock(side_effect=OSError("offline")))
        self.assertEqual([(row["ticker"], row["logo"]) for row in result["listings"]], [("SWMR", "")])
        with self.assertRaises(ValueError):
            ipos.listings("2026-03", Mock(side_effect=ValueError("down")), failing)

    def test_websites_are_looked_up_once(self):
        import tempfile
        from unittest.mock import patch
        import yahoo_http
        profile = {"quoteSummary": {"result": [{"assetProfile": {"website": "https://www.minimed.com"}}]}}
        with tempfile.TemporaryDirectory() as directory, patch.dict("os.environ", {"STOCKS_STATE_DIR": directory}), \
                patch.object(yahoo_http, "authenticated", return_value=profile) as request:
            self.assertEqual(ipos.website("MMED"), "https://www.minimed.com")
            self.assertEqual(ipos.website("MMED"), "https://www.minimed.com")
            request.assert_called_once()
            # A listing Yahoo has no site for yet is asked again later.
            request.return_value = {"quoteSummary": {"result": [{"assetProfile": {}}]}}
            self.assertEqual(ipos.website("NEWCO"), "")
            self.assertEqual(ipos.website("NEWCO"), "")
            self.assertEqual(request.call_count, 3)

    def test_period_is_a_day_or_a_month(self):
        self.assertEqual(ipos.period_bounds("2026-02"), (date(2026, 2, 1), date(2026, 2, 28)))
        self.assertEqual(ipos.period_bounds("2026-03-20"), (date(2026, 3, 20), date(2026, 3, 20)))
        with self.assertRaises(ValueError):
            ipos.period_bounds("ALL")


if __name__ == "__main__":
    unittest.main()
