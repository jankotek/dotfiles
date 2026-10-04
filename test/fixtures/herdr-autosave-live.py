#!/usr/bin/env python3
"""Real event-driven autosaving, including an existing-pane VM mapping."""

import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

from herdr_tools.autosave import default_path
from herdr_tools.common import Herdr, atomic_json, config_dir, read_json
from herdr_tools.layout import leaves


def eventually(check):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            if check():
                return
        except (FileNotFoundError, ConnectionRefusedError, StopIteration):
            pass
        time.sleep(.1)
    raise AssertionError("Timed out waiting for autosave")


def main():
    repo = Path(os.environ["OPT_JAN"])
    binary = os.environ.get("HERDR_TEST_BINARY", "herdr")
    with tempfile.TemporaryDirectory(prefix="herdr-autosave-") as temporary:
        root = Path(temporary)
        os.environ.update(XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"))
        for name in ("HERDR_SOCKET_PATH", "HERDR_CONFIG_PATH", "HERDR_SESSION", "HERDR_LAYOUT_AUTOSAVE"):
            os.environ.pop(name, None)
        api = Herdr("autosave-test")
        processes = []
        with (root / "test.log").open("w") as log:
            try:
                server = subprocess.Popen([binary, "server", "--session", "autosave-test"], stdout=log, stderr=log)
                processes.append(server)
                eventually(lambda: api.path.exists() and api.call("ping"))
                workspace = api.call("workspace.create", label="Autosave", cwd=str(root))["workspace"]["workspace_id"]
                # Merely registering this wrapper must start the default watcher.
                key = root / "key"
                key.write_text("unused test identity")
                key.chmod(0o600)
                hosts = root / "known_hosts"
                hosts.write_text("")
                hosts.chmod(0o600)
                atomic_json(config_dir() / "vms/dev.json", {
                    "schema_version": 1, "domain_uuid": str(uuid.uuid4()), "libvirt_uri": "qemu:///session",
                    "ssh_host": "127.0.0.1", "ssh_port": 22, "ssh_user": "worker", "ssh_host_key_alias": "test",
                    "ssh_identity_file": str(key), "ssh_known_hosts_file": str(hosts), "tmux_session": "main"})
                pane = next(p for p in api.call("session.snapshot")["snapshot"]["panes"] if p["workspace_id"] == workspace)
                command = [str(repo / "usr/bin/herdr-run"), "--agent", "codex", "vm-tmux", "attach", "dev", "--menu-first"]
                import shlex
                api.call("pane.send_text", pane_id=pane["pane_id"], text=shlex.join(command) + "\n")
                path = default_path(api)
                eventually(lambda: path.exists() and len(read_json(path)["mappings"]) == 1)
                saved = read_json(path)
                mapping = next(iter(saved["mappings"].values()))
                assert mapping["vm"]["operation"] == "attach" and mapping["env"]["HERDR_AGENT"] == "codex"
                count = sum(len(w["tabs"]) for w in saved["workspaces"])
                tab = api.call("tab.create", workspace_id=workspace, label="Automatically saved")["tab"]["tab_id"]
                eventually(lambda: sum(len(w["tabs"]) for w in read_json(path)["workspaces"]) == count + 1)
                assert path.with_name(path.name + ".previous").exists()
                description = api.call("layout.apply", tab_id=tab, tab_label="Split", root={
                    "type": "split", "direction": "right", "ratio": .4,
                    "first": {"type": "pane", "label": "Left"}, "second": {"type": "pane", "label": "Right"}})["layout"]
                def saved_tab():
                    return next(t for w in read_json(path)["workspaces"] for t in w["tabs"] if t["source_tab"] == description["tab_id"])
                eventually(lambda: len(list(leaves(saved_tab()["root"]))) == 2)
                api.call("tab.close", tab_id=description["tab_id"])
                eventually(lambda: sum(len(w["tabs"]) for w in read_json(path)["workspaces"]) == count)
                # Same destination watcher is a no-op; idle snapshots don't rotate.
                duplicate = subprocess.run([str(repo / "usr/bin/herdr-layout"), "--session", "autosave-test", "autosave"],
                                           timeout=10, capture_output=True)
                assert duplicate.returncode == 0, duplicate.stderr
                generation = read_json(path)["generation"]
                time.sleep(1)
                assert read_json(path)["generation"] == generation
                api.call("server.stop")
                server.wait(timeout=10)
                time.sleep(.5)
                assert read_json(path)["generation"] == generation
                print("PASS: wrapper starts autosave; VM mapping/env, new tab, split and closure saved; unchanged layout and shutdown preserved")
            finally:
                try:
                    api.call("server.stop")
                except OSError:
                    pass
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=10)
                if __import__("sys").exc_info()[0]:
                    print((root / "test.log").read_text()[-2000:])
                    for autosave_log in (root / "state/herdr-layout").glob("autosave-*.log"):
                        print(autosave_log.read_text()[-2000:])


if __name__ == "__main__":
    main()
