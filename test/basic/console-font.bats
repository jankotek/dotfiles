#!/usr/bin/env bats
# Verify console font is set to Terminus

load ../helpers

@test "terminus console font package is installed" {
    if command -v rpm &>/dev/null; then
        rpm -q terminus-bitmap-fonts
    elif command -v dpkg &>/dev/null; then
        dpkg -l fonts-terminus 2>/dev/null | grep -q '^ii'
    else
        skip "unknown package manager"
    fi
}

@test "vconsole.conf has terminus font" {
    if [[ -f /etc/vconsole.conf ]]; then
        grep -q '^FONT=ter-' /etc/vconsole.conf
    elif [[ -f /etc/default/console-setup ]]; then
        grep -q 'FONTFACE.*Terminus' /etc/default/console-setup
    else
        skip "no console font config found"
    fi
}

@test "jan-console-font-apply script exists" {
    assert_executable /usr/local/sbin/jan-console-font-apply
}
