#!/usr/bin/env bats
# Verify /opt/jan structure and repo contents

load ../helpers

@test "/opt/jan directory exists" {
    assert_dir "$OPT_JAN"
}

@test "/opt/jan/usr/bin exists" {
    assert_dir "$OPT_JAN/usr/bin"
}

@test "/opt/jan/usr/sbin exists" {
    assert_dir "$OPT_JAN/usr/sbin"
}

@test "/opt/jan/home exists" {
    assert_dir "$OPT_JAN/home"
}

@test "/opt/jan/setup exists" {
    assert_dir "$OPT_JAN/setup"
}

@test "jan-upgrade script exists in repo" {
    assert_executable "$OPT_JAN/usr/sbin/jan-upgrade"
}

@test "jan-update-opt script exists in repo" {
    assert_executable "$OPT_JAN/usr/sbin/jan-update-opt"
}

@test "/home is 0755" {
    [[ "$(stat -c %a /home)" == "755" ]]
}

@test "all home directories are 0700" {
    for dir in /home/*/; do
        [[ -d "$dir" ]] || continue
        local perms
        perms=$(stat -c %a "$dir")
        if [[ "$perms" != "700" ]]; then
            echo "$dir is $perms, expected 700" >&2
            return 1
        fi
    done
}
