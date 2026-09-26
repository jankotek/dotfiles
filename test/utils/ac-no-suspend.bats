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

@test "PowerDevil AC suspend defaults are do-nothing and not locked" {
    write_configuration
    local rc="$XDG_DIR/powerdevilrc"
    grep -qx '\[AC\]\[SuspendAndShutdown\]' "$rc"
    grep -qx 'AutoSuspendAction=0' "$rc"
    grep -qx 'LidAction=0' "$rc"
    ! grep -qF '[$' "$rc"
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
    local rc="$XDG_DIR/powerdevilrc" ac
    ac=$(sed -n '/^\[AC\]\[SuspendAndShutdown\]/,/^$/p' "$rc")
    [[ $(grep -c '^AutoSuspendAction=0$' <<<"$ac") -eq 1 ]]
    [[ $(grep -c '^LidAction=0$' <<<"$ac") -eq 1 ]]
    # The earlier value and immutable lock are both gone.
    ! grep -q '^AutoSuspendAction=1$' <<<"$ac"
    ! grep -qF 'LidAction[$i]' "$rc"
    grep -qx 'TurnOffDisplayIdleTimeoutSec=600' "$rc"
    grep -qx 'AutoSuspendIdleTimeoutSec=900' "$rc"
    grep -qx 'PowerButtonAction=8' "$rc"
    [[ $(sed -n '/^\[Battery\]\[SuspendAndShutdown\]/,/^$/p' "$rc") == *'LidAction=0'* ]]
    [[ $(sed -n '/^\[LowBattery\]\[SuspendAndShutdown\]/,$p' "$rc") == *'AutoSuspendAction=1'* ]]
    [[ $(stat -c %a "$rc") == 644 ]]
}

# Read the value KConfig resolves, so the checks follow its parser rather
# than this test's own reading of the file.
effective() {
    XDG_CONFIG_DIRS="$XDG_DIR" XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/empty-home" \
        kreadconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key "$1"
}

@test "old AC keys are removed across KConfig syntax variants" {
    mkdir -p "$XDG_DIR"
    printf '%s\r\n' '[AC][SuspendAndShutdown]' 'AutoSuspendAction[$i]=1' 'PowerButtonAction=8' \
        '' '[Battery][SuspendAndShutdown]' 'LidAction=1' > "$XDG_DIR/powerdevilrc"
    printf '%s\n' '' ' [AC][SuspendAndShutdown][$i] ' 'AutoSuspendAction = 1' \
        ' LidAction [$i] =1' 'AutoSuspendIdleTimeoutSec=900' >> "$XDG_DIR/powerdevilrc"
    write_configuration
    local rc="$XDG_DIR/powerdevilrc"
    ! grep -q $'\r' "$rc"
    ! grep -qF '[$' "$rc"
    ! grep -Eq '^[[:space:]]*(AutoSuspendAction|LidAction)[[:space:]]*=[[:space:]]*1' <(sed '/^\[Battery\]/,/^$/d' "$rc")
    [[ $(grep -c '^\[AC\]\[SuspendAndShutdown\]$' "$rc") -eq 2 ]]
    [[ $(grep -c '^AutoSuspendAction=0$' "$rc") -eq 2 ]]
    [[ $(grep -c '^LidAction=0$' "$rc") -eq 2 ]]
    grep -qx 'PowerButtonAction=8' "$rc"
    grep -qx 'AutoSuspendIdleTimeoutSec=900' "$rc"
    [[ $(sed -n '/^\[Battery\]\[SuspendAndShutdown\]/,/^$/p' "$rc") == *'LidAction=1'* ]]
    if command -v kreadconfig6 >/dev/null; then
        [[ $(effective AutoSuspendAction) == 0 ]]
        [[ $(effective LidAction) == 0 ]]
    fi
}

user_script_env() {
    source "$BATS_TEST_DIRNAME/../../usr/bin/ac-no-suspend"
    CONFIG_FILE="$BATS_TEST_TMPDIR/home/.config/powerdevilrc"
    CALLS="$BATS_TEST_TMPDIR/calls"
    kwriteconfig6() { echo "kwriteconfig6 $*" >> "$CALLS"; }
}

@test "user script writes both AC keys to an absolute user file" {
    user_script_env
    write_settings
    [[ -d $BATS_TEST_TMPDIR/home/.config ]]
    [[ $(cat "$CALLS") == "kwriteconfig6 --file $CONFIG_FILE --group AC --group SuspendAndShutdown --key AutoSuspendAction 0
kwriteconfig6 --file $CONFIG_FILE --group AC --group SuspendAndShutdown --key LidAction 0" ]]
}

@test "user script refuses a relative config path" {
    user_script_env
    (( EUID != 0 )) || skip "main refuses to run as root"
    CONFIG_FILE=relative/powerdevilrc
    run main
    [[ $status -ne 0 ]]
    [[ $output == *'must be absolute'* ]]
    [[ ! -e $CALLS ]]
}

@test "user script restarts only an already running PowerDevil" {
    user_script_env
    (( EUID != 0 )) || skip "main refuses to run as root"
    systemctl() {
        echo "systemctl $*" >> "$CALLS"
        [[ $2 != is-active ]] || return "$POWERDEVIL_ACTIVE"
    }
    POWERDEVIL_ACTIVE=1
    main
    ! grep -q 'restart' "$CALLS"
    POWERDEVIL_ACTIVE=0
    main
    grep -qx 'systemctl --user restart plasma-powerdevil.service' "$CALLS"
}
