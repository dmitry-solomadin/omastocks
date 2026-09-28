"""Shared Yahoo pacing/backoff and an anonymous, persistent bulk-data session."""
from contextlib import contextmanager
from email.utils import parsedate_to_datetime
import fcntl
import http.client
import http.cookiejar
import io
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib

LIMIT = 4 * 1024 * 1024
# The chart on screen and the search box go first; the data helper sets this.
priority = False


@contextmanager
def locked(name):
    from stocks import state_directory
    directory = state_directory() / "yahoo"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / (name + ".lock")).open("w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield directory


def reserve():
    """Claim this request's turn, 0.25 s after the one before, and wait for it
    outside the lock. With priority (the chart on screen) the turn is now, and
    later requests keep their distance from it. Returns the shared state read."""
    from stocks import read_json, write_json
    with locked("traffic") as directory:
        path = directory / "traffic.json"
        state = read_json(path, {})
        now = time.time()
        if state.get("retryAfter", 0) > now:
            raise ValueError("Yahoo Finance is rate limiting requests. Please try again later.")
        start = now if priority else max(now, state.get("next", 0))
        write_json(path, {**state, "next": max(start, state.get("next", 0)) + .25})
    time.sleep(start - now)
    return state


def outage(failed):
    """Yahoo unreachable: count requests that failed on the network or with a
    server error since the first one. Any reply from Yahoo clears it."""
    from stocks import read_json, write_json
    with locked("traffic") as directory:
        path = directory / "traffic.json"
        state = read_json(path, {})
        if failed:
            previous = state.get("outage") or {}
            state["outage"] = {"since": previous.get("since", time.time()), "failures": previous.get("failures", 0) + 1}
        elif state.pop("outage", None) is None:
            return
        write_json(path, state)


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


def awake():
    """Seconds since boot, counting time asleep; time.monotonic() stops during a
    suspend on Linux, so a connection left over one would look fresh."""
    return time.clock_gettime(time.CLOCK_BOOTTIME)


class KeepAlive:
    """One reused HTTPS connection per host for a long-lived helper, which saves
    a TLS handshake per request. A reused connection Yahoo has closed is
    reopened once, silently. One idle for over a minute is not reused: if a
    suspend or network change dropped it, a request would hang until timeout."""
    idle = 60
    connect = http.client.HTTPSConnection

    def __init__(self):
        self.connections = {}

    def open(self, request, timeout=10):
        parts = urllib.parse.urlsplit(request.full_url)
        target = parts.path + ("?" + parts.query if parts.query else "")
        for attempt in range(2):
            connection, used = self.connections.pop(parts.netloc, (None, 0))
            if connection is not None and awake() - used > self.idle:
                connection.close()
                connection = None
            reused = connection is not None
            connection = connection or self.connect(parts.netloc, timeout=timeout)
            try:
                connection.request(request.get_method(), target, body=request.data, headers=dict(request.header_items()))
                response = connection.getresponse()
            except (http.client.RemoteDisconnected, http.client.ImproperConnectionState,
                    ConnectionResetError, BrokenPipeError, ConnectionAbortedError) as error:
                connection.close()
                if reused and attempt == 0:
                    continue
                raise urllib.error.URLError(error) from error
            except (OSError, http.client.HTTPException) as error:
                connection.close()
                raise urllib.error.URLError(error) from error
            self.connections[parts.netloc] = (connection, awake())
            # The same errors urllib raises, so read() treats both transports alike.
            if response.status >= 400:
                raise urllib.error.HTTPError(request.full_url, response.status, response.reason,
                                             response.headers, io.BytesIO(response.read()))
            return response


class WithCookies:
    """A kept connection that carries Yahoo's session cookies, as a cookie opener
    does, so the data helper's quote requests reuse its connection too."""

    def __init__(self, transport, jar):
        self.transport, self.jar = transport, jar

    def open(self, request, timeout=10):
        if not request.has_header("User-agent"):
            request.add_header("User-Agent", "Mozilla/5.0")
        self.jar.add_cookie_header(request)
        try:
            response = self.transport.open(request, timeout)
        except urllib.error.HTTPError as error:
            self.jar.extract_cookies(error, request)
            raise
        self.jar.extract_cookies(response, request)
        return response


# The transport for requests without their own opener; the data helper sets a KeepAlive.
persistent = None


def read(request, opener=None):
    # Recover from brief DNS/network outages before falling back to cached quotes.
    # Reserve every attempt so retries still respect the shared provider cooldown.
    # A request held back by the shared cooldown never reached Yahoo: not an outage.
    opener = opener or persistent
    # Compressed replies are a quarter of the size and arrive in about half the time.
    if isinstance(request, urllib.request.Request) and not request.has_header("Accept-encoding"):
        request.add_header("Accept-Encoding", "gzip")
    for attempt in range(3):
        traffic = reserve()
        # Normal operation writes nothing extra; only an outage on record is cleared.
        recorded = isinstance(traffic, dict) and "outage" in traffic
        try:
            with (opener.open if opener else urllib.request.urlopen)(request, timeout=10) as response:
                raw = response.read(LIMIT + 1)
                if response.headers.get("Content-Encoding") == "gzip":
                    # Bounded, so a small reply cannot expand without limit.
                    try:
                        raw = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(raw, LIMIT + 1)
                    except zlib.error as error:
                        raise ValueError("Yahoo Finance returned a damaged response.") from error
        except urllib.error.HTTPError as error:
            # Any reply but a server error proves Yahoo is reachable, even a 404.
            if error.code < 500 and recorded:
                outage(False)
            if error.code == 429:
                throttled(error.headers)
                raise ValueError("Yahoo Finance is rate limiting requests. Please try again later.") from error
            if error.code not in (500, 502, 503, 504) or attempt == 2:
                if error.code >= 500:
                    outage(True)
                raise
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 2:
                outage(True)
                raise
        else:
            if recorded:
                outage(False)
            if len(raw) > LIMIT:
                raise ValueError("Yahoo Finance returned an oversized response.")
            return raw
        time.sleep(2 ** attempt)


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
            # Signing in stays with the cookie opener, which follows redirects;
            # the data request reuses the helper's connection when there is one.
            try:
                return json.loads(read(request, WithCookies(persistent, jar) if persistent else opener))
            except urllib.error.HTTPError as error:
                if error.code == 401 and attempt == 0:
                    saved = {}
                    jar.clear()
                    write_json(session, {})
                    continue
                raise ValueError(f"Yahoo Finance returned HTTP {error.code}.") from error
        raise ValueError("Yahoo session could not be initialized.")
