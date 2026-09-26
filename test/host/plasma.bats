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
# closed. setup-ac-no-suspend sets the system defaults in /etc/xdg/powerdevilrc;
# a user's ~/.config/powerdevilrc value (set by ac-no-suspend or System
# Settings) takes precedence. kreadconfig6 resolves each value the way
# PowerDevil does (duplicate groups, blanks, flags, directory cascade). With
# several users logged in on different TTYs, any one session may suspend the
# machine: run as root to check every /home user; a regular user checks only
# their own settings. This inspects configuration on disk, not what an
# already-running PowerDevil has loaded.
@test "no user auto-suspends or lid-suspends on AC power" {
    command -v plasmashell &>/dev/null || skip "plasma not installed"
    command -v kreadconfig6 &>/dev/null || skip "kreadconfig6 not installed"
    local failed=0 user uid home key value
    while IFS=: read -r user _ uid _ _ home _; do
        [[ "$home" == /home/* ]] || continue
        (( EUID == 0 || uid == EUID )) || continue
        for key in AutoSuspendAction LidAction; do
            value=$(XDG_CONFIG_HOME="$home/.config" \
                XDG_CONFIG_DIRS="$home/.config/kdedefaults:/usr/local/etc/xdg:/etc/xdg:/usr/etc/xdg" \
                kreadconfig6 --file powerdevilrc \
                    --group AC --group SuspendAndShutdown --key "$key")
            if [[ "$value" != 0 ]]; then
                echo "$user: AC $key=${value:-built-in default} ($home/.config/powerdevilrc)" >&2
                failed=1
            fi
        done
    done < <(getent passwd)
    if [[ "$failed" -ne 0 ]]; then
        echo "machine could suspend while plugged in; run setup-ac-no-suspend or ac-no-suspend" >&2
        return 1
    fi
    (( EUID == 0 )) || echo "# checked only $USER; run as root to check every user" >&3
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
