#!/usr/bin/env bats
#
# Integration test for jan-pod-setup security hardening.
# Creates a temporary pod user, verifies permissions, then removes it.
#
# Run manually as root:  bats test/utils/pod-security.bats
# NOT triggered by test-host.sh or test-vm.sh.
#

load ../helpers

# POD_NAME must be stable across test invocations. Bats re-sources this file
# in a fresh subshell for each @test, so a file-level `$(date ...)` would
# generate a different value per test and the user created in setup_file
# would not match what the tests look for. We persist POD_NAME via
# BATS_FILE_TMPDIR (unique per `bats` invocation, cleaned up automatically).
_pod_name_file() { echo "${BATS_FILE_TMPDIR:-/tmp}/pod-security.pod-name"; }

setup_file() {
    if [[ "$EUID" -ne 0 ]]; then
        skip "requires root"
    fi
    if ! command -v jan-pod-setup &>/dev/null && ! [[ -x "$OPT_JAN/usr/sbin/jan-pod-setup" ]]; then
        skip "jan-pod-setup not found"
    fi

    POD_NAME="test-$(date +%y%m%d-%H%M%S)"
    echo "$POD_NAME" > "$(_pod_name_file)"
    POD_HOME="/var/pod/${POD_NAME}"

    "$OPT_JAN/usr/sbin/jan-pod-setup" "$POD_NAME" >/dev/null 2>&1 || \
        jan-pod-setup "$POD_NAME" >/dev/null 2>&1
}

setup() {
    if [[ -r "$(_pod_name_file)" ]]; then
        POD_NAME=$(cat "$(_pod_name_file)")
        POD_HOME="/var/pod/${POD_NAME}"
    fi
}

teardown_file() {
    if [[ "$EUID" -ne 0 ]]; then
        return
    fi
    # POD_NAME is set per-test by setup() from BATS_FILE_TMPDIR; teardown_file
    # runs in the file-level shell where setup() was never called, so we read
    # it back from the same file.
    if [[ -r "$(_pod_name_file)" ]]; then
        POD_NAME=$(cat "$(_pod_name_file)")
        POD_HOME="/var/pod/${POD_NAME}"
    fi
    [[ -n "${POD_NAME:-}" ]] || return 0
    local uid
    uid=$(id -u "$POD_NAME" 2>/dev/null) || return 0

    loginctl disable-linger "$POD_NAME" 2>/dev/null || true
    systemctl stop "user@${uid}.service" 2>/dev/null || true
    userdel -r "$POD_NAME" 2>/dev/null || true
    rm -rf "$POD_HOME"

    # Clean up system config files
    rm -f "/etc/sudoers.d/deny-${POD_NAME}"
    rm -f "/etc/sysctl.d/90-podman-${POD_NAME}.conf"
    rm -f "/etc/tmpfiles.d/podman-${POD_NAME}.conf"
    rm -f "/etc/apparmor.d/podman-${POD_NAME}"
    rm -f "/etc/systemd/system/user@${uid}.service.d/delegate.conf"
    rmdir "/etc/systemd/system/user@${uid}.service.d" 2>/dev/null || true

    # Remove from deny lists
    sed -i "/^${POD_NAME}$/d" /etc/cron.deny 2>/dev/null || true
    sed -i "/^${POD_NAME}$/d" /etc/at.deny 2>/dev/null || true

    # Remove ACLs
    for dir in /home /root /tmp /var/tmp /var/log /var/spool /var/mail /etc/ssh; do
        setfacl -x "u:${POD_NAME}" "$dir" 2>/dev/null || true
    done
}

run_as_pod() {
    local uid
    uid=$(id -u "$POD_NAME")
    sudo -u "$POD_NAME" \
        XDG_RUNTIME_DIR="/run/user/${uid}" \
        HOME="$POD_HOME" \
        bash -c "$1" 2>&1
}

# --- User creation ---

@test "pod user exists" {
    id "$POD_NAME"
}

@test "pod user has nologin shell" {
    local shell
    shell=$(getent passwd "$POD_NAME" | cut -d: -f7)
    [[ "$shell" == */nologin ]]
}

@test "pod user password is locked" {
    passwd -S "$POD_NAME" | grep -q 'L\|LK'
}

@test "pod user has no user group (nogroup)" {
    local gid group
    gid=$(id -g "$POD_NAME")
    group=$(getent group "$gid" | cut -d: -f1)
    [[ "$group" == "nogroup" || "$group" == "nobody" ]]
}

# --- Home directory ---

@test "home directory exists with 0700" {
    [[ -d "$POD_HOME" ]]
    [[ "$(stat -c %a "$POD_HOME")" == "700" ]]
}

@test "/var/pod is 0711 (traverse only)" {
    [[ "$(stat -c %a /var/pod)" == "711" ]]
}

@test "data directory exists" {
    [[ -d "$POD_HOME/data" ]]
}

@test "private tmp directory exists" {
    [[ -d "$POD_HOME/.tmp" ]]
}

# --- Sudo denied ---

@test "sudoers deny file exists" {
    assert_file "/etc/sudoers.d/deny-${POD_NAME}"
}

# --- Cron/at denied ---

@test "user is in cron.deny" {
    grep -q "^${POD_NAME}$" /etc/cron.deny 2>/dev/null
}

# --- Filesystem ACLs ---

@test "cannot read /home" {
    run run_as_pod "ls /home"
    [[ "$status" -ne 0 ]]
}

@test "cannot read /root" {
    run run_as_pod "ls /root"
    [[ "$status" -ne 0 ]]
}

@test "cannot read /tmp" {
    run run_as_pod "ls /tmp"
    [[ "$status" -ne 0 ]]
}

@test "cannot read /var/log" {
    run run_as_pod "ls /var/log"
    [[ "$status" -ne 0 ]]
}

@test "cannot read /etc/ssh" {
    run run_as_pod "ls /etc/ssh"
    [[ "$status" -ne 0 ]]
}

@test "cannot read /var/spool" {
    run run_as_pod "ls /var/spool"
    [[ "$status" -ne 0 ]]
}

@test "can read own home" {
    run run_as_pod "ls $POD_HOME"
    [[ "$status" -eq 0 ]]
}

@test "cannot list /var/pod (other pods hidden)" {
    run run_as_pod "ls /var/pod"
    [[ "$status" -ne 0 ]]
}

# --- Podman config ---

@test "containers.conf exists" {
    assert_file "$POD_HOME/containers.conf"
}

@test "storage.conf exists" {
    assert_file "$POD_HOME/storage.conf"
}

@test "quadlet container file exists" {
    assert_file "$POD_HOME/app.container"
}

# --- Systemd ---

@test "linger is enabled" {
    [[ -f "/var/lib/systemd/linger/${POD_NAME}" ]]
}

@test "cgroup delegation is configured" {
    local uid
    uid=$(id -u "$POD_NAME")
    assert_file "/etc/systemd/system/user@${uid}.service.d/delegate.conf"
}

# --- Sysctl ---

@test "sysctl config exists" {
    assert_file "/etc/sysctl.d/90-podman-${POD_NAME}.conf"
}

@test "unprivileged port start is >= 1024" {
    local val
    val=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start)
    [[ "$val" -ge 1024 ]]
}
