#!/bin/bash
#
# Clone the base Xubuntu 26.04 VM, provision it with setup/vm-xub26,
# run bats tests, then clean up.
#
# Expected local base:
#   VM:   xub26
#   disk: ~/.local/share/libvirt/images/xub26.qcow2
#
# Usage: ./test-vm-xub26-deploy.sh [--keep]
# Override with BASE_VM=/ BASE_DISK= if the local base has a different name.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export BASE_VM="${BASE_VM:-xub26}"
export BASE_DISK="${BASE_DISK:-$HOME/.local/share/libvirt/images/${BASE_VM}.qcow2}"
export SETUP_SCRIPT="${SETUP_SCRIPT:-/opt/jan/setup/vm-xub26}"
export VM_NAME_PREFIX="${VM_NAME_PREFIX:-xub26-test}"

exec "$SCRIPT_DIR/test-vm-deploy.sh" "$@"
