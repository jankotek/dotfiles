#!/usr/bin/env bats
# ci: fixture

setup() {
    AVAIL="$BATS_TEST_TMPDIR/conf.avail"
    CONF_D="$BATS_TEST_TMPDIR/conf.d"
    mkdir -p "$AVAIL"
    export JAN_FONTCONFIG_AVAIL="$AVAIL" JAN_FONTCONFIG_CONF_D="$CONF_D"
    # Keep the real font cache untouched.
    fc-cache() { :; }
    source "$BATS_TEST_DIRNAME/../../usr/sbin/install-fontconfig"
}

@test "every repo fragment is linked, and a rerun changes nothing" {
    : > "$AVAIL/60-jan-subpixel.conf"
    : > "$AVAIL/60-jan-jetbrains-mono.conf"
    : > "$AVAIL/notes.txt"
    install_fontconfig
    [[ $(readlink "$CONF_D/60-jan-subpixel.conf") == "$AVAIL/60-jan-subpixel.conf" ]]
    [[ $(readlink "$CONF_D/60-jan-jetbrains-mono.conf") == "$AVAIL/60-jan-jetbrains-mono.conf" ]]
    # Only .conf fragments belong in conf.d.
    [[ ! -e "$CONF_D/notes.txt" ]]
    install_fontconfig
    [[ $(find "$CONF_D" -maxdepth 1 -type l | wc -l) == 2 ]]
}

@test "a stale link is repointed rather than left dangling" {
    : > "$AVAIL/60-jan-subpixel.conf"
    mkdir -p "$CONF_D"
    ln -sfn /nonexistent/old.conf "$CONF_D/60-jan-subpixel.conf"
    install_fontconfig
    [[ -e "$CONF_D/60-jan-subpixel.conf" ]]
    [[ $(readlink "$CONF_D/60-jan-subpixel.conf") == "$AVAIL/60-jan-subpixel.conf" ]]
}

@test "an empty or missing fragment directory is reported, not silently skipped" {
    install_fontconfig
    [[ ! -e "$CONF_D/60-jan-subpixel.conf" ]]
    rmdir "$AVAIL"
    run install_fontconfig
    [[ $status == 1 ]]
    [[ $output == *"missing $AVAIL"* ]]
}

@test "the subpixel fragment outranks a per-user rgba override" {
    command -v fc-match >/dev/null || skip "fontconfig tools not installed"
    local repo="$BATS_TEST_DIRNAME/../../usr/share/fontconfig/conf.avail"
    local root="$BATS_TEST_TMPDIR/fc"
    mkdir -p "$root/conf.d"
    # 56-user.conf pulls in the per-user fontconfig, where KDE's font KCM
    # writes rgba=none. Stand that in at its real position and check the
    # resolved value, rather than just comparing file names.
    cat > "$root/conf.d/56-user-sim.conf" <<'USER'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <match target="font">
    <edit mode="assign" name="rgba"><const>none</const></edit>
  </match>
</fontconfig>
USER
    cat > "$root/fonts.conf" <<'MAIN'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>/usr/share/fonts</dir>
  <include ignore_missing="yes">conf.d</include>
</fontconfig>
MAIN
    local rgba
    rgba=$(FONTCONFIG_PATH="$root" fc-match -v sans 2>/dev/null |
        sed -n 's/^[[:space:]]*rgba:[[:space:]]*\([0-9]*\).*/\1/p')
    [[ -n $rgba ]] || skip "no matchable font in this environment"
    # Without our fragment the per-user rule wins: 5 is FC_RGBA_NONE.
    [[ $rgba == 5 ]]
    cp "$repo/60-jan-subpixel.conf" "$root/conf.d/"
    rgba=$(FONTCONFIG_PATH="$root" fc-match -v sans 2>/dev/null |
        sed -n 's/^[[:space:]]*rgba:[[:space:]]*\([0-9]*\).*/\1/p')
    # 1 is FC_RGBA_RGB.
    [[ $rgba == 1 ]]
}
