"""Save registered layout changes from the public Herdr event stream."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import time
import uuid

from .common import ToolError, state_dir


EVENTS = (
    "workspace.created", "workspace.renamed", "workspace.moved", "workspace.reordered",
    "workspace.closed", "workspace.focused", "tab.created", "tab.closed", "tab.focused",
    "tab.renamed", "tab.moved", "pane.created", "pane.closed", "pane.updated",
    "pane.focused", "pane.moved", "layout.updated",
)


def default_path(api):
    key = hashlib.sha256(str(api.path).encode()).hexdigest()[:16]
    return state_dir() / f"layout-{key}.json"


def start(api, path=None):
    if os.environ.get("HERDR_LAYOUT_AUTOSAVE") == "0":
        return
    path = (path or default_path(api)).resolve()
    script = Path(__file__).resolve().parents[2] / "bin/herdr-layout"
    # Freeze the caller's socket, rather than infer the currently focused pane.
    env = dict(os.environ, HERDR_SOCKET_PATH=str(api.path))
    key = hashlib.sha256((str(api.path) + str(path)).encode()).hexdigest()[:16]
    log_path = state_dir() / f"autosave-{key}.log"
    fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, "a") as log:
        subprocess.Popen([sys.executable, str(script), "autosave", "--file", str(path)],
                         env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                         start_new_session=True)


def watch(api, path, debounce=.5):
    from .layout import save

    path = path.resolve()
    key = hashlib.sha256((str(api.path) + str(path)).encode()).hexdigest()[:16]
    with (state_dir() / f"autosave-{key}.lock").open("a") as owner:
        os.chmod(owner.name, 0o600)
        try:
            fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return  # One watcher per socket and destination.
        instance = api.instance()
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(15)
            connection.connect(str(api.path))
            request = uuid.uuid4().hex
            connection.sendall(json.dumps({"id": request, "method": "events.subscribe", "params": {
                "subscriptions": [{"type": event} for event in EVENTS]}}).encode() + b"\n")
            buffer = b""
            acknowledged = False
            first_dirty = due = None
            while True:
                if api.instance() != instance:
                    return  # Never capture native shells from a replacement server.
                now = time.monotonic()
                timeout = min(1, max(0, due - now)) if due is not None else 1
                if select.select([connection], [], [], timeout)[0]:
                    block = connection.recv(65536)
                    if not block:
                        return  # Do not capture a partial layout during shutdown.
                    buffer += block
                    if len(buffer) > 8 * 1024 * 1024:
                        raise ToolError("Oversized autosave event response")
                    while b"\n" in buffer:
                        line, buffer = buffer.split(b"\n", 1)
                        message = json.loads(line)
                        if "error" in message:
                            raise ToolError(f"Autosave subscription failed: {message['error']}")
                        if not acknowledged:
                            if message.get("id") != request or message.get("result", {}).get("type") != "subscription_started":
                                raise ToolError("Unexpected autosave subscription response")
                            acknowledged = True
                        # Mapping registration/clearing emits pane.updated.
                        # Terminal output isn't subscribed and cannot cause writes.
                        if first_dirty is None:
                            first_dirty = time.monotonic()
                        due = min(time.monotonic() + debounce, first_dirty + 2)
                if due is not None and time.monotonic() >= due:
                    try:
                        save(api, path, only_changed=True, expected_instance=instance)
                    except ToolError as error:
                        print(f"Autosave deferred: {error}", file=sys.stderr, flush=True)
                        due = time.monotonic() + 1
                    else:
                        first_dirty = due = None
