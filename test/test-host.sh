#!/bin/bash
#
# Run tests for host system (basic + host-plasma).
# Installs bats if not found.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export OPT_JAN="${SCRIPT_DIR%/test}"

# Install bats-core if not available
if ! command -v bats &>/dev/null; then
    echo "bats not found, installing..."
    if command -v zypper &>/dev/null; then
        sudo zypper install -y bats
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y bats
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y bats
    else
        echo "Cannot install bats automatically. Install it manually."
        exit 1
    fi
fi

echo "=== Host tests ==="
echo "OPT_JAN=$OPT_JAN"
echo ""

bats "$SCRIPT_DIR"/basic/ "$SCRIPT_DIR"/host/ "$@"
