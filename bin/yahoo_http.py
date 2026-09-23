"""Shared Yahoo pacing/backoff and an anonymous, persistent bulk-data session."""
from contextlib import contextmanager
from email.utils import parsedate_to_datetime
import fcntl
import http.cookiejar
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request


@contextmanager
def locked(name):
    from stocks import state_directory
    directory = state_directory() / "yahoo"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / (name + ".lock")).open("w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield directory


def reserve():
    from stocks import read_json, write_json
    with locked("traffic") as directory:
        path = directory / "traffic.json"
        state = read_json(path, {})
        now = time.time()
        if state.get("retryAfter", 0) > now:
            raise ValueError("Yahoo Finance is rate limiting requests. Please try again later.")
        time.sleep(max(0, state.get("next", 0) - now))
        write_json(path, {**state, "next": time.time() + .25})


def throttled(headers):
    from stocks import read_json, write_json
    with locked("traffic") as directory:
        path = directory / "traffic.json"
        state = read_json(path, {})
        now = time.time()
        attempts = state.get("attempts", 0) + 1 if now - state.get("last429", 0) < 86400 else 1
        delay = min(3600, 120 * 2 ** min(attempts - 1, 5))
        retry = headers.get("Retry-After", "")
        try:
            delay = max(delay, float(retry))
        except ValueError:
            try:
                delay = max(delay, parsedate_to_datetime(retry).timestamp() - now)
            except (ValueError, TypeError, OverflowError):
                pass
        write_json(path, {**state, "attempts": attempts, "last429": now, "retryAfter": max(state.get("retryAfter", 0), now + delay)})


def read(request, opener=None):
    reserve()
    try:
        with (opener.open if opener else urllib.request.urlopen)(request, timeout=10) as response:
            raw = response.read(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            raise ValueError("Yahoo Finance returned an oversized response.")
        return raw
    except urllib.error.HTTPError as error:
        if error.code == 429:
            throttled(error.headers)
            raise ValueError("Yahoo Finance is rate limiting requests. Please try again later.") from error
        raise


def authenticated(path, body=None, **parameters):
    from stocks import read_json, write_json
    with locked("session") as directory:
        cookies = directory / "cookies.txt"
        session = directory / "session.json"
        jar = http.cookiejar.LWPCookieJar(str(cookies))
        try:
            jar.load(ignore_discard=True)
        except (OSError, http.cookiejar.LoadError):
            pass
        saved = read_json(session, {})
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        opener.addheaders = [("User-Agent", "Mozilla/5.0")]
        for attempt in range(2):
            crumb = saved.get("crumb") if saved.get("expires", 0) > time.time() and len(jar) else None
            if not crumb:
                try:
                    read("https://fc.yahoo.com", opener)
                except urllib.error.HTTPError as error:
                    if error.code != 404:
                        raise ValueError(f"Yahoo session returned HTTP {error.code}.") from error
                crumb = read("https://query1.finance.yahoo.com/v1/test/getcrumb", opener).decode().strip()
                if not crumb or len(crumb) > 100 or "<" in crumb:
                    raise ValueError("Yahoo session could not be initialized.")
                jar.save(ignore_discard=True)
                os.chmod(cookies, 0o600)
                saved = {"crumb": crumb, "expires": time.time() + 43200}
                write_json(session, saved)
                os.chmod(session, 0o600)
            url = "https://query1.finance.yahoo.com" + path + "?" + urllib.parse.urlencode({**parameters, "crumb": crumb})
            request = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                             headers={"Content-Type": "application/json"})
            try:
                return json.loads(read(request, opener))
            except urllib.error.HTTPError as error:
                if error.code == 401 and attempt == 0:
                    saved = {}
                    jar.clear()
                    write_json(session, {})
                    continue
                raise ValueError(f"Yahoo Finance returned HTTP {error.code}.") from error
        raise ValueError("Yahoo session could not be initialized.")
