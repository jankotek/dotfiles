"""Golden-image disk bundles with bounded filesystems and sparse expansion space."""

import json
import os
from pathlib import Path
import re
import subprocess

from herdr_tools.common import ToolError, read_json
from vm_image import digest, run

GIB = 1024 ** 3
LAYOUT = {
    "root": {"virtual_bytes": 100 * GIB, "partition_bytes": 4 * GIB, "filesystem": "xfs"},
    "home": {"virtual_bytes": 2100 * GIB, "partition_bytes": 6 * GIB, "filesystem": "ext4"},
    "swap": {"virtual_bytes": GIB, "partition_bytes": GIB - 2 * 1024 ** 2, "filesystem": "swap"},
}


def fish(disks, commands, readonly=False):
    argv = ["guestfish"] + (["--ro"] if readonly else [])
    for disk in disks:
        argv += ["--format=qcow2", "-a", str(disk)]
    result = subprocess.run(argv, input="\n".join(commands) + "\n", text=True,
                            capture_output=True, timeout=1200)
    if result.returncode:
        raise ToolError("guestfish failed: " + result.stderr.strip())
    return result.stdout.strip()


def quote(value):
    return json.dumps(str(value))


def create_swap(path):
    """New blank file, including a fresh swap UUID; never inherit old swap pages."""
    run(["qemu-img", "create", "-f", "qcow2", str(path), "1G"])
    fish([path], ["run", "part-init /dev/sda gpt", "part-add /dev/sda p 2048 -2049",
                  "part-set-gpt-type /dev/sda 1 0657FD6D-A4AB-43C4-84E5-0933C84B4F4F",
                  "mkswap /dev/sda1 label:JAN-SWAP"])


class DiskSet(dict):
    """Paths plus the actual root filesystem/partition contract for the manifest."""
    root_info = None


def split_image(source, directory):
    """Preserve source GPT numbers and boot references while migrating root/home."""
    root_tar, home_tar = directory / "root.tar", directory / "home.tar"
    roots = fish([source], ["run", "inspect-os"], readonly=True).splitlines()
    if len(roots) != 1 or not re.fullmatch(r"/dev/sda[0-9]+", roots[0]):
        raise ToolError("Expected one plain-partition cloud root filesystem")
    source_root = roots[0]
    root_num = int(re.search(r"[0-9]+$", source_root).group())
    metadata = fish([source], ["run", f"vfs-type {source_root}", f"vfs-uuid {source_root}",
                              f"vfs-label {source_root}", "part-list /dev/sda"], readonly=True)
    lines = metadata.splitlines()
    if lines[0] not in ("xfs", "ext4") or not re.fullmatch(r"[0-9a-f-]{36}", lines[1]):
        raise ToolError("Unsupported cloud root filesystem")
    root_fs, root_uuid, root_label = lines[:3]
    fish([source], ["run", f"mount-ro {source_root} /",
                   f"tar-out /home {quote(home_tar)} numericowner:true xattrs:true selinux:true acls:true",
                   f"tar-out / {quote(root_tar)} numericowner:true excludes:./home xattrs:true selinux:true acls:true"], readonly=True)
    small_root = directory / "root-small.qcow2"
    small_home = directory / "home-small.qcow2"
    parts = []
    for block in re.findall(r"\{(.*?)\}", metadata, re.S):
        fields = dict(re.findall(r"(part_num|part_start|part_end|part_size): (\d+)", block))
        if fields:
            parts.append({key: int(value) for key, value in fields.items()})
    numbers = [part["part_num"] for part in parts]
    if root_num not in numbers or len(numbers) != len(set(numbers)):
        raise ToolError("Unsupported cloud partition table")
    root_part = next(part for part in parts if part["part_num"] == root_num)
    root_end = root_part["part_start"] // 512 + LAYOUT["root"]["partition_bytes"] // 512 - 1
    # Growing a recreated root must not collide with a preserved boot partition.
    for part in parts:
        if part["part_num"] != root_num and not (part["part_end"] < root_part["part_start"] or part["part_start"] > root_end * 512 + 511):
            raise ToolError("Requested root size overlaps a source boot partition")
    gpt = fish([source], ["run"] + [command for part in parts for command in
                (f"part-get-gpt-type /dev/sda {part['part_num']}",
                 f"part-get-gpt-guid /dev/sda {part['part_num']}")], readonly=True).splitlines()
    for index, part in enumerate(parts):
        part["type"], part["guid"] = gpt[2 * index:2 * index + 2]
    max_number = max(numbers)
    tail = max(root_end * 512 + 512, max(part["part_end"] + 1 for part in parts if part["part_num"] != root_num))
    filler_start = (tail + 2 * 1024 ** 2 + 511) // 512
    small_size = (tail + (max_number + 4) * 1024 ** 2 + GIB - 1) // GIB * GIB
    run(["qemu-img", "create", "-f", "qcow2", str(small_root), str(small_size)])
    commands = [f"add-drive-opts {quote(source)} readonly:true format:qcow2",
                f"add-drive-opts {quote(small_root)} format:qcow2", "run", "part-init /dev/sdb gpt"]
    actual = {part["part_num"]: part for part in parts}
    fillers = []
    # Temporarily occupy GPT gaps so Debian/Ubuntu partition14/15 keep their IDs.
    for number in range(1, max_number + 1):
        if number in actual:
            part = actual[number]
            end = root_end if number == root_num else part["part_end"] // 512
            commands.append(f"part-add /dev/sdb p {part['part_start'] // 512} {end}")
            commands.append(f"part-set-gpt-type /dev/sdb {number} {part['type']}")
            commands.append(f"part-set-gpt-guid /dev/sdb {number} {part['guid']}")
        else:
            commands.append(f"part-add /dev/sdb p {filler_start} {filler_start + 2047}")
            filler_start += 2048
            fillers.append(number)
    commands += [f"part-del /dev/sdb {number}" for number in fillers]
    commands += ["copy-device-to-device /dev/sda /dev/sdb size:446"]
    commands += [f"copy-device-to-device /dev/sda{number} /dev/sdb{number} sparse:true"
                 for number in numbers if number != root_num]
    fish([], commands)
    label_option = " " + quote("label:" + root_label) if root_label else ""
    features = " features:^orphan_file,^metadata_csum_seed" if root_fs == "ext4" else ""
    fish([small_root], ["run", f"mkfs {root_fs} /dev/sda{root_num}{label_option}{features}",
                       f"set-uuid /dev/sda{root_num} {root_uuid}", f"mount /dev/sda{root_num} /",
                       f"tar-in {quote(root_tar)} / xattrs:true selinux:true acls:true",
                       "mkdir-p /home", "mkdir-p /opt/jan", "mkdir-p /boot/efi"])
    run(["qemu-img", "create", "-f", "qcow2", str(small_home), "7G"])
    home_end = 2048 + LAYOUT["home"]["partition_bytes"] // 512 - 1
    home_uuid = fish([small_home], ["run", "part-init /dev/sda gpt",
                                  f"part-add /dev/sda p 2048 {home_end}",
                                  "mkfs ext4 /dev/sda1 label:JAN-HOME",
                                  "mount /dev/sda1 /",
                                  f"tar-in {quote(home_tar)} / xattrs:true selinux:true acls:true",
                                  "vfs-uuid /dev/sda1"])
    fstab = fish([small_root], ["run", f"mount-ro /dev/sda{root_num} /", "cat /etc/fstab"], readonly=True)
    retained = []
    for line in fstab.splitlines():
        fields = line.split()
        if len(fields) >= 3 and not line.lstrip().startswith("#"):
            if fields[1] in ("/home", "/opt", "/opt/jan", "/home/jan/doc") or fields[2] == "swap":
                continue
        retained.append(line)
    retained += ["", "# Golden image: dedicated home and swap disks",
                 f"UUID={home_uuid} /home ext4 defaults 0 2",
                 "LABEL=JAN-SWAP none swap defaults 0 0", "",
                 "# Host shares (virtiofs tags supplied by the VM definition)",
                 "host-opt /opt virtiofs ro,nofail,x-systemd.automount 0 0",
                 "opt-jan /opt/jan virtiofs ro,nofail,x-systemd.automount 0 0",
                 "host-docs /home/jan/doc virtiofs rw,nofail,x-systemd.automount 0 0", ""]
    fstab_file = directory / "fstab"
    fstab_file.write_text("\n".join(retained))
    fish([small_root], ["run", f"mount /dev/sda{root_num} /", f"upload {quote(fstab_file)} /etc/fstab",
                       "chmod 0644 /etc/fstab"])
    result = DiskSet()
    result.root_info = {"filesystem": root_fs, "partition_number": root_num,
                        "partition_start_bytes": root_part["part_start"]}
    for role, small in (("root", small_root), ("home", small_home)):
        target = directory / (role + ".qcow2")
        # Sparsify only 5/7 GiB disks; never zero-fill a 2100 GiB virtual tail.
        run(["virt-sparsify", "--format", "qcow2", "--convert", "qcow2", str(small), str(target)])
        run(["qemu-img", "resize", str(target), str(LAYOUT[role]["virtual_bytes"])])
        fish([target], ["run", "part-expand-gpt /dev/sda"])
        run(["qemu-img", "check", str(target)])
        result[role] = target
        small.unlink()
    result["swap"] = directory / "swap.qcow2"
    create_swap(result["swap"])
    root_tar.unlink()
    home_tar.unlink()
    return result


def read_bundle(path):
    """Resolve only manifest-owned, standalone disk files in a private bundle."""
    path = Path(path).resolve(strict=True)
    manifest = path / "manifest.json" if path.is_dir() else path
    record = read_json(manifest)
    if record.get("schema_version") != 2 or set(record.get("disks", {})) != set(LAYOUT):
        raise ToolError("Expected a three-disk golden-image manifest")
    disks = {}
    for role, item in record["disks"].items():
        if item.get("file") != role + ".qcow2":
            raise ToolError("Unexpected golden disk filename")
        disk = manifest.parent / item["file"]
        if disk.is_symlink() or item.get("sha256") != digest(disk):
            raise ToolError("Golden disk does not match its manifest: " + role)
        info = json.loads(run(["qemu-img", "info", "--output=json", str(disk)]))
        if info.get("backing-filename") or info["virtual-size"] != LAYOUT[role]["virtual_bytes"]:
            raise ToolError("Unexpected backing chain or disk capacity: " + role)
        disks[role] = disk
    return record, disks


def clone_bundle(disks, directory, prefix):
    result = {}
    for role in ("root", "home"):
        overlay = directory / f"{prefix}-{role}.qcow2"
        run(["qemu-img", "create", "-f", "qcow2", "-F", "qcow2", "-b", str(disks[role]), str(overlay)])
        result[role] = overlay
    result["swap"] = directory / f"{prefix}-swap.qcow2"
    create_swap(result["swap"])
    return result
