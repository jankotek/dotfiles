#!/usr/bin/env bats
# Verify network configuration shared by host and VMs

load ../helpers

@test "NetworkManager leaves tailscale0 to tailscaled" {
    # Host tests run as the user; /usr/sbin may not be on PATH.
    if [[ ! -d /etc/NetworkManager && ! -x /usr/sbin/NetworkManager ]]; then
        skip "NetworkManager is not installed"
    fi
    local conf=/etc/NetworkManager/conf.d/90-jan-tailscale-unmanaged.conf
    assert_file_contains "$conf" '^match-device=interface-name:tailscale0$'
    assert_file_contains "$conf" '^managed=0$'
    # Check the running daemon too when Tailscale is up.
    if systemctl is-active --quiet NetworkManager.service && [[ -e /sys/class/net/tailscale0 ]]; then
        run nmcli -g GENERAL.STATE device show tailscale0
        [[ $status -eq 0 && $output == *unmanaged* ]]
    fi
}
