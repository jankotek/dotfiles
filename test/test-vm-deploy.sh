#!/bin/bash
#
# Clone a base VM, provision it, run bats tests, then clean up.
#
# Usage: ./test-vm-deploy.sh [--keep]
#   --keep  Do not destroy the VM after tests (for debugging)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPT_JAN="${SCRIPT_DIR%/test}"
VM_EXEC="$OPT_JAN/usr/bin/vm-exec"
VM_WAIT="$OPT_JAN/usr/bin/vm-start-and-wait"

IMAGES_DIR="$HOME/.local/share/libvirt/images"
BASE_VM="${BASE_VM:-xub}"
BASE_DISK="${BASE_DISK:-$IMAGES_DIR/${BASE_VM}.qcow2}"
SETUP_SCRIPT="${SETUP_SCRIPT:-/opt/jan/setup/vm-xub24}"
VM_NAME_PREFIX="${VM_NAME_PREFIX:-test}"

VM_NAME="${VM_NAME_PREFIX}-$(date +%y%m%d-%H%M)"
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
echo "Base VM: $BASE_VM"
echo "Base disk: $BASE_DISK"
echo "Setup script: $SETUP_SCRIPT"

if [[ ! -e "$BASE_DISK" ]]; then
    echo "ERROR: base disk not found: $BASE_DISK" >&2
    exit 1
fi

# 0. Base VM must be shut off (QEMU locks the backing file)
BASE_STATE=$(virsh domstate "$BASE_VM" 2>/dev/null || echo "unknown")
if [[ "$BASE_STATE" == "unknown" ]]; then
    echo "ERROR: base VM not found: $BASE_VM" >&2
    exit 1
fi
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

BASE_XML=$(virsh dumpxml "$BASE_VM" --inactive)

require_template_xml() {
    local pattern=$1
    local message=$2
    if ! grep -Eq "$pattern" <<<"$BASE_XML"; then
        echo "ERROR: base VM '$BASE_VM' is missing $message" >&2
        exit 1
    fi
}

require_template_dir_entry() {
    local dir=$1
    local entry=$2
    local message=$3
    if ! virt-ls -a "$BASE_DISK" "$dir" 2>/dev/null | grep -Fxq "$entry"; then
        echo "ERROR: base disk '$BASE_DISK' is missing $message" >&2
        exit 1
    fi
}

require_template_file_contains() {
    local path=$1
    local pattern=$2
    local message=$3
    if ! virt-cat -a "$BASE_DISK" "$path" 2>/dev/null | grep -Eq "$pattern"; then
        echo "ERROR: base disk '$BASE_DISK' is missing $message" >&2
        exit 1
    fi
}

require_template_xml '<memoryBacking>' 'shared-memory configuration required by virtiofs'
require_template_xml "<source type='memfd'/>" 'memfd memory backing'
require_template_xml "<access mode='shared'/>" 'shared memory access'
require_template_xml "<target type='virtio' name='org.qemu.guest_agent.0'/>" 'QEMU guest-agent channel'
require_template_xml "<driver type='virtiofs'/>" 'virtiofs driver for /opt/jan'
require_template_xml "<target dir='opt-jan'/>" 'opt-jan virtiofs target'

VIDEO_VRAM=$(awk '
    /<video>/ { in_video=1 }
    in_video && /<model / {
        if (match($0, /vram='\''[0-9]+'\''/)) {
            value=substr($0, RSTART + 6, RLENGTH - 7)
            print value
        } else {
            print 0
        }
        exit
    }
' <<<"$BASE_XML")
if [[ "${VIDEO_VRAM:-0}" -lt 131072 ]]; then
    echo "ERROR: base VM '$BASE_VM' video memory is ${VIDEO_VRAM:-0} KiB; expected at least 131072 KiB" >&2
    exit 1
fi

require_template_dir_entry /etc/systemd/system/multi-user.target.wants qemu-guest-agent.service 'enabled qemu-guest-agent service'
require_template_dir_entry /etc/systemd/system/multi-user.target.wants spice-vdagentd.service 'enabled spice-vdagentd service'
require_template_file_contains /etc/fstab '^[[:space:]]*opt-jan[[:space:]]+/opt/jan[[:space:]]+virtiofs[[:space:]]' '/opt/jan virtiofs fstab entry'

# 1. Create qcow2 overlay backed by the base image
echo "Creating overlay disk..."
qemu-img create -f qcow2 -b "$BASE_DISK" -F qcow2 "$VM_DISK"

# 2. Export base VM XML and patch it for the clone
XML=$BASE_XML

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
echo "=== Running $SETUP_SCRIPT ==="
"$VM_EXEC" "$VM_NAME" "$SETUP_SCRIPT"

# 5. Reboot to apply systemd services and other changes
echo ""
echo "=== Cold restarting VM ==="
virsh shutdown "$VM_NAME" 2>/dev/null || true
for i in $(seq 1 30); do
    [[ "$(virsh domstate "$VM_NAME" 2>/dev/null)" == "shut off" ]] && break
    sleep 1
done
if [[ "$(virsh domstate "$VM_NAME" 2>/dev/null)" != "shut off" ]]; then
    virsh destroy "$VM_NAME"
fi
virsh start "$VM_NAME" >/dev/null
"$VM_WAIT" "$VM_NAME"

# Wait for desktop session (autologin + XFCE startup)
echo "Waiting for desktop session..."
for i in $(seq 1 30); do
    if "$VM_EXEC" "$VM_NAME" "pgrep -u jan xfce4-panel >/dev/null && pgrep -u jan xfdesktop >/dev/null" &>/dev/null; then
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
