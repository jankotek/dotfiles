#!/usr/bin/env bats
# ci: fixture

load ../helpers

setup() {
    command -v kwriteconfig6 &>/dev/null || skip "kwriteconfig6 not installed"
    export XDG_DIR="$BATS_TEST_TMPDIR/xdg"
    source "$BATS_TEST_DIRNAME/../../usr/sbin/setup-plasma-defaults"
}

@test "writes the font rendering keys" {
    setup_plasma_defaults
    local file="$XDG_DIR/kdeglobals"
    assert_file "$file"
    assert_file_contains "$file" '^XftSubPixel=rgb$'
    assert_file_contains "$file" '^XftHintStyle=hintslight$'
}

@test "merges into an existing kdeglobals without discarding other groups" {
    mkdir -p "$XDG_DIR"
    printf '[General]\nWidgetStyle=Oxygen\n\n[Locale]\nCountry=cz\n' > "$XDG_DIR/kdeglobals"
    setup_plasma_defaults
    assert_file_contains "$XDG_DIR/kdeglobals" '^WidgetStyle=Oxygen$'
    assert_file_contains "$XDG_DIR/kdeglobals" '^Country=cz$'
    assert_file_contains "$XDG_DIR/kdeglobals" '^XftSubPixel=rgb$'
}

@test "a rerun changes nothing" {
    setup_plasma_defaults
    cp "$XDG_DIR/kdeglobals" "$BATS_TEST_TMPDIR/expected"
    setup_plasma_defaults
    cmp "$XDG_DIR/kdeglobals" "$BATS_TEST_TMPDIR/expected"
}

@test "rendering keys survive the Sweet-dark kdeglobals sitting above them" {
    # host-weed-kde points /usr/local/etc/xdg/kdeglobals at the colour scheme,
    # which defines no Xft keys. They must fall through to /etc/xdg while
    # ColorScheme still comes from the higher-priority file.
    setup_plasma_defaults
    local high="$BATS_TEST_TMPDIR/high"
    mkdir -p "$high" "$BATS_TEST_TMPDIR/home"
    cp "$BATS_TEST_DIRNAME/../../usr/share/color-schemes/Sweet-dark.colors" "$high/kdeglobals"
    run bash -c 'grep -c XftSubPixel "$1" || true' _ "$high/kdeglobals"
    [[ $output == 0 ]]
    local read_key=(env "XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home"
        "XDG_CONFIG_DIRS=$high:$XDG_DIR" kreadconfig6 --file kdeglobals)
    # Every rendering key, not just one: Qt reads these over fontconfig.
    [[ $("${read_key[@]}" --group General --key XftSubPixel) == rgb ]]
    [[ $("${read_key[@]}" --group General --key XftHintStyle) == hintslight ]]
    [[ $("${read_key[@]}" --group General --key XftHinting) == true ]]
    [[ $("${read_key[@]}" --group General --key XftAntialias) == true ]]
    [[ $("${read_key[@]}" --group General --key ColorScheme) == Sweet-dark ]]
    # The whole point of the helper: without this key Plasma falls back to
    # Breeze, loads the KDE template id and the panel reverts to the stock
    # bottom bar. Deleting it from the helper must fail a test.
    [[ $("${read_key[@]}" --group KDE --key LookAndFeelPackage) == org.openSUSE.desktop ]]
}

@test "a user's own choice still outranks these defaults" {
    setup_plasma_defaults
    local home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$home"
    env XDG_CONFIG_HOME="$home" kwriteconfig6 --file kdeglobals \
        --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop
    env XDG_CONFIG_HOME="$home" kwriteconfig6 --file kdeglobals \
        --group General --key XftSubPixel bgr
    local read_key=(env "XDG_CONFIG_HOME=$home" "XDG_CONFIG_DIRS=$XDG_DIR"
        kreadconfig6 --file kdeglobals)
    [[ $("${read_key[@]}" --group KDE --key LookAndFeelPackage) == org.kde.breezedark.desktop ]]
    [[ $("${read_key[@]}" --group General --key XftSubPixel) == bgr ]]
}
