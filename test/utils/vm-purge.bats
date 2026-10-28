#!/usr/bin/env bats
# ci: fixture

@test "Ubuntu purge patterns reach apt literally even when cwd contains matching files" {
    touch "$BATS_TEST_TMPDIR/cups-important.txt" "$BATS_TEST_TMPDIR/tumbler-data" \
        "$BATS_TEST_TMPDIR/local-packagekit-file"
    local block
    block=$(sed -n '/^apt-get purge -y /,/^$/p' "$OPT_JAN/setup/vm-xub26")
    run bash -c '
        cd "$1"
        apt-get() { printf "%s\n" "$@"; }
        eval "$2"
    ' _ "$BATS_TEST_TMPDIR" "$block"
    [[ $status == 0 ]]
    [[ $output == *$'\ncups*\n'* ]]
    [[ $output == *$'\ntumbler*\n'* ]]
    [[ $output == *$'\n*packagekit*\n'* ]]
    [[ $output != *important.txt* && $output != *tumbler-data* && $output != *local-packagekit-file* ]]
    [[ $(grep -cx xfce4-screensaver <<<"$output") == 1 ]]
}
