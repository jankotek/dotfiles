#!/bin/bash
# Install the shared text-only package set. Tumbleweed supplies apt via zypper-aptitude.
set -euo pipefail
if (( EUID != 0 )); then
    echo 'ERROR: install-cli-packages.sh must run as root' >&2
    exit 1
fi
SETUP_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# shellcheck source=setup/common-cli-packages.sh
source "$SETUP_DIR/common-cli-packages.sh"
export DEBIAN_FRONTEND=noninteractive
command -v apt >/dev/null || { echo 'ERROR: apt is required (zypper-aptitude on Tumbleweed)' >&2; exit 1; }
apt -y update
apt "${JAN_APT_INSTALL_OPTIONS[@]}" install \
    "${JAN_COMMON_CLI_PACKAGES[@]}" "${JAN_DISTRO_CLI_PACKAGES[@]}" \
    ca-certificates diffutils iftop tmux openssh-server util-linux
