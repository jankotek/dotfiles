#!/usr/bin/env bats
# Verify VM system-level configuration after provisioning

load ../helpers

@test "/opt/jan/usr symlinked into /usr/local" {
    [[ -L /usr/local/bin/jan-vm-resize-display ]] || \
    [[ -L /usr/local/bin/image-strip ]]
}

@test "jan-upgrade is available via symlink" {
    assert_executable /usr/local/sbin/jan-upgrade
}

@test "jan-update-opt is available via symlink" {
    assert_executable /usr/local/sbin/jan-update-opt
}

@test "terminator is installed" {
    assert_command terminator
}

@test "rofi is installed" {
    assert_command rofi
}

@test "mousepad is installed" {
    assert_command mousepad
}

@test "arandr is installed" {
    assert_command arandr
}

@test "home directory owned by jan" {
    [[ "$(stat -c %U "$JAN_HOME")" == "jan" ]]
}

@test "home directory has 0700 permissions" {
    [[ "$(stat -c %a "$JAN_HOME")" == "700" ]]
}

@test "snapd is not installed" {
    ! command -v snap
}

@test "xfce4-screensaver is not installed" {
    ! command -v xfce4-screensaver
}

@test "xfce4-terminal is not installed" {
    ! command -v xfce4-terminal
}

@test "snapd is blocked from reinstall" {
    if [[ -f /etc/apt/preferences.d/block-snapd.pref ]]; then
        grep -q "Pin-Priority: -1" /etc/apt/preferences.d/block-snapd.pref
    else
        skip "not an apt-based system"
    fi
}

@test "automatic APT updates are disabled" {
    local unit
    for unit in \
        apt-daily.timer \
        apt-daily-upgrade.timer \
        apt-daily.service \
        apt-daily-upgrade.service \
        unattended-upgrades.service; do
        [[ $(systemctl is-enabled "$unit" 2>/dev/null || true) == masked ]]
    done
    assert_file_contains /etc/apt/apt.conf.d/20auto-upgrades \
        '^APT::Periodic::Enable "0";$'
    assert_file_contains /etc/apt/apt.conf.d/20auto-upgrades \
        '^APT::Periodic::Unattended-Upgrade "0";$'
}

@test "Ubuntu cloud GRUB defaults preserve managed kernel parameters" {
    local dropin=/etc/default/grub.d/99-jan-kernel-tweaks.cfg
    [[ -f /etc/default/grub.d/50-cloudimg-settings.cfg ]] || \
        skip "not an Ubuntu cloud-image GRUB configuration"
    assert_file_contains "$dropin" 'zswap.enabled=1'
    assert_file_contains "$dropin" 'zswap.compressor=lzo'
    assert_file_contains "$dropin" 'ipv6.disable=1'
}

@test "tty11-root service is enabled" {
    systemctl is-enabled tty11-root.service
}
