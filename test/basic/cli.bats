#!/usr/bin/env bats
# Verify common CLI tools are available on all systems

load ../helpers

@test "git is installed" {
    assert_command git
}

@test "curl is installed" {
    assert_command curl
}

@test "mc is installed" {
    assert_command mc
}

@test "mcedit is installed" {
    assert_command mcedit
}

@test "htop is installed" {
    assert_command htop
}

@test "fish is installed" {
    assert_command fish
}

@test "nano is installed" {
    assert_command nano
}

@test "ncdu is installed" {
    assert_command ncdu
}

@test "starship is installed" {
    assert_command starship
}

@test "iotop is installed" {
    assert_executable /usr/sbin/iotop
}

@test "powertop is installed" {
    assert_executable /usr/sbin/powertop
}

@test "pwgen is installed" {
    assert_command pwgen
}

@test "telnet is installed" {
    assert_command telnet
}

@test "jdupes is installed" {
    assert_command jdupes
}

@test "just is installed" {
    assert_command just
}

@test "bats is installed" {
    assert_command bats
}

@test "zim is installed" {
    assert_command zim
}

@test "jetbrains-mono font is available" {
    fc-list | grep -qi "JetBrains Mono"
}
