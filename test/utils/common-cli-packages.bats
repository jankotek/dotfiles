#!/usr/bin/env bats
# ci: fixture

packages_for() {
    run env JAN_TEST_ZYPPER="$1" bash -c '
        command() {
            if [[ $1 == -v && $2 == zypper ]]; then
                [[ $JAN_TEST_ZYPPER == 1 ]]
            else
                builtin command "$@"
            fi
        }
        source "$1"
        printf "common=%s\n" "${JAN_COMMON_CLI_PACKAGES[*]}"
        printf "distro=%s\n" "${JAN_DISTRO_CLI_PACKAGES[*]}"
    ' _ "$BATS_TEST_DIRNAME/../../setup/common-cli-packages.sh"
    [[ $status == 0 ]]
}

@test "Tumbleweed selects xz and leaves Go optional with apt compatibility" {
    packages_for 1
    [[ $output == *$'\ndistro=xz' ]]
    [[ ! $output =~ (^|[[:space:]=])(go|golang-go)([[:space:]]|$) ]]
    [[ $output != *xz-utils* ]]
}

@test "Ubuntu selects xz-utils and leaves Go optional" {
    packages_for 0
    [[ $output == *$'\ndistro=xz-utils' ]]
    [[ ! $output =~ (^|[[:space:]=])(go|golang-go)([[:space:]]|$) ]]
}
