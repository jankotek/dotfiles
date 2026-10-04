#!/usr/bin/env python3
"""Bats virsh/SSH fixture: records literal remote argv and agent environment."""

import json
import os
from pathlib import Path
import shlex
import sys

root = Path(os.environ["TRANSPORT_FIXTURE"])
name = Path(sys.argv[0]).name
argv = sys.argv[1:]
with (root / "transport.jsonl").open("a") as output:
    output.write(json.dumps({"tool": name, "argv": argv, "remote": shlex.split(argv[-1]) if name == "ssh" else [],
                             "agent": os.environ.get("HERDR_AGENT")}) + "\n")
if name == "virsh":
    assert argv[:2] == ["-c", "qemu:///session"]
    state_path = root / "vm-state"
    state = state_path.read_text().strip()
    if argv[2] == "domstate":
        print("shut off" if state == "saved" else state)
    elif argv[2] == "dominfo":
        print("Managed save: " + ("yes" if state == "saved" else "no"))
    elif argv[2] in ("start", "resume"):
        state_path.write_text("running")
    else:
        sys.exit(1)
elif name == "ssh":
    if (root / "ssh-fail").exists():
        print("Host key verification failed", file=sys.stderr)
        sys.exit(255)
    remote = shlex.split(argv[-1])
    if "has-session" in remote and (root / "missing-session").exists():
        sys.exit(1)
    if "new-session" in remote and (root / "existing-session").exists():
        print("duplicate session", file=sys.stderr)
        sys.exit(1)
