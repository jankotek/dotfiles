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
VM_WAIT="$OPT_JAN/usr/bin/vm-wait"

IMAGES_DIR="$HOME/.local/share/libvirt/images"
BASE_VM="${BASE_VM:-xub26}"
BASE_DISK="${BASE_DISK:-$IMAGES_DIR/${BASE_VM}.qcow2}"
SETUP_SCRIPT="${SETUP_SCRIPT:-/opt/jan/setup/vm-xub26}"
VM_NAME_PREFIX="${VM_NAME_PREFIX:-test}"

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1
# shellcheck source=test/lib/vm-clone.bash
source "$SCRIPT_DIR/lib/vm-clone.bash"
init_test_clone "$VM_NAME_PREFIX"
prepare_test_clone

echo "=== Creating test VM: $VM_NAME ==="
echo "Base VM: $BASE_VM"
echo "Base disk: $BASE_DISK"
echo "Setup script: $SETUP_SCRIPT"

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

# Define only after the template checks succeed.
define_test_clone

echo "Starting VM..."
"$VM_WAIT" "$VM_NAME"

# 4. Run provisioning
echo ""
echo "=== Running $SETUP_SCRIPT ==="
"$VM_EXEC" "$VM_NAME" "$SETUP_SCRIPT"

# 5. Reboot to apply systemd services and other changes
echo ""
echo "=== Cold restarting VM ==="
virsh -c qemu:///session shutdown "$VM_NAME" 2>/dev/null || true
for _ in $(seq 1 30); do
    [[ "$(virsh -c qemu:///session domstate "$VM_NAME" 2>/dev/null)" == "shut off" ]] && break
    sleep 1
done
if [[ "$(virsh -c qemu:///session domstate "$VM_NAME" 2>/dev/null)" != "shut off" ]]; then
    virsh -c qemu:///session destroy "$VM_NAME"
fi
virsh -c qemu:///session start "$VM_NAME" >/dev/null
"$VM_WAIT" "$VM_NAME"

# Wait for desktop session (autologin + XFCE startup)
echo "Waiting for desktop session..."
for _ in $(seq 1 30); do
    if "$VM_EXEC" "$VM_NAME" "pgrep -u jan xfce4-panel >/dev/null && pgrep -u jan xfdesktop >/dev/null" &>/dev/null; then
        echo "Desktop ready"
        break
    fi
    sleep 1
done

# 6. Run tests (the provisioner installs bats with the standard CLI tools)
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
