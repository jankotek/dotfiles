#!/usr/bin/env bats
# Verify that VM provisioning applied the canonical skeleton to its user.

load ../helpers

primary_vm_user() {
    local users=()
    local user
    mapfile -t users < <(getent passwd | awk -F: '
        $3 >= 1000 && $3 < 65534 &&
        $6 ~ "^/home/[^/]+/?$" &&
        $7 !~ /(nologin|false)$/ { print $1 }
    ')
    for user in "${users[@]}"; do
        if [[ $user == jan ]]; then
            printf '%s\n' jan
            return
        fi
    done
    (( ${#users[@]} == 1 )) || return 1
    printf '%s\n' "${users[0]}"
}

@test "canonical skeleton is applied to the primary VM user" {
    local user home group
    user=$(primary_vm_user)
    home=$(getent passwd "$user" | cut -d: -f6)
    group=$(id -gn "$user")

    cmp -s /opt/jan/skel/home/.bashrc "$home/.bashrc"
    [[ $(stat -c %U "$home") == "$user" ]]
    [[ $(stat -c %U "$home/.bashrc") == "$user" ]]
    [[ $(stat -c %G "$home/.bashrc") == "$group" ]]
    local dir
    for dir in \
        "$home/.agents/skills" \
        "$home/.claude/skills" \
        "$home/.grok/skills" \
        "$home/.pi/agent/skills"; do
        [[ -d $dir && ! -L $dir ]]
        [[ $(readlink -- "$dir/host-lab-vm-cli") == /opt/jan/agent/skills/host-lab-vm-cli ]]
        [[ $(readlink -- "$dir/host-lab-vm-gui") == /opt/jan/agent/skills/host-lab-vm-gui ]]
        [[ -f $dir/host-lab-vm-cli/SKILL.md ]]
    done
}
