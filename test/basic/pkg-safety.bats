#!/usr/bin/env bats
# Verify package manager supply chain safety settings

load ../helpers

@test "npm ignore-scripts is set globally" {
    assert_file /etc/npmrc
    assert_file_contains /etc/npmrc 'ignore-scripts=true'
}

@test "pip only-binary is set globally" {
    assert_file /etc/pip.conf
    assert_file_contains /etc/pip.conf 'only-binary'
}

@test "uv only-binary is set globally" {
    if ! command -v uv &>/dev/null; then
        skip "uv not installed"
    fi
    assert_file /etc/uv/uv.toml
    assert_file_contains /etc/uv/uv.toml 'only-binary'
}

@test "gem no-document is set globally" {
    if ! command -v gem &>/dev/null; then
        skip "gem not installed"
    fi
    assert_file /etc/gemrc
    assert_file_contains /etc/gemrc 'no-document'
}
