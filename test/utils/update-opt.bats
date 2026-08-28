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
    [[ -s "$target/.versions/herdr.sha256" ]]

    run "$target/bin/herdr" --version
    [[ "$status" -eq 0 ]]

    local version
    version=$(<"$target/.versions/herdr")
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" herdr
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Herdr already at version $version"* ]]
}

@test "jan-update-opt installs and tracks Grok" {
    # Grok stable is ~160 MiB — network integration only.
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" grok
    if [[ "$status" -ne 0 ]]; then
        echo "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ -x "$target/bin/grok" ]]
    [[ -s "$target/.versions/grok" ]]
    [[ -s "$target/.versions/grok.sha256" ]]
    [[ "$output" == *"md5 verified"* ]]

    run "$target/bin/grok" --version
    [[ "$status" -eq 0 ]]

    local version
    version=$(<"$target/.versions/grok")
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" grok
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Grok already at version $version"* ]]
}

@test "jan-update-opt installs and tracks Codex" {
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" codex
    if [[ "$status" -ne 0 ]]; then
        echo "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ -x "$target/bin/codex" ]]
    [[ -s "$target/codex/.version" ]]
    [[ -s "$target/codex/.installed-sha256" ]]
    [[ "$output" == *"sha256 verified"* ]]

    run "$target/bin/codex" --version
    [[ "$status" -eq 0 ]]

    local version
    version=$(<"$target/codex/.version")
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" codex
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Codex CLI already at version $version"* ]]
}

@test "jan-update-opt installs and tracks native Pi archive" {
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" pi
    if [[ "$status" -ne 0 ]]; then
        echo "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ -x "$target/bin/pi" ]]
    [[ -s "$target/pi/.version" ]]
    [[ -s "$target/pi/.installed-sha256" ]]
    [[ -d "$target/pi/node_modules" ]]
    [[ "$output" == *"sha256 verified"* ]]

    run "$target/bin/pi" --version
    [[ "$status" -eq 0 ]]

    local version
    version=$(<"$target/pi/.version")
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" pi
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pi agent harness already at version $version"* ]]
}

@test "jan-update-opt installs and tracks native Claude Code archive" {
    command -v zstd >/dev/null || skip "zstd is required"
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" claude
    if [[ "$status" -ne 0 ]]; then
        echo "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ -x "$target/bin/claude" ]]
    [[ -s "$target/claude/.version" ]]
    [[ "$output" == *"sha256 verified"* ]]

    run "$target/bin/claude" --version
    [[ "$status" -eq 0 ]]

    local version
    version=$(<"$target/claude/.version")
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/jan-update-opt" claude
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Claude Code already at version $version"* ]]
}
