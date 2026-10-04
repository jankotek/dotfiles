#!/usr/bin/env python3
"""Provision a private baseweed copy with canonical dotfiles, then test Herdr."""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import socket
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET

from herdr_tools.common import Herdr, ToolError, atomic_json, config_dir, read_json, state_dir
from herdr_tools.layout import restore, save
from herdr_tools.vm import ssh_argv
from vm_image import digest


def run(argv, timeout=300):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{argv[0]} failed: {result.stderr.strip() or result.stdout[-4000:]}")
    return result.stdout.strip()


def eventually(check, seconds=120):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            if check():
                return
        except (OSError, RuntimeError, ToolError):
            pass  # Boot/reboot/provisioning can briefly remove the transport.
        time.sleep(.5)
    raise RuntimeError("Timed out waiting for the disposable test resource")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--keep", action="store_true", help="leave the successful VM and recovered Herdr session available")
    args = parser.parse_args()
    repo = Path(os.environ["OPT_JAN"]).resolve()
    base = args.base.resolve(strict=True)
    base_manifest = read_json(base.with_suffix(".manifest.json"))
    if (base_manifest.get("builder") != "dotfiles/usr/bin/vm-image-build"
            or base_manifest.get("source") != "original-opensuse-cloud"
            or base_manifest.get("image_sha256") != digest(base)):
        raise RuntimeError("Use a verified base newly built by dotfiles vm-image-build")
    name = "herdr-baseweed-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6]
    identifier = str(uuid.uuid4())
    profile_name = "baseweed-" + uuid.uuid4().hex[:8]
    herdr_session = profile_name
    root = Path.home() / ".local/share/libvirt/images" / name
    root.mkdir(mode=0o700)
    disk = root / "root.qcow2"
    profile_path = config_dir() / "vms" / f"{profile_name}.json"
    manifest_path = state_dir() / f"{name}.json"
    saved_path = root / "layout.json"
    manifest = {"name": name, "domain_uuid": identifier, "base": str(base), "directory": str(root),
                "profile": profile_name, "herdr_session": herdr_session, "status": "preparing"}
    atomic_json(manifest_path, manifest)
    print(f"VM: {name}\nManifest: {manifest_path}", flush=True)
    defined, complete = False, False
    api = Herdr(herdr_session)
    servers = []
    log = (root / "herdr.log").open("w")

    def virsh(*argv):
        return run(["virsh", "-c", "qemu:///session", *argv])

    def guest(argv, timeout=300):
        return run([str(repo / "usr/bin/vm-exec"), identifier, "--argv", *argv], timeout=timeout)

    def qga_ready():
        return subprocess.run(["virsh", "-c", "qemu:///session", "qemu-agent-command", identifier,
                               '{"execute":"guest-ping"}'], capture_output=True, timeout=10).returncode == 0

    def start_herdr():
        servers.append(subprocess.Popen([shutil.which("herdr"), "server", "--session", herdr_session],
                                        stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True))
        eventually(lambda: api.path.exists() and api.call("ping"), seconds=30)

    try:
        print("Copying verified baseweed into a standalone test disk", flush=True)
        run(["qemu-img", "convert", "-f", "qcow2", "-O", "qcow2", str(base), str(disk)])
        info = json.loads(run(["qemu-img", "info", "--output=json", str(disk)]))
        assert not info.get("backing-filename"), info
        run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(root / "operator-key")])
        payload = root / "dotfiles.tar.gz"
        run(["tar", "-czf", str(payload), "--exclude=.git", "--exclude=__pycache__", "-C", str(repo), "."])
        manifest.update(dotfiles_commit=run(["git", "-C", str(repo), "rev-parse", "HEAD"]),
                        payload_sha256=hashlib.sha256(payload.read_bytes()).hexdigest(), disk=str(disk))
        manifest["base_manifest"] = base_manifest
        atomic_json(manifest_path, manifest)
        pubkey = base64.b64encode((root / "operator-key.pub").read_bytes()).decode()
        bootstrap = root / "bootstrap.sh"
        bootstrap.write_text(r'''#!/bin/bash
set -euo pipefail
mkdir -p /opt/jan
tar -xzf /var/tmp/dotfiles.tar.gz -C /opt/jan
rm /var/tmp/dotfiles.tar.gz
if id admin >/dev/null 2>&1; then
    usermod -l worker -d /home/worker -m admin
fi
id worker >/dev/null 2>&1 || useradd -m -s /bin/bash worker
rm -f /etc/sudoers.d/99-admin
usermod -G '' worker
printf '%s\n' 'worker:WORKER_PASSWORD' | chpasswd
passwd -l root >/dev/null
worker_group=$(id -gn worker)
install -d -m 700 -o worker -g "$worker_group" /home/worker/.ssh
printf %s PUBLIC_KEY | base64 -d > /home/worker/.ssh/authorized_keys
chown "worker:$worker_group" /home/worker/.ssh/authorized_keys
chmod 600 /home/worker/.ssh/authorized_keys
mkdir -p /etc/ssh/sshd_config.d /etc/sysconfig
printf '%s\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' 'PermitRootLogin no' > /etc/ssh/sshd_config.d/00-herdr-baseweed.conf
rm -f /etc/ssh/ssh_host_*key /etc/ssh/ssh_host_*key.pub
ssh-keygen -A
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id /var/lib/systemd/random-seed
ln -s /etc/machine-id /var/lib/dbus/machine-id
printf 'FILTER_RPC_ARGS=""\n' > /etc/sysconfig/qemu-ga
mkdir -p /etc/systemd/system/qemu-guest-agent.service.d
printf '[Service]\nUMask=0022\n' > /etc/systemd/system/qemu-guest-agent.service.d/umask.conf
systemctl enable sshd qemu-guest-agent
'''.replace("WORKER_PASSWORD", secrets.token_urlsafe(48)).replace("PUBLIC_KEY", pubkey))
        bootstrap.chmod(0o600)
        unit = root / "herdr-baseweed-provision.service"
        unit.write_text("[Unit]\nDescription=Canonical dotfiles baseweed provisioning\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=oneshot\nRemainAfterExit=yes\nTimeoutStartSec=1800\nExecStart=/opt/jan/setup/vm-baseweed\nStandardOutput=append:/var/log/herdr-baseweed-provision.log\nStandardError=append:/var/log/herdr-baseweed-provision.log\n")
        print("Installing boot prerequisites offline; staging the canonical setup script", flush=True)
        run(["virt-copy-in", "-a", str(disk), str(payload), "/var/tmp"], timeout=180)
        run(["virt-customize", "--memsize", "4096", "--smp", "2", "-a", str(disk),
             "--install", "tmux,openssh-server,spice-vdagent,rsync,python3",
             "--run", str(bootstrap), "--upload", f"{unit}:/etc/systemd/system/herdr-baseweed-provision.service"], timeout=900)
        bootstrap.unlink()  # Discard the temporary random password material.
        payload.unlink()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        domain = ET.fromstring("""<domain type='kvm'>
          <name/><uuid/><memory unit='MiB'>4096</memory><vcpu>2</vcpu>
          <os><type arch='x86_64'>hvm</type><boot dev='hd'/></os>
          <features><acpi/><apic/></features><cpu mode='host-passthrough'/>
          <devices><disk type='file' device='disk'><driver name='qemu' type='qcow2'/><source/><target dev='vda' bus='virtio'/></disk>
          <interface type='user'><model type='virtio'/><backend type='passt'/><portForward proto='tcp' address='127.0.0.1'><range to='22'/></portForward></interface>
          <serial type='pty'><target port='0'/></serial><console type='pty'><target type='serial' port='0'/></console>
          <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
          </devices></domain>""")
        domain.find("name").text, domain.find("uuid").text = name, identifier
        domain.find("devices/disk/source").set("file", str(disk))
        domain.find("devices/interface/portForward/range").set("start", str(port))
        ET.ElementTree(domain).write(root / "domain.xml", encoding="unicode")
        virsh("define", str(root / "domain.xml"))
        defined = True
        virsh("start", identifier)
        eventually(qga_ready, seconds=180)
        print("Starting /opt/jan/setup/vm-baseweed in its own guest systemd service", flush=True)
        guest(["systemctl", "start", "--no-block", "herdr-baseweed-provision.service"])
        deadline = time.monotonic() + 1800
        while True:
            if time.monotonic() > deadline:
                raise RuntimeError("Canonical provisioning exceeded its time limit")
            status = None
            try:
                status = guest(["systemctl", "show", "herdr-baseweed-provision.service", "-p", "ActiveState", "-p", "SubState", "-p", "Result", "-p", "ExecMainStatus"])
            except (RuntimeError, subprocess.TimeoutExpired):
                print("Guest transport temporarily unavailable; provisioning service continues", flush=True)
            if status is not None:
                if "ActiveState=active" in status:
                    assert "ExecMainStatus=0" in status and "Result=success" in status, status
                    break
                if "ActiveState=failed" in status:
                    failure = guest(["tail", "-n", "70", "/var/log/herdr-baseweed-provision.log"])
                    raise RuntimeError("Canonical provisioning failed:\n" + status + "\n" + failure)
                try:
                    tail = guest(["tail", "-n", "1", "/var/log/herdr-baseweed-provision.log"])
                    print("Provisioning: " + tail, flush=True)
                except (RuntimeError, subprocess.TimeoutExpired):
                    pass
            time.sleep(10)
        (root / "provision.log").write_text(guest(["cat", "/var/log/herdr-baseweed-provision.log"]))
        print("Canonical provisioning succeeded; rebooting and checking dotfiles/network", flush=True)
        virsh("reboot", identifier)
        time.sleep(5)
        eventually(qga_ready, seconds=180)
        checks = guest(["bash", "-c", "OPT_JAN=/opt/jan bats /opt/jan/test/vm/network.bats /opt/jan/test/vm/provisioned-home.bats"], timeout=180)
        (root / "guest-tests.log").write_text(checks + "\n")
        print(checks, flush=True)
        hostkey = guest(["cat", "/etc/ssh/ssh_host_ed25519_key.pub"])
        assert hostkey.startswith("ssh-ed25519 "), hostkey
        known_hosts = root / "known_hosts"
        known_hosts.write_text(name + " " + hostkey + "\n")
        known_hosts.chmod(0o600)
        p = {"schema_version": 1, "domain_uuid": identifier, "libvirt_uri": "qemu:///session", "ssh_host": "127.0.0.1",
             "ssh_port": port, "ssh_user": "worker", "ssh_host_key_alias": name,
             "ssh_identity_file": str(root / "operator-key"), "ssh_known_hosts_file": str(known_hosts), "tmux_session": "main"}
        atomic_json(profile_path, p)

        def remote(argv):
            return run(ssh_argv(p, "exec " + shlex.join(argv)))

        remote(["bash", "-c", "mkdir -p ~/workspace; printf '%s\\n' 'Herdr baseweed workflow test' > ~/workspace/notes.txt; tmux new-session -d -s main -c ~/workspace; tmux new-session -d -s monitor htop; tmux new-session -d -s files -c ~/workspace mc; tmux new-session -d -s notes nano /home/worker/workspace/notes.txt"])
        def workloads():
            rows = remote(["ps", "-u", "worker", "-o", "pid=,comm="]).splitlines()
            return {name: int(pid) for pid, name in (row.split(maxsplit=1) for row in rows) if name in ("htop", "mc", "nano")}
        eventually(lambda: len(workloads()) == 3, seconds=30)
        original_pids = workloads()
        print("Guest workloads: " + json.dumps(original_pids), flush=True)
        start_herdr()
        created = api.call("workspace.create", label="Baseweed workflow", cwd=str(root))
        def leaf(session):
            return {"type": "pane", "label": session, "cwd": str(root),
                    "command": [str(repo / "usr/bin/herdr-run"), "vm-tmux", "attach", profile_name, "--session", session]}
        tree = {"type": "split", "direction": "right", "ratio": .5,
                "first": {"type": "split", "direction": "down", "ratio": .5, "first": leaf("main"), "second": leaf("monitor")},
                "second": {"type": "split", "direction": "down", "ratio": .5, "first": leaf("files"), "second": leaf("notes")}}
        api.call("layout.apply", tab_id=created["tab"]["tab_id"], tab_label="VM tools", root=tree)
        def clients():
            return remote(["tmux", "list-clients", "-F", "#{session_name}"]).splitlines()
        eventually(lambda: set(clients()) == {"main", "monitor", "files", "notes"}, seconds=30)
        save(api, saved_path)
        saved = read_json(saved_path)
        assert len(saved["mappings"]) == 4, saved
        api.call("server.stop")
        servers[-1].wait(timeout=10)
        eventually(lambda: not api.path.exists(), seconds=30)
        eventually(lambda: not clients(), seconds=30)
        assert workloads() == original_pids
        print("Herdr stopped; all original guest workloads remain alive", flush=True)
        start_herdr()
        eventually(lambda: all(not pane.get("tokens", {}).get("herdr_mapping") for pane in api.call("session.snapshot")["snapshot"]["panes"]), seconds=15)
        deadline = time.monotonic() + 5
        while True:
            try:
                restore(api, saved, recover=True)
                break
            except ToolError as error:
                if "not an idle shell" not in str(error) or time.monotonic() >= deadline:
                    raise
                time.sleep(.1)  # Wait for native shell initialization children.
        eventually(lambda: len([pane for pane in api.call("session.snapshot")["snapshot"]["panes"] if pane.get("tokens", {}).get("herdr_mapping")]) == 4, seconds=30)
        assert not clients(), "Cold restore attached before a menu choice"
        for pane in api.call("session.snapshot")["snapshot"]["panes"]:
            eventually(lambda pane=pane: "[a] Attach" in api.call("pane.read", pane_id=pane["pane_id"], source="visible")["read"]["text"], seconds=15)
            api.call("pane.send_text", pane_id=pane["pane_id"], text="a\n")
        eventually(lambda: set(clients()) == {"main", "monitor", "files", "notes"}, seconds=30)
        assert workloads() == original_pids
        restore(api, saved, recover=True)
        assert len(api.call("session.snapshot")["snapshot"]["panes"]) == 4
        manifest.update(status="ready", profile_path=str(profile_path), ssh_port=port, snapshot=str(saved_path), guest_pids=original_pids,
                        checks=["canonical-provisioning", "guest-reboot", "network-and-dotfiles", "verified-ssh", "cold-herdr-recovery", "menu-first", "unchanged-guest-pids"])
        atomic_json(manifest_path, manifest)
        complete = True
        print(f"PASS: canonical baseweed provisioning and cold Herdr recovery\nOpen: herdr --session {herdr_session}\nProfile: {profile_name}", flush=True)
    except BaseException as error:
        manifest.update(status="failed", error=str(error))
        atomic_json(manifest_path, manifest)
        raise
    finally:
        if not complete or not args.keep:
            if api.path.exists():
                try:
                    api.call("server.stop")
                except (ToolError, OSError):
                    pass
            for server in servers:
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.terminate()
                    server.wait(timeout=5)
            if defined:
                subprocess.run(["virsh", "-c", "qemu:///session", "destroy", identifier], capture_output=True, timeout=30)
                subprocess.run(["virsh", "-c", "qemu:///session", "undefine", identifier], capture_output=True, timeout=30)
            if profile_path.exists():
                profile_path.unlink()
            if complete:
                shutil.rmtree(root)
                manifest.update(status="completed-and-cleaned")
                atomic_json(manifest_path, manifest)
        log.close()


if __name__ == "__main__":
    main()
