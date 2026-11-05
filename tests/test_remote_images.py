import http.server
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock
import urllib.error
import urllib.request
import zlib

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bin"))
import remote_images


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def png(width=2, height=2, *extras):
    pixels = zlib.compress((b"\0" + b"\xff\0\0\xff" * width) * height)
    return (remote_images.PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + b"".join(extras) + chunk(b"IDAT", pixels) + chunk(b"IEND", b""))


def segment(marker, body):
    return bytes([0xFF, marker]) + struct.pack(">H", len(body) + 2) + body


def jpeg(width=2, height=2, marker=0xC0, scans=1, coded=b"\x12\xff\x00\x34\xff\xd0\x56"):
    frame = struct.pack(">BHHB", 8, height, width, 3) + b"\x01\x11\x00\x02\x11\x00\x03\x11\x00"
    scan = segment(0xDA, b"\x03\x01\x00\x02\x00\x03\x00\x00\x3f\x00") + coded
    return b"\xff\xd8" + segment(0xE0, b"JFIF\0" + b"\0" * 9) + segment(marker, frame) + scan * scans + b"\xff\xd9"


class FormatTests(unittest.TestCase):
    def test_png_keeps_only_the_chunks_that_draw_it(self):
        # 64 MiB of compressed text: the small file a decoder would expand.
        bomb = b"Comment\0\0" + zlib.compress(b"\0" * (64 * 1024 * 1024))
        plain = png()
        dirty = png(2, 2, chunk(b"zTXt", bomb), chunk(b"tEXt", b"a\0b"), chunk(b"iTXt", b"a\0\0\0\0\0b"),
                    chunk(b"iCCP", b"p\0\0" + zlib.compress(b"\0" * 1024)), chunk(b"eXIf", b"x"), chunk(b"acTL", b"\0" * 8))
        cleaned, suffix = remote_images.clean(dirty)
        self.assertEqual((cleaned, suffix), (plain, ".png"))
        self.assertEqual(remote_images.clean(cleaned)[0], cleaned)

    def test_png_keeps_palette_and_transparency(self):
        kept = chunk(b"PLTE", b"\0\0\0") + chunk(b"tRNS", b"\0")
        self.assertEqual(remote_images.clean(png(2, 2, kept))[0], png(2, 2, kept))

    def test_png_data_after_the_end_is_dropped(self):
        self.assertEqual(remote_images.clean(png() + b"x" * 100)[0], png())

    def test_pixel_limit_comes_from_the_header_alone(self):
        self.assertEqual(remote_images.clean(png(2000, 2000))[1], ".png")
        for width, height in ((2001, 2000), (65535, 65535), (0, 5), (5, 0)):
            header = remote_images.PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            with self.assertRaises(ValueError):
                remote_images.clean(header + chunk(b"IDAT", b"") + chunk(b"IEND", b""))
            with self.assertRaises(ValueError):
                remote_images.clean(jpeg(width, height))
        self.assertEqual(remote_images.clean(jpeg(2000, 2000))[1], ".jpg")

    def test_damaged_png_is_refused(self):
        good = png()
        flipped = bytearray(good)
        flipped[20] ^= 1
        no_data = remote_images.PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IEND", b"")
        chunk_first = remote_images.PNG_SIGNATURE + chunk(b"IDAT", b"") + good[8:]
        two_headers = good[:33] + good[8:]
        huge_length = remote_images.PNG_SIGNATURE + struct.pack(">I", 0xFFFFFFFF) + b"IHDR"
        short_header = remote_images.PNG_SIGNATURE + chunk(b"IHDR", b"\0" * 12) + good[33:]
        for data in (bytes(flipped), good[:-1], good[:20], remote_images.PNG_SIGNATURE, no_data,
                     chunk_first, two_headers, huge_length, short_header):
            with self.assertRaises(ValueError):
                remote_images.clean(data)

    def test_jpeg_passes_with_coded_data_and_many_markers(self):
        data = jpeg(marker=0xC2, scans=remote_images.MAX_SCANS)
        self.assertEqual(remote_images.clean(data), (data, ".jpg"))
        filled = jpeg().replace(b"\xff\xd9", b"\xff\xff\xd9")
        self.assertEqual(remote_images.clean(filled)[1], ".jpg")

    def test_jpeg_with_too_many_scans_is_refused(self):
        with self.assertRaises(ValueError):
            remote_images.clean(jpeg(marker=0xC2, scans=remote_images.MAX_SCANS + 1))

    def test_unusual_or_damaged_jpeg_is_refused(self):
        two_frames = jpeg().replace(b"\xff\xda", segment(0xC0, b"\x08\0\x02\0\x02\x03" + b"\x01\x11\0" * 3) + b"\xff\xda", 1)
        twelve_bit = jpeg().replace(b"\xff\xc0\x00\x11\x08", b"\xff\xc0\x00\x11\x0c")
        no_end = jpeg()[:-2]
        no_scan = b"\xff\xd8" + segment(0xC0, b"\x08\0\x02\0\x02\x03" + b"\x01\x11\0" * 3) + b"\xff\xd9"
        no_frame = b"\xff\xd8" + segment(0xDA, b"\0") + b"\xff\xd9"
        overrun = b"\xff\xd8" + b"\xff\xe0\xff\xff" + b"x"
        bad_length = b"\xff\xd8" + b"\xff\xe0\x00\x01" + b"\xff\xd9"
        garbage = b"\xff\xd8\xff\xe0" + b"\0"
        for data in (*(jpeg(marker=marker) for marker in remote_images.JPEG_OTHER_FRAMES), two_frames,
                     twelve_bit, no_end, no_scan, no_frame, overrun, bad_length, garbage):
            with self.assertRaises(ValueError):
                remote_images.clean(data)

    def test_only_png_and_jpeg_are_accepted(self):
        for data in (b"", b"GIF89a" + b"\0" * 32, b"RIFF\0\0\0\0WEBPVP8 ", b"<svg xmlns='http://www.w3.org/2000/svg'/>",
                     b"<html></html>", b"BM" + b"\0" * 32, b"\x00\x00\x01\x00" + b"\0" * 32):
            with self.assertRaises(ValueError):
                remote_images.clean(data)

    def test_truncated_real_shapes_never_escape_as_other_errors(self):
        for data in (png(), jpeg(), jpeg(marker=0xC2, scans=3)):
            for end in range(len(data)):
                try:
                    remote_images.clean(data[:end])
                except ValueError:
                    continue
                self.fail(f"A file cut at byte {end} was accepted.")


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send(self, code, body=b"", **headers):
        self.send_response(code)
        for name, value in headers.items():
            self.send_header(name.replace("_", "-"), value)
        self.end_headers()
        self.wfile.write(body)

    def endless(self):
        block = b"\0" * 65536
        try:
            while True:
                self.wfile.write(block)
                self.server.sent += len(block)
        except OSError:
            pass

    def do_GET(self):
        self.server.requests.append(self.path)
        self.path = self.path.split("?")[0]
        if self.path == "/picture.png":
            self.send(200, png(2, 2, chunk(b"tEXt", b"a\0b")), Content_Type="image/png")
        elif self.path == "/picture.jpg":
            self.send(200, jpeg(), Content_Type="image/jpeg")
        elif self.path == "/page":
            self.send(200, b"<html></html>", Content_Type="image/png")
        elif self.path == "/exact":
            self.send(200, png().ljust(remote_images.MAX_BYTES, b"\0"))
        elif self.path == "/over":
            self.send(200, png().ljust(remote_images.MAX_BYTES + 1, b"\0"))
        elif self.path == "/endless":
            self.send_response(200)
            self.end_headers()
            self.endless()
        elif self.path == "/redirect-endless-body":
            # A body that never ends: reading it would never reach the picture.
            self.send_response(302)
            self.send_header("Location", "/picture.png")
            self.send_header("Content-Length", str(10 ** 12))
            self.end_headers()
            self.endless()
        elif self.path == "/loop":
            self.send(302, Location="/loop", Content_Length="0")
        elif self.path == "/gone":
            self.send(404, b"missing", Content_Length="7")
        elif self.path == "/drip":
            self.send_response(200)
            self.end_headers()
            try:
                for _ in range(60):
                    self.wfile.write(b"\0")
                    self.wfile.flush()
                    time.sleep(0.05)
            except OSError:
                pass


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.server = Server(("127.0.0.1", 0), Handler)
        self.server.sent, self.server.requests = 0, []
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        opener = urllib.request.OpenerDirector()
        for handler in (urllib.request.HTTPHandler(), urllib.request.HTTPDefaultErrorHandler(),
                        urllib.request.HTTPErrorProcessor()):
            opener.add_handler(handler)
        for patcher in (mock.patch.object(remote_images, "OPENER", opener), mock.patch.object(remote_images, "SCHEME", "http")):
            patcher.start()
            self.addCleanup(patcher.stop)
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name) / "images"

    def test_saves_a_checked_copy_privately(self):
        url = self.base + "/picture.png"
        images = remote_images.collect([url, self.base + "/picture.jpg"], self.folder)
        self.assertEqual(set(images), {url, self.base + "/picture.jpg"})
        self.assertTrue(images[url].startswith("file:///"))
        path = Path(urllib.request.url2pathname(images[url][len("file://"):]))
        self.assertEqual(path.read_bytes(), png(), "The text chunk is gone")
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.folder.stat().st_mode & 0o777, 0o700)
        self.assertEqual({entry.suffix for entry in self.folder.iterdir()}, {".png", ".jpg"})

    def test_byte_limit_is_exact(self):
        self.assertEqual(len(remote_images.download(self.base + "/exact")), remote_images.MAX_BYTES)
        for path in ("/over", "/endless"):
            with self.assertRaises(ValueError):
                remote_images.download(self.base + path)

    def test_an_endless_response_stops_at_the_limit(self):
        self.assertEqual(remote_images.collect([self.base + "/endless"], self.folder), {})
        time.sleep(0.1)
        # Only what the sockets' buffers held beyond what was read.
        self.assertLess(self.server.sent, remote_images.MAX_BYTES + 32 * 1024 * 1024)
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_a_redirect_body_is_never_read(self):
        started = time.monotonic()
        self.assertEqual(remote_images.download(self.base + "/redirect-endless-body")[:8], remote_images.PNG_SIGNATURE)
        self.assertLess(time.monotonic() - started, 5)

    def test_redirects_are_limited(self):
        with self.assertRaises(ValueError):
            remote_images.download(self.base + "/loop")
        self.assertEqual(len(self.server.requests), remote_images.MAX_REDIRECTS + 1)

    def test_a_failed_or_foreign_response_is_not_saved(self):
        self.assertEqual(remote_images.collect([self.base + "/gone", self.base + "/page"], self.folder), {})
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_a_dripping_response_ends_at_the_deadline(self):
        good = self.base + "/picture.png"
        with mock.patch.object(remote_images, "DEADLINE", 1):
            started = time.monotonic()
            images = remote_images.collect([self.base + "/drip", good], self.folder)
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(list(images), [good], "A stuck picture doesn't cost the others")

    def test_reuses_a_saved_file_without_the_network(self):
        url = self.base + "/picture.png"
        remote_images.collect([url], self.folder)
        self.assertEqual(remote_images.collect([url], self.folder).keys(), {url})
        self.assertEqual(self.server.requests.count("/picture.png"), 1)

    def test_a_tampered_or_oversized_saved_file_is_replaced(self):
        url = self.base + "/picture.png"
        for tampered in (b"not a picture", png(2, 2, chunk(b"zTXt", b"a\0\0x")), png().ljust(remote_images.MAX_BYTES + 1, b"\0")):
            self.server.requests.clear()
            path = Path(urllib.request.url2pathname(remote_images.collect([url], self.folder)[url][len("file://"):]))
            path.write_bytes(tampered)
            self.assertEqual(remote_images.collect([url], self.folder).keys(), {url})
            self.assertEqual(path.read_bytes(), png())
            self.assertIn("/picture.png", self.server.requests)

    def test_url_count_and_length_are_limited(self):
        wanted = [f"{self.base}/picture.png?{index}" for index in range(remote_images.MAX_URLS + 5)]
        long_url = self.base + "/picture.png?" + "x" * remote_images.MAX_URL_LENGTH
        images = remote_images.collect([long_url, *wanted, *wanted], self.folder)
        self.assertEqual(set(images), set(wanted[:remote_images.MAX_URLS]))


class FetchRulesTests(unittest.TestCase):
    def test_the_real_opener_has_no_redirect_handler_and_only_https(self):
        self.assertFalse([handler for handler in remote_images.OPENER.handlers
                          if isinstance(handler, urllib.request.HTTPRedirectHandler)])
        self.assertIn("https", remote_images.OPENER.handle_open)
        self.assertEqual({"http", "ftp", "file", "data"} & set(remote_images.OPENER.handle_open), set())

    def test_refuses_anything_but_https(self):
        opener = mock.Mock()
        with mock.patch.object(remote_images, "OPENER", opener):
            for url in ("http://example.org/a.png", "file:///etc/passwd", "ftp://example.org/a.png",
                        "data:image/png;base64,AA==", "--force", ""):
                with self.assertRaises(ValueError):
                    remote_images.download(url)
        opener.open.assert_not_called()

    def test_a_redirect_away_from_https_is_refused_without_a_request(self):
        for location in ("http://example.org/a.png", "file:///etc/passwd"):
            opener = mock.Mock()
            opener.open.side_effect = urllib.error.HTTPError("https://example.org/", 302, "Found", {"Location": location}, None)
            with mock.patch.object(remote_images, "OPENER", opener), self.assertRaises(ValueError):
                remote_images.download("https://example.org/")
            self.assertEqual(opener.open.call_count, 1)

    def test_a_relative_redirect_stays_on_https(self):
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b"body"
        opener = mock.Mock()
        opener.open.side_effect = [urllib.error.HTTPError("https://example.org/a", 302, "Found", {"Location": "/b"}, None), response]
        with mock.patch.object(remote_images, "OPENER", opener):
            self.assertEqual(remote_images.download("https://example.org/a"), b"body")
        self.assertEqual(opener.open.call_args[0][0].full_url, "https://example.org/b")

    def test_a_malformed_url_costs_only_its_picture(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(remote_images.collect(["https://exa mple.org/\n", "https://[bad", "https://é.invalid/\x00"], Path(folder) / "images"), {})

    def test_prune_keeps_the_most_recent_within_both_budgets(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            for index in range(5):
                path = directory / f"{index}.png"
                path.write_bytes(b"x" * 100)
                os.utime(path, (1000 + index, 1000 + index))
            with mock.patch.object(remote_images, "MAX_FILES", 3):
                remote_images.prune(directory)
            self.assertEqual(sorted(path.name for path in directory.iterdir()), ["2.png", "3.png", "4.png"])
            with mock.patch.object(remote_images, "MAX_DISK", 200):
                remote_images.prune(directory)
            self.assertEqual(sorted(path.name for path in directory.iterdir()), ["3.png", "4.png"])

    def test_the_command_prints_json(self):
        with tempfile.TemporaryDirectory() as folder:
            done = subprocess.run([sys.executable, str(ROOT / "bin/remote_images.py"), "http://example.org/a.png", "--force"],
                                  capture_output=True, text=True, timeout=30, env={**os.environ, "STOCKS_STATE_DIR": folder})
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(json.loads(done.stdout), {"images": {}})


class QmlTests(unittest.TestCase):
    """Qt must never be given a remote picture: every way in goes through local()."""

    def sources(self):
        return {path.relative_to(ROOT / "qml").as_posix(): path.read_text() for path in (ROOT / "qml").rglob("*.qml")}

    def test_every_image_element_shows_a_checked_file(self):
        found = {}
        for name, source in self.sources().items():
            for match in re.finditer(r"(?<![\w.])(?:\w+\.)?(\w*Image|AnimatedSprite|Sprite|ShaderEffectSource)\s*\{", source):
                found.setdefault(name, []).append(match.group(1))
        self.assertEqual(found, {"stock/CompanyNews.qml": ["Image"]}, "A new image element must load only local() files")
        self.assertRegex(self.sources()["stock/CompanyNews.qml"], r"Image \{\s*source: pictures\.local\(article\.modelData\.image\)")

    def test_the_canvas_loads_only_the_checked_logo(self):
        users = {name for name, source in self.sources().items() if re.search(r"\b(loadImage|drawImage|createImageData)\(", source)}
        self.assertEqual(users, {"art/MarketSky.qml"})
        sky = self.sources()["art/MarketSky.qml"]
        self.assertIn("readonly property string logoFile: MarketStore.bannerLogo", sky)
        self.assertIn("readonly property string bannerLogo: banner ? bannerImages.local(banner.logo) : \"\"",
                      self.sources()["stores/MarketStore.qml"])
        self.assertNotIn(".logo\n", sky.split("function logoKey")[1].split("Canvas {")[0])
        self.assertEqual(re.findall(r"banners\.loadImage\((\w+)\)", sky), ["url"])
        self.assertIn("const url = logoFile", sky)
        self.assertIn("banners.unloadImage(url)", sky)

    def test_qml_has_no_other_network_loader(self):
        pattern = r"\b(XMLHttpRequest|WebSocket|WebEngineView|WebView|MediaPlayer|Video|Audio|FontLoader)\b\s*[({]"
        self.assertEqual({name: re.findall(pattern, source) for name, source in self.sources().items() if re.search(pattern, source)}, {})

    def test_local_accepts_only_files(self):
        source = self.sources()["data/LocalImages.qml"]
        self.assertIn(r"/^file:\/\/\//.test(file) ? file : ", source)
        self.assertIn('script: "../../bin/remote_images.py"', source)
        self.assertIn('import ".."', source, "DataRequest resolves through qml/qmldir, whatever loaded first")


if __name__ == "__main__":
    unittest.main()
