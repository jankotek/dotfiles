#!/bin/bash
#
# Run tests for host system (basic + host-plasma).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export OPT_JAN="${SCRIPT_DIR%/test}"

if ! command -v bats &>/dev/null; then
    echo "ERROR: bats is required; install it before running tests" >&2
    exit 1
fi

echo "=== Host tests ==="
echo "OPT_JAN=$OPT_JAN"
echo ""

bats "$SCRIPT_DIR"/basic/ "$SCRIPT_DIR"/host/ "$@"
