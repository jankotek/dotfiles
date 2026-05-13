#!/usr/bin/env bats
#
# Verify the desired post-fix state for the multi-monitor / TTY-switch
# flicker mitigations described in doc/todo/monitors.md.
#
# Each fix has a corresponding setup script in usr/sbin/jan-host-monitors-fix-*.
# These tests assume those scripts have been run and the system rebooted.
# Tests are skipped when not on host hardware (no DRM cards, in a VM, etc.)
# so this file is safe to run via test-host.sh on any system.

load ../helpers

setup() {
    if systemd-detect-virt -q -v 2>/dev/null; then
        skip "host-only tests (running inside a VM)"
    fi
}

# Yield user names for /home/* directories belonging to interactive users.
# Filters out service accounts using two heuristics:
#  1. login shell is interactive (not nologin/false/etc.)
#  2. primary group is NOT the same name as the user — service accounts
#     typically have a dedicated own-named primary group (forgejo-runner,
#     www-data, etc.), while real users share a generic group like
#     `users` (gid 100) or are explicitly in another shared group.
_human_home_users() {
    local d user shell pgrp
    for d in /home/*; do
        [[ -d "$d" ]] || continue
        user=$(stat -c '%U' "$d") || continue
        [[ "$user" == UNKNOWN ]] && continue
        id "$user" &>/dev/null || continue
        shell=$(getent passwd "$user" | cut -d: -f7)
        case "$shell" in
            ''|*/nologin|*/false|*/sync|*/halt|*/shutdown) continue ;;
        esac
        pgrp=$(id -gn "$user")
        [[ "$pgrp" == "$user" ]] && continue
        echo "$user $d"
    done
}

# --- Fix 1: home users in render+video ---

@test "every /home/* human user is in the render group" {
    while read -r user _; do
        id -nG "$user" | tr ' ' '\n' | grep -qxF render \
            || { echo "$user not in render" >&2; return 1; }
    done < <(_human_home_users)
}

@test "every /home/* human user is in the video group" {
    while read -r user _; do
        id -nG "$user" | tr ' ' '\n' | grep -qxF video \
            || { echo "$user not in video" >&2; return 1; }
    done < <(_human_home_users)
}

# --- Fix 2: EDID firmware cache ---

@test "/lib/firmware/edid contains a cached EDID for every connected output" {
    local cards=(/sys/class/drm/card*-*)
    [[ -e "${cards[0]}" ]] || skip "no DRM outputs visible"

    local found_any=0
    for sysdir in "${cards[@]}"; do
        [[ -d "$sysdir" ]] || continue
        [[ -r "$sysdir/status" ]] || continue
        [[ "$(cat "$sysdir/status")" == "connected" ]] || continue

        local name="${sysdir##*/}"
        [[ "$name" =~ ^card[0-9]+-(.+)$ ]] || continue
        local connector="${BASH_REMATCH[1]}"
        local cached="/lib/firmware/edid/edid-${connector}.bin"
        [[ -f "$cached" ]] || {
            echo "missing cached EDID: $cached" >&2
            return 1
        }
        [[ -s "$cached" ]] || {
            echo "empty cached EDID: $cached" >&2
            return 1
        }
        found_any=1
    done
    [[ $found_any -eq 1 ]] || skip "no connected outputs"
}

@test "kernel cmdline references drm.edid_firmware" {
    assert_file_contains /proc/cmdline 'drm.edid_firmware='
}

@test "drm.edid_firmware mapping points at every connected output" {
    local cmdline
    cmdline=$(tr ' ' '\n' < /proc/cmdline | grep '^drm\.edid_firmware=' || true)
    [[ -n "$cmdline" ]] || skip "drm.edid_firmware not set"

    local cards=(/sys/class/drm/card*-*)
    [[ -e "${cards[0]}" ]] || skip "no DRM outputs visible"

    for sysdir in "${cards[@]}"; do
        [[ -d "$sysdir" ]] || continue
        [[ -r "$sysdir/status" ]] || continue
        [[ "$(cat "$sysdir/status")" == "connected" ]] || continue
        local name="${sysdir##*/}"
        [[ "$name" =~ ^card[0-9]+-(.+)$ ]] || continue
        local connector="${BASH_REMATCH[1]}"
        echo "$cmdline" | grep -qF "${connector}:" \
            || { echo "no mapping for ${connector} in: $cmdline" >&2; return 1; }
    done
}

# --- Fix 5: amdgpu module options ---

@test "/etc/modprobe.d/amdgpu.conf pins dc=1 and dpm=1" {
    assert_file /etc/modprobe.d/amdgpu.conf
    grep -E '^[[:space:]]*options[[:space:]]+amdgpu[[:space:]].*\bdc=1\b' \
        /etc/modprobe.d/amdgpu.conf
    grep -E '^[[:space:]]*options[[:space:]]+amdgpu[[:space:]].*\bdpm=1\b' \
        /etc/modprobe.d/amdgpu.conf
}

@test "amdgpu module reports dc=1 at runtime" {
    [[ -r /sys/module/amdgpu/parameters/dc ]] || skip "amdgpu not loaded"
    local v
    v=$(cat /sys/module/amdgpu/parameters/dc)
    # On most kernels the value is 'Y' or '1' for true.
    [[ "$v" == "Y" || "$v" == "1" ]]
}

@test "amdgpu module reports dpm=1 at runtime" {
    [[ -r /sys/module/amdgpu/parameters/dpm ]] || skip "amdgpu not loaded"
    local v
    v=$(cat /sys/module/amdgpu/parameters/dpm)
    [[ "$v" == "1" || "$v" == "Y" ]]
}

# --- Fix 4: KWin DPMS lock disabled per user ---

@test "every human user's kwinrc disables Effect-dpms LockAfterLockScreen" {
    local found=0 kwinrc
    while read -r user d; do
        kwinrc="$d/.config/kwinrc"
        [[ -f "$kwinrc" ]] || continue
        found=1
        awk '
            /^\[/ { sect=$0 }
            sect=="[Effect-dpms]" && /^LockAfterLockScreen=/ { print; exit }
        ' "$kwinrc" | grep -qF 'LockAfterLockScreen=false' \
            || { echo "$kwinrc: [Effect-dpms] LockAfterLockScreen not false" >&2; return 1; }
    done < <(_human_home_users)
    [[ $found -eq 1 ]] || skip "no users have a kwinrc yet"
}

@test "every human user's kwinrc disables Wayland DpmsLockAfterLockScreen" {
    local found=0 kwinrc
    while read -r user d; do
        kwinrc="$d/.config/kwinrc"
        [[ -f "$kwinrc" ]] || continue
        found=1
        awk '
            /^\[/ { sect=$0 }
            sect=="[Wayland]" && /^DpmsLockAfterLockScreen=/ { print; exit }
        ' "$kwinrc" | grep -qF 'DpmsLockAfterLockScreen=false' \
            || { echo "$kwinrc: [Wayland] DpmsLockAfterLockScreen not false" >&2; return 1; }
    done < <(_human_home_users)
    [[ $found -eq 1 ]] || skip "no users have a kwinrc yet"
}
