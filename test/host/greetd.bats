#!/usr/bin/env bats
# Verify greetd + tuigreet setup on host

load ../helpers

@test "greetd is installed" {
    assert_command greetd
}

@test "tuigreet is installed" {
    assert_command tuigreet
}

@test "default greetd.service is disabled" {
    local state
    state=$(systemctl is-enabled greetd.service 2>/dev/null || echo "missing")
    [[ "$state" != "enabled" ]]
}

@test "greetd-tty3 config exists" {
    assert_file /etc/greetd/config-tty3.toml
    assert_file_contains /etc/greetd/config-tty3.toml 'vt = 3'
}

@test "greetd-tty4 config exists" {
    assert_file /etc/greetd/config-tty4.toml
    assert_file_contains /etc/greetd/config-tty4.toml 'vt = 4'
}

@test "greetd-tty5 config exists" {
    assert_file /etc/greetd/config-tty5.toml
    assert_file_contains /etc/greetd/config-tty5.toml 'vt = 5'
}

@test "greetd-tty6 config exists" {
    assert_file /etc/greetd/config-tty6.toml
    assert_file_contains /etc/greetd/config-tty6.toml 'vt = 6'
}

@test "greetd-tty7 config exists" {
    assert_file /etc/greetd/config-tty7.toml
    assert_file_contains /etc/greetd/config-tty7.toml 'vt = 7'
}

@test "greetd-tty8 config exists" {
    assert_file /etc/greetd/config-tty8.toml
    assert_file_contains /etc/greetd/config-tty8.toml 'vt = 8'
}

@test "greetd-tty9 config exists" {
    assert_file /etc/greetd/config-tty9.toml
    assert_file_contains /etc/greetd/config-tty9.toml 'vt = 9'
}

@test "greetd-tty3 service is enabled" {
    systemctl is-enabled greetd-tty3.service
}

@test "greetd-tty4 service is enabled" {
    systemctl is-enabled greetd-tty4.service
}

@test "greetd-tty5 service is enabled" {
    systemctl is-enabled greetd-tty5.service
}

@test "greetd-tty6 service is enabled" {
    systemctl is-enabled greetd-tty6.service
}

@test "greetd-tty7 service is enabled" {
    systemctl is-enabled greetd-tty7.service
}

@test "greetd-tty8 service is enabled" {
    systemctl is-enabled greetd-tty8.service
}

@test "greetd-tty9 service is enabled" {
    systemctl is-enabled greetd-tty9.service
}

@test "conflicting getty services are masked" {
    for tty in 3 4 5 6 7 8 9; do
        local state
        state=$(systemctl is-enabled "getty@tty${tty}.service" 2>/dev/null) || true
        if [[ "$state" != "masked" ]]; then
            echo "getty@tty${tty} is ${state:-missing}, expected masked" >&2
            return 1
        fi
    done
}

@test "all greetd configs use tuigreet" {
    for tty in 3 4 5 6 7 8 9; do
        assert_file_contains "/etc/greetd/config-tty${tty}.toml" 'tuigreet'
    done
}

@test "no other display manager is enabled" {
    for dm in lightdm gdm sddm xdm lxdm; do
        local state
        state=$(systemctl is-enabled "${dm}.service" 2>/dev/null || echo "missing")
        if [[ "$state" == "enabled" ]]; then
            echo "$dm is enabled, should be disabled or masked" >&2
            return 1
        fi
    done
}

@test "no other display manager is running" {
    for dm in lightdm gdm sddm xdm lxdm; do
        if systemctl is-active --quiet "${dm}.service" 2>/dev/null; then
            echo "$dm is running" >&2
            return 1
        fi
    done
}
