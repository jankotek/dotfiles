#!/usr/bin/env bats
# Unit tests for jan-pod-setup subordinate-ID allocation. These use fixtures
# only and do not require root or modify the host account databases.

setup() {
    SCRIPT="${OPT_JAN:-$BATS_TEST_DIRNAME/../..}/usr/sbin/jan-pod-setup"
    POD_SECURITY_TEST="${OPT_JAN:-$BATS_TEST_DIRNAME/../..}/test/utils/pod-security.bats"

    # Load the production helper functions without executing the privileged
    # setup body. Keep their closing braces at column zero for this extraction.
    eval "$(sed -n \
        '/^parse_subid_line()/,/^}/p; /^subid_file_is_shadow_writable()/,/^}/p; /^require_shadow_writable_subid_files()/,/^}/p; /^shadow_lock_plan_exec()/,/^}/p; /^allocate_subuid_range()/,/^}/p; /^subid_ranges_for_user()/,/^}/p; /^subid_to_usermod_range()/,/^}/p; /^subid_can_copy_range()/,/^}/p; /^plan_subid_reconciliation_locked()/,/^}/p' \
        "$SCRIPT")"
    export -f parse_subid_line subid_file_is_shadow_writable \
        require_shadow_writable_subid_files allocate_subuid_range \
        subid_ranges_for_user subid_to_usermod_range subid_can_copy_range \
        plan_subid_reconciliation_locked
}

run_controller() {
    local lock_file="$BATS_TEST_TMPDIR/.pwd.lock"
    local id_dir="$BATS_TEST_TMPDIR/mock-bin"
    local subuid_file="$1" subgid_file="$2" user="$3"
    local user_uid="$4" usermod_cmd="$5"
    mkdir -p "$id_dir"
    cat > "$id_dir/id" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "$MOCK_ID_LOG"
printf '\n' >> "$MOCK_ID_LOG"
[[ "$1" == -u && "$2" == -- && -n "$3" ]]
printf '%s\n' "$MOCK_ID_UID"
MOCK
    chmod +x "$id_dir/id"
    MOCK_ID_UID="$user_uid" MOCK_ID_LOG="$BATS_TEST_TMPDIR/id.log" \
        PATH="$id_dir:$PATH" \
        shadow_lock_plan_exec "$lock_file" bash -c \
        'plan_subid_reconciliation_locked "$@"' _ \
        "$subuid_file" "$subgid_file" "$user" "$usermod_cmd"
}

make_usermod_mock() {
    USERMOD_MOCK="$BATS_TEST_TMPDIR/usermod-mock"
    MOCK_LOG="$BATS_TEST_TMPDIR/usermod.log"
    MOCK_SUBUID="$BATS_TEST_TMPDIR/subuid"
    MOCK_SUBGID="$BATS_TEST_TMPDIR/subgid"
    export MOCK_LOG MOCK_SUBUID MOCK_SUBGID

    cat > "$USERMOD_MOCK" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >> "$MOCK_LOG"
printf '\n' >> "$MOCK_LOG"

user="${!#}"
while (( $# > 1 )); do
    option="$1"
    range="$2"
    shift 2
    start="${range%-*}"
    last="${range#*-}"
    count=$((10#$last - 10#$start + 1))
    case "$option" in
        --add-subuids) printf '%s:%s:%s\n' "$user" "$start" "$count" >> "$MOCK_SUBUID" ;;
        --add-subgids) printf '%s:%s:%s\n' "$user" "$start" "$count" >> "$MOCK_SUBGID" ;;
        *) exit 64 ;;
    esac
done
MOCK
    chmod +x "$USERMOD_MOCK"
}

@test "pod security test never edits live subid databases directly" {
    run grep -E '(>>|sed[[:space:]]+-i).*\/etc\/sub(uid|gid)' "$POD_SECURITY_TEST"

    [[ "$status" -eq 1 ]]
}

@test "setup never redirects a lock descriptor onto subid databases" {
    run grep -E '[0-9]+>>?"?/etc/sub(uid|gid)' "$SCRIPT"

    [[ "$status" -eq 1 ]]
}

@test "allocator considers both subuid and subgid databases" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    local subgid="$BATS_TEST_TMPDIR/subgid"
    printf '%s\n' \
        'alice:100000:65536' \
        'bob:200000:10000' > "$subuid"
    printf '%s\n' 'carol:270000:1000' > "$subgid"

    run allocate_subuid_range "$subuid" "$subgid"

    [[ "$status" -eq 0 ]]
    [[ "$output" == '327680-393215' ]]
}

@test "allocator leaves fixture databases unchanged" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    local subgid="$BATS_TEST_TMPDIR/subgid"
    printf '%s\n' 'alice:100000:65536' > "$subuid"
    printf '%s\n' 'alice:100000:65536' > "$subgid"
    local subuid_before subgid_before
    subuid_before=$(sha256sum "$subuid")
    subgid_before=$(sha256sum "$subgid")

    allocate_subuid_range "$subuid" "$subgid" >/dev/null

    [[ "$(sha256sum "$subuid")" == "$subuid_before" ]]
    [[ "$(sha256sum "$subgid")" == "$subgid_before" ]]
}

@test "allocator rejects malformed database entries" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    local subgid="$BATS_TEST_TMPDIR/subgid"
    printf '%s\n' 'alice:not-a-number:65536' > "$subuid"
    : > "$subgid"

    run allocate_subuid_range "$subuid" "$subgid"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'invalid subordinate-ID entry'* ]]
}

@test "range lookup returns all unique ranges in stable order" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    printf '%s\n' \
        'pod:300000:65536' \
        'other:100000:65536' \
        'pod:200000:65536' \
        'pod:300000:65536' > "$subuid"

    run subid_ranges_for_user "$subuid" pod 4242

    [[ "$status" -eq 0 ]]
    [[ "$output" == $'200000:65536\n300000:65536' ]]
}

@test "allocator honors a last record with no terminating newline" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    local subgid="$BATS_TEST_TMPDIR/subgid"
    printf 'alice:100000:65536' > "$subuid"
    : > "$subgid"

    run allocate_subuid_range "$subuid" "$subgid"

    [[ "$status" -eq 0 ]]
    [[ "$output" == '196608-262143' ]]
}

@test "shadow-writable check rejects an unterminated final record" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    printf 'alice:100000:65536' > "$subuid"

    run subid_file_is_shadow_writable "$subuid"

    [[ "$status" -ne 0 ]]
}

@test "shadow-writable check accepts empty and newline-terminated files" {
    local empty="$BATS_TEST_TMPDIR/empty"
    local subuid="$BATS_TEST_TMPDIR/subuid"
    : > "$empty"
    printf '%s\n' 'alice:100000:65536' > "$subuid"

    subid_file_is_shadow_writable "$empty"
    subid_file_is_shadow_writable "$subuid"
}

@test "allocator rejects leading-zero fields" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    local subgid="$BATS_TEST_TMPDIR/subgid"
    printf '%s\n' 'alice:0100000:65536' > "$subuid"
    : > "$subgid"

    run allocate_subuid_range "$subuid" "$subgid"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'invalid subordinate-ID entry'* ]]
}

@test "allocator rejects an empty owner" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    local subgid="$BATS_TEST_TMPDIR/subgid"
    printf '%s\n' ':100000:65536' > "$subuid"
    : > "$subgid"

    run allocate_subuid_range "$subuid" "$subgid"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'invalid subordinate-ID entry'* ]]
}

@test "allocator rejects a trailing colon" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    local subgid="$BATS_TEST_TMPDIR/subgid"
    printf '%s\n' 'alice:100000:65536:' > "$subuid"
    : > "$subgid"

    run allocate_subuid_range "$subuid" "$subgid"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'invalid subordinate-ID entry'* ]]
}

@test "allocator refuses a range that leaves no 32-bit block" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    local subgid="$BATS_TEST_TMPDIR/subgid"
    printf '%s\n' 'alice:4294836224:65536' > "$subuid"
    : > "$subgid"

    run allocate_subuid_range "$subuid" "$subgid"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'no usable 32-bit subordinate-ID range remaining'* ]]
    [[ "$output" != *'4294967296-'* ]]
}

@test "parser rejects a range containing the unmapped ID sentinel" {
    run parse_subid_line 'alice:4294901760:65536' fixture

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'exceeds usable 32-bit ID space'* ]]
}

@test "parser accepts the maximum usable exclusive end" {
    local range_end=0
    parse_subid_line 'alice:0:4294967295' fixture

    [[ "$range_end" -eq 4294967295 ]]
}

@test "lookup rejects arithmetic tokens in count" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    printf '%s\n' 'pod:196608:1+65535' > "$subuid"

    run subid_ranges_for_user "$subuid" pod 4242

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'invalid subordinate-ID entry'* ]]
}

@test "usermod range conversion uses inclusive last id" {
    run subid_to_usermod_range 196608:65536

    [[ "$status" -eq 0 ]]
    [[ "$output" == '196608-262143' ]]
}

@test "repair refuses a range that overlaps the destination" {
    local dest="$BATS_TEST_TMPDIR/subuid"
    printf '%s\n' 'alice:196608:65536' > "$dest"

    run subid_can_copy_range "$dest" '196608:65536'

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'overlaps'* ]]
}

@test "repair allows a range adjacent to the destination" {
    local dest="$BATS_TEST_TMPDIR/subuid"
    printf '%s\n' 'alice:100000:65536' > "$dest"

    run subid_can_copy_range "$dest" '196608:65536'

    [[ "$status" -eq 0 ]]
}

@test "lookup treats the account name and numeric UID as the same owner" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    printf '%s\n' \
        'pod:196608:65536' \
        '4242:262144:65536' \
        '4243:327680:65536' > "$subuid"

    run subid_ranges_for_user "$subuid" pod 4242

    [[ "$status" -eq 0 ]]
    [[ "$output" == $'196608:65536\n262144:65536' ]]
}

@test "controller allocates both databases and is idempotent on rerun" {
    make_usermod_mock
    printf '%s\n' 'alice:100000:65536' > "$MOCK_SUBUID"
    printf '%s\n' 'alice:100000:65536' > "$MOCK_SUBGID"

    run run_controller \
        "$MOCK_SUBUID" "$MOCK_SUBGID" pod 4242 "$USERMOD_MOCK"

    [[ "$status" -eq 0 ]]
    grep -qxF 'pod:196608:65536' "$MOCK_SUBUID"
    grep -qxF 'pod:196608:65536' "$MOCK_SUBGID"
    grep -q -- '--add-subuids 196608-262143 --add-subgids 196608-262143 pod' "$MOCK_LOG"

    : > "$MOCK_LOG"
    run run_controller \
        "$MOCK_SUBUID" "$MOCK_SUBGID" pod 4242 "$USERMOD_MOCK"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'Existing subordinate UID/GID range: 196608:65536'* ]]
    [[ ! -s "$MOCK_LOG" ]]
}

@test "controller repairs one-sided numeric-owner state" {
    make_usermod_mock
    printf '%s\n' '4242:196608:65536' > "$MOCK_SUBUID"
    : > "$MOCK_SUBGID"

    run run_controller \
        "$MOCK_SUBUID" "$MOCK_SUBGID" pod 4242 "$USERMOD_MOCK"

    [[ "$status" -eq 0 ]]
    grep -qxF 'pod:196608:65536' "$MOCK_SUBGID"
    grep -q -- '--add-subgids 196608-262143 pod' "$MOCK_LOG"
    grep -q -- '-u -- pod' "$BATS_TEST_TMPDIR/id.log"
    [[ "$(subid_ranges_for_user "$MOCK_SUBUID" pod 4242)" == \
        "$(subid_ranges_for_user "$MOCK_SUBGID" pod 4242)" ]]
}

@test "controller refuses multiple or divergent effective ranges" {
    make_usermod_mock
    printf '%s\n' \
        'pod:196608:65536' \
        '4242:262144:65536' > "$MOCK_SUBUID"
    printf '%s\n' 'pod:196608:65536' > "$MOCK_SUBGID"

    run run_controller \
        "$MOCK_SUBUID" "$MOCK_SUBGID" pod 4242 "$USERMOD_MOCK"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'inconsistent subuid/subgid ranges'* ]]
    [[ ! -e "$MOCK_LOG" ]]
}

@test "shadow lock remains held by the execed controller" {
    local lock_file="$BATS_TEST_TMPDIR/.pwd.lock"
    local checker="$BATS_TEST_TMPDIR/check-lock.py"
    cat > "$checker" <<'PY'
#!/usr/bin/env python3
import errno
import fcntl
import os
import sys

pid = os.fork()
if pid == 0:
    fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as exc:
        if exc.errno in (errno.EACCES, errno.EAGAIN):
            raise SystemExit(0)
        raise
    raise SystemExit("lock was not inherited across exec")
_, status = os.waitpid(pid, 0)
raise SystemExit(os.waitstatus_to_exitcode(status))
PY
    chmod +x "$checker"

    run shadow_lock_plan_exec "$lock_file" bash -c \
        'printf "%s\0" "$1" "$2"' _ "$checker" "$lock_file"

    [[ "$status" -eq 0 ]]
}
