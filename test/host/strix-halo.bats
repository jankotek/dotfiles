#!/usr/bin/env bats
# Verify Strix Halo GPU configuration for llama.cpp / ROCm

load ../helpers

setup() {
    if ! lspci -nn 2>/dev/null | grep -qi 'Strix Halo'; then
        skip "not a Strix Halo system"
    fi
}

@test "sdbootutil is installed" {
    assert_command sdbootutil
}

@test "amdgpu.gttsize is set in boot params" {
    assert_file_contains /proc/cmdline 'amdgpu.gttsize=120832'
}

@test "iommu=pt in boot params" {
    assert_file_contains /proc/cmdline 'iommu=pt'
}

@test "amd_iommu=on in boot params" {
    assert_file_contains /proc/cmdline 'amd_iommu=on'
}

@test "amdgpu.noretry=0 in boot params" {
    assert_file_contains /proc/cmdline 'amdgpu.noretry=0'
}

@test "ttm.page_pool_size in boot params" {
    assert_file_contains /proc/cmdline 'ttm.page_pool_size=25600000'
}

@test "ttm.pages_limit in boot params" {
    assert_file_contains /proc/cmdline 'ttm.pages_limit=32505856'
}

@test "GTT size is at least 110GB" {
    local gtt_bytes
    gtt_bytes=$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | head -1)
    [[ -n "$gtt_bytes" ]] || skip "cannot read gtt total"
    # 110GB in bytes
    [[ "$gtt_bytes" -ge 118111600640 ]]
}

@test "fixed VRAM is 512MB (set in BIOS)" {
    local vram_bytes
    vram_bytes=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
    [[ -n "$vram_bytes" ]] || skip "cannot read vram total"
    # 512MB = 536870912, allow up to 600MB for rounding
    [[ "$vram_bytes" -le 629145600 ]]
}
