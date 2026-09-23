"""Bounded RSS parsing without DTDs or custom entity expansion."""
# ElementTree is only used with the DTD-rejecting target below.
import xml.etree.ElementTree as ET  # nosec B405

MAX_BYTES = 2 * 1024 * 1024


class FeedTreeBuilder(ET.TreeBuilder):
    def doctype(self, name, pubid, system):
        # Called before the internal subset is processed, including for UTF-16
        # documents. RSS from our providers never needs a DTD or custom entities.
        raise ValueError("News feeds must not contain a document type declaration.")


def parse_xml(raw):
    size = len(raw.encode("utf-8")) if isinstance(raw, str) else len(raw)
    if size > MAX_BYTES:
        raise ValueError("News feed is too large.")
    parser = ET.XMLParser(target=FeedTreeBuilder())  # nosec B314
    try:
        # DTDs are rejected before entity definitions; tested with UTF-8/UTF-16.
        return ET.fromstring(raw, parser=parser)  # nosec B314
    except ET.ParseError as error:
        raise ValueError("News feed is invalid.") from error
