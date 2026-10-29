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
    # QGA and SSH checks run outside the graphical session. Inspect the
    # actual compositor owned by the tested account instead of caller env.
    local uid
    uid=$(stat -c %u "$JAN_HOME")
    pgrep -u "$uid" -x kwin_wayland
    pgrep -u "$uid" -x plasmashell
}

# bats test_tags=bare-metal
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
    assert_file /usr/local/share/konsole/dark.profile
    assert_file /usr/local/share/konsole/white.profile
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

@test "the wallpaper is installed and distribution images are untouched" {
    assert_file /usr/local/share/jan-wallpaper.jpg
    if [[ -L /usr/local/share/jan-wallpaper.jpg ]]; then
        echo "wallpaper is a symlink; it must resolve without the checkout" >&2
        return 1
    fi
    # Provisioning must not redirect rpm-owned images at the repo wallpaper: a
    # package update would restore them and silently revert the background.
    local dirs=() dir hijacked=() scan=0
    for dir in /usr/share/wallpapers /usr/share/backgrounds; do
        [[ -d "$dir" ]] && dirs+=("$dir")
    done
    if (( ! ${#dirs[@]} )); then
        return 0
    fi
    # Process substitution would hide find's status, so scan to a file: an
    # unreadable subtree must fail loudly rather than report nothing wrong.
    find "${dirs[@]}" \( -lname '/usr/local/*' -o -xtype l \) -print0 \
        > "$BATS_TEST_TMPDIR/hijacked" || scan=$?
    if (( scan != 0 )); then
        echo "could not scan the wallpaper directories (find exit $scan)" >&2
        return 1
    fi
    mapfile -t -d '' hijacked < "$BATS_TEST_TMPDIR/hijacked"
    if (( ${#hijacked[@]} )); then
        echo "redirected or dangling distribution wallpapers:" >&2
        printf '  %s\n' "${hijacked[@]}" >&2
        return 1
    fi
}

@test "lock screen shows the installed wallpaper on a dark background" {
    command -v kreadconfig6 &>/dev/null || skip "kreadconfig6 not installed"
    assert_file /usr/local/etc/xdg/kscreenlockerrc
    # Read the administrator cascade with an empty per-user config: the caller
    # may be root over SSH with no XDG_CONFIG_DIRS, and a user override must
    # not be able to mask a broken system default.
    locker_default() {
        XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/empty-config" \
            XDG_CONFIG_DIRS=/usr/local/etc/xdg:/etc/xdg:/usr/etc/xdg \
            kreadconfig6 --file kscreenlockerrc "$@"
    }
    [[ $(locker_default --group Greeter --key WallpaperPlugin) == org.kde.image ]]
    local group=(--group Greeter --group Wallpaper --group org.kde.image --group General)
    # org.kde.image defaults Color to #ffffff; an unreadable image must not
    # leave a white lock screen.
    [[ $(locker_default "${group[@]}" --key Color) == 0,0,0 ]]
    local image
    image=$(locker_default "${group[@]}" --key Image)
    [[ $image == /usr/local/share/jan-wallpaper.jpg ]]
    assert_file "$image"
}
