"""Capture live topology, and replay only registered launch commands."""

import argparse
import contextlib
import hashlib
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid

from .common import (Herdr, ToolError, atomic_json, checked_id, lock, mapping_path,
                     read_json, state_dir, validate_mapping)


def leaves(node):
    if node.get("type") == "pane":
        yield node
    elif node.get("type") == "split":
        yield from leaves(node["first"])
        yield from leaves(node["second"])
    else:
        raise ToolError("Invalid layout node")


def validate_tree(node, depth=0):
    if depth > 16:
        raise ToolError("Layout exceeds Herdr's depth limit")
    if node.get("type") == "split":
        if node.get("direction") not in ("right", "down") or not isinstance(node.get("ratio"), (float, int)) or not 0 < node["ratio"] < 1:
            raise ToolError("Invalid layout split")
        validate_tree(node["first"], depth + 1)
        validate_tree(node["second"], depth + 1)
    elif node.get("type") == "pane":
        if node.get("mapping"):
            checked_id(node["mapping"])
        if node.get("label") is not None and not isinstance(node["label"], str):
            raise ToolError("Invalid pane label")
    else:
        raise ToolError("Invalid layout node")
    if depth == 0 and len(list(leaves(node))) > 24:
        raise ToolError("Layout exceeds Herdr's 24-pane limit per tab")


def snapshot(api):
    return api.call("session.snapshot")["snapshot"]


def journal_path(api):
    key = hashlib.sha256(str(api.path).encode()).hexdigest()[:16]
    return state_dir() / f"restore-{key}.json"


def inventory(snap):
    # Ignore terminal output/revisions; include user topology, focus, and mappings.
    return {
        "workspaces": [(w["workspace_id"], w["label"], w["number"], w["active_tab_id"]) for w in snap["workspaces"]],
        "tabs": [(t["tab_id"], t["workspace_id"], t["label"], t["number"]) for t in snap["tabs"]],
        "panes": [(p["pane_id"], p["tab_id"], p.get("tokens", {}).get("herdr_mapping")) for p in snap["panes"]],
        "focus": snap.get("focused_workspace_id"),
    }


def collect(api):
    before = snapshot(api)
    panes = {p["pane_id"]: p for p in before["panes"]}
    mappings = {}
    workspaces = []

    def convert(node):
        if node["type"] == "split":
            return {"type": "split", "direction": node["direction"], "ratio": node["ratio"],
                    "first": convert(node["first"]), "second": convert(node["second"])}
        pane = panes[node["pane_id"]]
        identifier = pane.get("tokens", {}).get("herdr_mapping")
        if identifier:
            path = mapping_path(identifier)
            if path.exists():
                mappings[identifier] = validate_mapping(read_json(path))
        # Never preserve an API-exported foreground command or inherited env.
        return {"type": "pane", "source_pane": node["pane_id"], "mapping": identifier,
                "label": node.get("label") or pane.get("label")}

    exports = {}
    for workspace in sorted(before["workspaces"], key=lambda w: w["number"]):
        tabs = []
        for tab in sorted((t for t in before["tabs"] if t["workspace_id"] == workspace["workspace_id"]), key=lambda t: t["number"]):
            description = api.call("layout.export", tab_id=tab["tab_id"])["layout"]
            root = convert(description["root"])
            validate_tree(root)
            exports[tab["tab_id"]] = description
            tabs.append({"source_tab": tab["tab_id"], "label": tab["label"], "root": root,
                         "focused_pane": description["focused_pane_id"], "zoomed": description["zoomed"]})
        if not tabs:
            raise ToolError("Incomplete capture: a workspace has no tabs")
        workspaces.append({"source_workspace": workspace["workspace_id"], "label": workspace["label"],
                           "active_tab": workspace["active_tab_id"], "tabs": tabs})
    if inventory(before) != inventory(snapshot(api)):
        raise ToolError("Herdr layout changed during capture; retry save")
    for identifier, description in exports.items():
        again = api.call("layout.export", tab_id=identifier)["layout"]
        # Compare tree/focus/zoom independently of incidental exported launch env.
        def shape(node):
            if node["type"] == "pane":
                return (node["pane_id"], node.get("label"))
            return (node["direction"], node["ratio"], shape(node["first"]), shape(node["second"]))
        if (shape(description["root"]), description["focused_pane_id"], description["zoomed"]) != (shape(again["root"]), again["focused_pane_id"], again["zoomed"]):
            raise ToolError("Herdr split/focus changed during capture; retry save")
    return {"schema_version": 1, "generation": uuid.uuid4().hex,
            "herdr_version": before["version"], "herdr_protocol": before["protocol"],
            "source_instance": api.instance(), "focused_workspace": before.get("focused_workspace_id"),
            "workspaces": workspaces, "mappings": mappings}


def validate_capture(saved):
    if not isinstance(saved, dict) or saved.get("schema_version") != 1 or not isinstance(saved.get("workspaces"), list):
        raise ToolError("Unsupported snapshot schema")
    checked_id(saved["generation"])
    if len(saved["workspaces"]) > 128:
        raise ToolError("Snapshot is too large")
    if not isinstance(saved.get("mappings"), dict):
        raise ToolError("Invalid snapshot mappings")
    for identifier, record in saved["mappings"].items():
        if identifier != record["id"]:
            raise ToolError("Mapping identifier mismatch")
        validate_mapping(record)
    for workspace in saved["workspaces"]:
        if not isinstance(workspace["label"], str) or not workspace["tabs"] or len(workspace["tabs"]) > 128:
            raise ToolError("Invalid workspace")
        for tab in workspace["tabs"]:
            if not isinstance(tab["label"], str):
                raise ToolError("Invalid tab label")
            validate_tree(tab["root"])
    return saved


def save(api, path, *, only_changed=False, expected_instance=None):
    with lock("layout"):
        if expected_instance is not None and api.instance() != expected_instance:
            raise ToolError("Herdr server changed; stopping autosave")
        path_to_journal = journal_path(api)
        if path_to_journal.exists():
            journal = read_json(path_to_journal)
            if journal.get("status") != "complete" and journal.get("instance") == api.instance():
                raise ToolError("Restore is incomplete; reconcile it before publishing a snapshot")
        last_error = None
        for _ in range(3):
            try:
                captured = collect(api)
                break
            except ToolError as error:
                last_error = error
        else:
            raise last_error
        validate_capture(captured)
        if expected_instance is not None and api.instance() != expected_instance:
            raise ToolError("Herdr server changed; stopping autosave")
        if path.exists():
            previous = validate_capture(read_json(path))
            if only_changed and {k: v for k, v in previous.items() if k != "generation"} == {k: v for k, v in captured.items() if k != "generation"}:
                return False
            atomic_json(path.with_name(path.name + ".previous"), previous)
        atomic_json(path, captured)
        print(f"Saved {len(captured['workspaces'])} workspace(s), {len(captured['mappings'])} mapping(s) to {path}")
        return True


def launcher():
    return str(Path(__file__).resolve().parents[2] / "bin/herdr-run")


def launch_tree(node, saved):
    if node["type"] == "split":
        return {"type": "split", "direction": node["direction"], "ratio": node["ratio"],
                "first": launch_tree(node["first"], saved), "second": launch_tree(node["second"], saved)}
    identifier = node.get("mapping")
    record = saved["mappings"].get(identifier)
    if record and Path(record["cwd"]).is_dir():
        argv = [launcher(), "--restore-mapping", identifier]
        cwd = record["cwd"]
    else:
        reason = "Unmapped pane" if not identifier else f"Missing mapping or working directory: {identifier}"
        argv = [launcher(), "--placeholder", reason]
        cwd = str(Path.home())
    # Launch the supervisor without HERDR_AGENT; it scopes saved env to its child.
    return {"type": "pane", "label": node.get("label"), "cwd": cwd, "command": argv, "env": {}}


def focus_pane(api, description, pane):
    if description["focused_pane_id"] == pane:
        return
    for source in leaves(description["root"]):
        for direction in ("left", "right", "up", "down"):
            neighbor = api.call("pane.neighbor", pane_id=source["pane_id"], direction=direction)["neighbor"]
            if neighbor.get("neighbor_pane_id") == pane:
                api.call("pane.focus_direction", pane_id=source["pane_id"], direction=direction)
                return
    raise ToolError(f"Herdr could not restore focus to pane {pane}")


def source_manifest(saved):
    """A capture already contains the native identities needed for cold recovery."""
    def native(node):
        if node["type"] == "pane":
            return {"type": "pane", "pane_id": node["source_pane"], "label": node.get("label")}
        return {"type": "split", "direction": node["direction"], "ratio": node["ratio"],
                "first": native(node["first"]), "second": native(node["second"])}
    return {"status": "complete", "generation": saved["generation"],
            "workspaces": {w["source_workspace"]: {"id": w["source_workspace"]} for w in saved["workspaces"]},
            "tabs": {t["source_tab"]: {"tab_id": t["source_tab"], "root": native(t["root"])}
                     for w in saved["workspaces"] for t in w["tabs"]}}


def tree_shape(node):
    if node["type"] == "pane":
        return (node["pane_id"], node.get("label"))
    return (node["direction"], node["ratio"], tree_shape(node["first"]), tree_shape(node["second"]))


def check_cold_tab(api, tab, expected):
    current = api.call("layout.export", tab_id=expected["tab_id"])["layout"]
    live = snapshot(api)
    if (not any(t["tab_id"] == expected["tab_id"] and t["label"] == tab["label"] for t in live["tabs"])
            or tree_shape(current["root"]) != tree_shape(expected["root"])):
        raise ToolError("Cold recovery layout changed; refusing to replace user work")
    return current


def check_cold_workspace(api, workspace, journal):
    live = snapshot(api)
    target = journal["workspaces"][workspace["source_workspace"]]["id"]
    expected_tabs = {journal["tabs"][tab["source_tab"]]["tab_id"] if tab["source_tab"] in journal["tabs"]
                     else journal["native_tabs"][tab["source_tab"]] for tab in workspace["tabs"]}
    if (not any(w["workspace_id"] == target and w["label"] == workspace["label"] for w in live["workspaces"])
            or expected_tabs != {t["tab_id"] for t in live["tabs"] if t["workspace_id"] == target}):
        raise ToolError("Cold recovery workspace/tabs changed; refusing to replace user work")


def idle_shell(api, pane):
    info = api.call("pane.process_info", pane_id=pane["pane_id"])["process_info"]
    foreground = info.get("foreground_processes", [])
    shell_pid = info["shell_pid"]
    children = Path(f"/proc/{shell_pid}/task/{shell_pid}/children")
    if (len(foreground) != 1 or foreground[0]["pid"] != shell_pid
            or foreground[0]["name"] not in ("bash", "zsh", "fish", "sh", "dash")
            or not children.exists() or children.read_text().strip()):
        raise ToolError(f"Pane {pane['pane_id']} is not an idle shell; refusing cold recovery")
    return shell_pid


@contextlib.contextmanager
def guard_cold_tab(api, tab, expected, workspace_check=None):
    """Prevent checked shells from starting a program before their replacement.

    pidfds pin process identities; stopping only these shells never signals a
    process that has replaced them. Always resume surviving shells on failure.
    """
    stopped = []
    try:
        if workspace_check:
            workspace_check()
        current = check_cold_tab(api, tab, expected)
        for pane in leaves(current["root"]):
            pid = idle_shell(api, pane)
            fd = os.pidfd_open(pid)
            stopped.append(fd)
            signal.pidfd_send_signal(fd, signal.SIGSTOP)
            deadline = time.monotonic() + 2
            while True:
                status = Path(f"/proc/{pid}/status").read_text()
                if any(line.startswith("State:") and line.split()[1] == "T" for line in status.splitlines()):
                    break
                if time.monotonic() >= deadline:
                    raise ToolError("Could not guard an idle shell; refusing cold recovery")
                time.sleep(0.01)
            # A command may have started between inspection and SIGSTOP. Check
            # again while the shell cannot exec or fork; leave such work alive.
            idle_shell(api, pane)
        check_cold_tab(api, tab, expected)
        if workspace_check:
            workspace_check()
        yield
    finally:
        for fd in stopped:
            try:
                signal.pidfd_send_signal(fd, signal.SIGCONT)
            except ProcessLookupError:
                pass  # Successful replacement has already closed this shell.
            finally:
                os.close(fd)


def cold_journal(api, saved, previous, instance):
    """Identify only previously replayed tabs whose native restart left idle shells."""
    if previous.get("status") != "complete" or previous.get("generation") != saved["generation"]:
        raise ToolError("Cold recovery requires a completed replay of this generation")
    live = snapshot(api)
    workspaces = {w["workspace_id"]: w for w in live["workspaces"]}
    native_tabs = {}

    for workspace in saved["workspaces"]:
        target = previous["workspaces"][workspace["source_workspace"]]["id"]
        if target not in workspaces or workspaces[target]["label"] != workspace["label"]:
            raise ToolError("Cold recovery workspace differs from the completed replay")
        expected_tabs = {previous["tabs"][tab["source_tab"]]["tab_id"] for tab in workspace["tabs"]}
        if expected_tabs != {t["tab_id"] for t in live["tabs"] if t["workspace_id"] == target}:
            raise ToolError("Cold recovery tabs changed; refusing to replace user work")
        for tab in workspace["tabs"]:
            old = previous["tabs"][tab["source_tab"]]
            tab_id = old["tab_id"]
            current = check_cold_tab(api, tab, old)
            for pane in leaves(current["root"]):
                idle_shell(api, pane)
            native_tabs[tab["source_tab"]] = tab_id
    return {"instance": instance, "generation": saved["generation"], "status": "restoring",
            "pending": None, "workspaces": previous["workspaces"], "native_tabs": native_tabs,
            "native_layouts": previous["tabs"],
            "tabs": {}, "prepared": {}, "finished": {}}


def restore(api, saved, recover=False):
    validate_capture(saved)
    with lock("layout"):
        path_to_journal = journal_path(api)
        instance = api.instance()
        source_socket = saved.get("source_instance", "").rsplit(":", 2)[0]
        own_capture = source_socket == str(api.path.resolve())
        if recover and saved.get("source_instance") == instance:
            print("Snapshot belongs to this live server; leaving user changes intact")
            return
        # Preflight before publishing any retryable replacement plan.
        for identifier, record in saved["mappings"].items():
            path = mapping_path(identifier)
            if path.exists() and read_json(path) != record:
                raise ToolError(f"Saved mapping conflicts with current mapping: {identifier}")
        if path_to_journal.exists():
            journal = read_json(path_to_journal)
            if journal["instance"] == instance:
                if journal["generation"] != saved["generation"]:
                    raise ToolError("A different generation has already been restored here; use a fresh named Herdr session")
                if journal["status"] == "complete":
                    print("This generation is already restored; leaving user changes intact")
                    return
                if journal.get("pending"):
                    raise ToolError("Previous restore ended during a Herdr operation; reconcile the uncertain object before retrying")
            else:
                base = (journal if journal.get("generation") == saved["generation"]
                        else source_manifest(saved) if own_capture else journal)
                journal = cold_journal(api, saved, base, instance) if recover else None
                if journal is not None:
                    atomic_json(path_to_journal, journal)
        else:
            journal = cold_journal(api, saved, source_manifest(saved), instance) if recover and own_capture else None
            if journal is not None:
                atomic_json(path_to_journal, journal)
        if journal is None:
            live = snapshot(api)
            labels = {w["label"] for w in live["workspaces"]}
            if saved.get("source_instance") == instance or any(w["label"] in labels for w in saved["workspaces"]):
                raise ToolError("Original/native-restored workspaces are present; restore into a fresh named session to avoid duplicates")
            journal = {"instance": instance, "generation": saved["generation"], "status": "restoring",
                       "pending": None, "workspaces": {}, "tabs": {}, "prepared": {}, "finished": {}}
            atomic_json(path_to_journal, journal)
        for identifier, record in saved["mappings"].items():
            path = mapping_path(identifier)
            atomic_json(path, record)

        def operation(operation_name, method, **params):
            journal["pending"] = operation_name
            atomic_json(path_to_journal, journal)
            result = api.call(method, **params)
            # Callers commit resulting IDs before clearing pending. If the
            # process dies here, replay is refused instead of duplicating work.
            return result

        def commit():
            journal["pending"] = None
            atomic_json(path_to_journal, journal)

        for workspace in saved["workspaces"]:
            key = workspace["source_workspace"]
            if key not in journal["workspaces"]:
                result = operation(f"create workspace {key}", "workspace.create", label=workspace["label"], cwd=str(Path.home()), focus=False)
                journal["workspaces"][key] = {"id": result["workspace"]["workspace_id"], "starter": result["tab"]["tab_id"]}
                commit()
            target = journal["workspaces"][key]
            for tab in workspace["tabs"]:
                tab_key = tab["source_tab"]
                if tab_key not in journal["tabs"]:
                    params = {"tab_label": tab["label"], "root": launch_tree(tab["root"], saved), "focus": False}
                    # Replace only the starter tab we just created, never user tabs.
                    if tab_key in journal.get("native_tabs", {}):
                        params["tab_id"] = journal["native_tabs"][tab_key]
                    elif tab == workspace["tabs"][0]:
                        params["tab_id"] = target["starter"]
                    else:
                        params["workspace_id"] = target["id"]
                    if tab_key in journal.get("native_tabs", {}):
                        if tab_key not in journal.get("native_layouts", {}):
                            raise ToolError("Old cold recovery journal lacks guards; use a fresh target session")
                        with guard_cold_tab(api, tab, journal["native_layouts"][tab_key],
                                            lambda: check_cold_workspace(api, workspace, journal)):
                            result = operation(f"apply tab {tab_key}", "layout.apply", **params)["layout"]
                    else:
                        result = operation(f"apply tab {tab_key}", "layout.apply", **params)["layout"]
                    journal["tabs"][tab_key] = result
                    commit()
                description = journal["tabs"][tab_key]
                pane_map = {old["source_pane"]: new["pane_id"] for old, new in zip(leaves(tab["root"]), leaves(description["root"]), strict=True)}
                if tab_key not in journal["prepared"]:
                    focus_pane(api, description, pane_map[tab["focused_pane"]])
                    if tab["zoomed"]:
                        operation(f"zoom tab {tab_key}", "pane.zoom", pane_id=pane_map[tab["focused_pane"]], mode="on")
                    journal["prepared"][tab_key] = True
                    commit()
            api.call("tab.focus", tab_id=journal["tabs"][workspace["active_tab"]]["tab_id"])
        focused = saved.get("focused_workspace")
        if focused in journal["workspaces"]:
            api.call("workspace.focus", workspace_id=journal["workspaces"][focused]["id"])
        journal["status"] = "complete"
        atomic_json(path_to_journal, journal)
        print(f"Restored {len(saved['workspaces'])} workspace(s); VM panes are menu-first")


def ensure_server(api, session):
    """Probe the listener; a stale socket pathname is not a live server."""
    try:
        api.call("ping")
        return False
    except (FileNotFoundError, ConnectionRefusedError):
        pass
    binary = os.environ.get("HERDR_BIN_PATH", "herdr")
    subprocess.Popen([binary, "server", "--session", session],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    # Native Herdr owns stale socket cleanup. Never unlink a live listener.
    deadline = time.monotonic() + 15
    while True:
        try:
            api.call("ping")
            return True
        except (FileNotFoundError, ConnectionRefusedError):
            if time.monotonic() >= deadline:
                raise ToolError("Herdr server did not start") from None
            time.sleep(.1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", help="explicit named Herdr session")
    parser.add_argument("operation", choices=["save", "restore", "open", "autosave"])
    parser.add_argument("--recover", action="store_true", help="recover idle shells from a previous completed replay after server restart")
    parser.add_argument("--file", type=Path, help="private snapshot JSON path")
    parser.add_argument("--background", action="store_true", help="run autosave in the background until this server exits")
    args = parser.parse_args()
    api = Herdr(args.session)
    session_key = hashlib.sha256(str(api.path).encode()).hexdigest()[:16]
    path = args.file or state_dir() / f"layout-{session_key}.json"
    if args.background and args.operation != "autosave":
        parser.error("--background requires autosave")
    if args.operation == "autosave":
        from .autosave import start, watch
        if args.background:
            start(api, path)
        else:
            watch(api, path)
    elif args.operation == "open":
        saved = read_json(path)
        starting = ensure_server(api, args.session or os.environ.get("HERDR_SESSION", "default"))
        # Fresh interactive shells can briefly have prompt/startup children.
        # Wait for them only when this launcher started the headless server.
        deadline = time.monotonic() + (5 if starting else 0)
        while True:
            try:
                restore(api, saved, recover=True)
                break
            except ToolError as error:
                if "not an idle shell" not in str(error) or time.monotonic() >= deadline:
                    raise
                time.sleep(0.1)
        from .autosave import start
        start(api, path)
        binary = os.environ.get("HERDR_BIN_PATH", "herdr")
        os.execvp(binary, [binary, "--session", args.session or os.environ.get("HERDR_SESSION", "default")])
    elif args.operation == "save":
        save(api, path)
    else:
        restore(api, read_json(path), recover=args.recover)


if __name__ == "__main__":
    sys.exit(main())
