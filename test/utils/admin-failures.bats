#!/usr/bin/env bats
# ci: fixture

setup() {
    export CALLS="$BATS_TEST_TMPDIR/calls"
    export SYSTEMD_DIR="$BATS_TEST_TMPDIR/systemd"
    mkdir -p "$SYSTEMD_DIR"
    cat > "$BATS_TEST_TMPDIR/stubs.sh" <<'SH'
record() {
    printf '%s\n' "$*" >> "$CALLS"
    [[ $* != "${FAIL_COMMAND:-}" ]]
}
command() {
    if [[ $1 == -v ]]; then
        [[ $2 == "${MANAGER:-}" ]]
    else
        builtin command "$@"
    fi
}
zypper() { record "zypper $*"; }
dnf() { record "dnf $*"; }
apt-get() { record "apt-get $*"; }
apt() { record "apt $*"; }
find() { :; }
systemctl() { record "systemctl $*"; }
SH
}

run_admin() {
    run bash -c 'source "$1"; source "$2"; "$3"' _ \
        "$OPT_JAN/usr/sbin/$1" "$BATS_TEST_TMPDIR/stubs.sh" "$2"
}

@test "distribution upgrade stops on package-manager failures" {
    local manager failure
    while IFS='|' read -r manager failure; do
        export MANAGER=$manager FAIL_COMMAND=$failure
        : > "$CALLS"
        run_admin distro-upgrade upgrade_system
        [[ $status -ne 0 ]]
        [[ $output != *'System updated successfully'* ]]
        [[ $(tail -1 "$CALLS") == "$failure" ]]
    done <<'CASES'
zypper|zypper --non-interactive update
dnf|dnf -y update
apt-get|apt-get update
apt-get|apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade -y
apt-get|apt-get autoremove -y
apt-get|apt-get clean
apt|apt upgrade -y
CASES
}

@test "successful package-manager runs still report completion" {
    local manager
    for manager in zypper dnf apt-get apt; do
        export MANAGER=$manager
        run_admin distro-upgrade upgrade_system
        [[ $status == 0 ]]
        [[ $output == *'System updated successfully'* ]]
    done
}

@test "TTY12 installer stops before systemctl if writing the unit fails" {
    export SYSTEMD_DIR="$BATS_TEST_TMPDIR/missing/systemd"
    run_admin install-tty12-menu install_service
    [[ $status -ne 0 ]]
    [[ $output != *'Service installed and started successfully'* ]]
    [[ ! -e $CALLS ]]
}

@test "TTY12 installer stops on reload, enable and start failures" {
    local failure
    for failure in 'systemctl daemon-reload' 'systemctl enable tty12-menu.service' \
        'systemctl start tty12-menu.service'; do
        export FAIL_COMMAND=$failure
        : > "$CALLS"
        run_admin install-tty12-menu install_service
        [[ $status -ne 0 ]]
        [[ $output != *'Service installed and started successfully'* ]]
        [[ $(tail -1 "$CALLS") == "$failure" ]]
    done
}

@test "TTY12 installer reloads before enabling and starting the written unit" {
    run_admin install-tty12-menu install_service
    [[ $status == 0 ]]
    [[ $output == *'Service installed and started successfully'* ]]
    [[ $(cat "$CALLS") == 'systemctl daemon-reload
systemctl enable tty12-menu.service
systemctl start tty12-menu.service' ]]
    grep -qx 'ExecStart=/usr/local/sbin/tty12-menu' "$SYSTEMD_DIR/tty12-menu.service"
}
