#!/bin/bash
# Shared ownership checks for disposable deployment-test overlays.

init_test_clone() {
    local prefix=$1
    [[ $prefix =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "Invalid VM prefix: $prefix" >&2; return 2; }
    mkdir -p "$IMAGES_DIR"
    VM_WORK_DIR=$(mktemp -d "$IMAGES_DIR/${prefix}-$(date +%y%m%d-%H%M%S)-XXXXXX")
    VM_NAME=${VM_WORK_DIR##*/}
    VM_DISK="$VM_WORK_DIR/root.qcow2"
    VM_NVRAM="$VM_WORK_DIR/nvram.fd"
    VM_DEFINED=0
    VM_UUID=
    trap cleanup_test_clone EXIT
    if virsh -c qemu:///session dominfo "$VM_NAME" >/dev/null 2>&1; then
        echo "ERROR: generated VM name already exists: $VM_NAME" >&2
        return 1
    fi
}

cleanup_test_clone() {
    local rc=$? xml
    trap - EXIT
    if [[ $KEEP == 1 ]]; then
        echo "Test resources retained: $VM_NAME ($VM_WORK_DIR)"
        return "$rc"
    fi
    # Check before undefine --nvram, which itself deletes firmware storage.
    ensure_test_storage_unused || return 1
    if [[ $VM_DEFINED == 1 ]]; then
        # Address by recorded UUID, never by a name another run might reuse.
        if [[ $(virsh -c qemu:///session domuuid "$VM_NAME") != "$VM_UUID" ]]; then
            echo "ERROR: VM identity changed; retaining $VM_WORK_DIR" >&2
            return 1
        fi
        xml=$(virsh -c qemu:///session dumpxml "$VM_UUID" --inactive) || return 1
        if ! validate_clone_xml <<<"$xml"; then
            echo "ERROR: VM storage changed; retaining $VM_WORK_DIR" >&2
            return 1
        fi
        virsh -c qemu:///session destroy "$VM_UUID" 2>/dev/null || true
        if [[ $(virsh -c qemu:///session domstate "$VM_UUID") != 'shut off' ]]; then
            echo "ERROR: test VM did not stop; retaining $VM_WORK_DIR" >&2
            return 1
        fi
        if ! virsh -c qemu:///session undefine "$VM_UUID" --nvram; then
            echo "ERROR: could not undefine test VM; retaining $VM_WORK_DIR" >&2
            return 1
        fi
        VM_DEFINED=0
    fi
    ensure_test_storage_unused || return 1
    rm -rf -- "$VM_WORK_DIR"
    return "$rc"
}

ensure_test_storage_unused() {
    local domains other xml mode
    domains=$(virsh -c qemu:///session list --all --uuid) || return 1
    while IFS= read -r other; do
        [[ -n $other ]] || continue
        [[ $VM_DEFINED != 1 || $other != "$VM_UUID" ]] || continue
        # Runtime hotplug and next-boot configuration can reference different
        # storage. Retain the workspace if either view cannot be established.
        for mode in active inactive; do
            if [[ $mode == active ]]; then
                xml=$(virsh -c qemu:///session dumpxml "$other") || return 1
            else
                xml=$(virsh -c qemu:///session dumpxml "$other" --inactive) || return 1
            fi
            if ! python3 -c '
from pathlib import Path
import sys, xml.etree.ElementTree as E
directory=Path(sys.argv[1]).resolve()
for node in E.fromstring(sys.stdin.read()).iter():
    for value in [*node.attrib.values(), node.text or ""]:
        value=value.strip()
        if value.startswith("/") and Path(value).resolve().is_relative_to(directory):
            raise SystemExit("another domain references test storage")
' "$VM_WORK_DIR" <<<"$xml"; then
                echo "ERROR: cannot establish exclusive storage ownership; retaining $VM_WORK_DIR" >&2
                return 1
            fi
        done
    done <<<"$domains"
}

validate_clone_xml() {
    python3 -c '
import pathlib, sys, xml.etree.ElementTree as E
root = E.fromstring(sys.stdin.read())
disk, nvram = map(pathlib.Path, sys.argv[1:3])
sources = root.findall("./devices/disk[@device=\"disk\"]/source")
assert len(sources) == 1 and sources[0].get("file") == str(disk), "unexpected disk source"
node = root.find("./os/nvram")
assert node is None or (node.text or "").strip() == str(nvram), "shared NVRAM"
' "$VM_DISK" "$VM_NVRAM"
}

prepare_test_clone() {
    local base_state source_disk source_nvram
    base_state=$(virsh -c qemu:///session domstate "$BASE_VM")
    [[ $base_state == 'shut off' ]] || {
        echo "ERROR: base VM must be shut off: $BASE_VM" >&2
        return 1
    }
    [[ -f $BASE_DISK ]] || { echo "ERROR: missing base disk: $BASE_DISK" >&2; return 1; }
    BASE_DISK=$(realpath -e "$BASE_DISK")
    BASE_XML=$(virsh -c qemu:///session dumpxml "$BASE_VM" --inactive)
    source_disk=$(python3 -c '
import sys, xml.etree.ElementTree as E
nodes=E.fromstring(sys.stdin.read()).findall("./devices/disk[@device=\"disk\"]/source")
assert len(nodes)==1 and nodes[0].get("file"), "expected one file-backed base disk"
print(nodes[0].get("file"))
' <<<"$BASE_XML")
    [[ $(realpath -e "$source_disk") == "$(realpath -e "$BASE_DISK")" ]] || {
        echo "ERROR: BASE_DISK does not match the base domain" >&2
        return 1
    }
    qemu-img create -f qcow2 -b "$BASE_DISK" -F qcow2 "$VM_DISK"
    # virt-clone handles arbitrary MAC prefixes, multiple interfaces, UUIDs,
    # XML escaping, and a distinct firmware-variable path.
    XML=$(virt-clone --connect qemu:///session --original "$BASE_VM" \
        --name "$VM_NAME" --file "$VM_DISK" --nvram "$VM_NVRAM" \
        --preserve-data --print-xml)
    validate_clone_xml <<<"$XML"
    VM_UUID=$(python3 -c 'import sys,xml.etree.ElementTree as E; print(E.fromstring(sys.stdin.read()).findtext("uuid"))' <<<"$XML")
    [[ $VM_UUID =~ ^[a-fA-F0-9-]{36}$ ]] || return 1
    source_nvram=$(python3 -c 'import sys,xml.etree.ElementTree as E; print(E.fromstring(sys.stdin.read()).findtext("./os/nvram", "").strip())' <<<"$BASE_XML")
    if [[ -n $source_nvram ]]; then
        cp --reflink=auto -- "$source_nvram" "$VM_NVRAM"
    fi
}

define_test_clone() {
    validate_clone_xml <<<"$XML"
    printf '%s\n' "$XML" | virsh -c qemu:///session define /dev/stdin
    VM_DEFINED=1
}
