#!/usr/bin/env bats
# CLI checks only; never build a kernel or modify installed packages.

setup() {
    KERNEL_TOOL="$BATS_TEST_DIRNAME/../../usr/sbin/kernel-zbook-build"
}

@test "kernel-zbook-build help works through its deployment symlink" {
    ln -s "$KERNEL_TOOL" "$BATS_TEST_TMPDIR/kernel-zbook-build"
    run "$BATS_TEST_TMPDIR/kernel-zbook-build" --help
    [[ $status -eq 0 ]]
    [[ $output == 'Usage: kernel-zbook-build [--force]'* ]]
    [[ $output == *'JOBS=N'* ]]
    [[ $output == *'asks before installing the generated RPM'* ]]
}

@test "kernel-zbook-build rejects unknown arguments before setup" {
    run "$KERNEL_TOOL" --invalid-option
    [[ $status -ne 0 ]]
    [[ $output == 'ERROR: Unknown argument. Use --help.' ]]
}

@test "kernel-zbook-build requires root before setup" {
    (( EUID != 0 )) || skip 'Requires an unprivileged test runner'
    run "$KERNEL_TOOL"
    [[ $status -ne 0 ]]
    [[ $output == 'ERROR: Run this script as root.' ]]
}
