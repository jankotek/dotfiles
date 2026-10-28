#!/usr/bin/env bats
# ci: manual

setup() {
    export OPT_JAN=${OPT_JAN:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
    export PYTHONPATH="$OPT_JAN/usr/lib"
}

@test "text-only golden image builds, seals, compacts and passes two independent SSH clones" {
    if [[ -n ${GOLDEN_TEST_DISTRO:-} ]]; then
        run "$OPT_JAN/usr/bin/vm-image-build" --golden --distro "$GOLDEN_TEST_DISTRO" --repo "$OPT_JAN"
    else
        [[ -n ${GOLDEN_TEST_BOOT_BASE:-} ]] || skip 'set GOLDEN_TEST_DISTRO or GOLDEN_TEST_BOOT_BASE'
        run "$OPT_JAN/usr/bin/vm-image-build" --golden --base "$GOLDEN_TEST_BOOT_BASE" --repo "$OPT_JAN"
    fi
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "text-only VM promotes to minimal LightDM XFCE without changing identity or workspace" {
    [[ -n ${GOLDEN_TEST_BASE:-} ]] || skip 'set GOLDEN_TEST_BASE to a built CLI golden image'
    run python3 "$OPT_JAN/test/fixtures/vm-workstation-live.py"
    echo "$output"
    [ "$status" -eq 0 ]
}
