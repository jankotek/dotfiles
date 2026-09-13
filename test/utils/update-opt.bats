#!/usr/bin/env bats
#
# Network integration checks for portable tools managed by optupdate.
#
# Manually:
#   OPT_JAN="$PWD" bats test/utils/update-opt.bats
#

load ../helpers

@test "optupdate installs and tracks Herdr" {
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" herdr
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
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" herdr
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Herdr already at version $version"* ]]
}

@test "optupdate installs and tracks the complete Mjolnir archive" {
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" mjolnir
    if [[ "$status" -ne 0 ]]; then
        echo "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ -x "$target/bin/mj" ]]
    [[ -s "$target/mjolnir/.version" ]]
    [[ -s "$target/mjolnir/.installed-sha256" ]]
    [[ "$output" == *"sha256 verified"* ]]

    local binary
    for binary in mj mj-desktop mj-voice-worker \
        mj-worker-x86_64-unknown-linux-musl \
        mj-worker-aarch64-unknown-linux-musl; do
        [[ -x "$target/mjolnir/$binary" ]] || {
            echo "Missing Mjolnir bundle executable: $target/mjolnir/$binary" >&2
            return 1
        }
    done

    run "$target/bin/mj" --version
    [[ "$status" -eq 0 ]]

    local version
    version=$(<"$target/mjolnir/.version")
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" mjolnir
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Mjolnir already at version $version"* ]]
}

@test "optupdate installs and tracks Grok" {
    # Grok stable is ~160 MiB — network integration only.
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" grok
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
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" grok
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Grok already at version $version"* ]]
}

@test "optupdate installs and tracks Codex" {
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" codex
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
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" codex
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Codex CLI already at version $version"* ]]
}

@test "optupdate installs and tracks native Pi archive" {
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" pi
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
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" pi
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pi agent harness already at version $version"* ]]
}

@test "optupdate installs and tracks native Claude Code archive" {
    command -v zstd >/dev/null || skip "zstd is required"
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" claude
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
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" claude
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Claude Code already at version $version"* ]]
}

@test "optupdate selects a Linux Obsidian release and tracks it" {
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" obsidian
    if [[ "$status" -ne 0 ]]; then
        echo "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ -x "$target/bin/obsidian" ]]
    [[ -s "$target/obsidian/.version" ]]
    [[ -s "$target/obsidian/.installed-sha256" ]]
    [[ "$output" == *"sha256 verified"* ]]

    local version
    version=$(<"$target/obsidian/.version")
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" obsidian
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Obsidian already at version $version"* ]]
}

@test "optupdate installs and tracks Fresh Editor" {
    local target="$BATS_TEST_TMPDIR/opt"
    mkdir -p "$target"

    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" fresh
    if [[ "$status" -ne 0 ]]; then
        echo "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ -x "$target/bin/fresh" ]]
    [[ -s "$target/.versions/fresh" ]]
    [[ -s "$target/.versions/fresh.sha256" ]]
    [[ ! -e "$target/fresh-editor" ]]
    [[ "$output" == *"sha256 verified"* ]]

    run "$target/bin/fresh" --version
    [[ "$status" -eq 0 ]]

    local version
    version=$(<"$target/.versions/fresh")
    run env JAN_OPT="$target" "$OPT_JAN/usr/sbin/optupdate" fresh
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Fresh Editor already at version $version"* ]]
}
