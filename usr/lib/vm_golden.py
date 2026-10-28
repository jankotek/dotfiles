"""Bake and test a text-only golden image using the current checkout in a VM."""

import argparse
import fcntl
import hashlib
import json
import os
import re
from pathlib import Path
import shlex
import shutil
import socket
import subprocess
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET

from herdr_tools.common import ToolError, atomic_json, private, read_json
from vm_image import digest, run, customize_script
from vm_bootstrap import BOOTSTRAP, SEAL
from vm_disks import LAYOUT, clone_bundle, read_bundle, split_image


BUILDER_INPUTS = (
    "../bin/vm-image-build", "vm_golden.py", "vm_bootstrap.py", "vm_cloud.py",
    "vm_disks.py", "vm_image.py", "herdr_tools/__init__.py", "herdr_tools/common.py",
)


def builder_digest():
    """Fingerprint executing code independently of the selected guest checkout."""
    directory = Path(__file__).resolve().parent
    result = hashlib.sha256()
    for name in BUILDER_INPUTS:
        result.update(name.encode() + b"\0" + (directory / name).read_bytes() + b"\0")
    return result.hexdigest()


def recipe_fingerprints(repo, base_sha256):
    tree, builder = checkout_digest(repo), builder_digest()
    recipe = hashlib.sha256((tree + base_sha256 + builder).encode()).hexdigest()
    return tree, builder, recipe


def checkout_digest(repo):
    """Include dirty/untracked provisioning inputs and link targets, without following links."""
    result = hashlib.sha256()
    for root in ("setup", "skel", "usr", "agent/skills"):
        for path in sorted((repo / root).rglob("*")):
            if "__pycache__" in path.parts or (path.is_dir() and not path.is_symlink()):
                continue
            result.update(str(path.relative_to(repo)).encode() + b"\0")
            result.update(str(path.lstat().st_mode & 0o777).encode() + b"\0")
            result.update(os.readlink(path).encode() if path.is_symlink() else path.read_bytes())
            result.update(b"\0")
    return result.hexdigest()


def domain_xml(identifier, disk, repo, port, desktop=False, host_opt=None, host_docs=None):
    disks = disk if isinstance(disk, dict) else {"root": disk}
    domain = ET.fromstring("""<domain type='kvm'>
      <name/><uuid/><memory unit='MiB'>4096</memory><vcpu>2</vcpu>
      <os><type arch='x86_64'>hvm</type><boot dev='hd'/></os>
      <features><acpi/><apic/></features><cpu mode='host-passthrough'/>
      <memoryBacking><source type='memfd'/><access mode='shared'/></memoryBacking>
      <devices>
        <disk type='file' device='disk'><driver name='qemu' type='qcow2' discard='unmap'/><source/><target dev='vda' bus='virtio'/></disk>
        <interface type='user'><model type='virtio'/><backend type='passt'/><portForward proto='tcp' address='127.0.0.1'><range to='22'/></portForward></interface>
        <filesystem type='mount' accessmode='passthrough'><driver type='virtiofs'/><source/><target dir='opt-jan'/><readonly/></filesystem>
        <serial type='pty'><target port='0'/></serial><console type='pty'><target type='serial' port='0'/></console>
        <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
      </devices></domain>""")
    domain.find("name").text = "golden-" + identifier
    domain.find("uuid").text = identifier
    domain.find("devices/disk/source").set("file", str(disks["root"]))
    for role, device in (("home", "vdb"), ("swap", "vdc")):
        if role in disks:
            extra = ET.SubElement(domain.find("devices"), "disk", type="file", device="disk")
            ET.SubElement(extra, "driver", name="qemu", type="qcow2", discard="unmap")
            ET.SubElement(extra, "source", file=str(disks[role]))
            ET.SubElement(extra, "target", dev=device, bus="virtio")
    for tag, source, readonly in (("host-opt", host_opt, True), ("host-docs", host_docs, False)):
        if source is None:
            continue
        fs = ET.SubElement(domain.find("devices"), "filesystem", type="mount", accessmode="passthrough")
        ET.SubElement(fs, "driver", type="virtiofs")
        ET.SubElement(fs, "source", dir=str(source))
        ET.SubElement(fs, "target", dir=tag)
        if readonly:
            ET.SubElement(fs, "readonly")
        else:
            mapping = ET.SubElement(fs, "idmap")
            ET.SubElement(mapping, "uid", start="1000", target=str(os.getuid()), count="1")
            ET.SubElement(mapping, "gid", start="1000", target=str(os.getgid()), count="1")
    domain.find("devices/filesystem/source").set("dir", str(repo))
    domain.find("devices/interface/portForward/range").set("start", str(port))
    if desktop:
        ET.SubElement(ET.SubElement(domain.find("devices"), "video"), "model", type="virtio")
        graphics = ET.SubElement(domain.find("devices"), "graphics", type="spice")
        ET.SubElement(graphics, "listen", type="none")
    return ET.tostring(domain, encoding="unicode")


class Guest:
    def __init__(self, disk, repo, directory, desktop=False, host_opt=None, host_docs=None):
        self.host_opt = Path(host_opt) if host_opt is not None else Path("/opt")
        self.host_docs = Path(host_docs) if host_docs is not None else directory / "host-docs"
        self.desktop = desktop
        self.identifier = str(uuid.uuid4())
        self.disk, self.repo, self.directory = disk, repo, directory
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            self.port = sock.getsockname()[1]
        self.defined = False

    def virsh(self, *argv):
        return run(["virsh", "-c", "qemu:///session", *argv], timeout=60)

    def start(self):
        if not (self.host_opt / "jan").is_dir():
            raise ToolError("The read-only host /opt export needs an existing jan mountpoint")
        self.host_docs.mkdir(exist_ok=True, mode=0o700)
        xml = self.directory / (self.identifier + ".xml")
        xml.write_text(domain_xml(self.identifier, self.disk, self.repo, self.port, self.desktop, self.host_opt, self.host_docs))
        self.virsh("define", str(xml))
        self.defined = True
        self.virsh("start", self.identifier)
        run([str(self.repo / "usr/bin/vm-wait"), self.identifier], timeout=180)
        self.exec("mkdir -p /opt/jan; mountpoint -q /opt/jan || mount -t virtiofs opt-jan /opt/jan")
        # QGA can answer before SSH key generation and the normal boot target.
        self.exec('''for _ in $(seq 1 20); do
    if systemctl is-active --quiet multi-user.target && (systemctl is-active --quiet sshd || systemctl is-active --quiet ssh) &&
       ip route show default | grep -q . && timeout 2 getent hosts example.com >/dev/null; then
        test -e /opt/jan/setup/vm-cli
        exit 0
    fi
    sleep 1
done
echo 'Timed out waiting for boot, SSH, DHCP and DNS' >&2
exit 1''')

    def exec(self, script):
        return run([str(self.repo / "usr/bin/vm-exec"), self.identifier, "--argv", "bash", "-euc", 'set -o pipefail\ntrap \'echo "Guest command failed at line $LINENO: $BASH_COMMAND" >&2\' ERR\n' + script], timeout=90)

    def stop(self):
        self.virsh("shutdown", self.identifier)
        deadline = time.monotonic() + 120
        while self.virsh("domstate", self.identifier) != "shut off":
            if time.monotonic() > deadline:
                raise ToolError("Disposable guest did not shut down cleanly")
            time.sleep(1)

    def cleanup(self):
        if self.defined:
            # Only our fresh UUID is ever stopped or undefined.
            if self.virsh("domstate", self.identifier) != "shut off":
                self.virsh("destroy", self.identifier)
            self.virsh("undefine", self.identifier)
            self.defined = False






CHECK = """
test "$(systemctl get-default)" = multi-user.target
if systemctl is-active --quiet display-manager.service; then exit 1; fi
for unit in qemu-guest-agent systemd-networkd systemd-resolved; do
    systemctl is-active --quiet "$unit"
done
if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then :; else exit 1; fi
ip route show default | grep -q .
getent hosts example.com >/dev/null
for tool in mc htop git fzf lazygit curl wget unzip tar gzip xz zstd python3 gdu aria2c fish starship ncdu nano mosh rg rsync pwgen telnet jdupes just bats tmux; do
    command -v "$tool" >/dev/null
done
for tool in go zim Xorg; do
    if command -v "$tool"; then echo "Unexpected GUI/compiler tool: $tool" >&2; exit 1; fi
done
if command -v rpm >/dev/null; then
    if rpm -qa --qf '%{NAME}\\n' | grep -E '^(xfce4|xorg-x11-server|plasma6|chromium|google-chrome|brave-browser|brave-origin)'; then exit 1; fi
else
    if dpkg-query -W -f='${Package}\\n' | grep -E '^(xfce4|xserver-xorg-core|plasma-desktop|chromium|google-chrome|brave-browser)$'; then exit 1; fi
fi
test -s /etc/machine-id
test -f /home/jan/.bashrc
test -L /usr/local/bin/vm-exec
test -e /usr/local/bin/vm-exec
test "$(findmnt -n -t virtiofs -o SOURCE --target /opt/jan/setup/vm-cli)" = opt-jan
if mount -o remount,rw /opt/jan; then :; fi
if touch /opt/jan/.golden-write-test; then rm /opt/jan/.golden-write-test; exit 1; fi
tmux -L golden-check new-session -d -s check sleep 60
tmux -L golden-check has-session -t '=check'
tmux -L golden-check kill-server
test "$(blockdev --getsize64 /dev/vda)" = 107374182400
test "$(blockdev --getsize64 "$(findmnt -n -o SOURCE --target /)")" = 4294967296
test "$(blockdev --getsize64 /dev/vdb)" = 2254857830400
test "$(blockdev --getsize64 /dev/vdb1)" = 6442450944
test "$(blockdev --getsize64 /dev/vdc)" = 1073741824
test "$(findmnt -n -t ext4 -o SOURCE --target /home/jan)" = /dev/vdb1
grep -q '^/dev/vdc1 ' /proc/swaps
test "$(findmnt -n -t virtiofs -o SOURCE --target /opt)" = host-opt
runuser -u jan -- sh -c 'printf jan-owned > /home/jan/doc/.jan-write-check'
test "$(findmnt -n -t virtiofs -o SOURCE --target /home/jan/doc)" = host-docs
cat /etc/machine-id
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
"""


def wait_provision(guest, log):
    deadline = time.monotonic() + 1800
    while time.monotonic() < deadline:
        try:
            status = guest.exec("systemctl show golden-provision.service -p ActiveState -p Result -p ExecMainStatus")
        except ToolError:
            status = "transport unavailable"
        if "ActiveState=failed" in status:
            raise ToolError("Guest provisioning failed:\n" + guest.exec("tail -n 60 /var/log/golden-provision.log"))
        if "ActiveState=active" in status:
            if "ExecMainStatus=0" not in status or "Result=success" not in status:
                raise ToolError("Unsuccessful provisioning state: " + status)
            log.write_text(guest.exec("cat /var/log/golden-provision.log"))
            return
        print("Waiting for guest CLI provisioning...", flush=True)
        time.sleep(10)
    raise ToolError("CLI provisioning exceeded 30 minutes")


def check_clone(candidate, repo, directory, key, index):
    overlays = clone_bundle(candidate, directory, f"check-{index}")
    guest = Guest(overlays, repo, directory)
    try:
        guest.start()
        identity = guest.exec(CHECK).splitlines()
        if len(identity) < 2 or not re.fullmatch(r"[0-9a-f]{32}", identity[-2]):
            raise ToolError("Clone did not generate a valid machine identity")
        # QGA is the trusted enrollment channel. Only a temporary clone gets a key.
        host_key = guest.exec("cat /etc/ssh/ssh_host_ed25519_key.pub")
        public = shlex.quote(key.with_suffix(".pub").read_text().strip())
        guest.exec('group=$(id -gn jan); install -d -m 700 -o jan -g "$group" /home/jan/.ssh; '
                   f"printf '%s\\n' {public} > /home/jan/.ssh/authorized_keys; "
                   'chown "jan:$group" /home/jan/.ssh/authorized_keys; chmod 600 /home/jan/.ssh/authorized_keys; '
                   "usermod -p '*' jan")
        known = directory / f"known-hosts-{index}"
        known.write_text("[127.0.0.1]:" + str(guest.port) + " " + host_key + "\n")
        run(["ssh", "-F", "/dev/null", "-i", str(key), "-p", str(guest.port), "-o", "BatchMode=yes",
             "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
             "-o", f"UserKnownHostsFile={known}", "-o", "GlobalKnownHostsFile=/dev/null",
             "jan@127.0.0.1", "test \"$(id -un)\" = jan"], timeout=30)
        guest.stop()
        return {"machine_id": identity[-2], "host_key": host_key, "ssh": "passed"}
    finally:
        guest.cleanup()
        for overlay in overlays.values():
            overlay.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--golden", action="store_true", required=True)
    parser.add_argument("--base", type=Path, help="verified vm-image-build boot image")
    parser.add_argument("--distro", choices=("debian", "ubuntu"), help="build the distro boot input automatically")
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="checkout to mount as /opt/jan")
    parser.add_argument("--output-dir", type=Path, default=Path.home() / ".local/share/libvirt/images/dotfiles-golden")
    args = parser.parse_args()
    repo = args.repo.resolve(strict=True)
    if not (repo / "setup/vm-cli").is_file():
        raise ToolError("Run from the dotfiles checkout or select it with --repo")
    if args.base is None:
        if args.distro is None:
            raise ToolError("Select --base or --distro debian/ubuntu")
        from vm_cloud import build_boot
        args.base = build_boot(args.distro)
    base = args.base.resolve(strict=True)
    for tool in ("virsh", "virt-customize", "virt-sparsify", "virt-resize", "guestfish", "qemu-img", "ssh", "ssh-keygen", "jq"):
        if not shutil.which(tool):
            raise ToolError("Required golden-image tool missing: " + tool)
    source = read_json(base.with_suffix(".manifest.json"))
    if source.get("builder") != "dotfiles/usr/bin/vm-image-build" or source.get("image_sha256") != digest(base):
        raise ToolError("Base must match a verified vm-image-build manifest")
    if json.loads(run(["qemu-img", "info", "--output=json", str(base)])).get("backing-filename"):
        raise ToolError("Boot input must be standalone")
    distro = source.get("config", {}).get("distro", "tumbleweed")
    if args.distro is not None and args.distro != distro:
        raise ToolError("Boot input does not match the requested distribution")
    tree, builder, recipe = recipe_fingerprints(repo, source["image_sha256"])
    args.output_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    private(args.output_dir)
    with (args.output_dir / f".{distro}.build.lock").open("a") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        destination = args.output_dir / f"golden-cli-{distro}-{recipe[:16]}"
        manifest = destination / "manifest.json"
        if destination.exists():
            saved, _ = read_bundle(destination)
            if saved.get("recipe_sha256") != recipe:
                raise ToolError("Existing golden image does not match its manifest")
            print(destination)
            return
        # Failed builds keep private diagnostics; no approved/current pointer exists.
        directory = Path(tempfile.mkdtemp(prefix="build-", dir=args.output_dir))
        disk = directory / "builder.qcow2"
        guest = Guest(disk, repo, directory)
        try:
            print("Building text-only candidate in " + str(directory), flush=True)
            run(["qemu-img", "create", "-f", "qcow2", "-F", "qcow2", "-b", str(base), str(disk)])
            bootstrap = directory / "bootstrap.sh"
            bootstrap.write_text(BOOTSTRAP)
            customize_script(disk, bootstrap, resolve_dns=True)
            guest.start()
            guest.exec("cat > /etc/systemd/system/golden-provision.service <<'EOF'\n"
                       "[Unit]\nDescription=Golden CLI provisioning\nAfter=network-online.target\nWants=network-online.target\n"
                       "[Service]\nType=oneshot\nRemainAfterExit=yes\nTimeoutStartSec=1800\n"
                       "ExecStart=/opt/jan/setup/vm-cli\nStandardOutput=append:/var/log/golden-provision.log\n"
                       "StandardError=append:/var/log/golden-provision.log\nEOF\n"
                       "systemctl daemon-reload; systemctl start --no-block golden-provision.service")
            wait_provision(guest, directory / "provision.log")
            packages = guest.exec("if command -v rpm >/dev/null; then rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\\n'; else dpkg-query -W -f='${Package} ${Version}\\n'; fi | sort")
            trim = guest.exec("fstrim -av")
            guest.stop()
            guest.cleanup()
            seal = directory / "seal.sh"
            seal.write_text(SEAL)
            customize_script(disk, seal)
            candidate_dir = directory / "candidate"
            candidate_dir.mkdir(mode=0o700)
            print("Migrating root/home to bounded filesystems; expanding sparse virtual disks...", flush=True)
            candidates = split_image(disk, candidate_dir)
            before = {role: digest(path) for role, path in candidates.items()}
            for path in candidates.values():
                os.chmod(path, 0o444)
            key = directory / "test-key"
            run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)])
            checks = []
            for index in (1, 2):
                print(f"Testing fresh clone {index}/2 (CLI, read-only mount, SSH and identity)...", flush=True)
                checks.append(check_clone(candidates, repo, directory, key, index))
            if checks[0]["machine_id"] == checks[1]["machine_id"] or checks[0]["host_key"] == checks[1]["host_key"]:
                raise ToolError("Cloned guests reused machine identity or SSH host keys")
            if any(digest(path) != before[role] for role, path in candidates.items()) or digest(base) != source["image_sha256"]:
                raise ToolError("A base image changed during golden-image validation")
            if checkout_digest(repo) != tree or builder_digest() != builder:
                raise ToolError("Provisioning checkout or builder changed during build; rerun against stable inputs")
            record = {"schema_version": 2, "builder": "dotfiles/vm-image-build --golden", "profile": "cli", "distro": distro,
                      "recipe_sha256": recipe, "checkout_sha256": tree, "builder_sha256": builder,
                      "disks": {role: {"file": path.name, "sha256": before[role], **LAYOUT[role], **(candidates.root_info if role == "root" else {}),
                                                "allocated_bytes": path.stat().st_blocks * 512}
                                for role, path in candidates.items()},
                      "boot_manifest": source, "guest_user": "jan",
                      "host_shares": {"host-opt": {"target": "/opt", "access": "ro"},
                                      "host-docs": {"target": "/home/jan/doc", "access": "rw"},
                                      "opt-jan": {"target": "/opt/jan", "access": "ro"}}, "packages": packages.splitlines(), "clones": checks,
                      "compaction": {"trim": trim, "method": "virt-sparsify + standalone qcow2",
                                     "source_chain_allocated_bytes": (disk.stat().st_blocks + base.stat().st_blocks) * 512,
                                     "golden_allocated_bytes": sum(path.stat().st_blocks * 512 for path in candidates.values())}}
            atomic_json(candidate_dir / "manifest.json", record)
            os.rename(candidate_dir, destination)
            disk.unlink()
            print("Built and verified text-only golden image:", flush=True)
            print(destination, flush=True)
        except BaseException:
            print("Build diagnostics retained in " + str(directory), flush=True)
            raise
        finally:
            guest.cleanup()
            for secret in (directory / "test-key", directory / "test-key.pub"):
                secret.unlink(missing_ok=True)
