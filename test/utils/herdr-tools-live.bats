#!/usr/bin/env bats
# ci: manual

@test "real Herdr round-trips example programs and live pane rearrangements" {
    export OPT_JAN=${OPT_JAN:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
    export PYTHONPATH="$OPT_JAN/usr/lib"
    command -v "${HERDR_TEST_BINARY:-herdr}" >/dev/null || skip "Herdr is required"
    for program in htop mc nano; do
        command -v "$program" >/dev/null || skip "$program is required"
    done
    run python3 "$OPT_JAN/test/fixtures/herdr-tools-live.py"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "real Herdr autosaves layout changes and new VM wrapper mappings" {
    export OPT_JAN=${OPT_JAN:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
    export PYTHONPATH="$OPT_JAN/usr/lib"
    command -v "${HERDR_TEST_BINARY:-herdr}" >/dev/null || skip "Herdr is required"
    run python3 "$OPT_JAN/test/fixtures/herdr-autosave-live.py"
    echo "$output"
    [ "$status" -eq 0 ]
}
