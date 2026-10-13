"""Background agent research jobs shared by the AI features. Status never starts model or market calls."""
from contextlib import contextmanager
from dataclasses import dataclass
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from typing import Callable
import urllib.parse
import uuid

import ai_runner
from stocks import read_json, state_directory, symbol, write_json


PREFERENCES = ("default", "claude", "codex", "opencode")


@dataclass(frozen=True)
class Task:
    """One AI feature: where its jobs live, how they research and how they are checked."""
    folder: str              # Under the app state directory
    version: int             # Results from another version are ignored
    ttl: float               # A newer result is reused by start, and older ones are marked stale
    timeout: float           # Whole job, including market context
    name: str                # Notification title: "AMD · <name> ready"
    action: str              # The button that shows the result, for notification text
    title: str               # The agent's session title, where it has one
    context: Callable        # ticker -> market context
    prompt: Callable         # (job, context) -> prompt
    schema: dict
    validate: Callable       # (document, job, context) -> result
    expired: Callable = lambda result, ticker: False
    publish: Callable = lambda path, result: None  # Called under the job lock before the result is saved
    stage: str = "Researching"  # Shown once market context is ready
    steps: int = 16


def valid_url(url):
    parts = urllib.parse.urlsplit(url)
    return (parts.scheme in ("http", "https") and bool(parts.hostname) and not parts.username and not parts.password
            and len(url) <= 2048 and not any(ord(char) < 32 for char in url))


def directory(task, ticker, preference):
    if preference not in PREFERENCES:
        raise ValueError("Unknown analysis agent.")
    key = hashlib.sha256(f"{ticker}:{preference}".encode()).hexdigest()
    path = state_directory() / task.folder / key
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


@contextmanager
def locked(path):
    with (path / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def process_identity(pid):
    """A PID alone is unsafe after a reboot or process reuse."""
    try:
        fields = Path(f"/proc/{int(pid)}/stat").read_text().rsplit(")", 1)[1].split()
        if fields[0] == "Z":
            return ""
        return Path("/proc/sys/kernel/random/boot_id").read_text().strip() + ":" + fields[19]
    except (OSError, ValueError, IndexError):
        return ""


def alive(job):
    return bool(job.get("processIdentity")) and process_identity(job.get("pid", 0)) == job["processIdentity"]


def reply(task, job, saved, ticker, preference):
    result = dict(saved) if saved.get("symbol") == ticker and saved.get("version") == task.version else {}
    return {**result, "symbol": ticker, "preference": preference, "pending": job.get("state") == "running",
            "stage": job.get("stage", ""), "job": job.get("id", ""),
            "workingAgent": (job.get("agent") or {}).get("name", ""),
            "error": job.get("error", ""),
            "notifyRequested": job.get("notifyRequested", False),
            "stale": bool(result) and time.time() - result.get("generated", 0) >= task.ttl}


def notify_finished(task, path, job):
    """Called under the job lock; notifications belong to a specific request."""
    if not job.get("notifyRequested") or job.get("notified") or job.get("state") not in ("complete", "failed"):
        return
    ready = job["state"] == "complete"
    title = f"{job['symbol']} · {task.name} {'ready' if ready else 'failed'}"
    body = (f"Open Stocks and choose {task.action} to read it." if ready
            else f"Research could not finish. Open Stocks and choose {task.action} to retry.")
    try:
        subprocess.run(["notify-send", "--app-name=Stocks", "--icon=" + str(Path(__file__).resolve().parents[1] / "assets/icon.svg"),
                        title, body], check=True, timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return
    job["notified"] = True
    write_json(path / "job.json", job)


def main(task, script, arguments):
    """`script` is the feature's own entry point; its worker runs `ai_jobs.worker` with the same task."""
    if len(arguments) < 3 or arguments[0] not in ("status", "start", "cancel", "notify"):
        raise ValueError("Use status, start, cancel or notify with a symbol and agent.")
    action, ticker, preference = arguments[:3]
    ticker = symbol(ticker)
    path = directory(task, ticker, preference)
    with locked(path):
        job, saved = read_json(path / "job.json", {}), read_json(path / "result.json", {})
        if task.expired(saved, ticker):
            saved = {}
            write_json(path / "result.json", saved)
        if job.get("state") == "running" and (not alive(job) or time.time() - job.get("started", 0) > task.timeout + 10):
            if alive(job):
                os.kill(job["pid"], signal.SIGTERM)
            job.update(state="failed", error="The research job stopped or timed out. Retry the analysis.")
            write_json(path / "job.json", job)
        if action == "notify":
            if len(arguments) > 3 and arguments[3] == job.get("id"):
                job["notifyRequested"] = True
                write_json(path / "job.json", job)
            notify_finished(task, path, job)
            return reply(task, job, saved, ticker, preference)
        notify_finished(task, path, job)
        if action == "cancel":
            # The request ID prevents a delayed click from cancelling a new job.
            if len(arguments) > 3 and arguments[3] == job.get("id") and job.get("state") == "running":
                job.update(state="cancelled", error="Research cancelled.")
                write_json(path / "job.json", job)
                if alive(job):
                    os.kill(job["pid"], signal.SIGTERM)
            return reply(task, job, saved, ticker, preference)
        if action == "status" or job.get("state") == "running":
            return reply(task, job, saved, ticker, preference)
        try:
            agent = ai_runner.resolve(preference)
            if ("--force" not in arguments and saved.get("version") == task.version
                    and saved.get("agentId") == agent["id"] and time.time() - saved.get("generated", 0) < task.ttl):
                return reply(task, {}, saved, ticker, preference)
            identity = uuid.uuid4().hex
            job = {"id": identity, "symbol": ticker, "preference": preference, "agent": agent,
                   "started": time.time(), "state": "running", "stage": "Gathering market context", "error": ""}
            # The child acquires this lock before reading; startup cannot race the
            # parent's publication of its PID and identity.
            process = subprocess.Popen([sys.executable, str(Path(script).resolve()), "worker", ticker, preference, identity],
                                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       start_new_session=True)
            job.update(pid=process.pid, processIdentity=process_identity(process.pid))
            write_json(path / "job.json", job)
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            job = {"state": "failed", "error": str(error)}
            write_json(path / "job.json", job)
        return reply(task, job, saved, ticker, preference)


def update(path, identity, **changes):
    with locked(path):
        job = read_json(path / "job.json", {})
        if job.get("id") != identity or job.get("state") != "running":
            return False
        job.update(changes)
        write_json(path / "job.json", job)
        return True


@contextmanager
def capacity(root):
    # Two simultaneous research jobs per feature at most, across windows and symbols.
    for slot in range(2):
        lock = (root / f"worker-{slot}.lock").open("w")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            lock.close()
            continue
        try:
            yield
        finally:
            lock.close()
        return
    raise ValueError("Two analyses are already running. Wait for one to finish, then retry.")


def worker(task, ticker, preference, identity):
    path = directory(task, symbol(ticker), preference)
    if not re.fullmatch(r"[a-f0-9]{32}", identity):
        return
    def stop(*_):
        raise InterruptedError("Research cancelled or timed out.")
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGALRM, stop)
    signal.alarm(int(task.timeout))
    try:
        with locked(path):
            job = read_json(path / "job.json", {})
        if job.get("id") != identity or job.get("state") != "running":
            return
        with capacity(path.parent):
            context = task.context(ticker)
            if not update(path, identity, stage=task.stage):
                return
            folder = path / identity
            folder.mkdir(mode=0o700)
            write_json(folder / "context.json", context)
            document = ai_runner.run(job["agent"], task.prompt(job, context), task.schema, folder,
                                     timeout=task.timeout - 90, title=task.title, steps=task.steps)
            result = task.validate(document, job, context)
            if task.expired(result, ticker):
                raise ValueError("A new trading session started during research. Retry for the latest move.")
            with locked(path):
                current = read_json(path / "job.json", {})
                if current.get("id") == identity and current.get("state") == "running":
                    task.publish(path, result)
                    write_json(path / "result.json", result)
                    write_json(path / "job.json", {**current, "state": "complete", "stage": "", "error": ""})
    except Exception as error:
        update(path, identity, state="failed", stage="", error=str(error))
    finally:
        signal.alarm(0)
        with locked(path):
            current = read_json(path / "job.json", {})
            if current.get("id") == identity:
                notify_finished(task, path, current)


def cli(task, script, handle=None):
    """The command-line entry point of a feature's script; `handle` adds its own actions."""
    os.umask(0o077)
    if len(sys.argv) == 5 and sys.argv[1] == "worker":
        worker(task, *sys.argv[2:])
    else:
        try:
            print(json.dumps((handle or (lambda arguments: main(task, script, arguments)))(sys.argv[1:]), allow_nan=False))
        except Exception as error:
            print(json.dumps({"pending": False, "error": str(error)}))
