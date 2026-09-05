#!/usr/bin/env bats

load ../helpers

setup() {
    export UTIL_TMP="$BATS_TEST_TMPDIR/utilities"
    mkdir -p "$UTIL_TMP/bin" "$UTIL_TMP/home" "$UTIL_TMP/out"
}

@test "new utility commands provide help" {
    local utility
    for utility in \
        jan-clean-check \
        jan-doctor \
        jan-dotfiles-diff \
        jan-download \
        jan-vm-reset \
        jan-vm-smoke; do
        run "$OPT_JAN/usr/bin/$utility" --help
        [[ $status -eq 0 ]]
        [[ $output == Usage:* ]]
    done
}

@test "jan-dotfiles-diff previews canonical files without modifying home" {
    run env OPT_JAN="$OPT_JAN" \
        "$OPT_JAN/usr/bin/jan-dotfiles-diff" "$UTIL_TMP/home"
    [[ $status -eq 0 ]]
    [[ $output == *".bashrc"* ]]
    [[ ! -e "$UTIL_TMP/home/.bashrc" ]]
}

@test "jan-dotfiles-diff explains how to seed a missing account" {
    run env OPT_JAN="$OPT_JAN" \
        "$OPT_JAN/usr/bin/jan-dotfiles-diff" jan-user-that-does-not-exist
    [[ $status -eq 2 ]]
    [[ $output == *"skel/install"* ]]
    [[ $output == *"useradd --create-home"* ]]
}

@test "jan-download verifies checksum and publishes atomically" {
    cat > "$UTIL_TMP/bin/aria2c" <<'EOF'
#!/bin/bash
set -euo pipefail
for argument in "$@"; do
    case "$argument" in
        --dir=*) destination_dir=${argument#--dir=} ;;
        --out=*) destination_name=${argument#--out=} ;;
        file://*) source_file=${argument#file://} ;;
    esac
done
cp "$source_file" "$destination_dir/$destination_name"
EOF
    chmod +x "$UTIL_TMP/bin/aria2c"
    checksum=$(sha256sum "$OPT_JAN/README.md" | awk '{print $1}')

    run env PATH="$UTIL_TMP/bin:$PATH" \
        "$OPT_JAN/usr/bin/jan-download" \
        "file://$OPT_JAN/README.md" "$UTIL_TMP/out/readme" "$checksum"
    [[ $status -eq 0 ]]
    cmp "$OPT_JAN/README.md" "$UTIL_TMP/out/readme"
    [[ ! -e "$UTIL_TMP/out/readme.partial" ]]
    [[ ! -e "$UTIL_TMP/out/readme.partial.url" ]]
}

@test "jan-download rejects an invalid checksum before downloading" {
    run env PATH="$UTIL_TMP/bin:$PATH" \
        "$OPT_JAN/usr/bin/jan-download" \
        https://example.invalid/file "$UTIL_TMP/out/file" invalid
    [[ $status -eq 2 ]]
    [[ ! -e "$UTIL_TMP/out/file" ]]
    [[ ! -e "$UTIL_TMP/out/file.partial" ]]
}

@test "jan-download deletes content after a checksum mismatch" {
    cat > "$UTIL_TMP/bin/aria2c" <<'EOF'
#!/bin/bash
set -euo pipefail
for argument in "$@"; do
    case "$argument" in
        --dir=*) destination_dir=${argument#--dir=} ;;
        --out=*) destination_name=${argument#--out=} ;;
        file://*) source_file=${argument#file://} ;;
    esac
done
cp "$source_file" "$destination_dir/$destination_name"
EOF
    chmod +x "$UTIL_TMP/bin/aria2c"

    run env PATH="$UTIL_TMP/bin:$PATH" \
        "$OPT_JAN/usr/bin/jan-download" \
        "file://$OPT_JAN/README.md" "$UTIL_TMP/out/bad" \
        0000000000000000000000000000000000000000000000000000000000000000
    [[ $status -eq 1 ]]
    [[ ! -e "$UTIL_TMP/out/bad" ]]
    [[ ! -e "$UTIL_TMP/out/bad.partial" ]]
    [[ ! -e "$UTIL_TMP/out/bad.partial.url" ]]
}

@test "jan-vm-reset refuses to reset a VM from itself" {
    run "$OPT_JAN/usr/bin/jan-vm-reset" same-vm same-vm
    [[ $status -eq 2 ]]
    [[ $output == *"must differ"* ]]
}
