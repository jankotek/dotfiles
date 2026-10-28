#!/usr/bin/env bats
# ci: fixture

setup() {
    export OPT_JAN=${OPT_JAN:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
    export PYTHONPATH="$OPT_JAN/usr/lib"
}

@test "golden recipes include actual checkout inputs and isolate disposable domains" {
    run python3 "$OPT_JAN/test/fixtures/vm-golden.py"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "CLI packages exclude Go, GUI applications and language package managers" {
    source "$OPT_JAN/setup/common-cli-packages.sh"
    local package
    for package in "${JAN_COMMON_CLI_PACKAGES[@]}"; do
        case $package in
            go|golang*|zim|*xfce*|*chrome*|npm|*pip*|uv|pnpm|yarn) return 1 ;;
        esac
    done
}

@test "apt frontend uses distro-specific recommendation flags and archive names" {
    run bash -c 'command() { if [[ $* == "-v zypper" ]]; then return 0; fi; builtin command "$@"; }; source "$1"; printf "%s\n" "${JAN_APT_INSTALL_OPTIONS[*]}" "${JAN_DISTRO_CLI_PACKAGES[*]}"' _ "$OPT_JAN/setup/common-cli-packages.sh"
    [ "$status" -eq 0 ]
    [[ $output == *'--without-recommends'* && $output == *$'\nxz' ]]
    run bash -c 'command() { if [[ $* == "-v zypper" ]]; then return 1; fi; builtin command "$@"; }; source "$1"; printf "%s\n" "${JAN_APT_INSTALL_OPTIONS[*]}" "${JAN_DISTRO_CLI_PACKAGES[*]}"' _ "$OPT_JAN/setup/common-cli-packages.sh"
    [ "$status" -eq 0 ]
    [[ $output == *'--no-install-recommends'* && $output == *xz-utils ]]
}
