#!/usr/bin/env bats
# Verify the host's multi-VT greetd + tuigreet configuration.

load ../helpers

GREETD_TTYS=(3 4 5 6 7 8 9 10)

@test "greetd and tuigreet are installed" {
    assert_command greetd
    assert_command tuigreet
}

@test "tty3 through tty10 have non-autologin tuigreet configs" {
    local tty config
    for tty in "${GREETD_TTYS[@]}"; do
        config="/etc/greetd/config-tty${tty}.toml"
        assert_file "$config"
        assert_file_contains "$config" "vt = $tty"
        assert_file_contains "$config" 'switch = false'
        assert_file_contains "$config" 'service = "greetd"'
        assert_file_contains "$config" '/usr/bin/tuigreet'
        assert_file_contains "$config" 'sessions /usr/share/wayland-sessions'
        assert_file_contains "$config" "session-wrapper '/usr/local/bin/jan-greetd-session wayland'"
        assert_file_contains "$config" 'xsessions /usr/share/xsessions'
        assert_file_contains "$config" "xsession-wrapper '/usr/local/bin/jan-greetd-session x11'"
        if grep -q '^\[initial_session\]' "$config"; then
            echo "$config unexpectedly enables autologin" >&2
            return 1
        fi
    done
}

@test "graphical wrapper serializes users and reconciles activation environment" {
    assert_executable /usr/local/bin/jan-greetd-session
    assert_command startx
    assert_command dbus-update-activation-environment
    assert_command flock
    assert_file_contains /usr/local/bin/jan-greetd-session 'flock -n'
    assert_file_contains /usr/local/bin/jan-greetd-session 'mapfile -d'
    assert_file_contains /usr/local/bin/jan-greetd-session 'systemctl --user import-environment DISPLAY XAUTHORITY'
    assert_file_contains /usr/local/bin/jan-greetd-session 'dbus-update-activation-environment DISPLAY XAUTHORITY'
    assert_file_contains /usr/local/bin/jan-greetd-session 'systemctl --user unset-environment'
    assert_file_contains /usr/local/bin/jan-greetd-session 'publish_wayland_environment'
    assert_file_contains /usr/local/bin/jan-greetd-session 'trap clear_activation_environment_on_exit EXIT'
}

@test "tty3 through tty10 greetd services are enabled" {
    local tty
    for tty in "${GREETD_TTYS[@]}"; do
        systemctl is-enabled "greetd-tty${tty}.service"
        [[ ! -e "/etc/systemd/system/multi-user.target.wants/greetd-tty${tty}.service" ]]
        [[ ! -L "/etc/systemd/system/multi-user.target.wants/greetd-tty${tty}.service" ]]
    done
}

@test "tty11 and tty12 have no stale greetd ownership" {
    local tty state
    for tty in 11 12; do
        [[ ! -e "/etc/greetd/config-tty${tty}.toml" ]]
        [[ ! -e "/etc/systemd/system/greetd-tty${tty}.service" ]]
        state=$(systemctl is-active "greetd-tty${tty}.service" 2>/dev/null || true)
        [[ "$state" != active ]]
        state=$(systemctl is-enabled "greetd-tty${tty}.service" 2>/dev/null || true)
        [[ "$state" != enabled && "$state" != enabled-runtime ]]
    done
}

@test "greetd services use upstream shutdown and PAM ordering" {
    local tty properties
    for tty in "${GREETD_TTYS[@]}"; do
        properties=$(systemctl show "greetd-tty${tty}.service" \
            -p SendSIGHUP -p TimeoutStopUSec -p KeyringMode -p After -p Conflicts)
        [[ "$properties" == *"SendSIGHUP=yes"* ]]
        [[ "$properties" == *"TimeoutStopUSec=30s"* ]]
        [[ "$properties" == *"KeyringMode=shared"* ]]
        [[ "$properties" == *"systemd-user-sessions.service"* ]]
        [[ "$properties" == *"systemd-logind.service"* ]]
        [[ "$properties" == *"getty@tty${tty}.service"* ]]
        [[ "$properties" == *"autovt@tty${tty}.service"* ]]
    done
}

@test "greetd PAM stack includes pam_systemd" {
    local pam_file
    pam_file=/etc/pam.d/greetd
    [[ -r "$pam_file" ]] || pam_file=/usr/lib/pam.d/greetd
    if grep -Eq '^[[:space:]]*session[[:space:]].*pam_systemd\.so' "$pam_file"; then
        return 0
    fi
    grep -Eq '^[[:space:]]*session[[:space:]]+(include|substack)[[:space:]]+common-session' "$pam_file"
    grep -Eq '^[[:space:]]*session[[:space:]].*pam_systemd\.so' /etc/pam.d/common-session
}

@test "getty and autovt own none of tty3 through tty10" {
    local tty template state
    for tty in "${GREETD_TTYS[@]}"; do
        for template in getty autovt; do
            state=$(systemctl is-enabled "${template}@tty${tty}.service" 2>/dev/null || true)
            [[ "$state" == masked ]] || {
                echo "${template}@tty${tty} is ${state:-missing}, expected masked" >&2
                return 1
            }
        done
    done
}

@test "tty1 and tty2 remain available for emergency text login" {
    local tty state
    for tty in 1 2; do
        state=$(systemctl is-enabled "getty@tty${tty}.service" 2>/dev/null || true)
        [[ "$state" != masked && "$state" != masked-runtime ]]
        state=$(systemctl is-enabled "autovt@tty${tty}.service" 2>/dev/null || true)
        [[ "$state" != masked && "$state" != masked-runtime ]]
    done
}

@test "logind autovt policy stops at tty2" {
    assert_file_contains /etc/systemd/logind.conf.d/80-jan-greetd-vts.conf 'NAutoVTs=2'
    assert_file_contains /etc/systemd/logind.conf.d/80-jan-greetd-vts.conf 'ReserveVT=2'

    local effective
    effective=$(systemd-analyze cat-config systemd/logind.conf)
    [[ $(awk -F= '/^[[:space:]]*NAutoVTs[[:space:]]*=/ { value=$2 } END { gsub(/[[:space:]]/, "", value); print value }' <<< "$effective") == 2 ]]
    [[ $(awk -F= '/^[[:space:]]*ReserveVT[[:space:]]*=/ { value=$2 } END { gsub(/[[:space:]]/, "", value); print value }' <<< "$effective") == 2 ]]
}

@test "boot switch selects tty3 after all greetd instances" {
    systemctl is-enabled jan-greetd-switch-tty3.service
    assert_file_contains /etc/systemd/system/jan-greetd-switch-tty3.service 'ExecStart=/usr/bin/chvt 3'
    assert_file_contains /etc/systemd/system/jan-greetd-switch-tty3.service 'After=greetd-tty3.service'
    assert_file_contains /etc/systemd/system/jan-greetd-switch-tty3.service 'greetd-tty10.service'
}

@test "competing display managers are masked" {
    local dm state
    for dm in display-manager display-manager-legacy greetd sddm lightdm gdm gdm3 xdm lxdm; do
        state=$(systemctl is-enabled "${dm}.service" 2>/dev/null || true)
        [[ "$state" == masked ]] || {
            echo "$dm is ${state:-missing}, expected masked" >&2
            return 1
        }
    done
}
