"""Private storage and the public newline-delimited Herdr socket API."""

import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import socket
import tempfile
import uuid


class ToolError(Exception):
    pass


def checked_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", value):
        raise ToolError("Invalid identifier")
    return value


def config_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "herdr-layout"


def state_dir():
    path = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "herdr-layout"
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    private(path)
    return path


def private(path):
    info = path.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ToolError(f"Expected a private, current-user-owned path: {path}")


def read_json(path):
    private(path)
    if path.stat().st_size > 8 * 1024 * 1024:
        raise ToolError(f"JSON file is too large: {path}")
    with path.open() as stream:
        return json.load(stream)


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    private(path.parent)
    fd, temporary = tempfile.mkstemp(prefix=".writing-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2, ensure_ascii=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextlib.contextmanager
def lock(name):
    with (state_dir() / f"{checked_id(name)}.lock").open("a") as stream:
        os.chmod(stream.name, 0o600)
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def mapping_path(identifier):
    return state_dir() / "mappings" / f"{checked_id(identifier)}.json"


def validate_mapping(record):
    if not isinstance(record, dict) or record.get("schema_version") != 1:
        raise ToolError("Unsupported mapping schema")
    checked_id(record["id"])
    argv = record.get("argv")
    if not isinstance(argv, list) or not argv or len(argv) > 256:
        raise ToolError("Expected a nonempty command argument array")
    if any(not isinstance(v, str) or "\0" in v for v in argv) or sum(map(len, argv)) > 65536:
        raise ToolError("Invalid command arguments")
    env = record.get("env")
    if not isinstance(env, dict):
        raise ToolError("Invalid launch environment")
    for key, value in env.items():
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) or not isinstance(value, str) or "\0" in value:
            raise ToolError("Invalid launch environment")
        if key.startswith("HERDR_") and key != "HERDR_AGENT":
            raise ToolError("Herdr caller context cannot be saved as launch environment")
    if env.get("HERDR_AGENT") not in (None, "claude", "codex"):
        raise ToolError("Unsupported agent hint")
    if not isinstance(record.get("cwd"), str) or not Path(record["cwd"]).is_absolute():
        raise ToolError("Mapping cwd must be absolute")
    if record.get("kind") not in ("local", "ssh", "vm-tmux"):
        raise ToolError("Invalid launch kind")
    if record["kind"] == "vm-tmux":
        target = record.get("vm")
        if not isinstance(target, dict) or target.get("operation") not in ("attach", "new"):
            raise ToolError("Invalid saved VM target")
        checked_id(target["profile"])
        if not isinstance(target.get("timeout"), int) or not 1 <= target["timeout"] <= 600:
            raise ToolError("Invalid saved VM timeout")
    return record


class Herdr:
    def __init__(self, session=None):
        root = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "herdr"
        config_path = os.environ.get("HERDR_CONFIG_PATH")
        if config_path:
            root = Path(config_path).expanduser().parent
        if session is None and os.environ.get("HERDR_SOCKET_PATH"):
            self.path = Path(os.environ["HERDR_SOCKET_PATH"])
        else:
            session = session or os.environ.get("HERDR_SESSION", "default")
            checked_id(session)
            self.path = root / "herdr.sock" if session == "default" else root / "sessions" / session / "herdr.sock"

    def instance(self):
        info = self.path.stat()
        return f"{self.path.resolve()}:{info.st_ino}:{info.st_ctime_ns}"

    def call(self, method, **params):
        identifier = uuid.uuid4().hex
        payload = json.dumps({"id": identifier, "method": method, "params": params}).encode() + b"\n"
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(15)
            connection.connect(str(self.path))
            connection.sendall(payload)
            with connection.makefile("rb") as stream:
                line = stream.readline(8 * 1024 * 1024 + 1)
        if len(line) > 8 * 1024 * 1024 or not line.endswith(b"\n"):
            raise ToolError("Incomplete or oversized Herdr response")
        response = json.loads(line)
        if response.get("id") != identifier:
            raise ToolError("Herdr response ID mismatch")
        if "error" in response:
            raise ToolError(f"{method}: {response['error'].get('message', response['error'])}")
        return response["result"]

    def current(self):
        pane = os.environ.get("HERDR_PANE_ID")
        if not pane or os.environ.get("HERDR_ENV") != "1":
            raise ToolError("Run herdr-run inside a Herdr pane")
        return self.call("pane.current", caller_pane_id=pane)["pane"]

    def bind(self, identifier):
        pane = self.current()
        self.call("pane.report_metadata", pane_id=pane["pane_id"], source="herdr-run",
                  tokens={"herdr_mapping": identifier})
        return pane


def entry(main):
    try:
        return main()
    except KeyboardInterrupt:
        return 130
    except (ToolError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"ERROR: {error}", file=__import__("sys").stderr)
        return 1
