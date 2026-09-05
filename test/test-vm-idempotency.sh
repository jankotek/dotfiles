#!/bin/bash
#
# Clone xub26, run setup/vm-xub26 once, drop user-data sentinels, then run
# test/utils/idempotency.bats which re-runs setup and verifies the second
# run is clean and didn't blast user data.
#
# Usage: ./test-vm-idempotency.sh [--keep]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPT_JAN="${SCRIPT_DIR%/test}"
VM_EXEC="$OPT_JAN/usr/bin/vm-exec"
VM_WAIT="$OPT_JAN/usr/bin/vm-start-and-wait"

BASE_VM="${BASE_VM:-xub26}"
BASE_DISK="${BASE_DISK:-$HOME/.local/share/libvirt/images/${BASE_VM}.qcow2}"
IMAGES_DIR="$HOME/.local/share/libvirt/images"

VM_NAME="idempo-$(date +%y%m%d-%H%M)"
VM_DISK="$IMAGES_DIR/${VM_NAME}.qcow2"

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

cleanup() {
    if [[ $KEEP -eq 1 ]]; then
        echo "=== VM '$VM_NAME' kept for debugging ==="
        return
    fi
    virsh -c qemu:///session destroy "$VM_NAME" 2>/dev/null || true
    virsh -c qemu:///session undefine "$VM_NAME" 2>/dev/null || true
    rm -f "$VM_DISK"
}
trap cleanup EXIT

if [[ "$(virsh -c qemu:///session domstate "$BASE_VM" 2>/dev/null)" == "running" ]]; then
    virsh -c qemu:///session shutdown "$BASE_VM"
    for i in $(seq 1 60); do
        [[ "$(virsh -c qemu:///session domstate "$BASE_VM")" == "shut off" ]] && break
        sleep 1
    done
fi

qemu-img create -f qcow2 -b "$BASE_DISK" -F qcow2 "$VM_DISK"

XML=$(virsh -c qemu:///session dumpxml "$BASE_VM" --inactive)
XML=$(echo "$XML" | sed '/<uuid>/d')
XML=$(echo "$XML" | sed "s|<name>$BASE_VM</name>|<name>$VM_NAME</name>|")
XML=$(echo "$XML" | sed "s|$BASE_DISK|$VM_DISK|")
NEW_MAC="52:54:00:$(printf '%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))"
XML=$(echo "$XML" | sed -E "s|<mac address='52:54:00:[^']+'/>|<mac address='$NEW_MAC'/>|")

echo "$XML" | virsh -c qemu:///session define /dev/stdin
"$VM_WAIT" "$VM_NAME"

echo "=== First setup/vm-xub26 ==="
"$VM_EXEC" "$VM_NAME" "/opt/jan/setup/vm-xub26"

echo "=== Run idempotency.bats (re-runs setup/vm-xub26 in setup_file) ==="
set +e
"$VM_EXEC" "$VM_NAME" 'export OPT_JAN=/opt/jan; bats /opt/jan/test/utils/idempotency.bats'
RC=$?
set -e

if [[ $RC -eq 0 ]]; then
    echo "=== ALL IDEMPOTENCY TESTS PASSED ==="
else
    echo "=== TESTS FAILED (exit $RC) ==="
fi
exit $RC
