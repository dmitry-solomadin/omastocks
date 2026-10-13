"""Small, credential-free adapters for the user's installed agent CLIs."""
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import time

from stocks import write_json


AGENTS = {"claude": "Claude Code", "codex": "Codex", "opencode": "OpenCode"}
MAX_OUTPUT = 4 * 1024 * 1024


def resolve(preference):
    if preference == "default":
        command = shutil.which("omarchy-default-agent")
        preference = command and subprocess.run([command], capture_output=True, text=True, check=True, timeout=5).stdout.strip()
        if not preference:
            raise ValueError("Set your Omarchy default agent, or choose Claude Code or Codex in Settings → AI.")
    if preference not in AGENTS:
        raise ValueError("Stocks can run Claude Code, Codex or OpenCode. Choose Claude Code or Codex in Settings → AI, "
                         "or change your Omarchy default agent.")
    executable = (shutil.which("opencode2") or shutil.which("opencode")) if preference == "opencode" else shutil.which(preference)
    if not executable:
        raise ValueError(AGENTS[preference] + " is not installed. Install and sign in to it, then retry.")
    # Omarchy's lazy-install stubs are not installed agents. Never run installers
    # from an analysis request; the user owns installation and authentication.
    if Path(executable).is_file() and Path(executable).stat().st_size < 4096:
        try:
            if "mise use -g" in Path(executable).read_text():
                raise ValueError(AGENTS[preference] + " needs setup. Launch it once and sign in, then retry.")
        except UnicodeError:
            pass
    return {"id": preference, "name": AGENTS[preference], "executable": executable}


def command(agent, folder, schema, title="Stocks · Explain latest move", steps=16):
    executable, kind = agent["executable"], agent["id"]
    if kind == "claude":
        # --tools limits only built-in tools; without --strict-mcp-config the user's
        # MCP servers and claude.ai connectors (brokerage, mail) still load.
        return [executable, "-p", "--output-format", "stream-json", "--verbose",
                "--no-session-persistence", "--permission-mode", "dontAsk", "--strict-mcp-config",
                "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch",
                "--json-schema", json.dumps(schema)]
    if kind == "codex":
        write_json(folder / "schema.json", schema)
        return [executable, "exec", "--skip-git-repo-check", "--ephemeral", "--json",
                "--sandbox", "read-only", "-c", 'approval_policy="never"',
                "-c", 'web_search="live"', "--output-schema", str(folder / "schema.json"), "-"]
    # A private run cannot interrupt another OpenCode conversation. The local
    # profile inherits the user's provider/model/search configuration and auth.
    write_json(folder / "opencode.json", {
        "$schema": "https://opencode.ai/config.json", "snapshots": False, "warming": False,
        "agents": {"stock-research": {"mode": "primary", "steps": steps,
            "description": "Research a stock from fresh public sources",
            "permissions": [{"action": "*", "resource": "*", "effect": "deny"},
                            {"action": "websearch", "resource": "*", "effect": "allow"},
                            {"action": "webfetch", "resource": "*", "effect": "allow"}]}}})
    return [executable, "run", "--standalone", "--format", "json", "--agent", "stock-research",
            "--title", title, "--file", str(folder / "prompt.txt"),
            "Complete the stock research task in the attached file. Return only its requested JSON."]


def json_document(text):
    text = text.strip()
    if text.startswith("```json\n") and text.endswith("```"):
        text = text[8:-3].strip()
    elif text.startswith("```\n") and text.endswith("```"):
        text = text[4:-3].strip()
    try:
        value = json.loads(text)
    except (ValueError, TypeError) as error:
        raise ValueError("The agent returned an incomplete or invalid analysis. Retry to regenerate.") from error
    if not isinstance(value, dict):
        raise ValueError("The agent did not return an analysis object.")
    return value


class Output:
    """Normalize native events; never mistake progress text for the final answer."""
    def __init__(self, kind):
        self.kind = kind
        self.text = ""
        self.document = None
        self.complete = False
        self.researched = False
        self.failed = False
        self.error = ""
        self.web_calls = set()

    def feed(self, event):
        if not isinstance(event, dict):
            return
        kind = event.get("type")
        if self.kind == "opencode":
            part = event.get("part") or {}
            if kind == "text":
                self.text = part.get("text", "")
            if kind == "step_finish":
                self.complete = part.get("reason") in ("stop", "end_turn")
            if kind == "tool_use":
                self.complete = False
                if part.get("tool") in ("websearch", "webfetch") and (part.get("state") or {}).get("status") == "completed":
                    self.researched = True
            if kind == "error":
                self.failed = True
                self.error = str((event.get("error") or {}).get("message") or "")
        elif self.kind == "codex":
            item = event.get("item") or {}
            if kind == "item.completed" and item.get("type") == "agent_message":
                self.text = item.get("text", "")
            if kind == "item.completed" and item.get("type") == "web_search" and item.get("status") != "failed":
                self.researched = True
            if kind == "turn.completed":
                self.complete = True
            if kind in ("turn.failed", "error"):
                self.failed = True
        else:
            # System events such as permission_denied carry a plain-text message.
            message = event.get("message")
            for block in (message.get("content") if isinstance(message, dict) else None) or []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use" and block.get("name") in ("WebSearch", "WebFetch"):
                    self.web_calls.add(block.get("id"))
                if block.get("type") == "tool_result" and block.get("tool_use_id") in self.web_calls and not block.get("is_error"):
                    self.researched = True
            if kind == "result":
                self.failed = bool(event.get("is_error")) or event.get("subtype") != "success"
                self.complete = not self.failed
                self.document = event.get("structured_output")
                self.text = event.get("result", "")

    def result(self, successful_exit=False):
        # V2 reconciles its final message from the service when the last live
        # step event was missed. In that case text + a successful CLI exit is
        # the completion contract; progress prose still fails JSON validation.
        if self.kind == "opencode" and successful_exit and self.text:
            self.complete = True
        if self.failed or not self.complete:
            raise ValueError("The agent did not complete its research. Check its sign-in, model and usage limits, then retry.")
        if not self.researched:
            raise ValueError("The agent returned no web research. Enable its web search/fetch tools, or choose another agent in Settings.")
        return self.document if isinstance(self.document, dict) else json_document(self.text)


def run(agent, prompt, schema, folder, timeout=210, title="Stocks · Explain latest move", steps=16):
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    (folder / "prompt.txt").write_text(prompt)
    args = command(agent, folder, schema, title, steps)
    environment = os.environ.copy()
    # OpenCode resolves its project from PWD before process.cwd(); subprocess
    # cwd alone would load the host app's project instead of this job's profile.
    environment["PWD"] = str(folder.resolve())
    # This is a new job, not a nested session or a continuation of the host UI.
    for key in ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "OPENCODE_SERVER", "OPENCODE_SESSION_ID",
                "HERDR_PANE_ID", "HERDR_SOCKET_PATH", "HERDR_CLIENT_SOCKET_PATH"):
        environment.pop(key, None)
    parser = Output(agent["id"])
    # Use a file as stdin so a large context cannot deadlock against startup logs.
    with (folder / "prompt.txt").open("rb") as input_file:
        process = subprocess.Popen(args, cwd=folder, env=environment,
                                   stdin=subprocess.DEVNULL if agent["id"] == "opencode" else input_file,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        pending, stderr, size, deadline = b"", b"", 0, time.monotonic() + timeout
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ, "stdout")
            selector.register(process.stderr, selectors.EVENT_READ, "stderr")
            while selector.get_map():
                if time.monotonic() > deadline:
                    raise ValueError("Research timed out. Retry, or choose a faster model in your agent.")
                for key, _ in selector.select(.2):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    size += len(chunk)
                    if size > MAX_OUTPUT:
                        raise ValueError("The agent's research output was too large. Try again with a shorter task.")
                    if key.data != "stdout":
                        stderr = (stderr + chunk)[-2048:]
                        continue
                    pending += chunk
                    while b"\n" in pending:
                        line, pending = pending.split(b"\n", 1)
                        try:
                            parser.feed(json.loads(line))
                        except (ValueError, UnicodeError):
                            pass  # Some CLIs emit startup notices before JSON.
            if pending.strip():
                try:
                    parser.feed(json.loads(pending))
                except (ValueError, UnicodeError):
                    pass
        if process.wait(timeout=max(.1, deadline - time.monotonic())) != 0:
            message = parser.error or stderr.decode("utf-8", errors="replace")
            message = " ".join(message.split())
            # Provider diagnostics occasionally include credentials. Never surface them.
            message = re.sub(r"(?i)(?:sk-[\w-]+|bearer\s+\S+|(?:api[_-]?key|token|password)[=:]\s*\S+)", "[redacted]", message)
            raise ValueError(agent["name"] + " failed. " + (message[:350] + " " if message else "")
                             + "Check its sign-in, model and usage limits, then retry.")
        return parser.result(successful_exit=True)
    finally:
        # Only this job's process group; never the user's shared agent service.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        process.stdout.close()
        process.stderr.close()
