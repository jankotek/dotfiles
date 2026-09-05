# shellcheck shell=bash
# shellcheck disable=SC2034 # This array is consumed by the sourcing setup scripts.
# CLI package names shared by the supported VM provisioners.

readonly -a JAN_COMMON_CLI_PACKAGES=(
    mc
    htop
    git
    lazygit
    curl
    aria2
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
