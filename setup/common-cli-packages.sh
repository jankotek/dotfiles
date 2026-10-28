# shellcheck shell=bash
# shellcheck disable=SC2034 # This array is consumed by the sourcing setup scripts.
# CLI packages shared by host and VM provisioners. Language package managers
# (pip, pipx, npm, pnpm, yarn, uv, gem, ...) are optional, never base tools.

readonly -a JAN_COMMON_CLI_PACKAGES=(
    mc
    htop
    git
    fzf
    lazygit
    curl
    wget
    unzip
    tar
    gzip
    zstd
    python3
    gdu
    aria2
    powertop
    fish
    starship
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

# xz has different package names on Ubuntu and openSUSE.
if command -v zypper >/dev/null 2>&1; then
    readonly -a JAN_DISTRO_CLI_PACKAGES=(xz)
else
    readonly -a JAN_DISTRO_CLI_PACKAGES=(xz-utils)
fi
