#!/usr/bin/env python3
"""Failure-path regressions with isolated real shells and stubbed public APIs."""

import copy
import io
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from herdr_tools import layout, runner, vm
from herdr_tools.common import ToolError, atomic_json, mapping_path, read_json


def eventually(check):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(.01)
    raise AssertionError("Timed out waiting for test shell")


class ShellAPI:
    def __init__(self, root):
        self.path = root / "herdr.sock"
        self.path.touch(mode=0o600)
        self.identity = "old"
        self.shells = [subprocess.Popen(["bash", "--noprofile", "--norc"], stdin=subprocess.PIPE,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       cwd=root, text=True, start_new_session=True) for _ in range(2)]
        self.state = {"version": "fixture", "protocol": 19, "focused_workspace_id": "w1",
                      "workspaces": [{"workspace_id": "w1", "label": "Tools", "number": 1, "active_tab_id": "w1:t1"}],
                      "tabs": [], "panes": []}
        self.descriptions, self.pids, self.applies = {}, {}, []
        for index, shell in enumerate(self.shells, 1):
            tab, pane = f"w1:t{index}", f"w1:p{index}"
            self.state["tabs"].append({"tab_id": tab, "workspace_id": "w1", "number": index, "label": str(index)})
            self.state["panes"].append({"pane_id": pane, "tab_id": tab, "tokens": {}})
            self.descriptions[tab] = {"tab_id": tab, "workspace_id": "w1", "focused_pane_id": pane,
                                      "zoomed": False, "root": {"type": "pane", "pane_id": pane, "label": None}}
            self.pids[pane] = shell.pid
        eventually(lambda: all(Path(f"/proc/{p.pid}/comm").read_text().strip() == "bash" for p in self.shells))

    def instance(self):
        return f"{self.path.resolve()}:1:{self.identity}"

    def current(self):
        return self.state["panes"][0]

    def bind(self, identifier):
        self.current()["tokens"]["herdr_mapping"] = identifier

    def call(self, method, **params):
        if method == "session.snapshot":
            return {"snapshot": copy.deepcopy(self.state)}
        if method == "layout.export":
            return {"layout": copy.deepcopy(self.descriptions[params["tab_id"]])}
        if method == "pane.process_info":
            pid = self.pids[params["pane_id"]]
            pids = [pid, *map(int, Path(f"/proc/{pid}/task/{pid}/children").read_text().split())]
            foreground = [{"pid": p, "name": Path(f"/proc/{p}/comm").read_text().strip()} for p in pids]
            return {"process_info": {"shell_pid": pid, "foreground_processes": foreground}}
        if method == "layout.apply":
            self.applies.append(copy.deepcopy(params))
            old_tab = params["tab_id"]
            old = self.descriptions.pop(old_tab)
            new_tab, new_pane = f"w1:t{len(self.applies)+10}", f"w1:p{len(self.applies)+10}"
            for tab in self.state["tabs"]:
                if tab["tab_id"] == old_tab:
                    tab["tab_id"] = new_tab
            for pane in self.state["panes"]:
                if pane["tab_id"] == old_tab:
                    self.pids[new_pane] = self.pids[pane["pane_id"]]
                    pane.update(tab_id=new_tab, pane_id=new_pane)
            result = {**old, "tab_id": new_tab, "focused_pane_id": new_pane,
                      "root": {**params["root"], "pane_id": new_pane}}
            self.descriptions[new_tab] = result
            return {"layout": copy.deepcopy(result)}
        if method in ("tab.focus", "workspace.focus"):
            return {}
        if method == "pane.report_metadata":
            self.current()["tokens"].pop("herdr_mapping", None)
            return {}
        raise AssertionError(f"Unexpected API call: {method}")

    def close(self):
        for process in self.shells:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
            process.stdin.close()


class Regressions(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="herdr-regression-")
        self.root = Path(self.temporary.name)
        self.environment = patch.dict(os.environ, XDG_STATE_HOME=str(self.root / "state"), XDG_CONFIG_HOME=str(self.root / "config"))
        self.environment.start()
        self.api = ShellAPI(self.root)

    def tearDown(self):
        self.api.close()
        self.environment.stop()
        self.temporary.cleanup()

    def test_interrupted_recovery_rechecks_remaining_tabs(self):
        saved = layout.collect(self.api)
        self.api.identity = "restarted"
        interrupted = False

        def interrupt_after_commit(path, value):
            nonlocal interrupted
            atomic_json(path, value)
            if not interrupted and value.get("status") == "restoring" and len(value.get("tabs", {})) == 1 and value.get("pending") is None:
                interrupted = True
                raise ToolError("Simulated interruption after confirmed tab")

        with patch.object(layout, "atomic_json", side_effect=interrupt_after_commit):
            with self.assertRaisesRegex(ToolError, "Simulated interruption"):
                layout.restore(self.api, saved, recover=True)
        self.assertEqual(len(self.api.applies), 1)
        second = self.api.shells[1]
        second.stdin.write("sleep 300\n")
        second.stdin.flush()
        eventually(lambda: Path(f"/proc/{second.pid}/task/{second.pid}/children").read_text().strip())
        with self.assertRaisesRegex(ToolError, "not an idle shell"):
            layout.restore(self.api, saved, recover=True)
        self.assertEqual(len(self.api.applies), 1, "Retry replaced newly started user work")
        self.assertIsNone(second.poll())

    def test_mapping_conflict_does_not_publish_replacement_plan(self):
        record = {"schema_version": 1, "id": "conflict", "kind": "local", "argv": ["htop"],
                  "cwd": str(self.root), "env": {}}
        atomic_json(mapping_path(record["id"]), record)
        self.api.bind(record["id"])
        saved = layout.collect(self.api)
        self.api.identity = "restarted"
        atomic_json(mapping_path(record["id"]), {**record, "argv": ["mc"]})
        with self.assertRaisesRegex(ToolError, "conflicts"):
            layout.restore(self.api, saved, recover=True)
        self.assertFalse(layout.journal_path(self.api).exists())
        self.assertFalse(self.api.applies)

    def test_command_starting_during_guard_is_preserved(self):
        tab = layout.collect(self.api)["workspaces"][0]["tabs"][0]
        expected = self.api.descriptions[tab["source_tab"]]
        shell = self.api.shells[0]
        original_open = os.pidfd_open

        def start_command(pid):
            shell.stdin.write("exec sleep 300\n")
            shell.stdin.flush()
            eventually(lambda: Path(f"/proc/{pid}/comm").read_text().strip() == "sleep")
            return original_open(pid)

        with patch.object(os, "pidfd_open", side_effect=start_command):
            with self.assertRaisesRegex(ToolError, "not an idle shell"):
                with layout.guard_cold_tab(self.api, tab, expected):
                    self.fail("Guard accepted a newly started command")
        self.assertIsNone(shell.poll())
        self.assertEqual(Path(f"/proc/{shell.pid}/comm").read_text().strip(), "sleep")
        self.assertNotIn("State:\tT", Path(f"/proc/{shell.pid}/status").read_text(), "Guard left user's process stopped")

    def test_ssh_timeout_returns_to_menu_and_creation_is_uncertain(self):
        target = {"operation": "attach", "profile": "dev", "session": "main", "timeout": 1, "menu_first": True}
        profile = {"ssh_port": 12345, "ssh_identity_file": "/key", "ssh_known_hosts_file": "/hosts",
                   "ssh_host_key_alias": "dev", "ssh_user": "worker", "ssh_host": "127.0.0.1"}
        timeout = subprocess.TimeoutExpired("ssh", 15)
        output = io.StringIO()
        with patch.object(vm, "checked_profile", return_value=profile), patch.object(vm, "ensure_running"), patch.object(vm, "wait_endpoint"), \
                patch.object(vm.subprocess, "run", side_effect=timeout) as run, patch("builtins.input", side_effect=["a", "q"]), \
                patch("sys.stdout", output), patch("sys.stderr", output):
            self.assertEqual(vm.execute(target, {}), 0)
            self.assertEqual(run.call_count, 1)
        self.assertIn("SSH command timed out", output.getvalue())
        with patch.object(vm.subprocess, "run", side_effect=timeout) as run:
            with self.assertRaisesRegex(ToolError, "creation outcome is uncertain"):
                vm.ssh_call(profile, ["tmux", "new-session", "-s", "main"], {}, capture=True)
            self.assertEqual(run.call_count, 1)

    def test_save_during_creation_exposes_only_final_attachment(self):
        target = {"profile": "dev", "operation": "new", "session": "main", "timeout": 1,
                  "command": ["nano", "/file"], "cwd": None}
        captures = []

        def creation(target, env, on_created=None, restoring=False):
            captures.append(layout.collect(self.api))
            self.assertFalse(captures[-1]["mappings"])
            self.assertFalse(list((self.root / "state/herdr-layout/mappings").glob("*.json")))
            on_created()
            captures.append(layout.collect(self.api))
            return 0

        with patch.object(runner, "Herdr", return_value=self.api), patch.object(runner, "detect", return_value={}), \
                patch.object(vm, "resolve", return_value=target), patch.object(vm, "execute", side_effect=creation), \
                patch.object(sys, "argv", ["herdr-run", "vm-tmux", "new", "dev", "--", "nano", "/file"]):
            self.assertEqual(runner.main(), 0)
        record = next(iter(captures[1]["mappings"].values()))
        self.assertEqual(record["vm"]["operation"], "attach")
        self.assertEqual(record["vm"]["command"], [])
        self.assertEqual(record["argv"][1], "attach")
        self.assertEqual(record, read_json(mapping_path(record["id"])))

    def test_server_probe_waits_for_api_and_preserves_live_or_inaccessible_servers(self):
        for missing in (FileNotFoundError(), ConnectionRefusedError()):
            with self.subTest(missing=type(missing).__name__), \
                    patch.object(self.api, "call", side_effect=[missing, ConnectionRefusedError(), {}]) as ping, \
                    patch.object(layout.subprocess, "Popen") as start, patch.object(layout.time, "sleep"):
                self.assertTrue(layout.ensure_server(self.api, "test"))
                start.assert_called_once()
                self.assertEqual(ping.call_count, 3)
                self.assertTrue(all(call.args == ("ping",) for call in ping.call_args_list))
        with patch.object(self.api, "call", return_value={}), patch.object(layout.subprocess, "Popen") as start:
            self.assertFalse(layout.ensure_server(self.api, "test"))
            start.assert_not_called()
        for unavailable in (PermissionError(), TimeoutError(), ToolError("Invalid API response")):
            with self.subTest(unavailable=type(unavailable).__name__), \
                    patch.object(self.api, "call", side_effect=unavailable), patch.object(layout.subprocess, "Popen") as start:
                with self.assertRaises(type(unavailable)):
                    layout.ensure_server(self.api, "test")
                start.assert_not_called()

    def test_autosave_preserves_generation_and_guards_publication(self):
        path = self.root / "autosave.json"
        instance = self.api.instance()
        self.assertTrue(layout.save(self.api, path, only_changed=True, expected_instance=instance))
        original = path.read_bytes()
        self.assertFalse(layout.save(self.api, path, only_changed=True, expected_instance=instance))
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse(path.with_name(path.name + ".previous").exists())
        self.api.state["tabs"][0]["label"] = "Edited tab"
        atomic_json(layout.journal_path(self.api), {"status": "restoring", "instance": instance})
        with self.assertRaisesRegex(ToolError, "Restore is incomplete"):
            layout.save(self.api, path, only_changed=True, expected_instance=instance)
        self.assertEqual(path.read_bytes(), original)
        atomic_json(layout.journal_path(self.api), {"status": "complete", "instance": instance})
        self.assertTrue(layout.save(self.api, path, only_changed=True, expected_instance=instance))
        self.assertEqual(path.with_name(path.name + ".previous").read_bytes(), original)
        updated = path.read_bytes()
        self.api.identity = "new server"
        with self.assertRaisesRegex(ToolError, "server changed"):
            layout.save(self.api, path, only_changed=True, expected_instance=instance)
        self.assertEqual(path.read_bytes(), updated)


if __name__ == "__main__":
    unittest.main()
