"""Standalone dotfiles base-image builder; no qdistro checkout or disk inputs."""

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import tomllib
from urllib.parse import urlparse

from herdr_tools.common import ToolError, atomic_json, private, read_json


def run(argv, timeout=1200):
    try:
        result = subprocess.run(argv, text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise ToolError(f"{argv[0]} timed out") from error
    if result.returncode:
        raise ToolError(f"{argv[0]} failed: {result.stderr.strip() or result.stdout[-3000:]}")
    return result.stdout.strip()


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def load_config(path):
    with path.open("rb") as stream:
        config = tomllib.load(stream)
    if set(config) != {"arch", "snapshot", "cloud_url", "cloud_sha256", "signing_fingerprint", "disk_size", "selinux"}:
        raise ToolError("Unexpected or missing image configuration fields")
    if config["arch"] != platform.machine() or config["selinux"] not in ("enforcing", "permissive"):
        raise ToolError("Unsupported image architecture or SELinux profile")
    if not re.fullmatch(r"[0-9a-f]{64}", config["cloud_sha256"]) or not re.fullmatch(r"[A-F0-9]{40}", config["signing_fingerprint"]):
        raise ToolError("Invalid cloud digest or signing fingerprint")
    if not isinstance(config["snapshot"], str) or not re.fullmatch(r"20[0-9]{6}", config["snapshot"]):
        raise ToolError("Invalid Tumbleweed snapshot")
    try:
        snapshot = datetime.strptime(config["snapshot"], "%Y%m%d").date()
    except ValueError as error:
        raise ToolError("Invalid snapshot date") from error
    age = (datetime.now(timezone.utc).date() - snapshot).days
    if not 0 <= age <= 14:
        raise ToolError("Choose a Tumbleweed build snapshot no more than 14 days old")
    url = urlparse(config["cloud_url"])
    if url.scheme != "https" or not url.netloc or not url.path.endswith(".qcow2") or url.query or url.fragment:
        raise ToolError("Cloud URL must be an HTTPS qcow2 URL")
    if not re.fullmatch(r"[1-9][0-9]*G", config["disk_size"]):
        raise ToolError("Disk size must be a whole positive number of GiB")
    return config


def verify_cloud(image, checksum, signature, key, config):
    """Bind authenticated checksum to both the artifact name and explicit pin."""
    with tempfile.TemporaryDirectory(prefix="vm-image-gpg-") as temporary:
        home = Path(temporary)
        info = run(["gpg", "--homedir", str(home), "--batch", "--show-keys", "--with-colons", str(key)])
        fingerprint = next((line.split(":")[9] for line in info.splitlines() if line.startswith("fpr:")), None)
        if fingerprint != config["signing_fingerprint"]:
            raise ToolError("Unexpected openSUSE signing-key fingerprint")
        keyring = home / "keyring.gpg"
        run(["gpg", "--homedir", str(home), "--batch", "--dearmor", "--output", str(keyring), str(key)])
        status = run(["gpgv", "--homedir", str(home), "--status-fd", "1", "--keyring", str(keyring), str(signature), str(checksum)])
        valid = [line.split()[2] for line in status.splitlines() if line.startswith("[GNUPG:] VALIDSIG ")]
        if config["signing_fingerprint"] not in valid:
            raise ToolError("Cloud checksum was not signed by the pinned openSUSE key")
    basename = Path(urlparse(config["cloud_url"]).path).name
    signed = []
    for line in checksum.read_text().splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1].lstrip("*") == basename:
            signed.append(fields[0].lower())
    if signed != [config["cloud_sha256"]] or digest(image) != config["cloud_sha256"]:
        raise ToolError("Cloud image, signed artifact checksum and configured digest do not match")


def download_cloud(config, cache, key):
    directory = cache / config["cloud_sha256"]
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    private(directory)
    image, checksum, signature = [directory / name for name in ("cloud.qcow2", "cloud.sha256", "cloud.sha256.asc")]
    with (directory / "download.lock").open("a") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        if all(path.exists() for path in (image, checksum, signature)):
            verify_cloud(image, checksum, signature, key, config)
            print("Verified existing dotfiles cloud-download cache", flush=True)
            return image
        with tempfile.TemporaryDirectory(prefix="download-", dir=directory) as temporary:
            staging = Path(temporary)
            for path, suffix in ((image, ""), (checksum, ".sha256"), (signature, ".sha256.asc")):
                print("Downloading original openSUSE cloud input" + suffix, flush=True)
                run(["curl", "--fail", "--location", "--silent", "--show-error", "--output", str(staging / path.name), config["cloud_url"] + suffix])
            verify_cloud(staging / image.name, staging / checksum.name, staging / signature.name, key, config)
            for path in (image, checksum, signature):
                os.replace(staging / path.name, path)
        print("Cloud signature and pinned digest verified", flush=True)
        return image


def guest_recipe(config):
    snapshot = config["snapshot"]
    repositories = f'''#!/bin/bash
set -euo pipefail
mkdir -p /etc/zypp/repos.d /etc/zypp/services.d
find /etc/zypp/repos.d -maxdepth 1 -name '*.repo' -delete
find /etc/zypp/services.d -maxdepth 1 -name '*.service' -delete
cat > /etc/zypp/repos.d/dotfiles-snapshot.repo <<'EOF'
[dotfiles-oss]
name=Dotfiles Tumbleweed {snapshot}
enabled=1
autorefresh=0
keeppackages=1
baseurl=https://download.opensuse.org/history/{snapshot}/tumbleweed/repo/oss/
gpgcheck=1
[dotfiles-nonoss]
name=Dotfiles Tumbleweed non-OSS {snapshot}
enabled=1
autorefresh=0
keeppackages=1
baseurl=https://download.opensuse.org/history/{snapshot}/tumbleweed/repo/non-oss/
gpgcheck=1
EOF
zypper -n refresh
zypper -n install --no-recommends qemu-guest-agent spice-vdagent tmux openssh-server rsync python3
'''
    finalize = f'''#!/bin/bash
set -euo pipefail
id worker >/dev/null 2>&1 || useradd -m -u 1000 -s /bin/bash worker
passwd -l root >/dev/null
passwd -l worker >/dev/null
printf 'baseweed-dotfiles\\n' > /etc/hostname
systemctl enable qemu-guest-agent sshd serial-getty@ttyS0.service
systemctl mask cloud-init.service cloud-init-local.service cloud-config.service cloud-final.service cloud-init.target jeos-firstboot.service jeos-firstboot-snapshot.service
mkdir -p /etc/sysconfig /etc/systemd/system/qemu-guest-agent.service.d /etc/ssh/sshd_config.d
printf 'FILTER_RPC_ARGS=""\\n' > /etc/sysconfig/qemu-ga
printf '[Service]\\nUMask=0022\\n' > /etc/systemd/system/qemu-guest-agent.service.d/umask.conf
printf '%s\\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' 'PermitRootLogin no' > /etc/ssh/sshd_config.d/00-dotfiles.conf
sed -i 's/^SELINUX=.*/SELINUX={config["selinux"]}/' /etc/selinux/config
sed -i -e 's/^GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="console"/' -e 's/^GRUB_GFXPAYLOAD_LINUX=.*/GRUB_GFXPAYLOAD_LINUX="text"/' /etc/default/grub
grep -q '^GRUB_TERMINAL_OUTPUT=' /etc/default/grub || printf 'GRUB_TERMINAL_OUTPUT="console"\\n' >> /etc/default/grub
grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub || printf 'GRUB_GFXPAYLOAD_LINUX="text"\\n' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
rm -f /etc/ssh/ssh_host_*key /etc/ssh/ssh_host_*key.pub /var/lib/systemd/random-seed
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
find /tmp /var/tmp -mindepth 1 -delete
'''
    return repositories, finalize


def main():
    share = Path(__file__).resolve().parents[1] / "share/vm-image"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=share / "tumbleweed.toml")
    parser.add_argument("--output-dir", type=Path, default=Path.home() / ".local/share/libvirt/images/dotfiles-baseweed")
    parser.add_argument("--cache-dir", type=Path, default=Path.home() / ".cache/dotfiles/vm-images")
    args = parser.parse_args()
    config = load_config(args.config)
    key = share / "opensuse-tumbleweed-signing-key.asc"
    for tool in ("curl", "gpg", "gpgv", "qemu-img", "guestfish", "virt-cat", "virt-resize", "virt-customize"):
        if not shutil.which(tool):
            raise ToolError(f"Required image-builder tool missing: {tool}")
    args.output_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    private(args.output_dir)
    recipe = hashlib.sha256(Path(__file__).read_bytes() + args.config.read_bytes() + key.read_bytes()).hexdigest()
    destination = args.output_dir / f"baseweed-{config['snapshot']}-{recipe[:12]}.qcow2"
    manifest = destination.with_suffix(".manifest.json")
    with (args.output_dir / ".build.lock").open("a") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        if destination.exists():
            recorded = read_json(manifest)
            if recorded["recipe_sha256"] != recipe or recorded["image_sha256"] != digest(destination):
                raise ToolError("Existing immutable image does not match its build manifest")
            print(destination, flush=True)
            return
        cloud = download_cloud(config, args.cache_dir, key)
        release = run(["virt-cat", "-a", str(cloud), "/etc/os-release"])
        if not re.search(r'^VERSION_ID="?' + config["snapshot"] + r'"?$', release, re.M):
            raise ToolError("Cloud release differs from the pinned package repository snapshot")
        roots = run(["guestfish", "--ro", "-a", str(cloud), "-i", "inspect-get-roots"]).splitlines()
        if len(roots) != 1 or not re.fullmatch(r"/dev/[a-z]+[0-9]+", roots[0]):
            raise ToolError("Cloud image does not have one supported root partition")
        with tempfile.TemporaryDirectory(prefix="build-", dir=args.output_dir) as temporary:
            staging = Path(temporary)
            candidate = staging / "baseweed.qcow2"
            run(["qemu-img", "create", "-f", "qcow2", str(candidate), config["disk_size"]])
            print("Expanding verified cloud disk to " + config["disk_size"], flush=True)
            run(["virt-resize", "--quiet", "--expand", roots[0], str(cloud), str(candidate)])
            recipe_scripts = []
            for index, body in enumerate(guest_recipe(config)):
                path = staging / f"recipe-{index}.sh"
                path.write_text(body)
                recipe_scripts.append(path)
            print("Provisioning independent dotfiles baseweed boot image offline", flush=True)
            run(["virt-customize", "--memsize", "4096", "--smp", "2", "-a", str(candidate),
                 "--run", str(recipe_scripts[0]), "--run", str(recipe_scripts[1])])
            run(["qemu-img", "check", str(candidate)])
            info = json.loads(run(["qemu-img", "info", "--output=json", str(candidate)]))
            if info.get("backing-filename"):
                raise ToolError("Built base must have no backing-file dependency")
            record = {"schema_version": 1, "config": config, "recipe_sha256": recipe, "image_sha256": digest(candidate),
                      "source": "original-opensuse-cloud", "builder": "dotfiles/usr/bin/vm-image-build"}
            os.chmod(candidate, 0o444)
            # A failure never replaces an existing immutable image or approved pointer.
            atomic_json(manifest, record)
            os.rename(candidate, destination)
        print("Built a new standalone dotfiles base image:", flush=True)
        print(destination, flush=True)
