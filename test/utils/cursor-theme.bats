#!/usr/bin/env bats
# ci: fixture

load ../helpers

setup() {
    SRC="$BATS_TEST_TMPDIR/local-icons"
    DST="$BATS_TEST_TMPDIR/share-icons"
    mkdir -p "$SRC/DMZhaloG/cursors" "$SRC/RareAeroW7/cursors"
    export JAN_CURSOR_SRC="$SRC" JAN_CURSOR_DIR="$DST" \
        JAN_CURSOR_THEMES="DMZhaloG RareAeroW7 Absent"
    source "$BATS_TEST_DIRNAME/../../usr/sbin/install-cursor-theme"
}

@test "bundled themes are linked where libXcursor looks, and a rerun is a no-op" {
    install_cursor_theme
    [[ $(readlink "$DST/DMZhaloG") == "$SRC/DMZhaloG" ]]
    [[ $(readlink "$DST/RareAeroW7") == "$SRC/RareAeroW7" ]]
    # Absent themes are skipped, not linked to nothing.
    [[ ! -e "$DST/Absent" ]]
    install_cursor_theme
    [[ $(find "$DST" -maxdepth 1 -type l | wc -l) == 2 ]]
}

@test "a packaged directory is never replaced by a link" {
    mkdir -p "$DST/DMZhaloG"
    printf '[Icon Theme]\n' > "$DST/DMZhaloG/index.theme"
    run install_cursor_theme
    [[ $status == 0 ]]
    [[ $output == *"is packaged; leaving it alone"* ]]
    [[ ! -L "$DST/DMZhaloG" ]]
    assert_file "$DST/DMZhaloG/index.theme"
    # The other theme is still wired up.
    [[ $(readlink "$DST/RareAeroW7") == "$SRC/RareAeroW7" ]]
}

@test "a stale link is repointed" {
    mkdir -p "$DST"
    ln -sfn /nonexistent/DMZhaloG "$DST/DMZhaloG"
    install_cursor_theme
    [[ $(readlink "$DST/DMZhaloG") == "$SRC/DMZhaloG" ]]
}

@test "a missing source directory is reported" {
    # JAN_CURSOR_SRC is read when the script is sourced, so override the
    # variable the helper actually uses.
    CURSOR_SRC="$BATS_TEST_TMPDIR/absent"
    run install_cursor_theme
    [[ $status == 1 ]]
    [[ $output == *"missing $BATS_TEST_TMPDIR/absent"* ]]
}

@test "libXcursor does not search /usr/local, which is why the links exist" {
    # If this ever changes upstream the helper becomes unnecessary. The library
    # path differs between openSUSE and Debian multiarch, so discover it.
    command -v strings >/dev/null || skip "binutils not installed"
    # ldconfig is not on a normal user's PATH, so glob the usual locations:
    # openSUSE uses lib64, Debian and Ubuntu use multiarch.
    local lib="" cand
    for cand in /usr/lib64/libXcursor.so.1 /usr/lib/*-linux-gnu*/libXcursor.so.1 \
                /usr/lib/libXcursor.so.1; do
        if [[ -e $cand ]]; then lib=$cand; break; fi
    done
    [[ -n $lib ]] || skip "libXcursor not installed"
    run bash -c "strings -a \"\$1\" | grep -xE '~?/[a-z/.:~]*icons[a-z/.:~]*'" _ "$lib"
    [[ $status == 0 ]]
    [[ $output != */usr/local/share/icons* ]]
    [[ $output == */usr/share/icons* ]]
}
