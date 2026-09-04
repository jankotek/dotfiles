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

# On AC power the machine must never auto-suspend/sleep: it should stay running
# whenever the adapter is plugged in. PowerDevil stores this per-user in
# powerdevilrc as [AC][SuspendAndShutdown] AutoSuspendAction, where 0 = do
# nothing and any non-zero value = suspend/sleep/hibernate after the idle
# timeout. The suite runs as root, so check every user whose home is under
# /home/* (excludes root and system accounts) — any one of them suspending
# would put the box to sleep.
@test "no user auto-suspends on AC power" {
    command -v plasmashell &>/dev/null || skip "plasma not installed"
    local failed=0
    while IFS=: read -r user _ uid _ _ home _; do
        [[ "$home" == /home/* ]] || continue
        local rc="$home/.config/powerdevilrc"
        local action
        action="$(ini_value "$rc" '[AC][SuspendAndShutdown]' AutoSuspendAction)"
        if [[ -n "$action" && "$action" != "0" ]]; then
            echo "AutoSuspendAction=$action on AC for user $user ($rc)" >&2
            failed=1
        fi
    done < <(getent passwd)
    if [[ "$failed" -ne 0 ]]; then
        echo "machine would suspend while plugged in; it must stay always-on" >&2
        return 1
    fi
}
