#!/usr/bin/env bats
# ci: manual

@test "canonical baseweed provisioning supports cold Herdr VM recovery" {
    [[ -n ${HERDR_BASEWEED_TEST_BASE:-} ]] || skip "set HERDR_BASEWEED_TEST_BASE to the output of dotfiles vm-image-build"
    [[ -f $HERDR_BASEWEED_TEST_BASE ]] || skip "baseweed input does not exist"
    export OPT_JAN=${OPT_JAN:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
    export PYTHONPATH="$OPT_JAN/usr/lib"
    for command in herdr virsh virt-copy-in virt-customize qemu-img ssh ssh-keygen; do
        command -v "$command" >/dev/null || skip "$command is required"
    done
    args=(--base "$HERDR_BASEWEED_TEST_BASE")
    [[ ${HERDR_BASEWEED_TEST_KEEP:-0} != 1 ]] || args+=(--keep)
    run python3 "$OPT_JAN/test/fixtures/herdr-baseweed-live.py" "${args[@]}"
    echo "$output"
    [ "$status" -eq 0 ]
}
