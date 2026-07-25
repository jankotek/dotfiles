#!/usr/bin/env bats
#
# Network integration checks for portable tools managed by jan-update-opt.
#
# Manually:
#   OPT_JAN="$PWD" bats test/utils/update-opt.bats
#

load ../helpers

@test "jan-update-opt installs and tracks Herdr" {
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" herdr
    if [[ "$status" -ne 0 ]]; then
        echo "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ -x "$target/bin/herdr" ]]
    [[ -s "$target/.versions/herdr" ]]

    run "$target/bin/herdr" --version
    [[ "$status" -eq 0 ]]

    local version
    version=$(<"$target/.versions/herdr")
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" herdr
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Herdr already at version $version"* ]]
}
