#!/usr/bin/env bats
# Verify host-specific setup: Plasma desktop on Wayland

load ../helpers

@test "plasmashell is installed" {
    assert_command plasmashell
}

@test "kwin_wayland is installed" {
    assert_command kwin_wayland
}

@test "wayland session is active" {
    [[ "$XDG_SESSION_TYPE" == "wayland" ]] || \
    [[ -n "$WAYLAND_DISPLAY" ]]
}

@test "not running inside a VM" {
    ! systemd-detect-virt -q -v 2>/dev/null
}

@test "konsole is installed" {
    assert_command konsole
}

@test "installer-created user received curated Plasma and Konsole defaults" {
    assert_file "$JAN_HOME/.config/kdeglobals"
    assert_file "$JAN_HOME/.config/konsolerc"
    assert_file_contains "$JAN_HOME/.config/konsolerc" '^DefaultProfile=dark.profile$'
    assert_file "$JAN_HOME/.local/share/konsole/dark.profile"
    assert_file "$JAN_HOME/.local/share/konsole/white.profile"
    [[ $(stat -c %U "$JAN_HOME/.local/share/konsole/dark.profile") == \
        $(stat -c %U "$JAN_HOME") ]]
}

@test "Sweet palette is the referenced KDE system default" {
    [[ -L /usr/local/etc/xdg/kdeglobals ]]
    [[ $(readlink /usr/local/etc/xdg/kdeglobals) == \
        /usr/local/share/color-schemes/Sweet-dark.colors ]]
    assert_file /usr/local/share/color-schemes/Sweet-dark.colors
    [[ -L /etc/profile.d/jan-xdg-local-first.sh ]]
    local configured_dirs
    configured_dirs=$(XDG_CONFIG_DIRS=/etc/xdg:/usr/local/etc/xdg:/usr/etc/xdg \
        sh -c '. /etc/profile.d/jan-xdg-local-first.sh; printf "%s" "$XDG_CONFIG_DIRS"')
    [[ $configured_dirs == \
        /usr/local/etc/xdg:/etc/xdg:/usr/etc/xdg ]]
}

@test "system monospace defaults to JetBrains Mono" {
    [[ $(fc-match --format '%{family}\n' monospace | head -1) == \
        "JetBrains Mono" ]]
    assert_file_contains \
        /usr/local/etc/xdg/katerc \
        '^Text Font=JetBrains Mono,10,'
    assert_file_contains \
        /usr/local/etc/xdg/kwriterc \
        '^Text Font=JetBrains Mono,10,'
}

@test "dolphin is installed" {
    assert_command dolphin
}

@test "virt-manager desktop file has GDK_BACKEND=x11" {
    assert_file /usr/share/applications/virt-manager.desktop
    assert_file_contains /usr/share/applications/virt-manager.desktop 'GDK_BACKEND=x11'
}

@test "remote-viewer desktop file has GDK_BACKEND=x11" {
    assert_file /usr/share/applications/remote-viewer.desktop
    assert_file_contains /usr/share/applications/remote-viewer.desktop 'GDK_BACKEND=x11'
}

# Read a key from a specific section of an INI-style file.
# Section header is matched literally, e.g. "[AC][SuspendAndShutdown]".
# Prints the value (empty if section/key absent).
ini_value() {
    local file="$1" section="$2" key="$3"
    [[ -f "$file" ]] || return 0
    awk -F= -v sec="$section" -v key="$key" '
        $0 == sec { insec = 1; next }
        /^\[/     { insec = 0 }
        insec && $1 == key { gsub(/[ \t\r]+$/, "", $2); print $2; exit }
    ' "$file"
}

# On AC power the machine must never suspend, whether idle or with the lid
# closed. setup-ac-no-suspend locks PowerDevil's AC actions system-wide with
# immutable [$i] keys, so a user's own powerdevilrc cannot re-enable suspend
# from any logged-in session, and tells logind to ignore the lid on AC.
@test "PowerDevil AC suspend actions are locked system-wide" {
    command -v plasmashell &>/dev/null || skip "plasma not installed"
    assert_file /etc/xdg/powerdevilrc
    [[ "$(ini_value /etc/xdg/powerdevilrc '[AC][SuspendAndShutdown]' 'AutoSuspendAction[$i]')" == 0 ]]
    [[ "$(ini_value /etc/xdg/powerdevilrc '[AC][SuspendAndShutdown]' 'LidAction[$i]')" == 0 ]]
}

@test "logind ignores the lid switch on AC power" {
    local value
    value=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager HandleLidSwitchExternalPower)
    [[ "$value" == 's "ignore"' ]]
}

# Docked lid handling and logind's own idle action bypass the AC setting above;
# both default to ignore and must stay that way.
@test "logind has no docked-lid or idle suspend" {
    local prop value
    for prop in HandleLidSwitchDocked IdleAction; do
        value=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
            org.freedesktop.login1.Manager "$prop")
        [[ "$value" == 's "ignore"' ]] || { echo "$prop=$value" >&2; return 1; }
    done
}
