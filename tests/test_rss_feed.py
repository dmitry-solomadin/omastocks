import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "bin"))
from rss_feed import MAX_BYTES, parse_xml
import company_news
import market_news


class RssSecurityTests(unittest.TestCase):
    def test_normal_entities_and_cdata_are_preserved(self):
        root = parse_xml(b'<rss><channel><title>Markets &amp; business</title><description><![CDATA[<b>News</b>]]></description></channel></rss>')
        self.assertEqual(root.findtext("channel/title"), "Markets & business")
        self.assertEqual(root.findtext("channel/description"), "<b>News</b>")

    def test_news_readers_reject_internal_and_external_dtds_in_all_encodings(self):
        declarations = [
            '<!DOCTYPE rss [<!ENTITY x "expanded">]>',
            '<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///etc/passwd">]>',
            '<!DOCTYPE rss SYSTEM "https://example.com/external.dtd">',
        ]
        for declaration in declarations:
            for encoding in ("utf-8", "utf-16", "utf-16-le", "utf-16-be"):
                payload = ('<?xml version="1.0" encoding="' + encoding + '"?>'
                           + declaration + '<rss><channel><title>News</title></channel></rss>').encode(encoding)
                for reader in (parse_xml, company_news.parse, market_news.parse):
                    with self.subTest(reader=reader.__name__, encoding=encoding, dtd=declaration), self.assertRaises(ValueError):
                        reader(payload)

    def test_malformed_and_oversized_documents_are_rejected(self):
        for payload in (b"<rss>", b" " * (MAX_BYTES + 1)):
            with self.assertRaises(ValueError):
                parse_xml(payload)
