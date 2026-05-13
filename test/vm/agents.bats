#!/usr/bin/env bats
# Verify VM guest agents and virtualization

load ../helpers

@test "running inside a VM" {
    systemd-detect-virt -q -v
}

@test "spice-vdagent is installed" {
    dpkg -l spice-vdagent 2>/dev/null || rpm -q spice-vdagent 2>/dev/null
}

@test "spice-vdagentd service is enabled" {
    systemctl is-enabled spice-vdagentd 2>/dev/null || \
    systemctl is-enabled spice-vdagent 2>/dev/null
}

@test "spice-vdagentd process is running" {
    pgrep spice-vdagentd
}

@test "spice-vdagent process is running as jan" {
    pgrep -u jan spice-vdagent
}

@test "qemu-guest-agent is installed" {
    dpkg -l qemu-guest-agent 2>/dev/null || rpm -q qemu-guest-agent 2>/dev/null
}

@test "qemu-guest-agent service is enabled" {
    systemctl is-enabled qemu-guest-agent
}
