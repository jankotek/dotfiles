#!/usr/bin/env bats

load ../helpers

@test "skel/home is the only user-dotfile source" {
    [[ ! -e "$OPT_JAN/home" ]]
    for script in setup/vm-xub24 setup/vm-xub26 setup/vm-baseweed; do
        assert_file_contains "$OPT_JAN/$script" 'rsync -a /opt/jan/skel/home/'
    done
}

@test "legacy provisioning traps preserve the failing status" {
    for script in setup/host-weed-kde setup/vm-xub24 setup/vm-baseweed; do
        assert_file_contains "$OPT_JAN/$script" 'local rc=\$?'
        assert_file_contains "$OPT_JAN/$script" 'exit "\$rc"'
    done
}

@test "aria2 is installed and used for artifact downloads" {
    assert_file_contains "$OPT_JAN/setup/common-cli-packages.sh" '^[[:space:]]*aria2$'
    assert_file_contains "$OPT_JAN/usr/sbin/jan-update-opt" 'command -v aria2c'
    assert_file_contains "$OPT_JAN/usr/sbin/jan-update-opt" 'download_file "\$url"'
}

@test "provisioning and update scripts do not manage Ollama" {
    ! grep -Riw ollama \
        "$OPT_JAN/setup" \
        "$OPT_JAN/usr/bin" \
        "$OPT_JAN/usr/sbin" \
        "$OPT_JAN/agent"
}

@test "host home backup is capped at 100 MiB" {
    assert_file_contains "$OPT_JAN/setup/host-weed-kde" \
        '^readonly HOME_BACKUP_MAX_KIB=102400$'
    assert_file_contains "$OPT_JAN/setup/host-weed-kde" \
        'HOME_SIZE_KIB > HOME_BACKUP_MAX_KIB'
}

@test "VM provisioners use systemd-networkd instead of NetworkManager" {
    for script in setup/vm-xub24 setup/vm-xub26 setup/vm-baseweed; do
        assert_file_contains "$OPT_JAN/$script" '^jan-setup-vm-networkd$'
    done
    assert_file_contains "$OPT_JAN/usr/sbin/jan-setup-vm-networkd" \
        '^DHCP=ipv4$'
    assert_file_contains "$OPT_JAN/usr/sbin/jan-setup-vm-networkd" \
        'apt-get purge -y network-manager network-manager-gnome'
}
