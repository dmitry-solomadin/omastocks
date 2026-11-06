#!/usr/bin/env python3
"""Pictures from the web as checked local files, so Qt never downloads one.

Qt buffers a whole image response inside the shell before decoding it, and
`sourceSize` limits only the decoding. QML passes the URLs here instead and shows
the files this separate process saves. Downloads use HTTPS and are limited in bytes
and time, and redirect bodies are never read. Only a well-formed PNG or JPEG within
the pixel limit is saved, and a PNG keeps only the chunks that draw it. A picture
that fails any of this isn't shown.

Usage: remote_images.py URL...  Prints {"images": {url: "file:///..."}}."""

import concurrent.futures
import hashlib
import json
import os
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zlib

from stocks import state_directory

# Well above real pictures: the largest seen was 188 KB and 1920x1120, a NYSE logo.
MAX_BYTES = 4 * 1024 * 1024
MAX_PIXELS = 4_000_000
# Each scan of a progressive JPEG is another pass over every pixel.
MAX_SCANS = 32
MAX_REDIRECTS = 3
MAX_URLS = 32
MAX_URL_LENGTH = 2048
WORKERS = 6
SOCKET_TIMEOUT = 8
# The whole run, including what a socket timeout can't stop: a stuck name lookup, or
# a response dripping slowly. Under the 45 seconds DataRequest allows a helper.
DEADLINE = 20
MAX_FILES = 256
MAX_DISK = 64 * 1024 * 1024

SCHEME = "https"
PICTURE_HEADERS = {"User-Agent": "Mozilla/5.0", "Accept": "image/png,image/jpeg"}
REDIRECTS = {301, 302, 303, 307, 308}
# Built by hand to leave out urllib's redirect handler, which reads a redirect's whole
# body before following it, and its handlers for other schemes.
OPENER = urllib.request.OpenerDirector()
for handler in (urllib.request.ProxyHandler(), urllib.request.HTTPSHandler(),
                urllib.request.HTTPDefaultErrorHandler(), urllib.request.HTTPErrorProcessor()):
    OPENER.add_handler(handler)

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# Compressed text and colour profiles expand inside the decoder, before any scaling.
PNG_DRAWING_CHUNKS = {b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND"}
# Baseline, extended sequential and progressive; the others are rare and unneeded.
JPEG_FRAMES = {0xC0, 0xC1, 0xC2}
JPEG_OTHER_FRAMES = {0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}


def check_size(width, height):
    if not width or not height or width * height > MAX_PIXELS:
        raise ValueError("The picture's dimensions are out of range.")


def clean_png(data):
    position, kept, seen = len(PNG_SIGNATURE), [PNG_SIGNATURE], set()
    while b"IEND" not in seen:
        length = int.from_bytes(data[position:position + 4], "big")
        kind, end = data[position + 4:position + 8], position + 12 + length
        if end > len(data) or zlib.crc32(data[position + 4:end - 4]) != int.from_bytes(data[end - 4:end], "big"):
            raise ValueError("The PNG is damaged.")
        if (kind == b"IHDR") == bool(seen) or (kind == b"IHDR" and length != 13):
            raise ValueError("The PNG has no valid header.")
        if kind == b"IHDR":
            check_size(int.from_bytes(data[position + 8:position + 12], "big"),
                       int.from_bytes(data[position + 12:position + 16], "big"))
        if kind in PNG_DRAWING_CHUNKS:
            kept.append(data[position:end])
        seen.add(kind)
        position = end
    if b"IDAT" not in seen:
        raise ValueError("The PNG has no image data.")
    return b"".join(kept)


def check_jpeg(data):
    """Walks the segments. A truncated file runs off the end, an IndexError."""
    position, frames, scans = 2, 0, 0
    while True:
        if data[position] != 0xFF:
            raise ValueError("The JPEG is damaged.")
        while data[position] == 0xFF:
            position += 1
        marker = data[position]
        position += 1
        if marker == 0xD9:
            break
        if marker == 0x01 or 0xD0 <= marker <= 0xD7:
            continue
        length = int.from_bytes(data[position:position + 2], "big")
        if length < 2 or position + length > len(data):
            raise ValueError("The JPEG is damaged.")
        if marker in JPEG_OTHER_FRAMES:
            raise ValueError("The JPEG's format is not supported.")
        if marker in JPEG_FRAMES:
            frames += 1
            components = data[position + 7]
            if data[position + 2] != 8 or components not in (1, 3, 4) or length != 8 + 3 * components:
                raise ValueError("The JPEG's format is not supported.")
            check_size(int.from_bytes(data[position + 5:position + 7], "big"),
                       int.from_bytes(data[position + 3:position + 5], "big"))
        position += length
        if marker == 0xDA:
            scans += 1
            if scans > MAX_SCANS:
                raise ValueError("The JPEG has too many scans.")
            # Coded data runs to the next marker; FF00 and restarts belong to it.
            while True:
                position = data.find(b"\xff", position)
                if position < 0:
                    raise ValueError("The JPEG is damaged.")
                following = data[position + 1]
                if following and not 0xD0 <= following <= 0xD7:
                    break
                position += 2
    if frames != 1 or not scans:
        raise ValueError("The JPEG is damaged.")


def clean(data):
    """The bytes to save and their suffix. Raises ValueError for anything else."""
    try:
        if data.startswith(PNG_SIGNATURE):
            return clean_png(data), ".png"
        if data.startswith(b"\xff\xd8\xff"):
            check_jpeg(data)
            return data, ".jpg"
    except IndexError:
        raise ValueError("The picture is damaged.") from None
    raise ValueError("Only PNG and JPEG pictures are shown.")


def download(url, headers=PICTURE_HEADERS):
    for _ in range(MAX_REDIRECTS + 1):
        if urllib.parse.urlsplit(url).scheme != SCHEME:
            raise ValueError("Pictures download over HTTPS only.")
        request = urllib.request.Request(url, headers=headers)
        try:
            with OPENER.open(request, timeout=SOCKET_TIMEOUT) as response:
                body = response.read(MAX_BYTES + 1)
        except urllib.error.HTTPError as error:
            location = error.headers.get("Location")
            error.close()
            if error.code not in REDIRECTS or not location:
                raise
            url = urllib.parse.urljoin(url, location)
            continue
        if len(body) > MAX_BYTES:
            raise ValueError("The picture is too large.")
        return body
    raise ValueError("The picture redirected too many times.")


def saved(path):
    """A saved file still counts only as what a download would save now."""
    try:
        if path.stat().st_size > MAX_BYTES:
            return False
        data = path.read_bytes()
        if clean(data)[0] != data:
            return False
        os.utime(path)
    except (OSError, ValueError):
        return False
    return True


def local_copy(url, directory):
    name = hashlib.sha256(url.encode()).hexdigest()
    for suffix in (".png", ".jpg"):
        if saved(directory / (name + suffix)):
            return directory / (name + suffix)
    data, suffix = clean(download(url))
    descriptor, temporary = tempfile.mkstemp(prefix=".", suffix=".part", dir=directory)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
        os.replace(temporary, directory / (name + suffix))
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return directory / (name + suffix)


def prune(directory):
    """Keeps the most recently used files within the budgets."""
    files = []
    for entry in os.scandir(directory):
        try:
            status = entry.stat()
        except OSError:
            continue
        files.append((status.st_mtime, status.st_size, entry.path))
    files.sort(reverse=True)
    total = 0
    for index, (_, size, path) in enumerate(files):
        total += size
        if index >= MAX_FILES or total > MAX_DISK:
            try:
                os.unlink(path)
            except OSError:
                pass


def collect(urls, directory):
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    wanted = list(dict.fromkeys(url for url in urls if len(url) <= MAX_URL_LENGTH))[:MAX_URLS]
    pool = concurrent.futures.ThreadPoolExecutor(WORKERS)
    futures = {pool.submit(local_copy, url, directory): url for url in wanted}
    images = {}
    try:
        for future in concurrent.futures.as_completed(futures, timeout=DEADLINE):
            try:
                images[futures[future]] = future.result().as_uri()
            except Exception:
                pass
    except concurrent.futures.TimeoutError:
        pass
    pool.shutdown(wait=False, cancel_futures=True)
    prune(directory)
    return images


if __name__ == "__main__":
    print(json.dumps({"images": collect(sys.argv[1:], (state_directory() / "images").absolute())}), flush=True)
    # A worker stuck past the deadline must not hold the process open.
    os._exit(0)
