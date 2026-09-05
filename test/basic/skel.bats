#!/usr/bin/env bats

load ../helpers

@test "new-user skeleton and installer are present" {
    assert_executable "$OPT_JAN/skel/install"
    assert_dir "$OPT_JAN/skel/home"
    assert_file "$OPT_JAN/skel/home/.config/git/config"
    assert_executable "$OPT_JAN/skel/home/.local/bin/autostart.sh"
}

@test "curated defaults use safe paths and desktop scoping" {
    assert_file_contains \
        "$OPT_JAN/skel/home/.config/user-dirs.dirs" \
        'XDG_PUBLICSHARE_DIR="\$HOME/media/share"'
    assert_file_contains \
        "$OPT_JAN/skel/home/.config/zim/preferences.conf" \
        '^file_templates_folder=~/doc/templates$'
    if grep -q '^[[:space:]]*export GTK_THEME=' \
        "$OPT_JAN/skel/home/.profile"; then
        return 1
    fi

    HOME="$OPT_JAN/skel/home" bash -c '
        source "$HOME/.bashrc"
        ! alias cp >/dev/null 2>&1
    '
}

@test "Plasma defaults match the XFCE Sweet appearance" {
    local kdeglobals="$OPT_JAN/skel/home/.config/kdeglobals"
    assert_file_contains "$kdeglobals" '^ColorScheme=Sweet-dark$'
    assert_file_contains "$kdeglobals" '^Theme=Sweet-Purple$'
    if grep -q '^\[Colors:' "$kdeglobals"; then
        return 1
    fi
}

@test "Konsole defaults to the pure black dark profile" {
    assert_file_contains \
        "$OPT_JAN/skel/home/.config/konsolerc" \
        '^DefaultProfile=dark.profile$'
    assert_file_contains \
        "$OPT_JAN/usr/share/konsole/dark.profile" \
        '^ColorScheme=WhiteOnBlack$'
    assert_file_contains \
        "$OPT_JAN/usr/share/konsole/white.profile" \
        '^ColorScheme=BlackOnWhite$'
    assert_file_contains \
        "$OPT_JAN/usr/share/konsole/dark.profile" \
        '^Font=JetBrains Mono,10,'
    assert_file_contains \
        "$OPT_JAN/usr/share/konsole/dark.profile" \
        '^WordModeAscii=true$'
    cmp \
        "$OPT_JAN/usr/share/konsole/dark.profile" \
        "$OPT_JAN/skel/home/.local/share/konsole/dark.profile"
    cmp \
        "$OPT_JAN/usr/share/konsole/white.profile" \
        "$OPT_JAN/skel/home/.local/share/konsole/white.profile"
}

@test "MC desktop shortcuts use the packaged icon name" {
    assert_file_contains \
        "$OPT_JAN/skel/home/desk/mc.desktop" \
        '^Icon=mc$'
}

@test "monospace defaults use JetBrains Mono 10" {
    assert_file_contains \
        "$OPT_JAN/usr/share/color-schemes/Sweet-dark.colors" \
        '^fixed=JetBrains Mono,10,'
    assert_file_contains \
        "$OPT_JAN/usr/etc/xdg/katerc" \
        '^Text Font Features=liga=1,calt=1$'
    assert_file_contains \
        "$OPT_JAN/usr/etc/xdg/kwriterc" \
        '^Text Font Features=liga=1,calt=1$'
    assert_file_contains \
        "$OPT_JAN/skel/home/.config/dconf-import.ini" \
        "monospace-font-name='JetBrains Mono 10'"
    assert_file \
        "$OPT_JAN/usr/share/fontconfig/conf.avail/60-jan-jetbrains-mono.conf"
}

@test "Plasma panel defaults reproduce the curated VM layout" {
    local layout="$OPT_JAN/skel/home/.local/share/plasma/layout-templates/org.opensuse.desktop.defaultPanel/contents/layout.js"
    local metadata="$OPT_JAN/skel/home/.local/share/plasma/layout-templates/org.opensuse.desktop.defaultPanel/metadata.json"
    assert_file "$layout"
    assert_file "$metadata"
    assert_file_contains "$layout" '^panel.location = "top"$'
    assert_file_contains "$layout" '^panel.height = 32$'
    assert_file_contains "$layout" \
        'addWidget("org.kde.plasma.taskmanager")'
    assert_file_contains "$layout" \
        'preferred://filemanager,applications:org.kde.konsole.desktop'
    assert_file_contains "$layout" \
        'clock.writeConfig("customDateFormat", "MM-dd ddd")'
    assert_file_contains "$layout" \
        'clock.writeConfig("use24hFormat", 2)'
}

@test "skeleton has no account-specific path or generated desktop state" {
    if grep -R -F /home/jan "$OPT_JAN/skel/home"; then
        return 1
    fi
    local forbidden generated
    for forbidden in \
        .cache \
        .config/kwinoutputconfig.json \
        .config/klipperrc \
        .config/kactivitymanagerdrc \
        .config/libvirt \
        .local/share/klipper \
        .local/share/kactivitymanagerd \
        .local/share/libvirt; do
        [[ ! -e "$OPT_JAN/skel/home/$forbidden" ]] || return 1
    done
    generated=$(find "$OPT_JAN/skel/home" -mindepth 1 \
        \( -type d -name .cache \
        -o -iname 'kwinoutputconfig*' \
        -o -iname '*klipper*' \
        -o -iname '*kactivitymanager*' \
        -o -type d -name libvirt \) \
        -print -quit)
    [[ -z $generated ]]
}

@test "VM display resize is a separate XFCE-only autostart" {
    local entry="$OPT_JAN/skel/home/.config/autostart/jan-vm-resize-display.desktop"
    assert_file_contains "$entry" '^OnlyShowIn=XFCE;$'
    if grep -F jan-vm-resize-display-loop \
        "$OPT_JAN/skel/home/.local/bin/autostart.sh" \
        "$OPT_JAN/skel/home/.xsessionrc"; then
        return 1
    fi
}

@test "installer preserves unmanaged paths and converges managed ownership" {
    if (( EUID != 0 )); then
        skip "ownership convergence requires root"
    fi

    local destination source relative installed
    destination=$(mktemp -d \
        -p "${BATS_TEST_TMPDIR:-/tmp}" jan-skel-install.XXXXXX)
    printf 'administrator sentinel\n' > "$destination/admin-sentinel"
    install -d "$destination/.config"
    printf 'unsafe old content\n' > "$destination/.bashrc"
    chown 65534:65534 "$destination/.bashrc" "$destination/.config"

    "$OPT_JAN/skel/install" "$destination"
    "$OPT_JAN/skel/install" "$destination"

    [[ $(<"$destination/admin-sentinel") == "administrator sentinel" ]]
    while IFS= read -r -d '' source; do
        relative=${source#"$OPT_JAN/skel/home/"}
        installed=$destination/$relative
        [[ -e $installed ]]
        [[ $(stat -c %U:%G "$installed") == root:root ]]
        if [[ -f $source ]]; then
            cmp "$source" "$installed"
            [[ $(stat -c %a "$source") == "$(stat -c %a "$installed")" ]]
        fi
    done < <(find "$OPT_JAN/skel/home" -mindepth 1 -print0)
}
