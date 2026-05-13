#!/usr/bin/env bats
# Verify kernel boot parameter tweaks

load ../helpers

@test "zswap is enabled" {
    [[ "$(cat /sys/module/zswap/parameters/enabled)" == "Y" ]]
}

@test "zswap uses lzo compressor" {
    [[ "$(cat /sys/module/zswap/parameters/compressor)" == "lzo" ]]
}

@test "zswap params in boot cmdline" {
    assert_file_contains /proc/cmdline 'zswap.enabled=1'
    assert_file_contains /proc/cmdline 'zswap.compressor=lzo'
}

@test "ipv6 is disabled" {
    assert_file_contains /proc/cmdline 'ipv6.disable=1'
}
