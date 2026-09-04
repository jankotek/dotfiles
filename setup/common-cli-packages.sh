# shellcheck shell=bash
# shellcheck disable=SC2034 # This array is consumed by the sourcing setup scripts.
# CLI package names shared by openSUSE Tumbleweed and Ubuntu 26.04.
# Ubuntu 24.04 intentionally keeps its own list because not every package
# below is available from its configured repositories.

readonly -a JAN_COMMON_CLI_PACKAGES=(
    mc
    htop
    git
    lazygit
    curl
    powertop
    fish
    iotop
    ncdu
    nano
    mosh
    ripgrep
    rsync
    pwgen
    telnet
    jdupes
    just
    bats
    zim
)
