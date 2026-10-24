#!/usr/bin/env bats
# ci: manual

@test "lab hardening survives real PAM sessions, installer reruns, and reboot" {
    [[ -n ${LAB_TEST_BASE:-} ]] || skip "set LAB_TEST_BASE to a vm-image-build image"
    export OPT_JAN=${OPT_JAN:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
    export PYTHONPATH="$OPT_JAN/usr/lib"
    run python3 "$OPT_JAN/test/fixtures/lab-hardening-live.py" --base "$LAB_TEST_BASE"
    echo "$output"
    [[ $status -eq 0 ]]
}
