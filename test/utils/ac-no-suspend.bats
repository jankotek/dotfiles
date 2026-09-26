#!/usr/bin/env bats
# ci: fixture

setup() {
    LOGIND_DIR="$BATS_TEST_TMPDIR/logind.conf.d"
    XDG_DIR="$BATS_TEST_TMPDIR/xdg"
    source "$BATS_TEST_DIRNAME/../../usr/sbin/setup-ac-no-suspend"
}

@test "logind ignores the lid only on external power" {
    write_configuration
    local conf="$LOGIND_DIR/80-jan-ac-no-suspend.conf"
    grep -qx '\[Login\]' "$conf"
    grep -qx 'HandleLidSwitchExternalPower=ignore' "$conf"
    # Battery lid handling stays at the distro default.
    ! grep -q '^HandleLidSwitch=' "$conf"
}

@test "PowerDevil AC suspend actions are locked to do nothing" {
    write_configuration
    local rc="$XDG_DIR/powerdevilrc"
    grep -qx '\[AC\]\[SuspendAndShutdown\]' "$rc"
    grep -qxF 'AutoSuspendAction[$i]=0' "$rc"
    grep -qxF 'LidAction[$i]=0' "$rc"
    ! grep -q '^\[Battery\]' "$rc"
}

@test "rerunning produces identical files" {
    write_configuration
    local first
    first=$(cat "$LOGIND_DIR"/* "$XDG_DIR"/*)
    write_configuration
    [[ $(cat "$LOGIND_DIR"/* "$XDG_DIR"/*) == "$first" ]]
}

@test "existing system PowerDevil settings are preserved" {
    mkdir -p "$XDG_DIR"
    cat > "$XDG_DIR/powerdevilrc" <<'RC'
[AC][Display]
TurnOffDisplayIdleTimeoutSec=600

[AC][SuspendAndShutdown]
AutoSuspendAction=1
AutoSuspendIdleTimeoutSec=900
LidAction[$i]=1
PowerButtonAction=8

[Battery][SuspendAndShutdown]
LidAction=0

[LowBattery][SuspendAndShutdown]
AutoSuspendAction=1
RC
    write_configuration
    write_configuration
    local rc="$XDG_DIR/powerdevilrc"
    [[ $(grep -c '^AutoSuspendAction' "$rc") -eq 2 ]]
    [[ $(grep -c '^LidAction' "$rc") -eq 2 ]]
    grep -qxF 'AutoSuspendAction[$i]=0' "$rc"
    grep -qxF 'LidAction[$i]=0' "$rc"
    ! grep -qxF 'AutoSuspendAction=1' <(sed -n '/^\[AC\]\[SuspendAndShutdown\]/,/^$/p' "$rc")
    grep -qx 'TurnOffDisplayIdleTimeoutSec=600' "$rc"
    grep -qx 'AutoSuspendIdleTimeoutSec=900' "$rc"
    grep -qx 'PowerButtonAction=8' "$rc"
    [[ $(sed -n '/^\[Battery\]\[SuspendAndShutdown\]/,/^$/p' "$rc") == *'LidAction=0'* ]]
    [[ $(sed -n '/^\[LowBattery\]\[SuspendAndShutdown\]/,$p' "$rc") == *'AutoSuspendAction=1'* ]]
    [[ $(stat -c %a "$rc") == 644 ]]
}

@test "PowerDevil restarts only in running user managers" {
    CALLS="$BATS_TEST_TMPDIR/calls"
    systemctl() {
        if [[ $1 == list-units ]]; then
            printf '%s\n' 'user@1001.service loaded active running User Manager for UID 1001' \
                'user@1102.service loaded active running User Manager for UID 1102' \
                'user@4242.service loaded active running User Manager for UID 4242'
        else
            echo "systemctl $*" >> "$CALLS"
        fi
    }
    id() {
        case $2 in
            1001) echo jan ;;
            1102) echo play2 ;;
            *) return 1 ;;
        esac
    }
    restart_running_powerdevil
    [[ $(cat "$CALLS") == "systemctl --user --machine=jan@.host try-restart plasma-powerdevil.service
systemctl --user --machine=play2@.host try-restart plasma-powerdevil.service" ]]
}
