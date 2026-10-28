#!/usr/bin/env bats
# ci: manual
# Run only inside a disposable VM; never stop the QGA service carrying Bats.

setup() {
    [[ ${QGA_GUARD_LIVE:-0} == 1 ]] || skip 'Set QGA_GUARD_LIVE=1 in a disposable VM'
    (( EUID == 0 )) || skip 'Guest root required'
    systemd-detect-virt -q -v || skip 'VM required'
    sleep 120 >/dev/null 2>&1 &
    owner_pid=$!
    token=
}

teardown() {
    if [[ -n ${token:-} ]]; then
        /usr/local/sbin/qga-guard release "$token" >/dev/null 2>&1 || true
    fi
    if [[ -n ${owner_pid:-} ]]; then
        kill "$owner_pid" 2>/dev/null || true
        wait "$owner_pid" 2>/dev/null || true
    fi
}

@test "QGA guard releases its runtime mask without stopping the service" {
    token=$(/usr/local/sbin/qga-guard acquire "$owner_pid")
    /usr/local/sbin/qga-guard verify "$token"
    [[ -L /run/systemd/system/qemu-guest-agent.service ]]
    systemctl is-active --quiet qemu-guest-agent.service
    /usr/local/sbin/qga-guard release "$token"
    token=
    [[ ! -e /run/systemd/system/qemu-guest-agent.service ]]
    systemctl is-active --quiet qemu-guest-agent.service
}

@test "QGA watchdog clears the runtime mask after its owner is killed" {
    token=$(/usr/local/sbin/qga-guard acquire "$owner_pid")
    kill -KILL "$owner_pid"
    wait "$owner_pid" 2>/dev/null || true
    owner_pid=
    for _ in {1..20}; do
        [[ -e /run/qga-guard/owner ]] || break
        sleep 1
    done
    [[ ! -e /run/qga-guard/owner ]]
    [[ ! -e /run/systemd/system/qemu-guest-agent.service ]]
    systemctl is-active --quiet qemu-guest-agent.service
    token=
}

@test "Tumbleweed provisioning failure clears legacy masks and its runtime lease" {
    command -v zypper >/dev/null || skip 'Tumbleweed-specific failure injection'
    local stubs="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stubs"
    printf '#!/bin/sh\nexit 42\n' > "$stubs/zypper"
    chmod +x "$stubs/zypper"
    systemctl mask qemu-guest-agent.service spice-vdagentd.service
    run env PATH="$stubs:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" /opt/jan/setup/vm-baseweed
    [[ $status == 42 ]]
    [[ ! -e /etc/systemd/system/qemu-guest-agent.service ]]
    [[ ! -e /etc/systemd/system/spice-vdagentd.service ]]
    [[ ! -e /run/systemd/system/qemu-guest-agent.service ]]
    [[ ! -e /run/qga-guard/owner ]]
    [[ ! -e /etc/systemd/system/jan-unmask-guest-agents.service ]]
    systemctl is-active --quiet qemu-guest-agent.service
}
