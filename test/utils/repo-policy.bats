#!/usr/bin/env bats

load ../helpers

@test "skel/home is the only user-dotfile source" {
    [[ ! -e "$OPT_JAN/home" ]]
    for script in setup/vm-xub26 setup/vm-baseweed; do
        assert_file_contains "$OPT_JAN/$script" 'rsync -a /opt/jan/skel/home/'
    done
}

@test "legacy provisioning traps preserve the failing status" {
    for script in setup/host-weed-kde setup/vm-xub26 setup/vm-baseweed; do
        assert_file_contains "$OPT_JAN/$script" 'local rc=\$?'
        assert_file_contains "$OPT_JAN/$script" 'exit "\$rc"'
    done
}

@test "aria2 is installed and used for artifact downloads" {
    assert_file_contains "$OPT_JAN/setup/common-cli-packages.sh" '^[[:space:]]*aria2$'
    assert_file_contains "$OPT_JAN/usr/sbin/host-optupdate" 'command -v aria2c'
    assert_file_contains "$OPT_JAN/usr/sbin/host-optupdate" 'download_file "\$url"'
}

@test "default CLI provisioning installs Starship and updates Fresh through opt" {
    assert_file_contains "$OPT_JAN/setup/common-cli-packages.sh" \
        '^[[:space:]]*starship$'
    assert_file_contains "$OPT_JAN/usr/sbin/host-optupdate" \
        '^ALL_TOOLS=.* fresh '
    assert_file_contains "$OPT_JAN/usr/sbin/host-optupdate" \
        'download_single_binary "Fresh Editor" "fresh"'
    assert_file_contains "$OPT_JAN/test/basic/cli.bats" \
        'assert_command fresh'
}

@test "portable updater uses the unified IntelliJ IDEA release feed" {
    assert_file_contains "$OPT_JAN/usr/sbin/host-optupdate" \
        'products/releases[?]code=IIU&latest=true&type=release'
    assert_file_not_contains "$OPT_JAN/usr/sbin/host-optupdate" \
        'products/releases[?]code=IIC&'
}

@test "provisioning and update scripts do not manage Ollama" {
    if grep -Riw ollama \
        "$OPT_JAN/setup" \
        "$OPT_JAN/usr/bin" \
        "$OPT_JAN/usr/sbin" \
        "$OPT_JAN/agent"; then
        echo "unexpected ollama references" >&2
        return 1
    fi
}

@test "host provisioner contains no direct existing-home mutations" {
    assert_file_contains "$OPT_JAN/setup/host-weed-kde" \
        '^"${REPO_DIR}/skel/install"$'
    assert_file_not_contains "$OPT_JAN/setup/host-weed-kde" \
        'HOME_(USER|DIR|BACKUP)|/home|home-root'
}

@test "VM provisioners apply skel without automatic home backups" {
    for script in setup/vm-xub26 setup/vm-baseweed; do
        assert_file_contains "$OPT_JAN/$script" 'rsync -a /opt/jan/skel/home/'
        assert_file_not_contains "$OPT_JAN/$script" \
            'jan_home_backup|HOME_DIR.*-backup-|home-before-vm'
        assert_file_contains "$OPT_JAN/$script" \
            "rmdir ~/Desktop ~/Documents ~/Downloads"
        assert_file_not_contains "$OPT_JAN/$script" 'rm -rf ~/Desktop'
    done
}

@test "VM provisioners use systemd-networkd instead of NetworkManager" {
    for script in setup/vm-xub26 setup/vm-baseweed; do
        assert_file_contains "$OPT_JAN/$script" '^setup-vm-networkd$'
    done
    assert_file_contains "$OPT_JAN/usr/sbin/setup-vm-networkd" \
        '^DHCP=ipv4$'
    assert_file_contains "$OPT_JAN/usr/sbin/setup-vm-networkd" \
        'apt-get purge -y network-manager network-manager-gnome'
}

@test "retired Ubuntu 24 VM provisioner stays absent" {
    [[ ! -e "$OPT_JAN/setup/vm-xub24" ]]
}

@test "Tumbleweed refresh keeps repository signature verification" {
    assert_file_contains "$OPT_JAN/setup/vm-baseweed" \
        'zypper -n --gpg-auto-import-keys refresh'
    assert_file_not_contains "$OPT_JAN/setup/vm-baseweed" '--no-gpg-checks'
}

@test "baseweed deployment supports the baked qdistro image" {
    assert_file_contains "$OPT_JAN/setup/vm-baseweed" \
        '^mapfile -t HOME_USERS'
    assert_file_contains "$OPT_JAN/test/test-vm-baseweed-deploy.sh" \
        "require_clone_xml '<memoryBacking>'"
    assert_file_contains "$OPT_JAN/test/test-vm-baseweed-deploy.sh" \
        '/opt/jan/test/vm/network.bats'
    assert_file_contains "$OPT_JAN/test/test-vm-baseweed-deploy.sh" \
        '/opt/jan/test/vm/provisioned-home.bats'
}

@test "vm-gui pins the session URI and uses literal guest argv" {
    assert_file_contains "$OPT_JAN/usr/bin/vm-gui" \
        '^LIBVIRT_URI=qemu:///session$'
    assert_file_contains "$OPT_JAN/usr/bin/vm-gui" \
        '"\$VM_EXEC" "\$VM" --argv --user jan'
    assert_file_contains "$OPT_JAN/usr/bin/vm-gui" \
        'exec setsid -f -- "\$@" </dev/null >/dev/null 2>&1'
    assert_file_not_contains "$OPT_JAN/usr/bin/vm-gui" 'su - jan -c'
}

@test "skills live under agent/skills and are discovered via per-skill symlinks" {
    local skill dir
    local repo_dirs=(.agents/skills .claude/skills .grok/skills .pi/skills)
    local skel_dirs=(
        skel/home/.agents/skills
        skel/home/.claude/skills
        skel/home/.grok/skills
        skel/home/.pi/agent/skills
    )
    for dir in "${repo_dirs[@]}" "${skel_dirs[@]}"; do
        [[ -d $OPT_JAN/$dir && ! -L $OPT_JAN/$dir ]]
    done
    shopt -s nullglob
    local paths=("$OPT_JAN"/agent/skills/*)
    for dir in "${repo_dirs[@]}" "${skel_dirs[@]}"; do
        paths+=("$OPT_JAN/$dir"/*)
    done
    for skill in "${paths[@]}"; do
        skill=${skill##*/}
        assert_file "$OPT_JAN/agent/skills/$skill/SKILL.md"
        assert_no_relative_markdown_links "$OPT_JAN/agent/skills/$skill/SKILL.md"
        for dir in "${repo_dirs[@]}"; do
            [[ -L $OPT_JAN/$dir/$skill ]]
            [[ $(readlink -- "$OPT_JAN/$dir/$skill") == ../../agent/skills/$skill ]]
            assert_file "$OPT_JAN/$dir/$skill/SKILL.md"
        done
        for dir in "${skel_dirs[@]}"; do
            [[ -L $OPT_JAN/$dir/$skill ]]
            [[ $(readlink -- "$OPT_JAN/$dir/$skill") == /opt/jan/agent/skills/$skill ]]
        done
    done
}

@test "create-user seeds the canonical skeleton before useradd" {
    assert_file_contains "$OPT_JAN/usr/sbin/create-user" \
        '"\$REPO_DIR/skel/install"'
    assert_file_contains "$OPT_JAN/usr/sbin/create-user" \
        '^    useradd \\'
    assert_file_contains "$OPT_JAN/usr/sbin/create-user" \
        '"\$REPO_DIR/skel/install" "\$USER_HOME"'
}

@test "PATH utils use domain-first kebab-case stems" {
    local path name
    for path in "$OPT_JAN"/usr/bin/* "$OPT_JAN"/usr/sbin/*; do
        [[ -f $path ]] || continue
        name=${path##*/}
        [[ $name == starship ]] && continue
        [[ $name =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
        [[ $name != *.sh ]]
        [[ $name != jan-* ]]
    done
}

@test "setup scripts retire leftover PATH util names after symlink" {
    local script
    for script in \
        setup/host \
        setup/host-weed-kde \
        setup/vm-xub26 \
        setup/vm-baseweed \
        setup/vm-ub26-xfce; do
        assert_file_contains "$OPT_JAN/$script" 'retire-path-util-names.sh'
    done
}

@test "test launchers never install packages" {
    if grep -E '(apt-get|zypper|dnf)[[:space:]]+install' \
        "$OPT_JAN/test/test-host.sh" \
        "$OPT_JAN/test/test-vm.sh" \
        "$OPT_JAN/test/test-vm-deploy.sh" \
        "$OPT_JAN/test/test-vm-idempotency.sh"; then
        echo "unexpected package installs in test launchers" >&2
        return 1
    fi
}
