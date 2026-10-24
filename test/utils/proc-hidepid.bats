#!/usr/bin/env bats
# ci: fixture

setup() {
    UNIT_DIR="$BATS_TEST_TMPDIR/units"
    LOGIN_DEFS="$BATS_TEST_TMPDIR/login.defs"
    printf 'UID_MIN 1000\nUID_MAX 60000\n' > "$LOGIN_DEFS"
    source "$BATS_TEST_DIRNAME/../../usr/sbin/setup-proc-hidepid"

    getent() {
        case $1:${2:-} in
            group:lab) echo 'lab:x:470:lab1,lab2' ;;
            group:*) return 2 ;;
            passwd:)
                cat <<'PASSWD'
root:x:0:0:root:/root:/bin/bash
polkitd:x:470:470::/var/lib/polkit:/usr/sbin/nologin
jan:x:1000:100::/home/jan:/bin/bash
play1:x:1001:100::/home/play1:/usr/bin/fish
lab1:x:1101:100::/home/lab1:/bin/bash
lab2:x:1102:100::/home/lab2:/bin/bash
labprimary:x:1103:470::/home/labprimary:/bin/bash
web:x:1200:65534::/var/pod/web:/usr/sbin/nologin
nobody:x:65534:65534::/:/bin/false
PASSWD
                ;;
        esac
    }
}

@test "only interactive non-lab accounts keep the full process view" {
    run visible_users
    [[ $status -eq 0 ]]
    [[ $output == $'jan\nplay1' ]]
}

@test "boot unit hides PIDs from everyone outside the proc group" {
    write_configuration 481
    local unit="$UNIT_DIR/proc-hidepid.service"
    grep -qx 'ExecStart=/bin/mount -o remount,hidepid=invisible,gid=481 /proc' "$unit"
    grep -qx 'Before=sysinit.target' "$unit"
    grep -qx 'WantedBy=sysinit.target' "$unit"
}

@test "services that read other users' processes join the proc group" {
    write_configuration 481
    local unit
    for unit in systemd-logind polkit rtkit-daemon NetworkManager dbus-broker dbus; do
        grep -qx 'SupplementaryGroups=proc' \
            "$UNIT_DIR/$unit.service.d/50-proc-hidepid.conf"
    done
}

@test "rerunning produces identical files" {
    write_configuration 481
    local first
    first=$(find "$UNIT_DIR" -type f -exec cat {} +)
    write_configuration 481
    [[ $(find "$UNIT_DIR" -type f -exec cat {} +) == "$first" ]]
}
