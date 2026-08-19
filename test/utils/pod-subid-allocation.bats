#!/usr/bin/env bats
# Unit tests for jan-pod-setup subordinate-ID allocation. These use fixtures
# only and do not require root or modify the host account databases.

setup() {
    SCRIPT="${OPT_JAN:-$BATS_TEST_DIRNAME/../..}/usr/sbin/jan-pod-setup"

    # Load the production helper functions without executing the privileged
    # setup body. Keep their closing braces at column zero for this extraction.
    eval "$(sed -n '/^allocate_subuid_range()/,/^}/p; /^subid_ranges_for_user()/,/^}/p' "$SCRIPT")"
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
