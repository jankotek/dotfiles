#!/usr/bin/env python3
"""Offline public-API fixture and TCP readiness listener for Bats."""

import json
from pathlib import Path
import socket
import sys
import threading

root = Path(sys.argv[1])
socket_path = root / "herdr.sock"
state = {
    "version": "fixture", "protocol": 19,
    "focused_workspace_id": "w1", "focused_tab_id": "w1:t1", "focused_pane_id": "w1:p1",
    "workspaces": [{"workspace_id": "w1", "number": 1, "label": "Source", "active_tab_id": "w1:t1", "tokens": {}}],
    "tabs": [{"tab_id": "w1:t1", "workspace_id": "w1", "number": 1, "label": "Tools"}],
    "panes": [{"pane_id": "w1:p1", "workspace_id": "w1", "tab_id": "w1:t1", "tokens": {}}],
    "layouts": [], "agents": [],
}
layouts = {"w1:t1": {"workspace_id": "w1", "tab_id": "w1:t1", "focused_pane_id": "w1:p1", "zoomed": False,
                       "root": {"type": "pane", "pane_id": "w1:p1", "label": "A hostile label $(touch forbidden)",
                                "command": ["sh", "-c", "touch forbidden"], "env": {"SECRET": "never-save"}}}}
serial = 1


def persist():
    (root / "live.json").write_text(json.dumps({"snapshot": state, "layouts": layouts}))


def call(method, p):
    global serial
    if (root / "fail").exists() and method == (root / "fail").read_text().strip():
        raise ValueError("injected API failure")
    if method == "session.snapshot":
        return {"type": "session_snapshot", "snapshot": state}
    if method == "pane.current":
        return {"pane": next(pane for pane in state["panes"] if pane["pane_id"] == p["caller_pane_id"])}
    if method == "pane.report_metadata":
        pane = next(pane for pane in state["panes"] if pane["pane_id"] == p["pane_id"])
        for key, value in p.get("tokens", {}).items():
            if value is None:
                pane["tokens"].pop(key, None)
            else:
                pane["tokens"][key] = value
        return {"type": "ok"}
    if method == "layout.export":
        return {"layout": layouts[p["tab_id"]]}
    if method == "workspace.create":
        serial += 1
        ws, tab, pane = f"w{serial}", f"w{serial}:t1", f"w{serial}:p1"
        workspace = {"workspace_id": ws, "number": serial, "label": p["label"], "active_tab_id": tab, "tokens": {}}
        tab_record = {"tab_id": tab, "workspace_id": ws, "number": 1, "label": "Starter"}
        pane_record = {"pane_id": pane, "workspace_id": ws, "tab_id": tab, "tokens": {}}
        state["workspaces"].append(workspace)
        state["tabs"].append(tab_record)
        state["panes"].append(pane_record)
        return {"workspace": workspace, "tab": tab_record, "root_pane": pane_record}
    if method == "layout.apply":
        if "tab_id" in p:
            old = next(tab for tab in state["tabs"] if tab["tab_id"] == p["tab_id"])
            ws = old["workspace_id"]
            state["tabs"].remove(old)
            state["panes"] = [pane for pane in state["panes"] if pane["tab_id"] != old["tab_id"]]
        else:
            ws = p["workspace_id"]
        serial += 1
        tab = f"{ws}:t{serial}"
        counter = 0

        def node(tree):
            nonlocal counter
            tree = dict(tree)
            if tree["type"] == "split":
                tree["first"], tree["second"] = node(tree["first"]), node(tree["second"])
            else:
                counter += 1
                tree["pane_id"] = f"{ws}:p{serial}-{counter}"
                state["panes"].append({"pane_id": tree["pane_id"], "workspace_id": ws, "tab_id": tab, "tokens": {}})
            return tree
        tree = node(p["root"])
        first = tree
        while first["type"] == "split":
            first = first["first"]
        result = {"workspace_id": ws, "tab_id": tab, "root": tree, "zoomed": False, "focused_pane_id": first["pane_id"]}
        layouts[tab] = result
        state["tabs"].append({"tab_id": tab, "workspace_id": ws, "number": serial, "label": p["tab_label"]})
        return {"layout": result}
    if method == "tab.focus":
        tab = next(tab for tab in state["tabs"] if tab["tab_id"] == p["tab_id"])
        workspace = next(ws for ws in state["workspaces"] if ws["workspace_id"] == tab["workspace_id"])
        workspace["active_tab_id"] = tab["tab_id"]
        return {"type": "ok"}
    if method == "workspace.focus":
        state["focused_workspace_id"] = p["workspace_id"]
        return {"type": "ok"}
    if method == "fixture.bind":
        state["panes"][0]["tokens"]["herdr_mapping"] = p["id"]
        return {"type": "ok"}
    if method == "fixture.empty":
        state.update(workspaces=[], tabs=[], panes=[])
        return {"type": "ok"}
    raise ValueError(f"Unexpected method {method}")


def tcp_listener():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        (root / "port").write_text(str(listener.getsockname()[1]))
        while True:
            connection, _ = listener.accept()
            connection.close()


threading.Thread(target=tcp_listener, daemon=True).start()
with socket.socket(socket.AF_UNIX) as listener:
    listener.bind(str(socket_path))
    listener.listen()
    (root / "ready").touch()
    persist()
    while True:
        connection, _ = listener.accept()
        with connection, connection.makefile("rb") as stream:
            request = json.loads(stream.readline())
            with (root / "requests.jsonl").open("a") as output:
                output.write(json.dumps(request) + "\n")
            try:
                result = call(request["method"], request["params"])
                response = {"id": request["id"], "result": result}
                persist()
            except (ValueError, KeyError, StopIteration) as error:
                response = {"id": request["id"], "error": {"message": str(error)}}
            connection.sendall(json.dumps(response).encode() + b"\n")
