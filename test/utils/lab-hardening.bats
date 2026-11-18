#!/usr/bin/env bats
# ci: fixture

setup() {
    ETC="$BATS_TEST_TMPDIR/etc"
    LIBEXEC="$BATS_TEST_TMPDIR/libexec"
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
    write_namespace_config lab1 lab2
    write_lab_session
    write_pam_snippet
    install_systemd_user
    install_common_session
    write_lab_policies 1280% lab1 lab2
}

@test "lab users get a fresh tmpfs /tmp; all but root a private /var/tmp" {
    configure
    # /tmp is a per-session tmpfs, not a bind: Codex's bwrap sandbox breaks on
    # a bound /tmp/tmp-inst/USER instance. Only lab users get it; others keep
    # the shared /tmp across their sessions.
    grep -Eq '^/tmp +/tmp/tmp-inst/ +tmpfs:mntopts=nosuid,nodev,size=10g,nr_inodes=4m +~lab1,lab2$' "$ETC/security/namespace.conf"
    grep -Eq '^/var/tmp +/var/tmp/tmp-inst/ +user +root$' "$ETC/security/namespace.conf"
    run grep -Eq '^[dX] /tmp/tmp-inst' "$ETC/tmpfiles.d/jan-namespace.conf"
    [[ $status -ne 0 ]]
    grep -qx 'd /var/tmp/tmp-inst 0000 root root -' "$ETC/tmpfiles.d/jan-namespace.conf"
    grep -qx 'X /var/tmp/tmp-inst' "$ETC/tmpfiles.d/jan-namespace.conf"
    grep -qx 'Before=systemd-tmpfiles-setup.service shutdown.target' \
        "$ETC/systemd/system/tmp-clean.service.d/50-jan-namespace.conf"
    bash -n "$SESSION_HELPER"
    grep -q 'org.kde.plasma.networkmanagement.so' "$SESSION_HELPER"
    grep -q 'kded/networkmanagement.so' "$SESSION_HELPER"
    [[ -x $SESSION_HELPER ]]
    # pam_exec cannot execute etc_t files under SELinux enforcing.
    [[ $SESSION_HELPER == "$LIBEXEC/lab-session" && ! -e $ETC/security/jan-lab-session ]]
}

@test "lab sessions require the namespace; other users get it when possible" {
    configure
    local -a stack
    mapfile -t stack < <(grep '^session' "$ETC/pam.d/jan-namespace")
    [[ ${stack[0]} == 'session [success=2 default=ignore] pam_succeed_if.so quiet user ingroup lab' ]]
    [[ ${stack[1]} == 'session optional pam_namespace.so mount_private' ]]
    [[ ${stack[2]} == 'session [default=2] pam_permit.so' ]]
    [[ ${stack[3]} == 'session requisite pam_namespace.so mount_private' ]]
    [[ ${stack[4]} == "session required pam_exec.so quiet type=open_session $LIBEXEC/lab-session" ]]
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

@test "lab processes may outlive logout so mosh-server survives its SSH login" {
    local conf="$ETC/systemd/logind.conf.d/60-jan-lab.conf"
    install -d "$ETC/systemd/logind.conf.d"
    printf '%s\n[Login]\nKillUserProcesses=yes\nKillOnlyUsers=lab1 lab2\n' "$MARKER" > "$conf"
    configure
    [[ ! -e $conf ]]
}

@test "an administrator's own logind drop-in is kept" {
    local conf="$ETC/systemd/logind.conf.d/60-jan-lab.conf"
    install -d "$ETC/systemd/logind.conf.d"
    printf '[Login]\nKillUserProcesses=yes\n' > "$conf"
    configure
    grep -qx 'KillUserProcesses=yes' "$conf"
}

@test "lab accounts reach this host only on DNS and ports 10000 and up" {
    configure
    local rules="$ETC/jan/lab-local-network.nft"
    grep -q 'meta skuid { 1201,1202 } oifname "lo" meta l4proto { tcp, udp } th dport 53 accept' "$rules"
    grep -q 'meta skuid { 1201,1202 } oifname "lo" meta l4proto { tcp, udp } th dport >= 10000 accept' "$rules"
    grep -q 'meta skuid { 1201,1202 } oifname "lo" ct state new counter reject' "$rules"
    grep -q 'meta skuid { 1201,1202 } oifname "tailscale0" counter reject' "$rules"
    grep -qx "ExecStart=/usr/sbin/nft -f $ETC/jan/lab-local-network.nft" \
        "$ETC/systemd/system/jan-lab-local-network.service"
    if command -v nft >/dev/null && nft -c -f /dev/null 2>/dev/null; then
        nft -c -f "$rules"
    fi
}

@test "the lab firewall also covers the accounts' subordinate UIDs" {
    printf 'lab1:200000:65536\n1202:300000:65536\nworker:400000:65536\n' > "$ETC/subuid"
    configure
    local rules="$ETC/jan/lab-local-network.nft"
    grep -q 'meta skuid { 1201,1202,200000-265535,300000-365535 } oifname "lo" ct state new counter reject' "$rules"
    grep -qx "ExecReload=/usr/sbin/nft -f $ETC/jan/lab-local-network.nft" \
        "$ETC/systemd/system/jan-lab-local-network.service"
    if command -v nft >/dev/null && nft -c -f /dev/null 2>/dev/null; then
        nft -c -f "$rules"
    fi
}

@test "lab accounts get rootless podman on crun with cgroupfs" {
    configure
    local uid file
    for uid in 1201 1202; do
        file="$ETC/containers/containers.rootless.conf.d/$uid/50-jan-lab.conf"
        is_managed "$file"
        grep -qx 'cgroup_manager = "cgroupfs"' "$file"
        grep -qx 'runtime = "crun"' "$file"
    done
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
    is_managed "$SESSION_HELPER"
    printf '#!/bin/bash\n# administrator script\n' > "$SESSION_HELPER"
    ! is_managed "$SESSION_HELPER"
}

@test "the old etc_t session helper is removed only when managed" {
    mkdir -p "$ETC/security"
    printf '#!/bin/bash\n%s\n' "$MARKER" > "$ETC/security/jan-lab-session"
    configure
    [[ ! -e $ETC/security/jan-lab-session ]]
    printf '#!/bin/bash\n# administrator script\n' > "$ETC/security/jan-lab-session"
    configure
    [[ -e $ETC/security/jan-lab-session ]]
}

@test "private tmp setup preserves the distro namespace initialization" {
    mkdir -p "$ETC/security"
    echo '# vendor X11 setup' > "$ETC/security/namespace.init"
    configure
    [[ $(cat "$ETC/security/namespace.init") == '# vendor X11 setup' ]]
    grep -qx 'DefaultDependencies=no' "$ETC/systemd/system/tmp-clean.service.d/50-jan-namespace.conf"
    grep -qx 'Conflicts=shutdown.target' "$ETC/systemd/system/tmp-clean.service.d/50-jan-namespace.conf"
}
