#!/usr/bin/env bats
# ci: fixture

setup() {
    source "$BATS_TEST_DIRNAME/../../usr/sbin/laptop-power"
    CPU_ROOT="$BATS_TEST_TMPDIR/cpu"
    POWER_ROOT="$BATS_TEST_TMPDIR/power"
    LID_ROOT="$BATS_TEST_TMPDIR/lid"
    CALLS="$BATS_TEST_TMPDIR/calls"
    LOGS="$BATS_TEST_TMPDIR/logs"
    STATE_FILE="$BATS_TEST_TMPDIR/laptop-power.state"
    mkdir -p "$CPU_ROOT"/policy{0,1} "$POWER_ROOT"/{AC,BAT0} "$LID_ROOT/LID0"
    echo Mains > "$POWER_ROOT/AC/type"
    echo 0 > "$POWER_ROOT/AC/online"
    echo Battery > "$POWER_ROOT/BAT0/type"
    echo Discharging > "$POWER_ROOT/BAT0/status"
    echo 50 > "$POWER_ROOT/BAT0/capacity"
    echo 'state: closed' > "$LID_ROOT/LID0/state"
    for policy in "$CPU_ROOT"/policy*; do
        echo 625000 > "$policy/cpuinfo_min_freq"
        echo 5187500 > "$policy/cpuinfo_max_freq"
        echo 1000000 > "$policy/scaling_min_freq"
        echo 2000000 > "$policy/scaling_max_freq"
    done
    powerprofilesctl() {
        echo "profile $*" >> "$CALLS"
        # Emulate the daemon disabling boost in power-saver mode.
        local p max=5187500
        [[ $2 != power-saver ]] || max=3000000
        for p in "$CPU_ROOT"/policy*; do echo "$max" > "$p/cpuinfo_max_freq"; done
    }
    systemctl() { echo "systemctl $*" >> "$CALLS"; }
    logger() { echo "logger $*" >> "$LOGS"; }
    id() {
        case "$2" in
            jan) echo 1001 ;;
            play1) echo 1101 ;;
            play2) echo 1102 ;;
            lab1) echo 1201 ;;
            *) return 1 ;;
        esac
    }
}

@test "closed lid caps every CPU and quotas apps while releasing session quotas" {
    apply_policy
    for policy in "$CPU_ROOT"/policy*; do
        [[ $(< "$policy/scaling_min_freq") == 625000 ]]
        [[ $(< "$policy/scaling_max_freq") == 625000 ]]
    done
    [[ $(cat "$CALLS") == *'--machine=jan@.host set-property --runtime app.slice CPUQuota=20%'* ]]
    [[ $(cat "$CALLS") == *'--machine=play1@.host set-property --runtime app.slice CPUQuota=20%'* ]]
    [[ $(cat "$CALLS") == *'--machine=play2@.host set-property --runtime app.slice CPUQuota=20%'* ]]
    [[ $(cat "$CALLS") == *'--machine=lab1@.host set-property --runtime app.slice CPUQuota=20%'* ]]
    [[ $(cat "$CALLS") == *'user-1001.slice CPUQuota='* ]]
    [[ $(cat "$CALLS") == *'user-1101.slice CPUQuota='* ]]
    [[ $(cat "$CALLS") == *'user-1102.slice CPUQuota='* ]]
    [[ $(cat "$CALLS") == *'user-1201.slice CPUQuota='* ]]
    [[ $(cat "$CALLS") != *'user-1001.slice CPUQuota=20%'* ]]
    [[ $(cat "$CALLS") != *'user-1101.slice CPUQuota=20%'* ]]
    [[ $(cat "$CALLS") != *'user-1102.slice CPUQuota=20%'* ]]
    [[ $(cat "$CALLS") != *'user-1201.slice CPUQuota=20%'* ]]
    [[ $(cat "$CALLS") != *'set-property --runtime session.slice'* ]]
    [[ $(cat "$CALLS") == *'user.slice CPUQuota='* ]]
    [[ $(cat "$CALLS") != *'user-1000.slice'* ]]
    [[ $(cat "$CALLS") != *'user.slice CPUQuota=20%'* ]]
    # A later call repairs drift without saving a baseline.
    echo 2000000 > "$CPU_ROOT/policy1/scaling_max_freq"
    apply_policy
    [[ $(< "$CPU_ROOT/policy1/scaling_max_freq") == 625000 ]]
}

@test "opening lid restores power-saver range and removes user quotas" {
    apply_policy
    echo 'state: open' > "$LID_ROOT/LID0/state"
    apply_policy
    [[ $(< "$CPU_ROOT/policy0/scaling_max_freq") == 3000000 ]]
    [[ $(tail -1 "$CALLS") == 'systemctl --user --machine=lab1@.host set-property --runtime app.slice CPUQuota=' ]]
}

@test "AC overrides closed lid and restores balanced hardware limits" {
    apply_policy
    echo 1 > "$POWER_ROOT/AC/online"
    apply_policy
    [[ $(< "$CPU_ROOT/policy0/scaling_min_freq") == 625000 ]]
    [[ $(< "$CPU_ROOT/policy0/scaling_max_freq") == 5187500 ]]
    [[ $(cat "$CALLS") == *'profile set balanced'* ]]
    [[ $(tail -1 "$CALLS") == 'systemctl --user --machine=lab1@.host set-property --runtime app.slice CPUQuota=' ]]
}

@test "unknown lid or power state fails before any changes" {
    rm "$LID_ROOT/LID0/state"
    run apply_policy
    [[ $status -ne 0 ]]
    [[ ! -e $CALLS ]]
    echo 'state: closed' > "$LID_ROOT/LID0/state"
    rm "$POWER_ROOT/AC/online" "$POWER_ROOT/BAT0/status"
    run apply_policy
    [[ $status -ne 0 ]]
    [[ ! -e $CALLS ]]
}

@test "dry run reports target without changes" {
    DRY_RUN=1
    apply_policy
    [[ ! -e $CALLS ]]
    [[ $(< "$CPU_ROOT/policy0/scaling_max_freq") == 2000000 ]]
}

@test "battery below 10 percent suspends before changing policy" {
    echo 9 > "$POWER_ROOT/BAT0/capacity"

    apply_policy

    [[ $(cat "$CALLS") == 'systemctl suspend' ]]
    [[ $(< "$CPU_ROOT/policy0/scaling_max_freq") == 2000000 ]]
}

@test "sleep hook mode never requests another suspend" {
    echo 9 > "$POWER_ROOT/BAT0/capacity"
    ALLOW_SUSPEND=0

    apply_policy

    [[ $(cat "$CALLS") != *'systemctl suspend'* ]]
    [[ $(< "$CPU_ROOT/policy0/scaling_max_freq") == 625000 ]]
}

@test "only the first present system battery controls low-battery suspend" {
    mkdir "$POWER_ROOT/BAT1"
    echo Battery > "$POWER_ROOT/BAT1/type"
    echo 1 > "$POWER_ROOT/BAT1/capacity"
    echo Discharging > "$POWER_ROOT/BAT1/status"

    apply_policy

    [[ $(cat "$CALLS") != *'systemctl suspend'* ]]
    [[ $(< "$CPU_ROOT/policy0/scaling_max_freq") == 625000 ]]
}

@test "system log records state transitions but not unchanged checks" {
    apply_policy
    apply_policy
    [[ $(wc -l < "$LOGS") -eq 1 ]]
    [[ $(cat "$LOGS") == *'unknown -> backpack'* ]]

    echo 1 > "$POWER_ROOT/AC/online"
    apply_policy
    [[ $(wc -l < "$LOGS") -eq 2 ]]
    [[ $(tail -1 "$LOGS") == *'backpack -> ac'* ]]
}

@test "frequency verification waits for an asynchronous kernel update" {
    request_frequency() {
        # Leave the old value visible until the simulated worker runs.
        ( sleep 0.12; printf '%s\n' "$2" > "$1" ) &
    }
    write_frequency "$CPU_ROOT/policy0/scaling_max_freq" 625000
    [[ $(< "$CPU_ROOT/policy0/scaling_max_freq") == 625000 ]]
    wait
}

@test "persistent frequency mismatch fails with a bounded wait" {
    request_frequency() { :; }
    sleep() { :; }
    run write_frequency "$CPU_ROOT/policy0/scaling_max_freq" 625000
    [[ $status -ne 0 ]]
    [[ $output == *'still reads 2000000 after 2 seconds'* ]]
    [[ $output == *'partially applied'* ]]
}

@test "failure to write is reported without waiting for readback" {
    request_frequency() { return 1; }
    wait_frequency() { echo 'unexpected readback'; }
    run write_frequency "$CPU_ROOT/policy0/scaling_max_freq" 625000
    [[ $status -ne 0 ]]
    [[ $output != *'unexpected readback'* ]]
}

@test "final verification detects limits overwritten later" {
    systemctl() {
        echo 1000000 > "$CPU_ROOT/policy0/scaling_max_freq"
    }
    sleep() { :; }
    run apply_policy
    [[ $status -ne 0 ]]
    [[ $output == *'still reads 1000000'* ]]
    [[ $output != *'Applied.'* ]]
}

@test "lock contention fails within the configured bound" {
    LOCK_FILE="$BATS_TEST_TMPDIR/laptop-power.lock"
    LOCK_WAIT_SECONDS=0.1
    exec 8>"$LOCK_FILE"
    flock -x 8

    run acquire_lock

    [[ $status -ne 0 ]]
    [[ $output == *'after 0.1 seconds'* ]]
}

@test "installer writes periodic, power-event, lid, sleep, and wakeup hooks" {
    REPO_DIR=/opt/jan
    SYSTEMD_DIR="$BATS_TEST_TMPDIR/systemd"
    ACPI_EVENTS_DIR="$BATS_TEST_TMPDIR/acpi"
    UDEV_RULES_DIR="$BATS_TEST_TMPDIR/udev"
    source "$BATS_TEST_DIRNAME/../../usr/sbin/install-laptop-power"

    write_configuration

    grep -q '^ExecStart=/opt/jan/usr/sbin/laptop-power$' \
        "$SYSTEMD_DIR/laptop-power.service"
    grep -q '^TimeoutStartSec=30s$' "$SYSTEMD_DIR/laptop-power.service"
    grep -q '^StartLimitIntervalSec=0$' \
        "$SYSTEMD_DIR/laptop-power-event.service"
    grep -q '^ExecStartPre=-/opt/jan/usr/sbin/laptop-power$' \
        "$SYSTEMD_DIR/laptop-power-event.service"
    grep -q '^ExecStart=/usr/bin/sleep 30$' \
        "$SYSTEMD_DIR/laptop-power-event.service"
    [[ $(grep -c '^ExecStart=/opt/jan/usr/sbin/laptop-power$' \
        "$SYSTEMD_DIR/laptop-power-event.service") -eq 1 ]]
    grep -q '^OnUnitInactiveSec=10min$' "$SYSTEMD_DIR/laptop-power.timer"
    grep -q '^WantedBy=timers.target$' "$SYSTEMD_DIR/laptop-power.timer"
    grep -q '^DefaultDependencies=no$' "$SYSTEMD_DIR/laptop-power-sleep.service"
    grep -q '^Before=sleep.target$' "$SYSTEMD_DIR/laptop-power-sleep.service"
    grep -q '^ExecStart=-/opt/jan/usr/sbin/laptop-power --no-suspend$' \
        "$SYSTEMD_DIR/laptop-power-sleep.service"
    grep -q '^ExecStop=-/opt/jan/usr/sbin/laptop-power --no-suspend$' \
        "$SYSTEMD_DIR/laptop-power-sleep.service"
    grep -q '^TimeoutStartSec=15s$' "$SYSTEMD_DIR/laptop-power-sleep.service"
    grep -q '^TimeoutStopSec=15s$' "$SYSTEMD_DIR/laptop-power-sleep.service"
    grep -q 'button/lid' "$ACPI_EVENTS_DIR/laptop-power"
    grep -q 'ac_adapter' "$ACPI_EVENTS_DIR/laptop-power"
    grep -q 'restart --no-block laptop-power-event.service' \
        "$ACPI_EVENTS_DIR/laptop-power"
    grep -q 'SUBSYSTEM=="power_supply"' \
        "$UDEV_RULES_DIR/80-laptop-power.rules"
    grep -q 'RUN+="/usr/bin/systemctl restart --no-block laptop-power-event.service"' \
        "$UDEV_RULES_DIR/80-laptop-power.rules"
}
