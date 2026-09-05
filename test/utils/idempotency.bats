#!/usr/bin/env bats
#
# Re-run idempotency + user-data preservation checks for setup/vm-xub26.
#
# Run inside an already-deployed VM as root. The launcher
# test/test-vm-idempotency.sh wires this up: clones xub26, runs
# setup/vm-xub26 once, drops sentinel files, then runs this bats file.
# This file then re-runs setup/vm-xub26 in setup_file and verifies the
# second run completed cleanly without destroying user data.
#
# Manually:
#   sudo bats test/utils/idempotency.bats
#

load ../helpers

SENTINEL_DOWN="/home/jan/down/.idempotency-sentinel"
SENTINEL_DOC="/home/jan/doc/.idempotency-sentinel"
SENTINEL_CACHE="/home/jan/.cache/.idempotency-sentinel"
RERUN_LOG="${BATS_FILE_TMPDIR:-/tmp}/vm-xub26-rerun.log"
RERUN_RC_FILE="${BATS_FILE_TMPDIR:-/tmp}/vm-xub26-rerun.rc"

setup_file() {
    if [[ "$EUID" -ne 0 ]]; then
        skip "requires root"
    fi
    if ! [[ -x /opt/jan/setup/vm-xub26 ]]; then
        skip "/opt/jan/setup/vm-xub26 not found"
    fi

    install -d -o jan -g users /home/jan/down /home/jan/doc /home/jan/.cache
    install -m 0644 -o jan -g users /dev/null "$SENTINEL_DOWN"
    install -m 0644 -o jan -g users /dev/null "$SENTINEL_DOC"
    install -m 0644 -o jan -g users /dev/null "$SENTINEL_CACHE"
    echo "preserve-me" > "$SENTINEL_DOWN"
    echo "preserve-me" > "$SENTINEL_DOC"
    echo "preserve-me" > "$SENTINEL_CACHE"

    set +e
    /opt/jan/setup/vm-xub26 >"$RERUN_LOG" 2>&1
    echo $? > "$RERUN_RC_FILE"
    set -e
}

@test "second setup/vm-xub26 run exits 0" {
    rc=$(cat "$RERUN_RC_FILE")
    if [[ "$rc" != "0" ]]; then
        echo "Re-run exit code: $rc" >&2
        echo "--- last 30 lines of re-run log ---" >&2
        tail -30 "$RERUN_LOG" >&2
    fi
    [[ "$rc" == "0" ]]
}

@test "sentinel in ~/down survived re-deploy" {
    [[ -f "$SENTINEL_DOWN" ]]
    [[ "$(cat "$SENTINEL_DOWN")" == "preserve-me" ]]
}

@test "sentinel in ~/doc survived re-deploy" {
    [[ -f "$SENTINEL_DOC" ]]
    [[ "$(cat "$SENTINEL_DOC")" == "preserve-me" ]]
}

@test "sentinel in ~/.cache survived re-deploy" {
    [[ -f "$SENTINEL_CACHE" ]]
    [[ "$(cat "$SENTINEL_CACHE")" == "preserve-me" ]]
}

@test "no nested /usr/local/bin/bin etc. from re-running cp -s" {
    # cp -f -s -r /opt/jan/usr/* /usr/local can create dst/bin/bin/ on
    # re-run if the implementation re-resolves the destination differently.
    # Verify no such nesting exists.
    [[ ! -d /usr/local/bin/bin ]]
    [[ ! -d /usr/local/sbin/sbin ]]
    [[ ! -d /usr/local/share/share ]]
}

@test "block-pkg pins are not duplicated on re-run" {
    # /etc/apt/preferences.d/block-<pkg>.pref should contain exactly one
    # 'Package:' line per file even after multiple runs.
    for f in /etc/apt/preferences.d/block-*.pref; do
        [[ -f "$f" ]] || continue
        local count
        count=$(grep -c '^Package:' "$f")
        [[ "$count" -eq 1 ]] || {
            echo "$f has $count Package: lines (expected 1)" >&2
            return 1
        }
    done
}
