#!/bin/bash
#
# Tumbleweed counterpart to test-vm-deploy.sh. Clones the `baseweed` VM,
# runs setup/vm-baseweed, reboots, then runs the basic suite and the portable
# systemd-networkd checks from the VM suite.
#
# Usage: ./test-vm-baseweed-deploy.sh [--keep]
#   BASE_VM=name       Override the base domain (default: baseweed)
#   BASE_DISK=path     Override its qcow2 disk path
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPT_JAN="${SCRIPT_DIR%/test}"
VM_EXEC="$OPT_JAN/usr/bin/vm-exec"
VM_WAIT="$OPT_JAN/usr/bin/vm-start-and-wait"

BASE_VM="${BASE_VM:-baseweed}"
BASE_DISK="${BASE_DISK:-$HOME/.local/share/libvirt/images/${BASE_VM}.qcow2}"
IMAGES_DIR="$HOME/.local/share/libvirt/images"

VM_NAME="weedtest-$(date +%y%m%d-%H%M%S)-$$"
VM_DISK="$IMAGES_DIR/${VM_NAME}.qcow2"

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1
VM_DISK_CREATED=0
VM_DEFINED=0

cleanup() {
    if [[ $KEEP -eq 1 && ( $VM_DEFINED -eq 1 || $VM_DISK_CREATED -eq 1 ) ]]; then
        echo ""
        echo "=== VM '$VM_NAME' kept for debugging ==="
        echo "  virsh -c qemu:///session console $VM_NAME"
        echo "  $VM_EXEC $VM_NAME <command>"
        echo "  Remove: virsh -c qemu:///session destroy $VM_NAME; virsh -c qemu:///session undefine $VM_NAME; rm $VM_DISK"
        return
    fi
    if [[ $VM_DEFINED -eq 1 || $VM_DISK_CREATED -eq 1 ]]; then
        echo ""
        echo "=== Cleaning up ==="
        if [[ $VM_DEFINED -eq 1 ]]; then
            virsh -c qemu:///session destroy "$VM_NAME" 2>/dev/null || true
            virsh -c qemu:///session undefine "$VM_NAME" 2>/dev/null || true
        fi
        if [[ $VM_DISK_CREATED -eq 1 ]]; then
            rm -f -- "$VM_DISK"
        fi
        echo "Removed resources created for '$VM_NAME'"
    fi
}
trap cleanup EXIT

echo "=== Creating test VM: $VM_NAME (Tumbleweed) ==="
echo "Base VM: $BASE_VM"
echo "Base disk: $BASE_DISK"

if ! virsh -c qemu:///session dominfo "$BASE_VM" >/dev/null 2>&1; then
    echo "ERROR: base VM not found: $BASE_VM" >&2
    exit 1
fi
if [[ ! -f "$BASE_DISK" ]]; then
    echo "ERROR: base disk not found: $BASE_DISK" >&2
    exit 1
fi
if virsh -c qemu:///session dominfo "$VM_NAME" >/dev/null 2>&1 || [[ -e "$VM_DISK" ]]; then
    echo "ERROR: generated disposable VM name already exists: $VM_NAME" >&2
    exit 1
fi

BASE_STATE=$(virsh -c qemu:///session domstate "$BASE_VM")
if [[ "$BASE_STATE" == "running" ]]; then
    echo "Base VM '$BASE_VM' is running — shutting it down for cloning..."
    virsh -c qemu:///session shutdown "$BASE_VM"
    for _ in {1..60}; do
        [[ "$(virsh -c qemu:///session domstate "$BASE_VM" 2>/dev/null)" == "shut off" ]] && break
        sleep 1
    done
    if [[ "$(virsh -c qemu:///session domstate "$BASE_VM" 2>/dev/null)" != "shut off" ]]; then
        echo "ERROR: base VM did not shut down; refusing to force-stop it: $BASE_VM" >&2
        exit 1
    fi
fi
if [[ "$(virsh -c qemu:///session domstate "$BASE_VM")" != "shut off" ]]; then
    echo "ERROR: base VM must be shut off: $BASE_VM" >&2
    exit 1
fi

BASE_XML=$(virsh -c qemu:///session dumpxml "$BASE_VM" --inactive)

echo "Creating overlay disk..."
qemu-img create -f qcow2 -b "$BASE_DISK" -F qcow2 "$VM_DISK"
VM_DISK_CREATED=1

# Tumbleweed defaults to SELinux enforcing with a strict qemu-guest-agent
# domain (`virt_qemu_ga_t`) that blocks the agent from running mount,
# systemctl, and most file ops. We need permissive mode for the test
# harness to work; the base image is left untouched. enforcing remains
# the production default — this is a test-only relaxation.
echo "Setting SELinux to permissive on clone..."
virt-customize -q -a "$VM_DISK" \
    --edit '/etc/selinux/config:s/^SELINUX=enforcing/SELINUX=permissive/'

XML=$BASE_XML
XML=$(echo "$XML" | sed '/<uuid>/d')
XML=$(echo "$XML" | sed "s|<name>$BASE_VM</name>|<name>$VM_NAME</name>|")
XML=$(echo "$XML" | sed "s|$BASE_DISK|$VM_DISK|")
NEW_MAC="52:54:00:$(printf '%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))"
XML=$(echo "$XML" | sed -E "s|<mac address='52:54:00:[^']+'/>|<mac address='$NEW_MAC'/>|")

# virtiofs requires shared guest memory. The minimal qdistro template used to
# bootstrap baseweed does not need it itself, so add it to the test clone.
if ! grep -q '<memoryBacking>' <<<"$XML"; then
    XML=$(echo "$XML" | sed "/<currentMemory/a\\
  <memoryBacking>\\
    <source type='memfd'/>\\
    <access mode='shared'/>\\
  </memoryBacking>")
fi

# Add a virtiofs filesystem entry that exposes this repository under the
# 'opt-jan' tag. Mount it manually at /opt/jan without changing guest fstab.
EXTRA_FS=$(cat <<EOF
    <filesystem type='mount' accessmode='passthrough'>
      <driver type='virtiofs'/>
      <source dir='${OPT_JAN}/'/>
      <target dir='opt-jan'/>
    </filesystem>
EOF
)
# Insert before the closing </devices> tag.
XML=$(echo "$XML" | awk -v extra="$EXTRA_FS" '
    /<\/devices>/ { print extra }
    { print }
')

require_clone_xml() {
    local pattern=$1
    local description=$2
    if ! grep -Fq "$pattern" <<<"$XML"; then
        echo "ERROR: clone XML is missing $description" >&2
        exit 1
    fi
}
require_clone_xml '<memoryBacking>' 'memoryBacking required by virtiofs'
require_clone_xml "<source type='memfd'/>" 'memfd memory backing'
require_clone_xml "<access mode='shared'/>" 'shared memory access'
require_clone_xml "<driver type='virtiofs'/>" 'virtiofs driver'
require_clone_xml "<target dir='opt-jan'/>" 'opt-jan virtiofs target'
require_clone_xml "<source file='$VM_DISK'/>" \
    'disposable disk source (BASE_DISK must match the base domain XML)'

echo "Defining VM..."
echo "$XML" | virsh -c qemu:///session define /dev/stdin
VM_DEFINED=1

echo "Starting VM..."
"$VM_WAIT" "$VM_NAME"

echo ""
echo "=== Mounting /opt/jan (virtiofs tag opt-jan) ==="
"$VM_EXEC" "$VM_NAME" "mkdir -p /opt/jan && /usr/bin/mount -t virtiofs opt-jan /opt/jan && ls /opt/jan/setup/"

echo ""
echo "=== Running setup/vm-baseweed ==="
"$VM_EXEC" "$VM_NAME" "/opt/jan/setup/vm-baseweed"

echo ""
echo "=== Rebooting VM ==="
virsh -c qemu:///session reboot "$VM_NAME"
sleep 5
"$VM_WAIT" "$VM_NAME"

echo ""
echo "=== Re-mounting /opt/jan after reboot ==="
"$VM_EXEC" "$VM_NAME" "mkdir -p /opt/jan && mountpoint -q /opt/jan || /usr/bin/mount -t virtiofs opt-jan /opt/jan"

echo ""
echo "=== Running basic and portable network bats suites ==="
set +e
"$VM_EXEC" "$VM_NAME" \
    "OPT_JAN=/opt/jan bats /opt/jan/test/basic/ /opt/jan/test/vm/network.bats /opt/jan/test/vm/provisioned-home.bats"
TEST_EXIT=$?
set -e

echo ""
if [[ $TEST_EXIT -eq 0 ]]; then
    echo "=== ALL TESTS PASSED ==="
else
    echo "=== TESTS FAILED (exit code: $TEST_EXIT) ==="
fi

exit $TEST_EXIT
