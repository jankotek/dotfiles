#!/usr/bin/env python3
"""Exercise real lab PAM sessions in a disposable qemu:///session guest."""

import argparse
import base64
from contextlib import suppress
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import tarfile
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET

from vm_image import digest


def run(argv, timeout=300, check=True):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f"{argv[0]} exited {result.returncode}:\n{result.stdout[-6000:]}\n{result.stderr[-4000:]}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(os.environ.get("OPT_JAN", Path(__file__).resolve().parents[2])).resolve()
    base = args.base.resolve(strict=True)
    manifest = json.loads(base.with_suffix(".manifest.json").read_text())
    assert manifest["builder"] == "dotfiles/usr/bin/vm-image-build"
    assert manifest["image_sha256"] == digest(base)
    name = "labtest-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6]
    root = Path(tempfile.mkdtemp(prefix=name + "-", dir=base.parent))
    disk = root / "root.qcow2"
    defined = False
    log = []

    def report(message):
        print(message, flush=True)
        log.append(message)
        (root / "checks.log").write_text("\n".join(log) + "\n")

    def virsh(*argv, **kwargs):
        return run(["virsh", "-c", "qemu:///session", *argv], **kwargs)

    def guest(script, **kwargs):
        return run([str(repo / "usr/bin/vm-exec"), name, "--argv", "bash", "-euc", script], **kwargs)

    def wait_agent():
        run([str(repo / "usr/bin/vm-wait"), name], timeout=150)

    try:
        report(f"Disposable VM: {name}; logs: {root}")
        run(["qemu-img", "create", "-f", "qcow2", "-F", "qcow2", "-b", str(base), str(disk)])
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        domain = ET.fromstring("""<domain type='kvm'>
          <name/><memory unit='MiB'>4096</memory><vcpu>4</vcpu>
          <os><type arch='x86_64'>hvm</type><boot dev='hd'/></os>
          <features><acpi/><apic/></features><cpu mode='host-passthrough'/>
          <devices><disk type='file' device='disk'><driver name='qemu' type='qcow2'/><source/><target dev='vda' bus='virtio'/></disk>
          <interface type='user'><model type='virtio'/><backend type='passt'/><portForward proto='tcp' address='127.0.0.1'><range to='22'/></portForward></interface>
          <serial type='pty'><target port='0'/></serial><console type='pty'><target type='serial' port='0'/></console>
          <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
          </devices></domain>""")
        domain.find("name").text = name
        domain.find("devices/disk/source").set("file", str(disk))
        domain.find("devices/interface/portForward/range").set("start", str(port))
        xml = root / "domain.xml"
        ET.ElementTree(domain).write(xml, encoding="unicode")
        virsh("define", str(xml))
        defined = True
        virsh("start", name)
        wait_agent()
        run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(root / "key")])
        # Stage files through QGA rather than sharing a writable host tree.
        payload = root / "payload.tar.gz"
        with tarfile.open(payload, "w:gz") as archive:
            for path in ("usr", "skel", "test", "setup"):
                archive.add(repo / path, arcname=path, filter=lambda info: None if "__pycache__" in info.name else info)
        guest("install -d /opt/jan; : > /var/tmp/lab-payload.b64")
        encoded = base64.b64encode(payload.read_bytes()).decode()
        for offset in range(0, len(encoded), 48000):
            guest("printf %s " + shlex.quote(encoded[offset:offset + 48000]) + " >> /var/tmp/lab-payload.b64")
        report("Installing VM-only prerequisites and lab accounts")
        pubkey = (root / "key.pub").read_text().strip()
        provisioning = r'''
base64 -d /var/tmp/lab-payload.b64 | tar -xz -C /opt/jan
rm /var/tmp/lab-payload.b64
zypper -n install --no-recommends sudo polkit pam-config nftables bats fzf starship zstd diffutils
for file in /opt/jan/usr/sbin/*; do ln -sf "$file" /usr/local/sbin/; done
/opt/jan/usr/sbin/create-lab-users > /root/lab-passwords.first
/opt/jan/usr/sbin/create-lab-users > /root/lab-passwords.second
/opt/jan/usr/sbin/setup-lab-hardening
/opt/jan/usr/sbin/setup-proc-hidepid
/opt/jan/usr/sbin/install-tmp-clean
for user in worker lab1 lab2; do
    home=$(getent passwd "$user" | cut -d: -f6)
    install -d -m 700 -o "$user" -g "$(id -gn "$user")" "$home/.ssh"
    printf '%s\n' PUBLIC_KEY > "$home/.ssh/authorized_keys"
    chown "$user:$(id -gn "$user")" "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
done
usermod -p "$(openssl passwd -6 "$(cat /proc/sys/kernel/random/uuid)")" worker
ssh-keygen -A
systemctl restart sshd
systemd-analyze verify --man=no tmp-clean.service systemd-tmpfiles-setup.service
OPT_JAN=/opt/jan bats /opt/jan/test/utils/lab-hardening.bats /opt/jan/test/utils/proc-hidepid.bats /opt/jan/test/utils/laptop-power.bats /opt/jan/test/basic/skel.bats
'''.replace("PUBLIC_KEY", shlex.quote(pubkey))
        # A detached service survives transport changes and keeps passwords out of logs.
        encoded_script = base64.b64encode(provisioning.encode()).decode()
        guest(f"printf %s {shlex.quote(encoded_script)} | base64 -d > /root/lab-provision.sh; systemd-run --unit=lab-test-provision --property=RemainAfterExit=yes /bin/bash -e /root/lab-provision.sh")
        deadline = time.monotonic() + 1200
        while True:
            state = guest("systemctl show lab-test-provision -p ActiveState -p SubState -p ExecMainStatus").stdout
            if "ActiveState=active" in state and "SubState=exited" in state:
                assert "ExecMainStatus=0" in state, state
                break
            if "ActiveState=failed" in state or time.monotonic() > deadline:
                failure = guest("journalctl -u lab-test-provision --no-pager").stdout
                (root / "provision.log").write_text(failure)
                raise RuntimeError(failure[-10000:])
            time.sleep(5)
        (root / "provision.log").write_text(guest("journalctl -u lab-test-provision --no-pager").stdout)
        report("PASS: provisioning, create-lab-users twice, hardening rerun, fixture tests, unit verification")
        hostkey = guest("cat /etc/ssh/ssh_host_ed25519_key.pub").stdout.strip()
        known = root / "known_hosts"
        known.write_text(name + " " + hostkey + "\n")

        def ssh(user, script, check=True):
            return run(["ssh", "-F", "/dev/null", "-i", str(root / "key"), "-p", str(port),
                        "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=10",
                        "-o", f"UserKnownHostsFile={known}", "-o", f"HostKeyAlias={name}",
                        f"{user}@127.0.0.1", "bash -euc " + shlex.quote(script)], check=check)

        def isolation_checks():
            guest("systemd-run --unit=lab-test-root-sleeper /bin/sleep infinity")
            pid = guest("systemctl show lab-test-root-sleeper -p MainPID --value").stdout.strip()
            ssh("worker", f"test -d /proc/{pid}; echo worker > /tmp/lab-private-marker")
            guest("test ! -e /tmp/lab-private-marker")
            script = f"test ! -e /proc/{pid}; test ! -e /tmp/lab-private-marker; "
            script += r'''uid=$(id -u)
test "$(findmnt -n -o FSTYPE -T /sys/fs/cgroup/user.slice)" = tmpfs
test "$(findmnt -n -o FSTYPE -T /sys/fs/cgroup/user.slice/user-$uid.slice)" = cgroup2
test "$(ls /sys/fs/cgroup/user.slice)" = "user-$uid.slice"
systemd-run --user --wait --pipe /bin/bash -ec 'test "$(findmnt -n -o FSTYPE -T /sys/fs/cgroup/user.slice)" = tmpfs'
'''
            ssh("lab1", script)
            guest("systemctl stop lab-test-root-sleeper")
            report("PASS: real SSH and systemd user sessions hide root processes, private tmp, other cgroups")

        isolation_checks()
        # Ordinary users remain able to log in while either custom mount operation fails.
        original = guest("base64 -w0 /etc/security/jan-lab-session").stdout.strip()
        for operation in ("mount -t proc", "mount --bind"):
            modified = base64.b64decode(original).decode().replace(operation, "false # injected mount failure: " + operation)
            value = base64.b64encode(modified.encode()).decode()
            guest(f"printf %s {shlex.quote(value)} | base64 -d > /etc/security/jan-lab-session")
            try:
                failed = ssh("lab1", "touch /home/lab1/SHOULD_NOT_RUN", check=False)
                assert failed.returncode != 0, "lab login survived failed isolation"
                guest("test ! -e /home/lab1/SHOULD_NOT_RUN")
                ssh("worker", "true")
                report(f"PASS: {operation} failure rejects lab login and keeps ordinary logins working")
            finally:
                guest(f"printf %s {shlex.quote(original)} | base64 -d > /etc/security/jan-lab-session")
        # Real loopback connections, rather than assertions about generated nft text.
        server = "import socket,time; s=[]\nfor p in (9999,10080):\n x=socket.socket(); x.bind(('0.0.0.0',p)); x.listen(); s.append(x)\ntime.sleep(180)"
        value = base64.b64encode(server.encode()).decode()
        guest(f"printf %s {shlex.quote(value)} | base64 -d > /run/lab-listeners.py; systemd-run --unit=lab-test-listeners python3 /run/lab-listeners.py")
        time.sleep(1)
        for user, expected in (("worker", True), ("lab1", False)):
            network = "import socket\nfor p in (9999,10080):\n s=socket.socket(); s.settimeout(3)\n ok=s.connect_ex(('127.0.0.1',p))==0\n assert ok == (p==10080 or " + repr(expected) + "), (p,ok)"
            ssh(user, "python3 -c " + shlex.quote(network))
        report("PASS: low host port rejected for lab; high VM-forwarding port and regular-user access work")
        guest("systemctl stop lab-test-listeners")
        for uid in guest("id -u lab1").stdout.split():
            limits = guest(f"systemctl show user-{uid}.slice -p MemoryHigh -p MemoryMax -p CPUQuotaPerSecUSec -p TasksMax").stdout
            properties = dict(line.split("=", 1) for line in limits.splitlines())
            assert properties["TasksMax"] == "8192", limits
            assert float(properties["CPUQuotaPerSecUSec"].removesuffix("s")) == 3.2, limits
            assert 0 < int(properties["MemoryHigh"]) < int(properties["MemoryMax"]), limits
        report("Rebooting disposable guest")
        previous_boot = guest("cat /proc/sys/kernel/random/boot_id").stdout.strip()
        virsh("reboot", name)
        time.sleep(5)
        deadline = time.monotonic() + 180
        while True:
            try:
                current_boot = guest("cat /proc/sys/kernel/random/boot_id", timeout=15).stdout.strip()
                if current_boot != previous_boot:
                    guest("systemctl is-active tmp-clean.service systemd-tmpfiles-setup.service proc-hidepid.service jan-lab-local-network.service")
                    break
            except (RuntimeError, subprocess.TimeoutExpired):
                pass  # The guest agent disappears during reboot.
            if time.monotonic() > deadline:
                raise RuntimeError("guest did not complete a new boot")
            time.sleep(1)
        boot = guest("systemctl is-active tmp-clean.service systemd-tmpfiles-setup.service proc-hidepid.service jan-lab-local-network.service; test -d /tmp/tmp-inst; journalctl -b --no-pager | grep -i 'ordering cycle' || true").stdout
        assert boot.splitlines() == ["active"] * 4, boot
        isolation_checks()
        report("PASS: reboot completes with tmp-clean, tmpfiles, proc-hidepid and firewall active; login isolation survives")
        report("All live checks passed")
    finally:
        if defined:
            with suppress(RuntimeError, subprocess.TimeoutExpired):
                (root / "guest-journal.log").write_text(guest("journalctl -b --no-pager -n 250", timeout=30).stdout)
            virsh("destroy", name, check=False)
            virsh("undefine", name)
        for domain_name in virsh("list", "--all", "--name").stdout.split():
            assert str(disk) not in virsh("domblklist", domain_name, "--details").stdout, "disk is still used by another domain"
        disk.unlink(missing_ok=True)
        (root / "key").unlink(missing_ok=True)
        (root / "payload.tar.gz").unlink(missing_ok=True)
        report("Removed disposable domain, disk and private SSH key; retained test logs")


if __name__ == "__main__":
    main()
