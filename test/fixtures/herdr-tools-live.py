#!/usr/bin/env python3
"""Real headless Herdr round trip; only isolated test sessions are controlled."""

import os
import fcntl
from pathlib import Path
import pty
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

from herdr_tools.common import Herdr, read_json
from herdr_tools.layout import collect, leaves, restore, save


def eventually(check, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.1)
    raise AssertionError("Timed out waiting for live Herdr state")


def normalized(saved):
    def tree(node):
        if node["type"] == "pane":
            return (node.get("label"), node.get("mapping"))
        return (node["direction"], round(node["ratio"], 4), tree(node["first"]), tree(node["second"]))
    result = []
    for ws in saved["workspaces"]:
        tabs = []
        for tab in ws["tabs"]:
            focused = next(i for i, leaf in enumerate(leaves(tab["root"])) if leaf["source_pane"] == tab["focused_pane"])
            tabs.append((tab["label"], tree(tab["root"]), focused, tab["zoomed"]))
        result.append((ws["label"], tabs, next(i for i, tab in enumerate(ws["tabs"]) if tab["source_tab"] == ws["active_tab"])))
    return result


def main():
    binary = os.environ.get("HERDR_TEST_BINARY", "herdr")
    repo = Path(os.environ["OPT_JAN"])
    commands = [shutil.which(name) for name in ("htop", "mc", "nano")]
    assert all(commands), "htop, mc and nano are required for the manual demo"
    with tempfile.TemporaryDirectory(prefix="herdr-layout-live-") as directory:
        root = Path(directory)
        os.environ.update(XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"))
        for key in ("HERDR_CONFIG_PATH", "HERDR_SOCKET_PATH", "HERDR_SESSION", "HERDR_ENV", "HERDR_PANE_ID", "HERDR_AGENT"):
            os.environ.pop(key, None)
        # External replay is the restore owner; native agent resume stays off.
        (root / "config/herdr").mkdir(parents=True)
        (root / "config/herdr/config.toml").write_text("[session]\nresume_agents_on_restore = false\n[update]\nversion_check = false\nmanifest_check = false\n")
        (root / "notes with spaces.txt").write_text("Herdr recovery test\n")
        processes, logs, apis = [], [], []
        try:
            for name in ("source", "recovered"):
                log = (root / f"{name}.log").open("w")
                logs.append(log)
                processes.append(subprocess.Popen([binary, "server", "--session", name], env=dict(os.environ), stdout=log, stderr=log))
                api = Herdr(name)
                apis.append(api)
                eventually(lambda: api.path.exists())
                api.call("ping")
            source, recovered = apis
            workspace = source.call("workspace.create", label="Recovery demo", cwd=str(root))["workspace"]
            ws = workspace["workspace_id"]
            original = source.call("session.snapshot")["snapshot"]
            starter = next(t["tab_id"] for t in original["tabs"] if t["workspace_id"] == ws)
            runner = str(repo / "usr/bin/herdr-run")

            def pane(label, argv):
                return {"type": "pane", "label": label, "cwd": str(root), "command": [runner, *argv]}
            hint = ["--agent", "codex", sys.executable, "-u", "-c", "import os,time; print('saved hint:',os.environ.get('HERDR_AGENT')); time.sleep(3600)"]
            layout = source.call("layout.apply", tab_id=starter, tab_label="Tools", root={
                "type": "split", "direction": "right", "ratio": 0.6,
                "first": {"type": "split", "direction": "down", "ratio": 0.4,
                          "first": pane("Monitor", [commands[0]]), "second": pane("Files", [commands[1]])},
                "second": {"type": "split", "direction": "down", "ratio": 0.7,
                           "first": pane("Notes", [commands[2], str(root / "notes with spaces.txt")]),
                           "second": pane("Remote hint demo", hint)},
            })["layout"]
            eventually(lambda: len([p for p in source.call("session.snapshot")["snapshot"]["panes"] if p.get("tokens", {}).get("herdr_mapping")]) == 4)
            eventually(lambda: any("codex" in (p.get("agent") or "").lower() for p in source.call("session.snapshot")["snapshot"]["panes"]))
            ids = [leaf["pane_id"] for leaf in leaves(layout["root"])]
            source.call("pane.swap", source_pane_id=ids[0], target_pane_id=ids[2])
            source.call("pane.move", pane_id=ids[1], destination={"type": "new_workspace", "label": "Moved files", "tab_label": "Browser"}, focus=False)
            source.call("pane.rename", pane_id=ids[2], label="Edited title")
            current = source.call("layout.export", tab_id=layout["tab_id"])["layout"]
            focus = list(leaves(current["root"]))[0]["pane_id"]
            source.call("pane.zoom", pane_id=focus, mode="on")
            # A newly opened then closed tab must not be resurrected.
            disposable = source.call("tab.create", workspace_id=ws, label="Closed tab")["tab"]["tab_id"]
            source.call("tab.close", tab_id=disposable)
            saved_path = root / "saved.json"
            save(source, saved_path)
            before = read_json(saved_path)
            assert len(before["mappings"]) == 4
            assert any(r["env"].get("HERDR_AGENT") == "codex" for r in before["mappings"].values())

            def running_programs(api=recovered):
                panes = api.call("session.snapshot")["snapshot"]["panes"]
                names = {process["name"] for pane in panes for process in
                         api.call("pane.process_info", pane_id=pane["pane_id"])["process_info"].get("foreground_processes", [])}
                return {"htop", "mc", "nano"} <= names

            def recover_idle(api, saved):
                try:
                    restore(api, saved, recover=True)
                    return True
                except ToolError as error:
                    if "not an idle shell" not in str(error):
                        raise
                    return False

            # Normal first-use workflow must recover its own capture without a
            # prior external replay journal.
            from herdr_tools.common import ToolError
            source.call("server.stop")
            processes[0].wait(timeout=10)
            eventually(lambda: not source.path.exists())
            source_process = subprocess.Popen([binary, "server", "--session", "source"],
                                              env=dict(os.environ), stdout=logs[0], stderr=logs[0])
            processes.append(source_process)
            eventually(lambda: source.path.exists())
            eventually(lambda: recover_idle(source, before))
            eventually(lambda: running_programs(source))
            assert normalized(before) == normalized(collect(source))
            restore(recovered, before)
            eventually(lambda: len([p for p in recovered.call("session.snapshot")["snapshot"]["panes"] if p.get("tokens", {}).get("herdr_mapping")]) == 4)
            eventually(lambda: any("codex" in (p.get("agent") or "").lower() for p in recovered.call("session.snapshot")["snapshot"]["panes"]))
            after = collect(recovered)
            assert normalized(before) == normalized(after), (normalized(before), normalized(after))
            assert before["mappings"] == after["mappings"]
            restore(recovered, before)
            assert len(recovered.call("session.snapshot")["snapshot"]["panes"]) == 4

            eventually(running_programs)
            # Publishing a new generation after replay must also remain usable.
            save(recovered, saved_path)
            before = read_json(saved_path)
            recovered.call("server.stop")
            processes[1].wait(timeout=10)
            eventually(lambda: not recovered.path.exists())
            recovered_process = subprocess.Popen([binary, "server", "--session", "recovered"],
                                                 env=dict(os.environ), stdout=logs[1], stderr=logs[1])
            processes.append(recovered_process)
            eventually(lambda: recovered.path.exists())
            # A bare Herdr restart restores topology but loses wrapper processes.
            assert not running_programs()
            native_count = len(recovered.call("session.snapshot")["snapshot"]["panes"])
            # Do not replace a shell where the user has started another command.
            idle = recovered.call("session.snapshot")["snapshot"]["panes"][0]["pane_id"]
            recovered.call("pane.send_text", pane_id=idle, text="sleep 300\n")
            eventually(lambda: any(p["name"] == "sleep" for p in recovered.call("pane.process_info", pane_id=idle)["process_info"].get("foreground_processes", [])))
            try:
                restore(recovered, before, recover=True)
            except ToolError as error:
                assert "not an idle shell" in str(error), error
            else:
                raise AssertionError("Cold recovery replaced a running command")
            recovered.call("pane.send_keys", pane_id=idle, keys=["ctrl+c"])
            eventually(lambda: all(p["name"] != "sleep" for p in recovered.call("pane.process_info", pane_id=idle)["process_info"].get("foreground_processes", [])))
            eventually(lambda: recover_idle(recovered, before))
            eventually(running_programs)
            eventually(lambda: len(collect(recovered)["mappings"]) == 4)
            assert native_count == len(recovered.call("session.snapshot")["snapshot"]["panes"])
            assert normalized(before) == normalized(collect(recovered))
            # Herdr checkpoints native IDs on shutdown. Start from that known
            # checkpoint, then crash without intervening topology changes.
            recovered.call("server.stop")
            recovered_process.wait(timeout=10)
            eventually(lambda: not recovered.path.exists())
            recovered_process = subprocess.Popen([binary, "server", "--session", "recovered"],
                                                 env=dict(os.environ), stdout=logs[1], stderr=logs[1])
            processes.append(recovered_process)
            eventually(lambda: recovered.path.exists())
            recovered.call("ping")
            # A crashed server leaves a stale socket that open must probe.
            recovered_process.kill()
            recovered_process.wait(timeout=10)
            assert recovered.path.exists(), "Crash did not leave a stale socket"
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
            launch_env = dict(os.environ, TERM="xterm-256color", HERDR_BIN_PATH=shutil.which(binary))
            def controlling_terminal():
                os.setsid()
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)
            client = subprocess.Popen([str(repo / "usr/bin/herdr-layout"), "--session", "recovered", "open", "--file", str(saved_path)],
                                      env=launch_env, stdin=slave, stdout=slave, stderr=slave, preexec_fn=controlling_terminal)
            processes.append(client)
            os.close(slave)
            output = bytearray()
            def drain_terminal():
                try:
                    while block := os.read(master, 65536):
                        output.extend(block)
                except OSError:
                    pass
            reader = threading.Thread(target=drain_terminal, daemon=True)
            reader.start()
            try:
                def responsive():
                    try:
                        recovered.call("ping")
                        return True
                    except (FileNotFoundError, ConnectionRefusedError):
                        return False
                eventually(responsive)
                try:
                    eventually(running_programs)
                except AssertionError as error:
                    raise AssertionError(output.decode(errors="replace")) from error
                assert client.poll() is None, "open launcher failed to attach the UI: " + output.decode(errors="replace")
                assert normalized(before) == normalized(collect(recovered))
                recovered.call("server.stop")
                client.wait(timeout=10)
            finally:
                os.close(master)
                reader.join(timeout=1)
            print("PASS: original save/restart/recover and new generation after replay; htop/mc/nano processes across cold restart/crashed-server open; idle-shell guards, topology, focus/zoom and saved hint")
        finally:
            for api in apis:
                try:
                    api.call("server.stop")
                except (OSError, RuntimeError):
                    pass
            for process in processes:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=5)
            for log in logs:
                log.close()
            if sys.exc_info()[0]:
                for path in root.glob("*.log"):
                    print(path.read_text()[-3000:], file=sys.stderr)


if __name__ == "__main__":
    main()
