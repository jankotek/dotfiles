#!/bin/bash
#
# Tumbleweed counterpart to test-vm-deploy.sh. Clones the `baseweed` VM,
# runs setup/vm-baseweed, reboots, then runs the basic suite and the portable
# systemd-networkd checks from the VM suite.
#
# Usage: ./test-vm-baseweed-deploy.sh [--keep]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPT_JAN="${SCRIPT_DIR%/test}"
VM_EXEC="$OPT_JAN/usr/bin/vm-exec"
VM_WAIT="$OPT_JAN/usr/bin/vm-start-and-wait"

BASE_VM="${BASE_VM:-baseweed}"
BASE_DISK="${BASE_DISK:-$HOME/.local/share/libvirt/images/${BASE_VM}.qcow2}"
IMAGES_DIR="$HOME/.local/share/libvirt/images"

VM_NAME="weedtest-$(date +%y%m%d-%H%M)"
VM_DISK="$IMAGES_DIR/${VM_NAME}.qcow2"

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

cleanup() {
    if [[ $KEEP -eq 1 ]]; then
        echo ""
        echo "=== VM '$VM_NAME' kept for debugging ==="
        echo "  virsh -c qemu:///session console $VM_NAME"
        echo "  $VM_EXEC $VM_NAME <command>"
        echo "  Remove: virsh -c qemu:///session destroy $VM_NAME; virsh -c qemu:///session undefine $VM_NAME; rm $VM_DISK"
        return
    fi
    echo ""
    echo "=== Cleaning up ==="
    virsh -c qemu:///session destroy "$VM_NAME" 2>/dev/null || true
    virsh -c qemu:///session undefine "$VM_NAME" 2>/dev/null || true
    rm -f "$VM_DISK"
    echo "Removed VM '$VM_NAME' and disk overlay"
}
trap cleanup EXIT

echo "=== Creating test VM: $VM_NAME (Tumbleweed) ==="

BASE_STATE=$(virsh -c qemu:///session domstate "$BASE_VM" 2>/dev/null || echo "unknown")
if [[ "$BASE_STATE" == "running" ]]; then
    echo "Base VM '$BASE_VM' is running — shutting it down for cloning..."
    virsh -c qemu:///session shutdown "$BASE_VM"
    for i in $(seq 1 60); do
        [[ "$(virsh -c qemu:///session domstate "$BASE_VM" 2>/dev/null)" == "shut off" ]] && break
        sleep 1
    done
    if [[ "$(virsh -c qemu:///session domstate "$BASE_VM" 2>/dev/null)" != "shut off" ]]; then
        virsh -c qemu:///session destroy "$BASE_VM"
    fi
fi

echo "Creating overlay disk..."
qemu-img create -f qcow2 -b "$BASE_DISK" -F qcow2 "$VM_DISK"

# Tumbleweed defaults to SELinux enforcing with a strict qemu-guest-agent
# domain (`virt_qemu_ga_t`) that blocks the agent from running mount,
# systemctl, and most file ops. We need permissive mode for the test
# harness to work; the base image is left untouched. enforcing remains
# the production default — this is a test-only relaxation.
echo "Setting SELinux to permissive on clone..."
virt-customize -q -a "$VM_DISK" \
    --edit '/etc/selinux/config:s/^SELINUX=enforcing/SELINUX=permissive/'

XML=$(virsh -c qemu:///session dumpxml "$BASE_VM" --inactive)
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

echo "Defining VM..."
echo "$XML" | virsh -c qemu:///session define /dev/stdin

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
echo "=== Running basic/ bats suite ==="
set +e
"$VM_EXEC" "$VM_NAME" \
    "OPT_JAN=/opt/jan bats /opt/jan/test/basic/ && bats --filter 'systemd-networkd|systemd-resolved|NetworkManager' /opt/jan/test/vm/system.bats"
TEST_EXIT=$?
set -e

echo ""
if [[ $TEST_EXIT -eq 0 ]]; then
    echo "=== ALL TESTS PASSED ==="
else
    echo "=== TESTS FAILED (exit code: $TEST_EXIT) ==="
fi

exit $TEST_EXIT
