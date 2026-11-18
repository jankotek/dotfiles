# shellcheck shell=bash
# shellcheck disable=SC2034 # This array is consumed by the sourcing setup scripts.
# CLI packages shared by host and VM provisioners. Language package managers
# (pip, pipx, npm, pnpm, yarn, uv, gem, ...) are optional, never base tools.

readonly -a JAN_COMMON_CLI_PACKAGES=(
    mc
    htop
    btop
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
    iotop-c
    gdu
    nano
    mosh
    ripgrep
    rsync
    pwgen
    telnet
    jdupes
    hashdeep
    just
    bats
    # Claude Code's Linux sandbox needs both; Codex brings its own bwrap.
    bubblewrap
    socat
)

# xz has different package names on Debian and openSUSE. openSUSE's git is a
# meta package that adds perl-Git for git-svn and send-email; git-core is the
# git command itself. Debian and Ubuntu have no git-core package.
if command -v zypper >/dev/null 2>&1; then
    readonly -a JAN_DISTRO_CLI_PACKAGES=(xz git-core)
else
    readonly -a JAN_DISTRO_CLI_PACKAGES=(xz-utils git)
fi

# zypper's apt frontend parses options before the action and uses aptitude's spelling.
if command -v zypper >/dev/null 2>&1; then
    readonly -a JAN_APT_INSTALL_OPTIONS=(-y --without-recommends)
else
    readonly -a JAN_APT_INSTALL_OPTIONS=(-y --no-install-recommends)
fi
