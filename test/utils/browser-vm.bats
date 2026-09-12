#!/usr/bin/env bats

setup() {
    export TEST_ROOT="$BATS_TEST_TMPDIR/browser-vm"
    export JAN_OPT_ROOT="$TEST_ROOT/opt"
    export JAN_APPLICATION_DIR="$TEST_ROOT/applications"
    export JAN_BIN_DIR="$TEST_ROOT/bin"
    mkdir -p "$JAN_OPT_ROOT"
}

@test "Chrome VM integration skips an absent shared browser" {
    run env JAN_OPT_ROOT="$JAN_OPT_ROOT" \
        JAN_APPLICATION_DIR="$JAN_APPLICATION_DIR" JAN_BIN_DIR="$JAN_BIN_DIR" \
        "$OPT_JAN/usr/sbin/install-chrome-vm"
    [[ $status -eq 0 ]]
    [[ $output == *"skipping VM integration"* ]]
    [[ ! -e $JAN_APPLICATION_DIR/google-chrome.desktop ]]
    [[ ! -e $JAN_BIN_DIR/chrome ]]
}

@test "Chrome VM integration creates only its launcher and PATH link" {
    local browser="$JAN_OPT_ROOT/google/chrome"
    mkdir -p "$browser"
    printf '#!/bin/sh\n' > "$browser/google-chrome"
    chmod 0755 "$browser/google-chrome"
    printf 'icon\n' > "$browser/product_logo_128.png"

    run env JAN_OPT_ROOT="$JAN_OPT_ROOT" \
        JAN_APPLICATION_DIR="$JAN_APPLICATION_DIR" JAN_BIN_DIR="$JAN_BIN_DIR" \
        "$OPT_JAN/usr/sbin/install-chrome-vm"
    [[ $status -eq 0 ]]
    [[ $(readlink "$JAN_BIN_DIR/chrome") == "$browser/google-chrome" ]]
    grep -q "^Exec=$browser/google-chrome %U$" \
        "$JAN_APPLICATION_DIR/google-chrome.desktop"
    grep -q "^Icon=$browser/product_logo_128.png$" \
        "$JAN_APPLICATION_DIR/google-chrome.desktop"
    [[ $(find "$TEST_ROOT" -type f | wc -l) -eq 3 ]]
}

@test "Brave VM integration skips an absent shared browser" {
    run env JAN_OPT_ROOT="$JAN_OPT_ROOT" \
        JAN_APPLICATION_DIR="$JAN_APPLICATION_DIR" JAN_BIN_DIR="$JAN_BIN_DIR" \
        "$OPT_JAN/usr/sbin/install-brave-vm"
    [[ $status -eq 0 ]]
    [[ $output == *"skipping VM integration"* ]]
    [[ ! -e $JAN_APPLICATION_DIR/brave-origin.desktop ]]
    [[ ! -e $JAN_BIN_DIR/brave ]]
}

@test "Brave VM integration creates only its launcher and PATH link" {
    local browser="$JAN_OPT_ROOT/brave.com/brave-origin-beta"
    mkdir -p "$browser"
    printf '#!/bin/sh\n' > "$browser/brave-origin-beta"
    chmod 0755 "$browser/brave-origin-beta"
    printf 'icon\n' > "$browser/product_logo_128_beta.png"

    run env JAN_OPT_ROOT="$JAN_OPT_ROOT" \
        JAN_APPLICATION_DIR="$JAN_APPLICATION_DIR" JAN_BIN_DIR="$JAN_BIN_DIR" \
        "$OPT_JAN/usr/sbin/install-brave-vm"
    [[ $status -eq 0 ]]
    [[ $(readlink "$JAN_BIN_DIR/brave") == "$browser/brave-origin-beta" ]]
    grep -q "^Exec=$browser/brave-origin-beta %U$" \
        "$JAN_APPLICATION_DIR/brave-origin.desktop"
    grep -q "^Icon=$browser/product_logo_128_beta.png$" \
        "$JAN_APPLICATION_DIR/brave-origin.desktop"
    [[ $(find "$TEST_ROOT" -type f | wc -l) -eq 3 ]]
}
