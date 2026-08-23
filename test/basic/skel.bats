#!/usr/bin/env bats

load ../helpers

@test "new-user skeleton and installer are present" {
    assert_executable "$OPT_JAN/skel/install"
    assert_dir "$OPT_JAN/skel/home"
    assert_file "$OPT_JAN/skel/home/.config/git/config"
    assert_executable "$OPT_JAN/skel/home/.local/bin/autostart.sh"
}

@test "new-user defaults stay synchronized with the deployed jan home" {
    diff -qr "$OPT_JAN/home" "$OPT_JAN/skel/home"
}

@test "skeleton has no account-specific path or generated desktop state" {
    if grep -R -F /home/jan "$OPT_JAN/skel/home"; then
        return 1
    fi
    if find "$OPT_JAN/skel/home" -type f | \
        grep -E '/(kwinoutputconfig|klipper|kactivitymanager|libvirt|\.cache)(/|$)'; then
        return 1
    fi
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
