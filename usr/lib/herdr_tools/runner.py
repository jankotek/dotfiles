"""Register explicit pane launch intent; detection remains a Bash script."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import uuid

from .common import (Herdr, ToolError, atomic_json, config_dir, mapping_path,
                     private, read_json, validate_mapping)


def detect(argv):
    custom = config_dir() / "agent-env"
    script = custom if custom.exists() else Path(__file__).resolve().parents[2] / "share/herdr-layout/agent-env"
    if custom.exists():
        private(custom)
    result = subprocess.run(["bash", str(script), *argv], capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise ToolError(f"Agent environment script failed: {result.stderr.strip()}")
    lines = result.stdout.splitlines()
    if not lines:
        return {}
    if len(lines) != 1 or lines[0] not in ("HERDR_AGENT=claude", "HERDR_AGENT=codex"):
        raise ToolError("agent-env must output nothing or one HERDR_AGENT=claude|codex assignment")
    return dict([lines[0].split("=", 1)])


def launch(record, api, restoring=False):
    validate_mapping(record)
    if not Path(record["cwd"]).is_dir():
        return placeholder(f"Working directory unavailable: {record['cwd']}")
    creating = record["kind"] == "vm-tmux" and record["vm"]["operation"] == "new" and not restoring
    if not creating:
        api.bind(record["id"])
        if not restoring:
            from .autosave import start
            start(api)
    env = dict(os.environ)
    env.pop("HERDR_AGENT", None)
    env.update(record["env"])
    try:
        if record["kind"] == "vm-tmux":
            from .vm import run_mapping
            def created():
                api.bind(record["id"])
                from .autosave import start
                start(api)
            return run_mapping(record, env, restoring=restoring,
                               on_created=created if creating else None)
        result = subprocess.run(record["argv"], cwd=record["cwd"], env=env)
        return result.returncode if result.returncode >= 0 else 128 - result.returncode
    except (ToolError, OSError) as error:
        if restoring:
            return placeholder(str(error))
        raise
    finally:
        # Resolve inherited caller identity again; a live pane may have moved.
        try:
            pane = api.current()
            if pane.get("tokens", {}).get("herdr_mapping") == record["id"]:
                api.call("pane.report_metadata", pane_id=pane["pane_id"], source="herdr-run",
                         tokens={"herdr_mapping": None})
        except (ToolError, OSError):
            pass  # Pane closure/server shutdown must not kill the guest workload.


def placeholder(message):
    print(f"Unavailable: {message}")
    try:
        input("Press Enter to close this placeholder. ")
    except EOFError:
        pass
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent", choices=["claude", "codex", "none"])
    parser.add_argument("--env", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--restore-mapping", help=argparse.SUPPRESS)
    parser.add_argument("--placeholder", help=argparse.SUPPRESS)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.placeholder:
        return placeholder(args.placeholder)
    api = Herdr()
    api.current()  # Never fall back to the UI-focused pane.
    if args.restore_mapping:
        return launch(read_json(mapping_path(args.restore_mapping)), api, restoring=True)
    argv = args.command
    if argv and argv[0] == "--":
        argv = argv[1:]
    if not argv:
        parser.error("a command is required")
    explicit = {}
    for assignment in args.env:
        if "=" not in assignment:
            parser.error("--env requires NAME=VALUE")
        key, value = assignment.split("=", 1)
        if key in explicit:
            parser.error("duplicate --env name")
        explicit[key] = value
    if args.agent and "HERDR_AGENT" in explicit and explicit["HERDR_AGENT"] != args.agent:
        parser.error("--agent and explicit HERDR_AGENT disagree")
    kind = Path(argv[0]).name
    kind = kind if kind in ("ssh", "vm-tmux") else "local"
    record = {"schema_version": 1, "id": uuid.uuid4().hex, "argv": argv,
              "cwd": os.getcwd(), "env": {}, "kind": kind}
    if kind == "vm-tmux":
        from .vm import parse_args, resolve
        vm_args = parse_args(argv[1:])
        record["vm"] = resolve(vm_args)
    validate_mapping(record)
    env = {} if args.agent or "HERDR_AGENT" in explicit else detect(argv)
    if not env.get("HERDR_AGENT") and kind == "vm-tmux" and record["vm"].get("agent"):
        env["HERDR_AGENT"] = record["vm"]["agent"]
    env.update(explicit)
    if args.agent == "none":
        env.pop("HERDR_AGENT", None)
    elif args.agent:
        env["HERDR_AGENT"] = args.agent
    record["agent"] = args.agent or env.get("HERDR_AGENT", "none")
    record["env"] = env
    validate_mapping(record)
    # Creation intent stays private in memory until an immutable attachment
    # record can be published. Saving during boot must never capture `new`.
    if kind != "vm-tmux" or record["vm"]["operation"] != "new":
        atomic_json(mapping_path(record["id"]), record)
    return launch(record, api)


if __name__ == "__main__":
    sys.exit(main())
