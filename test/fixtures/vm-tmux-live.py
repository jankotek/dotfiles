#!/usr/bin/env python3
"""Opt-in overlay VM check, provisioned through its trusted guest-agent channel."""

import base64
import os
from pathlib import Path
import pty
import select
import shlex
import socket
import subprocess
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET

from herdr_tools.common import atomic_json, config_dir
from herdr_tools.vm import profile, ssh_argv


def run(argv, **kwargs):
    return subprocess.run(argv, text=True, check=True, capture_output=True, timeout=240, **kwargs).stdout.strip()


def main():
    base = Path(os.environ["HERDR_VM_TEST_BASE"]).resolve(strict=True)
    repo = Path(os.environ["OPT_JAN"])
    images = Path.home() / ".local/share/libvirt/images"
    images.mkdir(parents=True, exist_ok=True)
    name = "vm-tmux-test-" + uuid.uuid4().hex[:12]
    domain_uuid = str(uuid.uuid4())
    master = None
    wrapper = None
    defined = False
    with tempfile.TemporaryDirectory(prefix=name + "-", dir=images) as directory:
        root = Path(directory)
        os.environ.update(XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"))
        for key in ("HERDR_AGENT", "HERDR_SOCKET_PATH", "HERDR_ENV", "HERDR_PANE_ID"):
            os.environ.pop(key, None)
        run(["qemu-img", "create", "-f", "qcow2", "-F", "qcow2", "-b", str(base), str(root / "root.qcow2")])
        run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(root / "key")])
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        domain = ET.fromstring("""<domain type='kvm'>
          <name/><uuid/><memory unit='MiB'>2048</memory><vcpu>2</vcpu>
          <os><type arch='x86_64'>hvm</type><boot dev='hd'/></os>
          <features><acpi/><apic/></features><cpu mode='host-passthrough'/>
          <devices><disk type='file' device='disk'><driver name='qemu' type='qcow2'/><source/><target dev='vda' bus='virtio'/></disk>
          <interface type='user'><model type='virtio'/><backend type='passt'/><portForward proto='tcp' address='127.0.0.1'><range to='22'/></portForward></interface>
          <serial type='pty'><target port='0'/></serial><console type='pty'><target type='serial' port='0'/></console>
          <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
          </devices></domain>""")
        domain.find("name").text = name
        domain.find("uuid").text = domain_uuid
        domain.find("devices/disk/source").set("file", str(root / "root.qcow2"))
        domain.find("devices/interface/portForward/range").set("start", str(port))
        xml_path = root / "domain.xml"
        ET.ElementTree(domain).write(xml_path, encoding="unicode")

        def virsh(*args):
            return run(["virsh", "-c", "qemu:///session", *args])

        try:
            virsh("define", str(xml_path))
            defined = True
            virsh("start", domain_uuid)
            deadline = time.monotonic() + 180
            while True:
                ping = subprocess.run(["virsh", "-c", "qemu:///session", "qemu-agent-command", domain_uuid,
                                       '{"execute":"guest-ping"}'], capture_output=True, timeout=10)
                if ping.returncode == 0:
                    break
                if time.monotonic() > deadline:
                    raise AssertionError("VM guest agent did not become ready")
                time.sleep(1)
            print("Guest agent ready; provisioning isolated test account and SSH trust", flush=True)
            pubkey = base64.b64encode((root / "key.pub").read_bytes()).decode()
            script = """set -eu
command -v tmux >/dev/null || zypper -n install --no-recommends tmux
command -v sshd >/dev/null || zypper -n install --no-recommends openssh-server
id herdrtest >/dev/null 2>&1 || useradd -m -s /bin/bash herdrtest
passwd -d herdrtest >/dev/null
install -d -m 700 -o herdrtest -g users /home/herdrtest/.ssh
printf %s KEY | base64 -d > /home/herdrtest/.ssh/authorized_keys
chown herdrtest:users /home/herdrtest/.ssh/authorized_keys
chmod 600 /home/herdrtest/.ssh/authorized_keys
rm -f /etc/ssh/ssh_host_*key /etc/ssh/ssh_host_*key.pub
ssh-keygen -A >/dev/null
mkdir -p /etc/ssh/sshd_config.d
printf '%s\\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' 'PubkeyAuthentication yes' > /etc/ssh/sshd_config.d/00-herdr-test.conf
systemctl restart sshd
cat /etc/ssh/ssh_host_ed25519_key.pub
""".replace("KEY", pubkey)
            hostkey = run([str(repo / "usr/bin/vm-exec"), domain_uuid, "--argv", "/bin/bash", "-c", script]).splitlines()[-1]
            assert hostkey.startswith("ssh-ed25519 "), hostkey
            known_hosts = root / "known_hosts"
            known_hosts.write_text(name + " " + hostkey + "\n")
            known_hosts.chmod(0o600)
            atomic_json(config_dir() / "vms/dev.json", {
                "schema_version": 1, "domain_uuid": domain_uuid, "libvirt_uri": "qemu:///session",
                "ssh_host": "127.0.0.1", "ssh_port": port, "ssh_user": "herdrtest",
                "ssh_host_key_alias": name, "ssh_identity_file": str(root / "key"),
                "ssh_known_hosts_file": str(known_hosts), "tmux_session": "code",
            })
            p = profile("dev")

            def remote(argv):
                return run(ssh_argv(p, "exec " + shlex.join(argv)))

            remote(["true"])
            print("Verified SSH host key obtained through guest agent", flush=True)
            master, slave = pty.openpty()
            wrapper = subprocess.Popen([str(repo / "usr/bin/vm-tmux"), "new", "dev", "--session", "code", "--",
                                        "bash", "-c", "echo GUEST_SESSION_READY; sleep 3600"],
                                       stdin=slave, stdout=slave, stderr=slave)
            os.close(slave)
            output = b""

            def expect(marker, timeout=30):
                nonlocal output
                wanted = marker.encode()
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    ready, _, _ = select.select([master], [], [], 0.2)
                    if ready:
                        output += os.read(master, 65536)
                        if wanted in output:
                            output = b""
                            return
                    if wrapper.poll() is not None:
                        break
                raise AssertionError(f"Missing {marker!r} in wrapper output: {output[-4000:]!r}")

            expect("GUEST_SESSION_READY")
            pid = remote(["tmux", "display-message", "-p", "-t", "=code", "#{pane_pid}"])
            remote(["tmux", "new-session", "-d", "-s", "code-long", "sleep 3600"])
            remote(["tmux", "detach-client", "-s", "=code"])
            expect("[q] Exit")
            os.write(master, b"r\n")
            expect("GUEST_SESSION_READY")
            # While paused, SSH keepalives must bring the wrapper back to menu.
            virsh("suspend", domain_uuid)
            expect("[q] Exit", timeout=40)
            os.write(master, b"s\n")
            expect("VM started/resumed")
            assert virsh("domstate", domain_uuid) == "running"
            assert remote(["tmux", "display-message", "-p", "-t", "=code", "#{pane_pid}"]) == pid
            virsh("managedsave", domain_uuid)
            assert virsh("domstate", domain_uuid) == "shut off"
            os.write(master, b"s\n")
            expect("VM started/resumed")
            assert remote(["tmux", "display-message", "-p", "-t", "=code", "#{pane_pid}"]) == pid
            os.write(master, b"q\n")
            assert wrapper.wait(timeout=10) == 0
            assert virsh("domstate", domain_uuid) == "running"
            remote(["tmux", "has-session", "-t", "=code"])
            # A mismatched host key must fail closed even on this working endpoint.
            original = known_hosts.read_text()
            known_hosts.write_text(name + " " + (root / "key.pub").read_text())
            denied = subprocess.run(ssh_argv(p, "true"), capture_output=True, timeout=15)
            assert denied.returncode == 255
            known_hosts.write_text(original)
            print("PASS: verified SSH, new/exact tmux session, detach/menu/reclaim, paused timeout/resume, managedsave/start, preserved guest PID, wrong-host rejection", flush=True)
        finally:
            if wrapper is not None and wrapper.poll() is None:
                wrapper.terminate()
                try:
                    wrapper.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    wrapper.kill()
                    wrapper.wait()
            if master is not None:
                os.close(master)
            if defined:
                # Only the UUID created by this test may be removed.
                subprocess.run(["virsh", "-c", "qemu:///session", "destroy", domain_uuid], capture_output=True, timeout=30)
                subprocess.run(["virsh", "-c", "qemu:///session", "undefine", domain_uuid, "--managed-save"], capture_output=True, timeout=30, check=True)


if __name__ == "__main__":
    main()
