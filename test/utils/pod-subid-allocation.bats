#!/usr/bin/env bats
# Unit tests for jan-pod-setup subordinate-ID allocation. These use fixtures
# only and do not require root or modify the host account databases.

setup() {
    SCRIPT="${OPT_JAN:-$BATS_TEST_DIRNAME/../..}/usr/sbin/jan-pod-setup"
    POD_SECURITY_TEST="${OPT_JAN:-$BATS_TEST_DIRNAME/../..}/test/utils/pod-security.bats"

    # Load the production helper functions without executing the privileged
    # setup body. Keep their closing braces at column zero for this extraction.
    eval "$(sed -n \
        '/^parse_subid_line()/,/^}/p; /^subid_file_is_shadow_writable()/,/^}/p; /^allocate_subuid_range()/,/^}/p; /^subid_ranges_for_user()/,/^}/p; /^subid_to_usermod_range()/,/^}/p; /^subid_can_copy_range()/,/^}/p' \
        "$SCRIPT")"
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

    run subid_ranges_for_user "$subuid" pod

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
    printf '%s\n' 'alice:4294901760:65536' > "$subuid"
    : > "$subgid"

    run allocate_subuid_range "$subuid" "$subgid"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'no 32-bit subordinate-ID range remaining'* ]]
    [[ "$output" != *'4294967296-'* ]]
}

@test "lookup rejects arithmetic tokens in count" {
    local subuid="$BATS_TEST_TMPDIR/subuid"
    printf '%s\n' 'pod:196608:1+65535' > "$subuid"

    run subid_ranges_for_user "$subuid" pod

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
