"""Existing-VM lifecycle and verified SSH transport for guest tmux."""

import argparse
import os
from pathlib import Path
import re
import shlex
import socket
import subprocess
import sys
import time
import uuid

from .common import (ToolError, atomic_json, checked_id, config_dir, lock,
                     mapping_path, private, read_json)


def parse_args(argv):
    parser = argparse.ArgumentParser(prog="vm-tmux", description=__doc__)
    subs = parser.add_subparsers(dest="operation", required=True)
    for operation in ("attach", "new"):
        sub = subs.add_parser(operation)
        sub.add_argument("profile")
        sub.add_argument("--session")
        sub.add_argument("--timeout", type=int, default=120, help="boot/SSH readiness seconds")
        if operation == "attach":
            sub.add_argument("--menu-first", action="store_true")
            sub.add_argument("--reclaim", action="store_true")
        else:
            sub.add_argument("--cwd", default=None, help="absolute guest working directory")
    command = []
    if argv and argv[0] == "new" and "--" in argv:
        separator = argv.index("--")
        command, argv = argv[separator + 1:], argv[:separator]
    args = parser.parse_args(argv)
    args.command = command
    if args.operation == "new" and not command:
        parser.error("new requires -- COMMAND [ARGS...]")
    if not 1 <= args.timeout <= 600:
        parser.error("--timeout must be between 1 and 600 seconds")
    return args


def profile(name):
    path = config_dir() / "vms" / f"{checked_id(name)}.json"
    p = read_json(path)
    if not isinstance(p, dict) or p.get("schema_version") != 1 or p.get("libvirt_uri", "qemu:///session") != "qemu:///session":
        raise ToolError("Only schema 1 profiles using qemu:///session are supported")
    p["domain_uuid"] = str(uuid.UUID(p["domain_uuid"]))
    for key in ("ssh_host", "ssh_user", "ssh_host_key_alias"):
        if not isinstance(p.get(key), str) or not re.fullmatch(r"[A-Za-z0-9_.:@-]+", p[key]) or p[key].startswith("-"):
            raise ToolError(f"Invalid profile {key}")
    if not isinstance(p.get("ssh_port"), int) or not 1 <= p["ssh_port"] <= 65535:
        raise ToolError("Invalid SSH port")
    for key in ("ssh_identity_file", "ssh_known_hosts_file"):
        path = Path(p[key]).expanduser()
        if not path.is_absolute():
            raise ToolError(f"{key} must be absolute")
        private(path)
        p[key] = str(path)
    if p.get("tmux_socket") and (not isinstance(p["tmux_socket"], str) or not p["tmux_socket"].startswith("/") or "\0" in p["tmux_socket"]):
        raise ToolError("tmux_socket must be an absolute guest path")
    if p.get("agent") not in (None, "claude", "codex", "none"):
        raise ToolError("Invalid profile agent")
    return p


def session_name(name):
    # tmux rejects periods/colons; an exact target must not be option-like.
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", name):
        raise ToolError("Session names must contain 1–80 letters, numbers, underscores or hyphens")
    return name


def resolve(args):
    p = profile(args.profile)
    if getattr(args, "cwd", None) and (not args.cwd.startswith("/") or "\0" in args.cwd):
        raise ToolError("--cwd must be an absolute guest path")
    return {"profile": args.profile, "domain_uuid": p["domain_uuid"],
            "ssh_host_key_alias": p["ssh_host_key_alias"], "ssh_user": p["ssh_user"],
            "tmux_socket": p.get("tmux_socket"),
            "session": session_name(args.session or p.get("tmux_session", "main")),
            "agent": p.get("agent") if p.get("agent") != "none" else None,
            "operation": args.operation, "cwd": getattr(args, "cwd", None),
            "command": args.command, "timeout": args.timeout,
            "menu_first": getattr(args, "menu_first", False),
            "reclaim": getattr(args, "reclaim", False)}


def checked_profile(target):
    p = profile(target["profile"])
    for key in ("domain_uuid", "ssh_host_key_alias", "ssh_user", "tmux_socket"):
        if p.get(key) != target.get(key):
            raise ToolError(f"Profile identity/target changed ({key}); explicitly remap this pane")
    session_name(target["session"])
    return p


def virsh(p, *argv):
    try:
        result = subprocess.run(["virsh", "-c", "qemu:///session", *argv, p["domain_uuid"]],
                                text=True, capture_output=True, timeout=30,
                                env={**os.environ, "LC_ALL": "C"})
    except subprocess.TimeoutExpired as error:
        raise ToolError("libvirt command timed out; refresh VM state before retrying") from error
    if result.returncode:
        raise ToolError(f"libvirt: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def observed_state(p):
    state = virsh(p, "domstate")
    if state == "shut off":
        info = virsh(p, "dominfo")
        if re.search(r"^Managed save:\s+yes$", info, re.M):
            return "saved"
    return state


def ensure_running(p):
    with lock(f"vm-{p['domain_uuid']}"):
        state = observed_state(p)
        if state == "paused":
            virsh(p, "resume")
        elif state in ("shut off", "saved"):
            virsh(p, "start")
        elif state != "running":
            raise ToolError(f"Unsupported VM state: {state}")


def ssh_argv(p, remote, pty=False):
    return ["ssh", "-F", "/dev/null", "-tt" if pty else "-T", "-p", str(p["ssh_port"]),
            "-i", p["ssh_identity_file"], "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
            "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", f"UserKnownHostsFile={p['ssh_known_hosts_file']}", "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", f"HostKeyAlias={p['ssh_host_key_alias']}", "-o", "UpdateHostKeys=no",
            "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
            "--", f"{p['ssh_user']}@{p['ssh_host']}", remote]


def wait_endpoint(p, seconds):
    deadline = time.monotonic() + seconds
    while True:
        try:
            with socket.create_connection((p["ssh_host"], p["ssh_port"]), timeout=1):
                return
        except OSError:
            if time.monotonic() >= deadline:
                raise ToolError("SSH endpoint did not become reachable within the boot timeout")
            time.sleep(0.5)


def tmux(target):
    return ["tmux"] + (["-S", target["tmux_socket"]] if target.get("tmux_socket") else [])


def ssh_call(p, argv, env, *, pty=False, capture=False):
    # SSH joins remote arguments into a shell command; quote every argument.
    command = "exec " + shlex.join(argv)
    try:
        result = subprocess.run(ssh_argv(p, command, pty), env=env, text=True,
                                capture_output=capture, timeout=15 if capture else None)
    except subprocess.TimeoutExpired as error:
        if "new-session" in argv:
            raise ToolError("SSH session creation timed out; creation outcome is uncertain. Check the guest session before explicitly retrying; no automatic retry was made") from error
        raise ToolError("SSH command timed out; guest session was not recreated") from error
    if result.returncode == 255:
        raise ToolError("SSH transport/authentication failed; check endpoint and pinned host identity"
                        + (f": {result.stderr.strip()}" if capture else ""))
    return result


def attach(target, p, env, reclaim=False):
    plain = dict(env)
    plain.pop("HERDR_AGENT", None)
    exists = ssh_call(p, tmux(target) + ["has-session", "-t", "=" + target["session"]], plain, capture=True)
    if exists.returncode:
        raise ToolError(f"Guest tmux session is missing: {target['session']} (not recreated)")
    command = tmux(target) + ["attach-session"] + (["-d"] if reclaim else []) + ["-t", "=" + target["session"]]
    return ssh_call(p, command, env, pty=True).returncode


def execute(target, env, on_created=None, restoring=False):
    p = checked_profile(target)
    plain = dict(env)
    plain.pop("HERDR_AGENT", None)
    agent = env.get("HERDR_AGENT")
    if agent not in (None, "claude", "codex"):
        raise ToolError("Unsupported agent hint")
    interactive = dict(plain)
    if agent:
        interactive["HERDR_AGENT"] = agent
    if target["operation"] == "new" and not restoring:
        ensure_running(p)
        wait_endpoint(p, target["timeout"])
        argv = tmux(target) + ["new-session", "-d", "-s", target["session"]]
        if target.get("cwd"):
            argv += ["-c", target["cwd"]]
        # tmux treats a single command argument as shell text. For one program,
        # prefix exec and quote it; multiple argv use tmux's direct-exec form.
        command = target["command"]
        argv += ["--"] + (["exec " + shlex.join(command)] if len(command) == 1 else command)
        created = ssh_call(p, argv, plain, capture=True)
        if created.returncode:
            raise ToolError(f"tmux session creation failed (existing sessions are never replaced): {created.stderr.strip()}")
        if on_created:
            on_created()
    if not restoring and not target.get("menu_first"):
        try:
            ensure_running(p)
            wait_endpoint(p, target["timeout"])
            attach(target, p, interactive, target.get("reclaim", False))
        except ToolError as error:
            print(f"{error}", file=sys.stderr)
        except KeyboardInterrupt:
            print("\nAttachment interrupted; guest session remains available")
    while True:
        print(f"\nVM {target['profile']} / tmux {target['session']}")
        print("[a] Attach  [r] Reclaim  [s] Start/resume  [f] Refresh  [q] Exit")
        try:
            choice = input("> ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        try:
            if choice in ("q", "exit"):
                return 0
            if choice == "f":
                print(f"VM state: {observed_state(p)}")
            elif choice == "s":
                ensure_running(p)
                print("VM started/resumed")
            elif choice in ("a", "r"):
                ensure_running(p)
                wait_endpoint(p, target["timeout"])
                try:
                    attach(target, p, interactive, choice == "r")
                except KeyboardInterrupt:
                    print("\nAttachment interrupted; guest session remains available")
        except ToolError as error:
            print(f"{error}", file=sys.stderr)


def run_mapping(record, env, restoring=False, on_created=None):
    target = record["vm"]

    def created():
        target.update(operation="attach", command=[], cwd=None, reclaim=False)
        record["argv"] = [record["argv"][0], "attach", target["profile"], "--session", target["session"]]
        atomic_json(mapping_path(record["id"]), record)
        if on_created:
            on_created()

    return execute(target, env, on_created=created, restoring=restoring)


def main():
    args = parse_args(sys.argv[1:])
    target = resolve(args)
    env = dict(os.environ)
    if "HERDR_AGENT" not in env and target.get("agent"):
        env["HERDR_AGENT"] = target["agent"]
    return execute(target, env)
