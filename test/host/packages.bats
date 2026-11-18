#!/usr/bin/env bats
# Verify host-specific packages: KDE apps, virtualization

load ../helpers

# --- KDE apps ---

@test "kdenlive is installed" {
    assert_command kdenlive
}

@test "kdiff3 is installed" {
    assert_command kdiff3
}

@test "kfind is installed" {
    assert_command kfind
}

@test "krename is installed" {
    assert_command krename
}

@test "krita is installed" {
    assert_command krita
}

@test "kstars is installed" {
    assert_command kstars
}

@test "ksystemlog is installed" {
    assert_command ksystemlog
}

@test "ktorrent is installed" {
    assert_command ktorrent
}

@test "kwrite is installed" {
    assert_command kwrite
}

@test "filelight is installed" {
    assert_command filelight
}

@test "partitionmanager is installed" {
    assert_command partitionmanager
}

# --- Virtualization ---

@test "virt-manager is installed" {
    assert_command virt-manager
}

@test "virt-install is installed" {
    assert_command virt-install
}

@test "virt-viewer is installed" {
    assert_command virt-viewer
}

@test "podman is installed" {
    assert_command podman
}

@test "lima is installed" {
    assert_command lima
}

# --- Dev tools ---

@test "maven is installed" {
    assert_command mvn
}

@test "java is installed" {
    assert_command java
}

@test "yq is installed" {
    assert_command yq
}

@test "host has a usable power profile service" {
    assert_command powerprofilesctl
    powerprofilesctl get
}

@test "host excludes standalone Xorg and X11 Plasma while retaining XWayland" {
    local package
    for package in xorg-x11-server xorg-x11-server-wrapper xterm xterm-bin; do
        if rpm -q "$package" >/dev/null 2>&1; then
            echo "unexpected host package: $package" >&2
            return 1
        fi
    done
    # Plasma 6.8 dropped the X11 session upstream; nothing may provide it.
    if command -v startplasma-x11 >/dev/null 2>&1; then
        echo "unexpected X11 Plasma session binary" >&2
        return 1
    fi
    rpm -q plasma6-session
    assert_command Xwayland
    assert_executable /usr/bin/startplasma-wayland
}

@test "graphical profile includes Zim" {
    assert_command zim
}

@test "golden image builder tools and appliance are installed" {
    rpm -q libguestfs guestfs-tools libguestfs-appliance libguestfs-xfs virtiofsd passt
    local tool
    for tool in guestfish virt-cat virt-customize virt-resize virt-sparsify qemu-img; do
        assert_command "$tool"
    done
}

# --- Banned desktop components ---

@test "SDDM, the Baloo indexer, and DrKonqi are absent and locked" {
    local pkg locks
    locks=$(zypper -n --no-refresh locks 2>/dev/null)
    for pkg in sddm sddm-qt6 kf6-baloo-file kf6-baloo-tools drkonqi6; do
        ! rpm -q "$pkg" >/dev/null 2>&1 || { echo "$pkg is installed" >&2; return 1; }
        grep -Eq "\| $pkg +\|" <<<"$locks" || { echo "$pkg is not locked" >&2; return 1; }
    done
}

@test "Baloo and DrKonqi units are masked for every user" {
    local unit
    for unit in plasma-baloorunner.service kde-baloo.service \
        drkonqi-coredump-launcher.socket drkonqi-sentry-postman.timer; do
        [[ $(readlink "/etc/systemd/user/$unit") == /dev/null ]] || {
            echo "$unit is not globally masked" >&2
            return 1
        }
    done
    [[ $(systemctl is-enabled drkonqi-coredump-processor@.service 2>/dev/null) == masked ]]
}

@test "Baloo file search and indexing are off by default" {
    assert_file_contains /usr/local/etc/xdg/krunnerrc '^baloosearchEnabled=false$'
    assert_file_contains /usr/local/etc/xdg/baloofilerc '^Indexing-Enabled=false$'
}

@test "disk, filesystem and performance tools are installed" {
    assert_executable /usr/sbin/mkfs.ext4   # e2fsprogs
    assert_command compsize
    assert_executable /usr/sbin/smartctl    # smartmontools
    assert_executable /usr/sbin/nvme        # nvme-cli
    assert_command iostat                   # sysstat
    assert_executable /usr/sbin/iotop
    assert_executable /usr/sbin/powertop
}

@test "dirty page cache is capped at 256 MiB background / 1 GiB blocking" {
    [[ $(</proc/sys/vm/dirty_background_bytes) -eq 268435456 ]]
    [[ $(</proc/sys/vm/dirty_bytes) -eq 1073741824 ]]
    assert_file /etc/sysctl.d/60-jan-writeback.conf
}

@test "passt SELinux policy is loaded so session VMs get DHCP under enforcing" {
    # Runs as the user: semodule needs root, so check the labels the loaded
    # modules give the binaries (unconfined bin_t when they are missing).
    [[ -e /sys/fs/selinux/enforce ]] || skip "SELinux is disabled"
    rpm -q passt-selinux >/dev/null 2>&1 || skip "passt-selinux is not installed"
    [[ $(stat -c %C /usr/bin/passt) == *:passt_exec_t:* ]]
    [[ $(stat -c %C /usr/bin/pasta) == *:pasta_exec_t:* ]]
}

@test "firewalld allows mosh in the default zone" {
    rpm -q firewalld >/dev/null 2>&1 || skip "firewalld is not installed"
    # /etc/firewalld is root-only; host tests normally run as the user.
    [[ -r /etc/firewalld/firewalld.conf ]] || skip "needs root to read /etc/firewalld"
    local zone
    zone=$(sed -n 's/^DefaultZone=//p' /etc/firewalld/firewalld.conf)
    [[ -n $zone ]] || zone=public
    grep -q '<service name="mosh"/>' "/etc/firewalld/zones/$zone.xml"
}

@test "DNS goes through the systemd-resolved stub" {
    systemctl is-active --quiet systemd-resolved.service
    [[ $(readlink /etc/resolv.conf) == ../run/systemd/resolve/stub-resolv.conf ]]
    grep -qx 'nameserver 127.0.0.53' /etc/resolv.conf
    assert_file_contains /etc/NetworkManager/conf.d/90-jan-dns-resolved.conf '^dns=systemd-resolved$'
    assert_file_contains /etc/NetworkManager/conf.d/90-jan-dns-resolved.conf '^rc-manager=unmanaged$'
    # NetworkManager must have handed the uplink's DNS to resolved.
    local uplink
    uplink=$(ip route show default | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
    [[ -n $uplink ]] || skip "no default route"
    resolvectl dns "$uplink" | grep -Eq ':[[:space:]]+[0-9a-f]'
}

@test "systemd-resolved leaves mDNS to avahi" {
    assert_file_contains /etc/systemd/resolved.conf.d/90-jan-mdns-avahi.conf '^MulticastDNS=no$'
    # The running daemon must have applied it: no link reports +mDNS.
    run resolvectl status
    [[ $status -eq 0 ]]
    [[ $output != *"+mDNS"* ]]
}
