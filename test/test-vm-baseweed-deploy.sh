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
VM_WAIT="$OPT_JAN/usr/bin/vm-wait"

BASE_VM="${BASE_VM:-baseweed}"
BASE_DISK="${BASE_DISK:-$HOME/.local/share/libvirt/images/${BASE_VM}.qcow2}"
IMAGES_DIR="$HOME/.local/share/libvirt/images"

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1
# shellcheck source=test/lib/vm-clone.bash
source "$SCRIPT_DIR/lib/vm-clone.bash"
init_test_clone weedtest
prepare_test_clone

echo "=== Creating test VM: $VM_NAME (Tumbleweed) ==="

# Tumbleweed defaults to SELinux enforcing with a strict qemu-guest-agent
# domain (`virt_qemu_ga_t`) that blocks the agent from running mount,
# systemctl, and most file ops. We need permissive mode for the test
# harness to work; the base image is left untouched. enforcing remains
# the production default — this is a test-only relaxation.
echo "Setting SELinux to permissive on clone..."
virt-customize -q -a "$VM_DISK" \
    --edit '/etc/selinux/config:s/^SELINUX=enforcing/SELINUX=permissive/'

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
define_test_clone

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
