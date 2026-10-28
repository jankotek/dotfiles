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
    for package in xorg-x11-server xorg-x11-server-wrapper plasma6-session-x11 kwin6-x11 xterm xterm-bin; do
        if rpm -q "$package"; then
            echo "unexpected host package: $package" >&2
            return 1
        fi
    done
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
