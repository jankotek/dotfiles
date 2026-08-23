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
