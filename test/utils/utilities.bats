#!/usr/bin/env bats

load ../helpers

setup() {
    export UTIL_TMP="$BATS_TEST_TMPDIR/utilities"
    mkdir -p "$UTIL_TMP/bin" "$UTIL_TMP/home" "$UTIL_TMP/out"
}

@test "new utility commands provide help" {
    local utility
    for utility in \
        clean-check \
        host-doctor \
        dotfiles-diff \
        opt-status \
        pod-doctor \
        sshd-audit \
        verified-download \
        vm-list \
        vm-reset \
        vm-smoke; do
        run "$OPT_JAN/usr/bin/$utility" --help
        [[ $status -eq 0 ]]
        [[ $output == Usage:* ]]
    done
}

@test "dotfiles-diff previews canonical files without modifying home" {
    run env OPT_JAN="$OPT_JAN" \
        "$OPT_JAN/usr/bin/dotfiles-diff" "$UTIL_TMP/home"
    [[ $status -eq 0 ]]
    [[ $output == *".bashrc"* ]]
    [[ ! -e "$UTIL_TMP/home/.bashrc" ]]
}

@test "dotfiles-diff explains how to seed a missing account" {
    run env OPT_JAN="$OPT_JAN" \
        "$OPT_JAN/usr/bin/dotfiles-diff" jan-user-that-does-not-exist
    [[ $status -eq 2 ]]
    [[ $output == *"skel/install"* ]]
    [[ $output == *"useradd --create-home"* ]]
}

@test "verified-download verifies checksum and publishes atomically" {
    cat > "$UTIL_TMP/bin/aria2c" <<'EOF'
#!/bin/bash
set -euo pipefail
for argument in "$@"; do
    case "$argument" in
        --dir=*) destination_dir=${argument#--dir=} ;;
        --out=*) destination_name=${argument#--out=} ;;
        file://*) source_file=${argument#file://} ;;
    esac
done
cp "$source_file" "$destination_dir/$destination_name"
EOF
    chmod +x "$UTIL_TMP/bin/aria2c"
    checksum=$(sha256sum "$OPT_JAN/README.md" | awk '{print $1}')

    run env PATH="$UTIL_TMP/bin:$PATH" \
        "$OPT_JAN/usr/bin/verified-download" \
        "file://$OPT_JAN/README.md" "$UTIL_TMP/out/readme" "$checksum"
    [[ $status -eq 0 ]]
    cmp "$OPT_JAN/README.md" "$UTIL_TMP/out/readme"
    [[ ! -e "$UTIL_TMP/out/readme.partial" ]]
    [[ ! -e "$UTIL_TMP/out/readme.partial.url" ]]
}

@test "verified-download rejects an invalid checksum before downloading" {
    run env PATH="$UTIL_TMP/bin:$PATH" \
        "$OPT_JAN/usr/bin/verified-download" \
        https://example.invalid/file "$UTIL_TMP/out/file" invalid
    [[ $status -eq 2 ]]
    [[ ! -e "$UTIL_TMP/out/file" ]]
    [[ ! -e "$UTIL_TMP/out/file.partial" ]]
}

@test "verified-download deletes content after a checksum mismatch" {
    cat > "$UTIL_TMP/bin/aria2c" <<'EOF'
#!/bin/bash
set -euo pipefail
for argument in "$@"; do
    case "$argument" in
        --dir=*) destination_dir=${argument#--dir=} ;;
        --out=*) destination_name=${argument#--out=} ;;
        file://*) source_file=${argument#file://} ;;
    esac
done
cp "$source_file" "$destination_dir/$destination_name"
EOF
    chmod +x "$UTIL_TMP/bin/aria2c"

    run env PATH="$UTIL_TMP/bin:$PATH" \
        "$OPT_JAN/usr/bin/verified-download" \
        "file://$OPT_JAN/README.md" "$UTIL_TMP/out/bad" \
        0000000000000000000000000000000000000000000000000000000000000000
    [[ $status -eq 1 ]]
    [[ ! -e "$UTIL_TMP/out/bad" ]]
    [[ ! -e "$UTIL_TMP/out/bad.partial" ]]
    [[ ! -e "$UTIL_TMP/out/bad.partial.url" ]]
}

@test "vm-reset refuses to reset a VM from itself" {
    run "$OPT_JAN/usr/bin/vm-reset" same-vm same-vm
    [[ $status -eq 2 ]]
    [[ $output == *"must differ"* ]]
}

@test "vm-list reports base and overlay disks without querying a shut-off guest" {
    local bin="$UTIL_TMP/bin" log="$UTIL_TMP/agent.log"
    cat > "$bin/virsh" <<EOF
#!/bin/bash
set -euo pipefail
if [[ \${1:-} == -c ]]; then shift 2; fi
cmd=\$1
shift
case "\$cmd" in
    list) printf 'basevm\\nclonevm\\n' ;;
    domstate)
        case \$1 in
            basevm) printf 'shut off\\n' ;;
            clonevm) printf 'running\\n' ;;
        esac
        ;;
    domblklist)
        case \$1 in
            basevm) printf 'file disk vda /images/base.qcow2\\n' ;;
            clonevm) printf 'file disk vda /images/clone.qcow2\\n' ;;
        esac
        ;;
    qemu-agent-command)
        printf '%s\\n' "\$1" >> "$log"
        printf '%s\\n' '{"return":[{"name":"lo","ip-addresses":[{"ip-address-type":"ipv4","ip-address":"127.0.0.1","prefix":8}]},{"name":"eth0","ip-addresses":[{"ip-address-type":"ipv4","ip-address":"192.168.122.20","prefix":24},{"ip-address-type":"ipv6","ip-address":"fe80::1","prefix":64}]}]}'
        ;;
    *) exit 1 ;;
esac
EOF
    cat > "$bin/qemu-img" <<'EOF'
#!/bin/bash
set -euo pipefail
path=${*: -1}
case "$path" in
    /images/base.qcow2)
        printf '%s\n' '{"format":"qcow2","actual-size":8589934592}'
        ;;
    /images/clone.qcow2)
        printf '%s\n' '{"format":"qcow2","actual-size":125829120,"full-backing-filename":"/images/base.qcow2"}'
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$bin/virsh" "$bin/qemu-img"

    run env PATH="$bin:$PATH" "$OPT_JAN/usr/bin/vm-list"
    [[ $status -eq 0 ]]
    [[ $output == *$'basevm                   shut off     base           8192  -                -'* ]]
    [[ $output == *$'clonevm                  running      overlay         120  192.168.122.20   base.qcow2'* ]]
    [[ $(cat "$log") == clonevm ]]
}

@test "vm-list reports a missing disk file without a zero size" {
    local bin="$UTIL_TMP/bin"
    cat > "$bin/virsh" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ ${1:-} == -c ]]; then shift 2; fi
cmd=$1
shift
case "$cmd" in
    list) printf 'gonevm\n' ;;
    domstate) printf 'shut off\n' ;;
    domblklist) printf 'file disk vda /images/missing.qcow2\n' ;;
    *) exit 1 ;;
esac
EOF
    cat > "$bin/qemu-img" <<'EOF'
#!/bin/bash
echo "No such file or directory" >&2
exit 1
EOF
    chmod +x "$bin/virsh" "$bin/qemu-img"

    run env PATH="$bin:$PATH" "$OPT_JAN/usr/bin/vm-list"
    [[ $status -eq 0 ]]
    [[ $output == *$'gonevm                   shut off     missing           -  -                -'* ]]
    [[ $output != *unknown* ]]
}

@test "vm-list keeps disk paths that contain spaces" {
    local bin="$UTIL_TMP/bin" log="$UTIL_TMP/qemu-img.log"
    cat > "$bin/virsh" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ ${1:-} == -c ]]; then shift 2; fi
cmd=$1
shift
case "$cmd" in
    list) printf 'spacevm\n' ;;
    domstate) printf 'shut off\n' ;;
    domblklist) printf 'file disk vda /images/my disk.qcow2\n' ;;
    *) exit 1 ;;
esac
EOF
    cat > "$bin/qemu-img" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\\n' "\$*" >> "$log"
[[ \${*: -2:1} == -- ]]
path=\${*: -1}
[[ \$path == '/images/my disk.qcow2' ]]
printf '%s\\n' '{"format":"qcow2","actual-size":1048576}'
EOF
    chmod +x "$bin/virsh" "$bin/qemu-img"

    run env PATH="$bin:$PATH" "$OPT_JAN/usr/bin/vm-list"
    [[ $status -eq 0 ]]
    [[ $output == *$'spacevm                  shut off     base              1  -                -'* ]]
    [[ -s $log ]]
}

@test "vm-list treats missing disk metadata as unknown" {
    local bin="$UTIL_TMP/bin"
    cat > "$bin/virsh" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ ${1:-} == -c ]]; then shift 2; fi
cmd=$1
shift
case "$cmd" in
    list) printf 'badjson\nnosize\n' ;;
    domstate) printf 'shut off\n' ;;
    domblklist)
        case $1 in
            badjson|nosize) printf 'file disk vda /images/%s.qcow2\n' "$1" ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    cat > "$bin/qemu-img" <<'EOF'
#!/bin/bash
set -euo pipefail
path=${*: -1}
case "$path" in
    /images/badjson.qcow2) printf 'not-json\n' ;;
    /images/nosize.qcow2) printf '%s\n' '{"format":"qcow2"}' ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$bin/virsh" "$bin/qemu-img"

    run env PATH="$bin:$PATH" "$OPT_JAN/usr/bin/vm-list"
    [[ $status -eq 0 ]]
    [[ $output == *$'badjson                  shut off     unknown           -  -                -'* ]]
    [[ $output == *$'nosize                   shut off     unknown           -  -                -'* ]]
    [[ $output != *base* ]]
}

@test "vm-list rejects string disk sizes and hides partial totals" {
    local bin="$UTIL_TMP/bin"
    cat > "$bin/virsh" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ ${1:-} == -c ]]; then shift 2; fi
cmd=$1
shift
case "$cmd" in
    list) printf 'zero\nstrsize\noctal\npair\n' ;;
    domstate) printf 'shut off\n' ;;
    domblklist)
        case $1 in
            pair)
                printf 'file disk vda /images/pair-a.qcow2\n'
                printf 'file disk vdb /images/pair-b.qcow2\n'
                ;;
            *) printf 'file disk vda /images/%s.qcow2\n' "$1" ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    cat > "$bin/qemu-img" <<'EOF'
#!/bin/bash
set -euo pipefail
path=${*: -1}
case "$path" in
    /images/zero.qcow2) printf '%s\n' '{"actual-size":0}' ;;
    /images/strsize.qcow2) printf '%s\n' '{"actual-size":"1048576"}' ;;
    /images/octal.qcow2) printf '%s\n' '{"actual-size":"08"}' ;;
    /images/pair-a.qcow2) printf '%s\n' '{"actual-size":1048576}' ;;
    /images/pair-b.qcow2) printf 'not-json\n' ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$bin/virsh" "$bin/qemu-img"

    run env PATH="$bin:$PATH" "$OPT_JAN/usr/bin/vm-list"
    [[ $status -eq 0 ]]
    [[ $output == *$'zero                     shut off     base              0  -                -'* ]]
    [[ $output == *$'strsize                  shut off     unknown           -  -                -'* ]]
    [[ $output == *$'octal                    shut off     unknown           -  -                -'* ]]
    [[ $output == *$'pair                     shut off     unknown           -  -                -'* ]]
}

@test "vm-list rejects extra arguments" {
    run "$OPT_JAN/usr/bin/vm-list" extra
    [[ $status -eq 2 ]]
}

@test "clean-check reports journals, storage, model caches, and kernel sizes" {
    local root="$UTIL_TMP/root" bin="$UTIL_TMP/bin"
    mkdir -p \
        "$root/home/alice-backup-2020" \
        "$root/home/alice/.cache/huggingface/hub" \
        "$root/home/alice/.local/share/containers/storage" \
        "$root/var/log/journal/system" \
        "$root/var/lib/containers/storage" \
        "$root/var/pod/demo/.local/share/containers/storage" \
        "$root/var/pod/demo/.cache/huggingface"
    printf 'backup\n' > "$root/home/alice-backup-2020/note"
    printf 'weights\n' > "$root/home/alice/.cache/huggingface/hub/blob"
    printf 'journal\n' > "$root/var/log/journal/system/system.journal"
    printf 'layers\n' > "$root/var/lib/containers/storage/layer"
    printf 'pod\n' > "$root/var/pod/demo/.local/share/containers/storage/layer"
    printf 'pod-model\n' > "$root/var/pod/demo/.cache/huggingface/blob"
    cat > "$bin/rpm" <<'EOF'
#!/bin/bash
printf '%s\t%s\n' 'bash-5.2-1.x86_64' 1000
printf '%s\t%s\n' 'kernel-zbook-6.12.0-1.x86_64' 209715200
printf '%s\t%s\n' 'kernel-default-6.12.0-1.x86_64' 104857600
EOF
    cat > "$bin/virsh" <<'EOF'
#!/bin/bash
echo "virsh should not run during a prefixed scan" >&2
exit 99
EOF
    cat > "$bin/qemu-img" <<'EOF'
#!/bin/bash
echo "qemu-img should not run during a prefixed scan" >&2
exit 99
EOF
    chmod +x "$bin/rpm" "$bin/virsh" "$bin/qemu-img"

    run env PATH="$bin:$PATH" CLEAN_CHECK_ROOT="$root" CLEAN_CHECK_KERNEL_QUERY=rpm \
        "$OPT_JAN/usr/bin/clean-check" 0
    [[ $status -eq 0 ]]
    [[ $output == *"alice-backup-2020"* ]]
    [[ $output == *"$root/var/log/journal"* ]]
    [[ $output == *"$root/var/lib/containers/storage"* ]]
    [[ $output == *"$root/home/alice/.local/share/containers/storage"* ]]
    [[ $output == *"$root/var/pod/demo/.local/share/containers/storage"* ]]
    [[ $output == *"$root/home/alice/.cache/huggingface"* ]]
    [[ $output == *"$root/var/pod/demo/.cache/huggingface"* ]]
    [[ $output == *"100 MiB  kernel-default-6.12.0-1.x86_64"* ]]
    [[ $output == *"200 MiB  kernel-zbook-6.12.0-1.x86_64"* ]]
    [[ $output != *"bash-5.2"* ]]
    [[ $output != *"Unattached qcow2 overlays:"*$'\n'*"/images"* ]]
}

@test "clean-check reports dpkg kernel package sizes" {
    local bin="$UTIL_TMP/bin" root="$UTIL_TMP/empty-root"
    mkdir -p "$root"
    cat > "$bin/dpkg-query" <<'EOF'
#!/bin/bash
printf '%s\t%s\n' 'linux-image-6.8.0-1-generic 6.8.0-1' 204800
EOF
    chmod +x "$bin/dpkg-query"

    run env PATH="$bin:$PATH" CLEAN_CHECK_ROOT="$root" CLEAN_CHECK_KERNEL_QUERY=dpkg \
        "$OPT_JAN/usr/bin/clean-check" 512
    [[ $status -eq 0 ]]
    [[ $output == *"200 MiB  linux-image-6.8.0-1-generic 6.8.0-1"* ]]
    [[ $output == *"Journal:"*$'\n'"absent"* ]]
    [[ $output == *"Podman storage:"*$'\n'"none"* ]]
    [[ $output == *"Hugging Face caches:"*$'\n'"none"* ]]
}

@test "pod-doctor accepts one healthy pod" {
    local root="$UTIL_TMP/pods" bin="$UTIL_TMP/bin"
    mkdir -p \
        "$root/var/pod/goodpod/bin" \
        "$root/var/pod/goodpod/.config/containers/systemd" \
        "$root/var/pod/stray/data" \
        "$root/var/lib/systemd/linger" \
        "$root/etc"
    printf 'ok\n' > "$root/var/pod/goodpod/bin/upgrade"
    printf 'goodpod-app.service\n' > "$root/var/pod/goodpod/.service-name"
    printf '[Container]\n' > "$root/var/pod/goodpod/.config/containers/systemd/app.container"
    : > "$root/var/lib/systemd/linger/goodpod"
    printf 'goodpod:100000:65536\n201001:100000:65536\n' > "$root/etc/subuid"
    printf 'goodpod:100000:65536' > "$root/etc/subgid"
    cat > "$bin/id" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ ${1:-} == -u && ${2:-} == -- ]]
case ${3:-} in
    goodpod) printf '201001\n' ;;
    *) exit 1 ;;
esac
EOF
    cat > "$bin/systemctl" <<'EOF'
#!/bin/bash
set -euo pipefail
joined="$*"
if [[ $joined == *LoadState* ]]; then
    [[ $joined == *--machine=goodpod@* ]]
    printf 'loaded\n'
    exit 0
fi
if [[ $joined == *Delegate* ]]; then
    [[ $joined == *user@201001.service* ]]
    printf 'yes\n'
    exit 0
fi
exit 1
EOF
    chmod +x "$bin/id" "$bin/systemctl"

    run env PATH="$bin:$PATH" POD_DOCTOR_ROOT="$root" "$OPT_JAN/usr/bin/pod-doctor"
    [[ $status -eq 0 ]]
    [[ $output == *"OK: goodpod subordinate IDs match (100000:65536)"* ]]
    [[ $output == *"OK: goodpod linger is enabled"* ]]
    [[ $output == *"OK: goodpod quadlet goodpod-app.service is loaded"* ]]
    [[ $output == *"OK: goodpod cgroup delegation is yes"* ]]
    [[ $output == *"Doctor found no problems."* ]]
    [[ $output != *stray* ]]
}

@test "pod-doctor reports mismatched ids, quadlet load, and delegation fallback" {
    local root="$UTIL_TMP/pods" bin="$UTIL_TMP/bin"
    mkdir -p \
        "$root/var/pod/badpod/bin" \
        "$root/var/pod/halfpod/bin" \
        "$root/var/pod/halfpod/.config/containers/systemd" \
        "$root/var/lib/systemd/linger" \
        "$root/etc/systemd/system/user@201003.service.d" \
        "$root/etc"
    printf 'ok\n' > "$root/var/pod/badpod/bin/upgrade"
    printf 'ok\n' > "$root/var/pod/halfpod/bin/upgrade"
    printf 'halfpod-app.service\n' > "$root/var/pod/halfpod/.service-name"
    printf '[Container]\n' > "$root/var/pod/halfpod/.config/containers/systemd/app.container"
    : > "$root/var/lib/systemd/linger/halfpod"
    printf 'badpod:200000:65536\nbadpod:0100000:65536\nbadpod:100000:65536:\nhalfpod:400000:65536\n' > "$root/etc/subuid"
    printf 'badpod:300000:65536\nhalfpod:400000:65536\n' > "$root/etc/subgid"
    printf '[Service]\nDelegate=cpu cpuset io memory pids\n' \
        > "$root/etc/systemd/system/user@201003.service.d/delegate.conf"
    cat > "$bin/id" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ ${1:-} == -u && ${2:-} == -- ]]
case ${3:-} in
    badpod) printf '201002\n' ;;
    halfpod) printf '201003\n' ;;
    *) exit 1 ;;
esac
EOF
    cat > "$bin/systemctl" <<'EOF'
#!/bin/bash
set -euo pipefail
joined="$*"
if [[ $joined == *LoadState* ]]; then
    printf 'not-found\n'
    exit 0
fi
if [[ $joined == *Delegate* && $joined == *user@201002.service* ]]; then
    printf 'memory\n'
    exit 0
fi
exit 1
EOF
    chmod +x "$bin/id" "$bin/systemctl"

    run env PATH="$bin:$PATH" POD_DOCTOR_ROOT="$root" "$OPT_JAN/usr/bin/pod-doctor"
    [[ $status -eq 1 ]]
    [[ $output == *"WARN: badpod invalid subordinate ID entry in $root/etc/subuid: badpod:0100000:65536"* ]]
    [[ $output == *"WARN: badpod invalid subordinate ID entry in $root/etc/subuid: badpod:100000:65536:"* ]]
    [[ $output == *"WARN: badpod subordinate IDs differ (subuid 200000:65536; subgid 300000:65536)"* ]]
    [[ $output == *"WARN: badpod linger is disabled"* ]]
    [[ $output == *"WARN: badpod has no quadlet files"* ]]
    [[ $output == *"WARN: badpod cgroup delegation is 'memory'"* ]]
    [[ $output == *"OK: halfpod subordinate IDs match (400000:65536)"* ]]
    [[ $output == *"WARN: halfpod quadlet halfpod-app.service load state is not-found"* ]]
    [[ $output == *"OK: halfpod cgroup delegation is cpu cpuset io memory pids"* ]]
    [[ $output == *"Doctor found 7 warning(s)."* ]]
}

@test "pod-doctor succeeds when no pods exist" {
    local root="$UTIL_TMP/nopods"
    mkdir -p "$root"

    run env POD_DOCTOR_ROOT="$root" "$OPT_JAN/usr/bin/pod-doctor"
    [[ $status -eq 0 ]]
    [[ $output == *"OK: no pods"* ]]
    [[ $output == *"Doctor found no problems."* ]]
    [[ $output != *WARN:* ]]
}

@test "pod-doctor ignores a drop-in when systemctl reports an empty Delegate" {
    local root="$UTIL_TMP/pods" bin="$UTIL_TMP/bin"
    mkdir -p \
        "$root/var/pod/emptydel/bin" \
        "$root/var/pod/emptydel/.config/containers/systemd" \
        "$root/var/lib/systemd/linger" \
        "$root/etc/systemd/system/user@201004.service.d" \
        "$root/etc"
    printf 'ok\n' > "$root/var/pod/emptydel/bin/upgrade"
    printf 'emptydel-app.service\n' > "$root/var/pod/emptydel/.service-name"
    printf '[Container]\n' > "$root/var/pod/emptydel/.config/containers/systemd/app.container"
    : > "$root/var/lib/systemd/linger/emptydel"
    printf 'emptydel:500000:65536\n' > "$root/etc/subuid"
    printf 'emptydel:500000:65536\n' > "$root/etc/subgid"
    printf '[Service]\nDelegate=yes\n' \
        > "$root/etc/systemd/system/user@201004.service.d/delegate.conf"
    cat > "$bin/id" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ ${1:-} == -u && ${2:-} == -- ]]
[[ ${3:-} == emptydel ]]
printf '201004\n'
EOF
    cat > "$bin/systemctl" <<'EOF'
#!/bin/bash
set -euo pipefail
joined="$*"
if [[ $joined == *LoadState* ]]; then
    printf 'loaded\n'
    exit 0
fi
if [[ $joined == *Delegate* ]]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$bin/id" "$bin/systemctl"

    run env PATH="$bin:$PATH" POD_DOCTOR_ROOT="$root" "$OPT_JAN/usr/bin/pod-doctor"
    [[ $status -eq 1 ]]
    [[ $output == *"WARN: emptydel cgroup delegation is 'unset'"* ]]
    [[ $output != *"cgroup delegation is yes"* ]]
    [[ $output == *"Doctor found 1 warning(s)."* ]]
}

@test "sshd-audit reports an unreadable config once" {
    local dir="$UTIL_TMP/ssh" bin="$UTIL_TMP/bin"
    mkdir -p "$dir" "$bin"
    touch -d @1600000000 "$dir/ssh_host_ed25519_key.pub"
    cat > "$bin/sshd" <<'EOF'
#!/bin/bash
echo "Permission denied" >&2
exit 1
EOF
    chmod +x "$bin/sshd"

    run env PATH="$bin:$PATH" SSHD_AUDIT_KEY_DIR="$dir" "$OPT_JAN/usr/bin/sshd-audit"
    [[ $status -eq 1 ]]
    [[ $output == *"WARN: sshd -T failed: Permission denied"* ]]
    [[ $output == *"PermitRootLogin: unknown"* ]]
    [[ $output == *"PasswordAuthentication: unknown"* ]]
    [[ $output != *"is missing"* ]]
    [[ $output == *"Audit found 1 warning(s)."* ]]
}

@test "sshd-audit accepts restricted login and reports host-key age" {
    local dir="$UTIL_TMP/ssh" bin="$UTIL_TMP/bin" config="$UTIL_TMP/sshd-good.txt"
    mkdir -p "$dir" "$bin"
    printf 'permitrootlogin prohibit-password\npasswordauthentication no\nkbdinteractiveauthentication no\n' \
        > "$config"
    cat > "$bin/sshd" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ ${1:-} == -T ]]
cat "$SSHD_STUB_CONFIG"
EOF
    chmod +x "$bin/sshd"
    touch -d @1600000000 "$dir/ssh_host_ed25519_key.pub"
    local expected=$(( ($(date +%s) - 1600000000) / 86400 ))

    run env PATH="$bin:$PATH" SSHD_AUDIT_KEY_DIR="$dir" SSHD_STUB_CONFIG="$config" \
        "$OPT_JAN/usr/bin/sshd-audit"
    [[ $status -eq 0 ]]
    [[ $output == *"PermitRootLogin: prohibit-password"* ]]
    [[ $output == *"OK: password authentication is disabled"* ]]
    [[ $output == *"ssh_host_ed25519_key.pub  $expected days"* ]]
    [[ $output == *"Host certificates:"*$'\n'"  none"* ]]
    [[ $output == *"Audit found no problems."* ]]
}

@test "sshd-audit warns about password login and an expired host certificate" {
    local dir="$UTIL_TMP/ssh" bin="$UTIL_TMP/bin" config="$UTIL_TMP/sshd-bad.txt"
    mkdir -p "$dir" "$bin"
    printf 'permitrootlogin yes\npasswordauthentication yes\nkbdinteractiveauthentication yes\n' \
        > "$config"
    printf 'cert\n' > "$dir/ssh_host_ed25519_key-cert.pub"
    touch -d @1600000000 "$dir/ssh_host_ed25519_key.pub"
    cat > "$bin/sshd" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ ${1:-} == -T ]]
cat "$SSHD_STUB_CONFIG"
EOF
    cat > "$bin/ssh-keygen" <<'EOF'
#!/bin/bash
printf '        Valid: from 2020-01-01T00:00:00 to 2020-06-01T00:00:00\n'
EOF
    chmod +x "$bin/sshd" "$bin/ssh-keygen"

    run env PATH="$bin:$PATH" SSHD_AUDIT_KEY_DIR="$dir" SSHD_STUB_CONFIG="$config" \
        "$OPT_JAN/usr/bin/sshd-audit"
    [[ $status -eq 1 ]]
    [[ $output == *"WARN: root login is enabled"* ]]
    [[ $output == *"WARN: password authentication is yes"* ]]
    [[ $output == *"WARN: keyboard-interactive authentication is yes"* ]]
    [[ $output == *"ssh_host_ed25519_key-cert.pub  Valid: from 2020-01-01T00:00:00 to 2020-06-01T00:00:00"* ]]
    [[ $output == *"WARN: ssh_host_ed25519_key-cert.pub expired"* ]]
    [[ $output == *"Audit found 4 warning(s)."* ]]
}

@test "sshd-audit accepts a forever host certificate" {
    local dir="$UTIL_TMP/ssh" bin="$UTIL_TMP/bin" config="$UTIL_TMP/sshd-forever.txt"
    mkdir -p "$dir" "$bin"
    printf 'permitrootlogin no\npasswordauthentication no\nkbdinteractiveauthentication no\n' > "$config"
    printf 'cert\n' > "$dir/ssh_host_ed25519_key-cert.pub"
    touch -d @1600000000 "$dir/ssh_host_ed25519_key.pub"
    cat > "$bin/sshd" <<'EOF'
#!/bin/bash
[[ ${1:-} == -T ]]
cat "$SSHD_STUB_CONFIG"
EOF
    cat > "$bin/ssh-keygen" <<'EOF'
#!/bin/bash
printf '        Valid: forever\n'
EOF
    chmod +x "$bin/sshd" "$bin/ssh-keygen"

    run env PATH="$bin:$PATH" SSHD_AUDIT_KEY_DIR="$dir" SSHD_STUB_CONFIG="$config" \
        "$OPT_JAN/usr/bin/sshd-audit"
    [[ $status -eq 0 ]]
    [[ $output == *"Valid: forever"* ]]
    [[ $output != *"could not parse expiry"* ]]
    [[ $output == *"Audit found no problems."* ]]
}

@test "sshd-audit treats a before-date host certificate as an expiry" {
    local dir="$UTIL_TMP/ssh" bin="$UTIL_TMP/bin" config="$UTIL_TMP/sshd-before.txt"
    mkdir -p "$dir" "$bin"
    printf 'permitrootlogin no\npasswordauthentication no\nkbdinteractiveauthentication no\n' > "$config"
    printf 'cert\n' > "$dir/ssh_host_ed25519_key-cert.pub"
    touch -d @1600000000 "$dir/ssh_host_ed25519_key.pub"
    cat > "$bin/sshd" <<'EOF'
#!/bin/bash
[[ ${1:-} == -T ]]
cat "$SSHD_STUB_CONFIG"
EOF
    cat > "$bin/ssh-keygen" <<'EOF'
#!/bin/bash
printf '        Valid: before 2020-01-01T00:00:00\n'
EOF
    chmod +x "$bin/sshd" "$bin/ssh-keygen"

    run env PATH="$bin:$PATH" SSHD_AUDIT_KEY_DIR="$dir" SSHD_STUB_CONFIG="$config" \
        "$OPT_JAN/usr/bin/sshd-audit"
    [[ $status -eq 1 ]]
    [[ $output == *"Valid: before 2020-01-01T00:00:00"* ]]
    [[ $output == *"WARN: ssh_host_ed25519_key-cert.pub expired"* ]]
    [[ $output != *"could not parse expiry"* ]]
}

@test "opt-status lists recorded versions" {
    local root="$UTIL_TMP/opt"
    mkdir -p "$root/idea" "$root/jdk/21" "$root/.versions" "$root/bin"
    printf '2026.1\n' > "$root/idea/.version"
    printf '21.0.4\n' > "$root/jdk/21/.version"
    printf '1.7.1\n' > "$root/.versions/jq"
    printf 'abc\n' > "$root/.versions/jq.sha256"

    run env JAN_OPT="$root" "$OPT_JAN/usr/bin/opt-status"
    [[ $status -eq 0 ]]
    [[ $output == *$'idea  2026.1'* ]]
    [[ $output == *$'jdk/21  21.0.4'* ]]
    [[ $output == *$'bin/jq  1.7.1'* ]]
    [[ $output != *sha256* ]]
    [[ $output != *abc* ]]
}

@test "opt-status reports a missing opt directory" {
    run env JAN_OPT="$UTIL_TMP/missing-opt" "$OPT_JAN/usr/bin/opt-status"
    [[ $status -eq 1 ]]
    [[ $output == *"not a directory"* ]]
}
