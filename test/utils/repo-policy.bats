#!/usr/bin/env bats
# ci: fixture

load ../helpers

@test "skel/home is the only user-dotfile source" {
    [[ ! -e "$OPT_JAN/home" ]]
    for script in setup/vm-xub26 setup/vm-cli; do
        assert_file_contains "$OPT_JAN/$script" 'rsync -a .*[/]opt/jan/skel/home/'
    done
}

@test "legacy provisioning traps preserve the failing status" {
    for script in setup/host-weed-kde setup/vm-xub26 setup/vm-cli; do
        assert_file_contains "$OPT_JAN/$script" 'local rc=\$?'
        assert_file_contains "$OPT_JAN/$script" 'exit "\$rc"'
    done
}

@test "aria2 is installed and used for artifact downloads" {
    assert_file_contains "$OPT_JAN/setup/common-cli-packages.sh" '^[[:space:]]*aria2$'
    assert_file_contains "$OPT_JAN/usr/sbin/optupdate" 'command -v aria2c'
    assert_file_contains "$OPT_JAN/usr/sbin/optupdate" 'download_file "\$url"'
}

@test "portable updater uses the canonical optupdate command name" {
    [[ -x "$OPT_JAN/usr/sbin/optupdate" ]]
    [[ ! -e "$OPT_JAN/usr/sbin/host-optupdate" ]]
    assert_file_contains "$OPT_JAN/setup/retire-path-util-names.sh" \
        '^[[:space:]]*host-optupdate$'
}

@test "default CLI provisioning installs Starship and updates Fresh through opt" {
    assert_file_contains "$OPT_JAN/setup/common-cli-packages.sh" \
        '^[[:space:]]*starship$'
    assert_file_contains "$OPT_JAN/usr/sbin/optupdate" \
        '^ALL_TOOLS=.* fresh '
    assert_file_contains "$OPT_JAN/usr/sbin/optupdate" \
        'download_single_binary "Fresh Editor" "fresh"'
    assert_file_contains "$OPT_JAN/test/basic/cli.bats" \
        'assert_command fresh'
}

@test "portable updater uses the unified IntelliJ IDEA release feed" {
    assert_file_contains "$OPT_JAN/usr/sbin/optupdate" \
        'products/releases[?]code=IIU&latest=true&type=release'
    assert_file_not_contains "$OPT_JAN/usr/sbin/optupdate" \
        'products/releases[?]code=IIC&'
}

@test "browser installers manage Origin and VM integration only" {
    [[ -x $OPT_JAN/usr/sbin/install-brave ]]
    [[ -x $OPT_JAN/usr/sbin/install-brave-vm ]]
    [[ -x $OPT_JAN/usr/sbin/install-chrome-vm ]]
    [[ ! -e $OPT_JAN/usr/sbin/install-brave-origin ]]
    [[ ! -e $OPT_JAN/usr/sbin/install-vivaldi ]]
    assert_file_contains "$OPT_JAN/usr/sbin/install-brave" 'brave-origin-beta'
    assert_file_contains "$OPT_JAN/usr/sbin/install-brave" \
        'zypper --non-interactive repos brave-browser-beta'
    assert_file_contains "$OPT_JAN/usr/sbin/install-brave" \
        'dnf config-manager addrepo --overwrite'
    assert_file_not_contains "$OPT_JAN/usr/sbin/install-brave" \
        'apt install -y brave-browser$'
    assert_file_contains "$OPT_JAN/setup/retire-path-util-names.sh" \
        '^[[:space:]]*install-brave-origin$'
    assert_file_contains "$OPT_JAN/setup/retire-path-util-names.sh" \
        '^[[:space:]]*install-vivaldi$'
    for script in setup/vm-xub26 setup/vm-baseweed; do
        assert_file_contains "$OPT_JAN/$script" '^/usr/local/sbin/install-chrome-vm$'
        assert_file_contains "$OPT_JAN/$script" '^/usr/local/sbin/install-brave-vm$'
    done
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
    for script in setup/vm-xub26 setup/vm-cli; do
        assert_file_contains "$OPT_JAN/$script" 'rsync -a .*[/]opt/jan/skel/home/'
        assert_file_not_contains "$OPT_JAN/$script" \
            'jan_home_backup|HOME_DIR.*-backup-|home-before-vm'
        assert_file_contains "$OPT_JAN/$script" \
            "rmdir ~/Desktop ~/Documents ~/Downloads"
        assert_file_not_contains "$OPT_JAN/$script" 'rm -rf ~/Desktop'
    done
}

@test "VM provisioners use systemd-networkd instead of NetworkManager" {
    for script in setup/vm-xub26 setup/vm-cli; do
        assert_file_contains "$OPT_JAN/$script" '^setup-vm-networkd$'
    done
    assert_file_contains "$OPT_JAN/usr/sbin/setup-vm-networkd" \
        '^DHCP=yes$'
    assert_file_contains "$OPT_JAN/usr/sbin/setup-vm-networkd" \
        'apt-get purge -y network-manager network-manager-gnome'
}

@test "retired Ubuntu 24 VM provisioner stays absent" {
    [[ ! -e "$OPT_JAN/setup/vm-xub24" ]]
}

@test "Tumbleweed refresh keeps repository signature verification" {
    assert_file_contains "$OPT_JAN/setup/install-cli-packages.sh" \
        'apt -y update'
    assert_file_not_contains "$OPT_JAN/setup/vm-baseweed" '--no-gpg-checks'
}

@test "baseweed deployment supports the baked qdistro image" {
    assert_file_contains "$OPT_JAN/setup/vm-cli" \
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
        setup/vm-cli \
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

@test "PATH utils are scripts, not vendored binaries" {
    local path magic
    for path in "$OPT_JAN"/usr/bin/* "$OPT_JAN"/usr/sbin/*; do
        [[ -f $path ]] || continue
        magic=$(head -c 4 -- "$path" | od -An -tx1 | tr -d ' \n')
        if [[ $magic == 7f454c46 ]]; then
            echo "vendored ELF binary: ${path#"$OPT_JAN"/}" >&2
            return 1
        fi
    done
}

@test "every utils test file declares its CI category" {
    local file tag
    for file in "$OPT_JAN"/test/utils/*.bats; do
        tag=$(sed -n '2p' "$file")
        if [[ ! $tag =~ ^\#\ ci:\ (fixture|portable-tools|manual)$ ]]; then
            echo "${file#"$OPT_JAN"/}: line 2 must be '# ci: fixture|portable-tools|manual'" >&2
            return 1
        fi
    done
}

@test "AGENTS.md directory layout names existing paths" {
    local path
    local -a paths
    mapfile -t paths < <(sed -n 's/^| `\([^`]*\)` |.*/\1/p' "$OPT_JAN/AGENTS.md")
    (( ${#paths[@]} > 5 ))
    for path in "${paths[@]}"; do
        [[ $path == */ ]] || continue
        if [[ ! -e $OPT_JAN/$path ]]; then
            echo "AGENTS.md lists missing path: $path" >&2
            return 1
        fi
    done
}

@test "CLAUDE.md points at the shared AGENTS.md" {
    [[ -L $OPT_JAN/CLAUDE.md ]]
    [[ $(readlink -- "$OPT_JAN/CLAUDE.md") == AGENTS.md ]]
    [[ ! -e $OPT_JAN/agents.md || $OPT_JAN/agents.md -ef $OPT_JAN/AGENTS.md ]]
}

@test "VM provisioners do not reference the retired home-root tree" {
    local script
    [[ ! -e $OPT_JAN/home-root ]]
    for script in setup/vm-xub26 setup/vm-baseweed; do
        assert_file_not_contains "$OPT_JAN/$script" 'home-root'
    done
}

@test "base packages include archive tools and exclude language package managers" {
    source "$OPT_JAN/setup/common-cli-packages.sh"
    local package
    for package in "${JAN_COMMON_CLI_PACKAGES[@]}"; do
        case $package in
            *pip*|npm*|pnpm*|yarn*|uv|bun|rubygem*|gem)
                echo "unexpected base package manager: $package" >&2
                return 1 ;;
        esac
    done
    for package in unzip tar gzip zstd python3 wget gdu; do
        [[ " ${JAN_COMMON_CLI_PACKAGES[*]} " == *" $package "* ]]
    done
    assert_file_contains "$OPT_JAN/setup/vm-xub26" 'apt-get install -y --no-install-recommends'
}

@test "Tumbleweed installs the distro apt compatibility frontend" {
    local script
    for script in setup/host-weed-kde usr/lib/vm_bootstrap.py; do
        assert_file_contains "$OPT_JAN/$script" 'zypper-aptitude'
    done
    # apt-get also exists on openSUSE now. Package names must come from zypper.
    for script in usr/sbin/setup-vm-networkd usr/sbin/guest-cleanup usr/sbin/pod-setup; do
        run bash -c 'text=$(cat "$1"); z=${text%%command -v zypper*}; a=${text%%command -v apt-get*}; (( ${#z} < ${#a} ))' _ "$OPT_JAN/$script"
        [[ $status == 0 ]]
    done
}

@test "host blocks Xorg before explicitly installing Plasma Wayland" {
    local script="$OPT_JAN/setup/host-weed-kde"
    assert_file_contains "$script" 'plasma6-session plasma6-nm'
    assert_file_contains "$script" 'xorg-x11-server xorg-x11-server-wrapper'
    assert_file_contains "$script" 'xterm xterm-bin'
    # Phantom lock names pass vacuously and hide a real gap. Plasma 6.8 ships
    # no separate X11 session package, so these must not be relied upon.
    assert_file_not_contains "$script" 'plasma6-session-x11'
    assert_file_not_contains "$script" 'kwin6-x11'
    run bash -c 'text=$(cat "$1"); locks=${text%%zypper -n addlock*}; install=${text%%zypper -n install*}; (( ${#locks} < ${#install} ))' _ "$script"
    [[ $status == 0 ]]
}

@test "the wallpaper is installed without touching distribution files" {
    local script="$OPT_JAN/setup/host-weed-kde"
    assert_file "$OPT_JAN/usr/share/jan-wallpaper.jpg"
    # A real copy, not the /usr/local -> /opt/jan symlink: Plasma stores this
    # absolute path, so it must resolve without the checkout.
    assert_file_contains "$script" 'install -D -m 0644 "\$WALLPAPER_SOURCE" "\$WALLPAPER_FILE"'
    assert_file_contains "$script" 'WALLPAPER_SOURCE="\${REPO_DIR}/usr/share/jan-wallpaper.jpg"'
    # Images under /usr/share/wallpapers are rpm-owned, so redirecting them makes
    # the wallpaper revert on the next package update. The script may still read
    # those directories to repair an older run; what it must never do again is
    # select images there and point them at the repo wallpaper.
    assert_file_not_contains "$script" 'ln -sf.*WALLPAPER_FILE'
    assert_file_not_contains "$script" "iname '\*\.jpe?g'"
    assert_file_not_contains "$script" 'wallpaper-branding'
}

@test "Plasma defaults name the installed wallpaper on a dark background" {
    local layout="$OPT_JAN/skel/home/.local/share/plasma/layout-templates/org.opensuse.desktop.defaultPanel/contents/layout.js"
    local locker="$OPT_JAN/usr/etc/xdg/kscreenlockerrc"
    # Desktop and lock screen are the only consumers; both name the image
    # directly so neither depends on a distribution wallpaper being installed.
    for file in "$layout" "$locker"; do
        assert_file_contains "$file" '/usr/local/share/jan-wallpaper.jpg'
        assert_file_contains "$file" '0,0,0'
    done
    assert_file_contains "$layout" 'wallpaperPlugin = "org.kde.image"'
    assert_file_contains "$layout" 'currentConfigGroup = \["Wallpaper", "org.kde.image", "General"\]'
    # Scoped like the look-and-feel layout that loads it, not across activities.
    assert_file_contains "$layout" 'desktopsForActivity(currentActivity())'
}

@test "lock screen defaults name an installed image and a dark fallback" {
    local rc="$OPT_JAN/usr/etc/xdg/kscreenlockerrc"
    assert_file "$rc"
    assert_file_contains "$rc" '^WallpaperPlugin=org.kde.image$'
    assert_file_contains "$rc" '^Image=/usr/local/share/jan-wallpaper.jpg$'
    # org.kde.image defaults Color to #ffffff, so an unreadable image leaves a
    # white lock screen. Pin the Sweet-dark background instead.
    assert_file_contains "$rc" '^Color=0,0,0$'
    assert_file_contains \
        "$OPT_JAN/usr/share/color-schemes/Sweet-dark.colors" '^BackgroundNormal=0,0,0$'
}

@test "the bundled cursor is the default at 48px for host and VMs" {
    assert_file "$OPT_JAN/dist/cursor/DMZhaloG/cursor.theme"
    assert_symlink "$OPT_JAN/usr/share/icons/DMZhaloG" \
        "$OPT_JAN/dist/cursor/DMZhaloG"
    # A cursor theme must not inherit itself; that is a lookup loop.
    assert_file_not_contains "$OPT_JAN/dist/cursor/DMZhaloG/cursor.theme" \
        '^Inherits=DMZhaloG$'
    # Plasma, system-wide so accounts that already exist pick it up...
    assert_file_contains "$OPT_JAN/usr/etc/xdg/kcminputrc" '^cursorTheme=DMZhaloG$'
    assert_file_contains "$OPT_JAN/usr/etc/xdg/kcminputrc" '^cursorSize=48$'
    # ...and per-user, because Plasma prepends ~/.config/kdedefaults to its
    # search path and the openSUSE look-and-feel writes breeze_cursors there,
    # which outranks any system file.
    assert_file_contains "$OPT_JAN/skel/home/.config/kcminputrc" '^cursorTheme=DMZhaloG$'
    assert_file_contains "$OPT_JAN/skel/home/.config/kcminputrc" '^cursorSize=48$'
    # libXcursor does not search /usr/local/share/icons, so the themes must be
    # linked into /usr/share/icons by every profile that installs them.
    assert_executable "$OPT_JAN/usr/sbin/install-cursor-theme"
    # update-alternatives owns this path on Debian/Ubuntu; do not ship it.
    [[ ! -e "$OPT_JAN/usr/share/icons/default" ]]
    assert_file_not_contains "$OPT_JAN/usr/sbin/install-cursor-theme" \
        '^read -r -a CURSOR_THEMES.*default'
    local script
    for script in setup/host-weed-kde setup/vm-cli setup/vm-xub26; do
        assert_file_contains "$OPT_JAN/$script" '^install-cursor-theme'
        # The helper replaces a hand-rolled copy that had no packaged-directory
        # guard, so no profile may reintroduce one.
        assert_file_not_contains "$OPT_JAN/$script" 'cp .*/usr/share/icons'
    done
    # GTK, via dconf; and XFCE, via the xsettings channel.
    assert_file_contains "$OPT_JAN/skel/home/.config/dconf-import.ini" \
        "^cursor-theme='DMZhaloG'$"
    assert_file_contains "$OPT_JAN/skel/home/.config/dconf-import.ini" \
        '^cursor-size=48$'
    local xsettings="$OPT_JAN/skel/home/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
    assert_file_contains "$xsettings" 'name="CursorThemeName" type="string" value="DMZhaloG"'
    assert_file_contains "$xsettings" 'name="CursorThemeSize" type="int" value="48"'
}

@test "RGB subpixel rendering is wired for every toolkit" {
    local fragment="$OPT_JAN/usr/share/fontconfig/conf.avail/60-jan-subpixel.conf"
    assert_file "$fragment"
    assert_file_contains "$fragment" '<const>rgb</const>'
    assert_file_contains "$fragment" '<const>hintslight</const>'
    # Qt reads kdeglobals in preference to fontconfig, so the two must agree.
    assert_file_contains "$OPT_JAN/skel/home/.config/kdeglobals" '^XftSubPixel=rgb$'
    assert_file_contains "$OPT_JAN/skel/home/.config/kdeglobals" '^XftHintStyle=hintslight$'
    assert_file_contains \
        "$OPT_JAN/skel/home/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" \
        'name="RGBA" type="string" value="rgb"'
    # Host and both VM families must install the fragments.
    local script
    for script in setup/host-weed-kde setup/vm-cli setup/vm-xub26; do
        assert_file_contains "$OPT_JAN/$script" '^install-fontconfig'
    done
    assert_executable "$OPT_JAN/usr/sbin/install-fontconfig"
}
