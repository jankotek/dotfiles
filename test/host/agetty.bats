#!/usr/bin/env bats
# Verify authenticated console logins and the CLI Plasma handoff.

load ../helpers

MANAGED_LOGIN_TTYS=(2 3 4 5 6 7 8 9 10)

@test "tty1 uses the stock distribution getty without local overrides" {
    local fragment drop_ins
    fragment=$(systemctl show getty@tty1.service -p FragmentPath --value)
    drop_ins=$(systemctl show getty@tty1.service -p DropInPaths --value)

    [[ $fragment == /usr/lib/systemd/system/getty@.service ]]
    [[ $drop_ins != *"/etc/systemd/system/getty@tty1.service.d/"* ]]
    [[ ! -e /etc/systemd/system/getty@tty1.service ]]
    [[ ! -e /etc/systemd/system/getty@tty1.service.d ]]
}

@test "tty2 through tty10 use ordinary getty services" {
    local tty state fragment
    for tty in "${MANAGED_LOGIN_TTYS[@]}"; do
        state=$(systemctl is-enabled "getty@tty${tty}.service")
        [[ $state == enabled ]]
        fragment=$(systemctl show "getty@tty${tty}.service" \
            -p FragmentPath -p ExecStart -p Restart)
        [[ $fragment == *"agetty"* ]]
        [[ $fragment == *"Restart=always"* ]]
    done
}

@test "agetty setup never changes the runtime state of a getty" {
    assert_file_contains /usr/local/sbin/jan-setup-agetty \
        'readonly -a MANAGED_LOGIN_TTYS=(2 3 4 5 6 7 8 9 10)'
    ! grep -Eq 'systemctl[[:space:]]+(start|stop|restart|try-restart)[[:space:]].*getty@tty' \
        /usr/local/sbin/jan-setup-agetty
}

@test "host setup does not reset a live virtual console" {
    local font_setup=/usr/local/sbin/jan-console-font
    ! grep -Eq 'systemctl[[:space:]]+restart[[:space:]]+systemd-vconsole-setup|setupcon[[:space:]]+--force' \
        "$font_setup"
}

@test "system upgrade has no unaudited service or session hook" {
    local upgrade=/usr/local/sbin/jan-upgrade
    ! sed '/^[[:space:]]*#/d' "$upgrade" | \
        grep -Eq 'systemctl|loginctl|jan-dotfiles-update'
}

@test "login PAM stack registers sessions with logind" {
    local pam_file
    pam_file=/etc/pam.d/login
    [[ -r $pam_file ]] || pam_file=/usr/lib/pam.d/login
    if grep -Eq '^[[:space:]]*session[[:space:]].*pam_systemd\.so' "$pam_file"; then
        return 0
    fi
    grep -Eq '^[[:space:]]*session[[:space:]]+(include|substack)[[:space:]]+common-session' "$pam_file"
    grep -Eq '^[[:space:]]*session[[:space:]].*pam_systemd\.so' /etc/pam.d/common-session
}

@test "agetty banner shows local system information" {
    assert_file /etc/issue.d/80-jan-system-info.issue
    assert_file_contains /etc/issue.d/80-jan-system-info.issue 'Host: \\n'
    assert_file_contains /etc/issue.d/80-jan-system-info.issue 'Architecture: \\m'
    assert_file_contains /etc/issue.d/80-jan-system-info.issue 'IPv4: \\4'
    assert_file_contains /etc/issue.d/80-jan-system-info.issue 'Console: \\l'
    assert_file_contains /etc/issue.d/80-jan-system-info.issue 'Start Plasma Wayland: exec jan-plasma-session'
    [[ ! -e /etc/issue.net.d/80-jan-system-info.issue ]]
}

@test "Plasma command replaces Bash with the supervised Wayland launcher" {
    assert_executable /usr/local/bin/jan-plasma-session
    assert_executable /usr/local/bin/jan-greetd-session
    assert_file_contains /usr/local/bin/jan-plasma-session '^exec /usr/local/bin/jan-greetd-session wayland /usr/bin/startplasma-wayland$'
    assert_file_contains /usr/local/bin/jan-greetd-session 'trap clear_activation_environment_on_exit EXIT'
    assert_file_contains /usr/local/bin/jan-greetd-session 'terminate_session_tree TERM 143'
}

@test "old greetd VT services and configurations are gone" {
    local tty state
    for tty in 3 4 5 6 7 8 9 10 11 12; do
        [[ ! -e /etc/greetd/config-tty${tty}.toml ]]
        [[ ! -e /etc/systemd/system/greetd-tty${tty}.service ]]
        state=$(systemctl is-active "greetd-tty${tty}.service" 2>/dev/null || true)
        [[ $state != active ]]
    done
    [[ ! -e /etc/systemd/system/jan-greetd-switch-tty3.service ]]
    [[ ! -e /etc/systemd/logind.conf.d/80-jan-greetd-vts.conf ]]
}

@test "display managers are masked" {
    local dm state
    for dm in display-manager display-manager-legacy greetd greetd-kde sddm lightdm gdm gdm3 xdm lxdm; do
        state=$(systemctl is-enabled "${dm}.service" 2>/dev/null || true)
        [[ $state == masked ]] || {
            echo "$dm is ${state:-missing}, expected masked" >&2
            return 1
        }
    done
}

@test "Full HD framebuffer settings survive repeat setup" {
    assert_file_contains /proc/cmdline 'video=1920x1080'
    if [[ -f /etc/default/grub ]]; then
        [[ $(grep -Ec '^GRUB_GFXMODE=' /etc/default/grub) -eq 1 ]]
        [[ $(grep -Ec '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub) -eq 1 ]]
        assert_file_contains /etc/default/grub '^GRUB_GFXMODE="1920x1080,auto"$'
        assert_file_contains /etc/default/grub '^GRUB_GFXPAYLOAD_LINUX="1920x1080"$'
        [[ $(grep -Eo '(^|[[:space:]])video=1920x1080($|[[:space:]"])' /etc/default/grub | wc -l) -eq 1 ]]
    else
        [[ $(grep -Eo '(^|[[:space:]])video=1920x1080($|[[:space:]])' /etc/kernel/cmdline | wc -l) -eq 1 ]]
    fi
}
