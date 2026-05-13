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

@test "go is installed" {
    assert_command go
}

@test "maven is installed" {
    assert_command mvn
}

@test "node is installed" {
    assert_command node
}

@test "tsc is installed" {
    assert_command tsc
}

@test "java is installed" {
    assert_command java
}

@test "yq is installed" {
    assert_command yq
}
