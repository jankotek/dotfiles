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
VM_WAIT="$OPT_JAN/usr/bin/vm-wait"

BASE_VM="${BASE_VM:-xub26}"
BASE_DISK="${BASE_DISK:-$HOME/.local/share/libvirt/images/${BASE_VM}.qcow2}"
IMAGES_DIR="$HOME/.local/share/libvirt/images"

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1
# shellcheck source=test/lib/vm-clone.bash
source "$SCRIPT_DIR/lib/vm-clone.bash"
init_test_clone idempo
prepare_test_clone
define_test_clone
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
