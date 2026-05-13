#!/bin/bash
#
# Run tests for VM (basic + vm).
# Installs bats if not found.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export OPT_JAN="${SCRIPT_DIR%/test}"

# Install bats-core if not available
if ! command -v bats &>/dev/null; then
    echo "bats not found, installing..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y bats
    elif command -v zypper &>/dev/null; then
        sudo zypper install -y bats
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y bats
    else
        echo "Cannot install bats automatically. Install it manually."
        exit 1
    fi
fi

echo "=== VM tests ==="
echo "OPT_JAN=$OPT_JAN"
echo ""

bats "$SCRIPT_DIR"/basic/ "$SCRIPT_DIR"/vm/ "$@"
