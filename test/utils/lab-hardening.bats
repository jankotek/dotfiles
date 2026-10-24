#!/usr/bin/env bats
# ci: fixture

setup() {
    ETC="$BATS_TEST_TMPDIR/etc"
    VENDOR_PAM_DIRS="$BATS_TEST_TMPDIR/vendor"
    mkdir -p "$ETC/pam.d" "$VENDOR_PAM_DIRS"
    echo 'session optional pam_systemd.so' > "$ETC/pam.d/common-session-pc"
    ln -s common-session-pc "$ETC/pam.d/common-session"
    printf 'account include common-account\nsession include common-session-nonlogin\n' \
        > "$VENDOR_PAM_DIRS/systemd-user"
    source "$BATS_TEST_DIRNAME/../../usr/sbin/setup-lab-hardening"
    id() {
        case ${!#} in
            lab1) echo 1201 ;;
            lab2) echo 1202 ;;
            *) return 1 ;;
        esac
    }
}

configure() {
    write_namespace_config
    write_lab_session
    write_pam_snippet
    install_systemd_user
    install_common_session
    write_lab_policies 1280% lab1 lab2
}

@test "every user but root gets a private /tmp and /var/tmp" {
    configure
    grep -Eq '^/tmp +/tmp/tmp-inst/ +user +root$' "$ETC/security/namespace.conf"
    grep -Eq '^/var/tmp +/var/tmp/tmp-inst/ +user +root$' "$ETC/security/namespace.conf"
    grep -qx 'd /tmp/tmp-inst 0000 root root -' "$ETC/tmpfiles.d/jan-namespace.conf"
    grep -qx 'X /tmp/tmp-inst' "$ETC/tmpfiles.d/jan-namespace.conf"
    grep -qx 'Before=systemd-tmpfiles-setup.service shutdown.target' \
        "$ETC/systemd/system/tmp-clean.service.d/50-jan-namespace.conf"
    bash -n "$ETC/security/jan-lab-session"
    [[ -x $ETC/security/jan-lab-session ]]
}

@test "lab sessions require the namespace; other users get it when possible" {
    configure
    local -a stack
    mapfile -t stack < <(grep '^session' "$ETC/pam.d/jan-namespace")
    [[ ${stack[0]} == 'session [success=2 default=ignore] pam_succeed_if.so quiet user ingroup lab' ]]
    [[ ${stack[1]} == 'session optional pam_namespace.so mount_private' ]]
    [[ ${stack[2]} == 'session [default=2] pam_permit.so' ]]
    [[ ${stack[3]} == 'session requisite pam_namespace.so mount_private' ]]
    [[ ${stack[4]} == "session required pam_exec.so quiet type=open_session $ETC/security/jan-lab-session" ]]
}

@test "common-session keeps pam-config's stack and adds the namespace after it" {
    configure
    [[ ! -L $ETC/pam.d/common-session ]]
    [[ $(grep '^session' "$ETC/pam.d/common-session") == \
        $'session include common-session-pc\nsession include jan-namespace' ]]
    # Rerunning reads the include back from the managed file.
    configure
    [[ $(grep -c '^session' "$ETC/pam.d/common-session") -eq 2 ]]
}

@test "an administrator's own common-session is never replaced" {
    rm "$ETC/pam.d/common-session"
    echo 'session include common-session-pc' > "$ETC/pam.d/common-session"
    run install_common_session
    [[ $status -ne 0 ]]
    [[ $(cat "$ETC/pam.d/common-session") == 'session include common-session-pc' ]]
}

@test "systemd --user sessions get the namespace too" {
    configure
    [[ $(tail -1 "$ETC/pam.d/systemd-user") == 'session include jan-namespace' ]]
    grep -qx 'session include common-session-nonlogin' "$ETC/pam.d/systemd-user"
}

@test "no systemd-user override when its stack already includes common-session" {
    printf 'session include common-session\n' > "$VENDOR_PAM_DIRS/systemd-user"
    configure
    [[ ! -e $ETC/pam.d/systemd-user ]]
}

@test "lab slices get high memory, CPU, and task caps" {
    configure
    local uid conf
    for uid in 1201 1202; do
        conf="$ETC/systemd/system/user-$uid.slice.d/50-jan-lab-limits.conf"
        grep -qx 'MemoryHigh=70%' "$conf"
        grep -qx 'MemoryMax=80%' "$conf"
        grep -qx 'CPUQuota=1280%' "$conf"
        grep -qx 'TasksMax=8192' "$conf"
    done
}

@test "logind kills only lab processes at logout" {
    configure
    local conf="$ETC/systemd/logind.conf.d/60-jan-lab.conf"
    grep -qx 'KillUserProcesses=yes' "$conf"
    grep -qx 'KillOnlyUsers=lab1 lab2' "$conf"
}

@test "lab accounts reach this host only on DNS and ports 10000 and up" {
    configure
    local rules="$ETC/jan/lab-local-network.nft"
    grep -q 'meta skuid { 1201,1202 } oifname "lo" meta l4proto { tcp, udp } th dport 53 accept' "$rules"
    grep -q 'meta skuid { 1201,1202 } oifname "lo" meta l4proto { tcp, udp } th dport >= 10000 accept' "$rules"
    grep -q 'meta skuid { 1201,1202 } oifname "lo" ct state new counter reject' "$rules"
    grep -qx "ExecStart=/usr/sbin/nft -f $ETC/jan/lab-local-network.nft" \
        "$ETC/systemd/system/jan-lab-local-network.service"
    if command -v nft >/dev/null && nft -c -f /dev/null 2>/dev/null; then
        nft -c -f "$rules"
    fi
}

@test "cron and at deny lab accounts once, keeping existing entries" {
    echo guest > "$ETC/cron.deny"
    configure
    configure
    [[ $(cat "$ETC/cron.deny") == $'guest\nlab1\nlab2' ]]
    [[ $(cat "$ETC/at.deny") == $'lab1\nlab2' ]]
}

@test "managed session helper survives the installer rerun preflight" {
    configure
    is_managed "$ETC/security/namespace.conf"
    is_managed "$ETC/security/jan-lab-session"
    printf '#!/bin/bash\n# administrator script\n' > "$ETC/security/jan-lab-session"
    ! is_managed "$ETC/security/jan-lab-session"
}

@test "private tmp setup preserves the distro namespace initialization" {
    mkdir -p "$ETC/security"
    echo '# vendor X11 setup' > "$ETC/security/namespace.init"
    configure
    [[ $(cat "$ETC/security/namespace.init") == '# vendor X11 setup' ]]
    grep -qx 'DefaultDependencies=no' "$ETC/systemd/system/tmp-clean.service.d/50-jan-namespace.conf"
    grep -qx 'Conflicts=shutdown.target' "$ETC/systemd/system/tmp-clean.service.d/50-jan-namespace.conf"
}
