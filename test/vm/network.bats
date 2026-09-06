#!/usr/bin/env bats
# Portable VM network checks shared by Ubuntu and Tumbleweed.

load ../helpers

@test "systemd-networkd manages VM Ethernet with DHCP" {
    assert_file_contains /etc/systemd/network/05-jan-wired.network '^Type=ether$'
    assert_file_contains /etc/systemd/network/05-jan-wired.network '^DHCP=ipv4$'
    systemctl is-enabled --quiet systemd-networkd.service
    systemctl is-active --quiet systemd-networkd.service
    ip -4 address show scope global | grep -q 'inet '
    ip route show default | grep -q .
}

@test "systemd-resolved provides VM DNS" {
    [[ $(readlink -f /etc/resolv.conf) == /run/systemd/resolve/stub-resolv.conf ]]
    systemctl is-enabled --quiet systemd-resolved.service
    systemctl is-active --quiet systemd-resolved.service
    getent hosts example.com >/dev/null
}

@test "NetworkManager is removed and masked" {
    assert_command_absent NetworkManager
    [[ $(systemctl is-enabled NetworkManager.service 2>/dev/null || true) == masked ]]
}
