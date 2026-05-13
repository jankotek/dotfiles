#!/bin/bash
#
# Clone the base xub VM, provision it, run bats tests, then clean up.
#
# Usage: ./test-vm-deploy.sh [--keep]
#   --keep  Do not destroy the VM after tests (for debugging)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPT_JAN="${SCRIPT_DIR%/test}"
VM_EXEC="$OPT_JAN/usr/bin/vm-exec"
VM_WAIT="$OPT_JAN/usr/bin/vm-start-and-wait"

BASE_VM="xub"
BASE_DISK="$HOME/.local/share/libvirt/images/xub.qcow2"
IMAGES_DIR="$HOME/.local/share/libvirt/images"

VM_NAME="test-$(date +%y%m%d-%H%M)"
VM_DISK="$IMAGES_DIR/${VM_NAME}.qcow2"

KEEP=0
if [[ "${1:-}" == "--keep" ]]; then
    KEEP=1
fi

cleanup() {
    if [[ $KEEP -eq 1 ]]; then
        echo ""
        echo "=== VM '$VM_NAME' kept for debugging ==="
        echo "  virsh console $VM_NAME"
        echo "  $VM_EXEC $VM_NAME <command>"
        echo "  To remove: virsh destroy $VM_NAME; virsh undefine $VM_NAME; rm $VM_DISK"
        return
    fi
    echo ""
    echo "=== Cleaning up ==="
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" 2>/dev/null || true
    rm -f "$VM_DISK"
    echo "Removed VM '$VM_NAME' and disk overlay"
}
trap cleanup EXIT

echo "=== Creating test VM: $VM_NAME ==="

# 0. Base VM must be shut off (QEMU locks the backing file)
BASE_STATE=$(virsh domstate "$BASE_VM" 2>/dev/null || echo "unknown")
if [[ "$BASE_STATE" == "running" ]]; then
    echo "Base VM '$BASE_VM' is running — shutting it down for cloning..."
    virsh shutdown "$BASE_VM"
    for i in $(seq 1 60); do
        [[ "$(virsh domstate "$BASE_VM" 2>/dev/null)" == "shut off" ]] && break
        sleep 1
    done
    if [[ "$(virsh domstate "$BASE_VM" 2>/dev/null)" != "shut off" ]]; then
        echo "Timeout waiting for $BASE_VM to shut down, forcing off..."
        virsh destroy "$BASE_VM"
    fi
    echo "Base VM stopped"
fi

# 1. Create qcow2 overlay backed by the base image
echo "Creating overlay disk..."
qemu-img create -f qcow2 -b "$BASE_DISK" -F qcow2 "$VM_DISK"

# 2. Export base VM XML and patch it for the clone
XML=$(virsh dumpxml "$BASE_VM" --inactive)

# Remove uuid (libvirt will generate a new one)
XML=$(echo "$XML" | sed '/<uuid>/d')

# Replace VM name
XML=$(echo "$XML" | sed "s|<name>$BASE_VM</name>|<name>$VM_NAME</name>|")

# Replace disk path
XML=$(echo "$XML" | sed "s|$BASE_DISK|$VM_DISK|")

# Generate a new MAC address (keep 52:54:00 prefix)
NEW_MAC="52:54:00:$(printf '%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))"
XML=$(echo "$XML" | sed -E "s|<mac address='52:54:00:[^']+'\/>|<mac address='$NEW_MAC'/>|")

# 3. Define and start the clone
echo "Defining VM..."
echo "$XML" | virsh define /dev/stdin

echo "Starting VM..."
"$VM_WAIT" "$VM_NAME"

# 4. Run provisioning
echo ""
echo "=== Running setup/vm-xub24 ==="
"$VM_EXEC" "$VM_NAME" "/opt/jan/setup/vm-xub24"

# 5. Reboot to apply systemd services and other changes
echo ""
echo "=== Rebooting VM ==="
virsh reboot "$VM_NAME"
sleep 5
"$VM_WAIT" "$VM_NAME"

# Wait for desktop session (autologin + XFCE startup)
echo "Waiting for desktop session..."
for i in $(seq 1 30); do
    if "$VM_EXEC" "$VM_NAME" "pgrep -u jan xfce4-panel" &>/dev/null; then
        echo "Desktop ready"
        break
    fi
    sleep 1
done

# 6. Install bats inside the VM
echo ""
echo "=== Installing bats ==="
"$VM_EXEC" "$VM_NAME" "DEBIAN_FRONTEND=noninteractive apt-get install -y bats"

# 7. Run tests
echo ""
echo "=== Running tests ==="
set +e
"$VM_EXEC" "$VM_NAME" "/opt/jan/test/test-vm.sh"
TEST_EXIT=$?
set -e

echo ""
if [[ $TEST_EXIT -eq 0 ]]; then
    echo "=== ALL TESTS PASSED ==="
else
    echo "=== TESTS FAILED (exit code: $TEST_EXIT) ==="
fi

exit $TEST_EXIT
