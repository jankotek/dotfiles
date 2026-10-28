#!/usr/bin/env bats
# ci: fixture

setup() {
    source "$BATS_TEST_DIRNAME/../../usr/sbin/setup-kernel-tweaks"
    PARAMS=(zswap.enabled=1 zswap.compressor=lzo)
    CALLS="$BATS_TEST_TMPDIR/calls"
    update-grub() { echo update-grub >> "$CALLS"; }
    sdbootutil() { echo "sdbootutil $*" >> "$CALLS"; }
}

@test "IPv6 migration removes only the disabled parameter including quoted boundaries" {
    local config="$BATS_TEST_TMPDIR/config"
    cat > "$config" <<'CONFIG'
ipv6.disable=1 quiet ipv6.disable=1
GRUB_CMDLINE_LINUX_DEFAULT="quiet ipv6.disable=1"
GRUB_CMDLINE_LINUX='ipv6.disable=1'
ipv6.disable=0 ipv6.disable=10 custom.ipv6.disable=1
CONFIG
    remove_ipv6_ban "$config"
    [[ $(sed -n '1p' "$config") == ' quiet ' ]]
    [[ $(sed -n '2p' "$config") == 'GRUB_CMDLINE_LINUX_DEFAULT="quiet "' ]]
    [[ $(sed -n '3p' "$config") == "GRUB_CMDLINE_LINUX=''" ]]
    [[ $(sed -n '4p' "$config") == 'ipv6.disable=0 ipv6.disable=10 custom.ipv6.disable=1' ]]
}

@test "GRUB migration preserves boot arguments and updates stale cloud drop-in" {
    local config="$BATS_TEST_TMPDIR/grub" dropins="$BATS_TEST_TMPDIR/grub.d"
    mkdir -p "$dropins"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet ipv6.disable=1"' > "$config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0"' > "$dropins/50-cloudimg-settings.cfg"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT ipv6.disable=1"' > "$dropins/99-jan-kernel-tweaks.cfg"
    add_params_grub "$config" "$dropins"
    grep -q 'quiet' "$config"
    grep -q 'zswap.enabled=1' "$config"
    if grep -q 'ipv6.disable=1' "$config" "$dropins/99-jan-kernel-tweaks.cfg"; then
        echo "IPv6 ban survived migration" >&2
        return 1
    fi
    grep -q 'console=ttyS0' "$dropins/50-cloudimg-settings.cfg"
    grep -q '^update-grub$' "$CALLS"
    cp "$config" "$config.expected"
    add_params_grub "$config" "$dropins"
    cmp "$config" "$config.expected"
}

@test "systemd-boot migration preserves machine parameters and refreshes entries on rerun" {
    local config="$BATS_TEST_TMPDIR/cmdline"
    echo 'root=UUID=example ipv6.disable=1 initcall_blacklist=sysfb_init,simpledrm_platform_driver_init' > "$config"
    add_params_sdboot "$config"
    grep -q 'root=UUID=example' "$config"
    grep -q 'initcall_blacklist=sysfb_init,simpledrm_platform_driver_init' "$config"
    grep -q 'zswap.compressor=lzo' "$config"
    if grep -q 'ipv6.disable=1' "$config"; then
        echo "IPv6 ban survived migration" >&2
        return 1
    fi
    cp "$config" "$config.expected"
    add_params_sdboot "$config"
    cmp "$config" "$config.expected"
    [[ $(wc -l < "$CALLS") == 2 ]]
}
