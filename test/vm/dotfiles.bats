#!/usr/bin/env bats
# Verify user dotfiles are deployed correctly (common to host and VM)

load ../helpers

@test "bashrc exists" {
    assert_file "$JAN_HOME/.bashrc"
}

@test "bashrc sets EDITOR to mcedit" {
    assert_file_contains "$JAN_HOME/.bashrc" 'EDITOR="mcedit"'
}

@test "bashrc sets VISUAL to mousepad" {
    assert_file_contains "$JAN_HOME/.bashrc" 'VISUAL="mousepad"'
}

@test "bashrc sources starship" {
    assert_file_contains "$JAN_HOME/.bashrc" 'starship init bash'
}

@test "fish config exists" {
    assert_file "$JAN_HOME/.config/fish/config.fish"
}

@test "fish config sets EDITOR to mcedit" {
    assert_file_contains "$JAN_HOME/.config/fish/config.fish" 'EDITOR "mcedit"'
}

@test "fish config sources starship" {
    assert_file_contains "$JAN_HOME/.config/fish/config.fish" 'starship init fish'
}

@test "user helper scripts retain executable modes" {
    assert_executable "$JAN_HOME/.local/bin/autostart.sh"
    # autostart.sh intentionally removes the deployed autoini.sh after its
    # one-time XFCE initialization, so check its canonical source instead.
    assert_executable "$OPT_JAN/skel/home/.local/bin/autoini.sh"
}

@test "profile does not force a GTK theme in Plasma" {
    assert_file "$JAN_HOME/.profile"
    if grep -q '^[[:space:]]*export GTK_THEME=' "$JAN_HOME/.profile"; then
        return 1
    fi
}

@test "XFCE selects the intended GTK theme through xsettings" {
    assert_file_contains \
        "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" \
        'name="ThemeName" type="string" value="Sweet-Dark-v40"'
}

@test "git config has correct user name" {
    assert_file "$JAN_HOME/.config/git/config"
    assert_file_contains "$JAN_HOME/.config/git/config" 'name = Jan Kotek'
}

@test "git config has correct email" {
    assert_file_contains "$JAN_HOME/.config/git/config" 'email = jan@kotek.net'
}

@test "git default branch is main" {
    assert_file_contains "$JAN_HOME/.config/git/config" 'defaultBranch = main'
}

@test "user-dirs uses lowercase folders" {
    assert_file "$JAN_HOME/.config/user-dirs.dirs"
    assert_file_contains "$JAN_HOME/.config/user-dirs.dirs" 'XDG_DESKTOP_DIR="\$HOME/desk"'
    assert_file_contains "$JAN_HOME/.config/user-dirs.dirs" 'XDG_DOWNLOAD_DIR="\$HOME/down"'
    assert_file_contains "$JAN_HOME/.config/user-dirs.dirs" 'XDG_TEMPLATES_DIR="\$HOME/doc/templates"'
    assert_file_contains "$JAN_HOME/.config/user-dirs.dirs" 'XDG_PUBLICSHARE_DIR="\$HOME/media/share"'
    assert_file_contains "$JAN_HOME/.config/user-dirs.dirs" 'XDG_DOCUMENTS_DIR="\$HOME/doc"'
    assert_file_contains "$JAN_HOME/.config/user-dirs.dirs" 'XDG_MUSIC_DIR="\$HOME/media/music"'
    assert_file_contains "$JAN_HOME/.config/user-dirs.dirs" 'XDG_PICTURES_DIR="\$HOME/media/pic"'
    assert_file_contains "$JAN_HOME/.config/user-dirs.dirs" 'XDG_VIDEOS_DIR="\$HOME/media/video"'
    [[ ! -e "$JAN_HOME/Documents" ]]
    [[ ! -e "$JAN_HOME/Downloads" ]]
    [[ ! -e "$JAN_HOME/Music" ]]
    [[ ! -e "$JAN_HOME/Pictures" ]]
    [[ ! -e "$JAN_HOME/Public" ]]
    [[ ! -e "$JAN_HOME/Templates" ]]
    [[ ! -e "$JAN_HOME/Videos" ]]
}
