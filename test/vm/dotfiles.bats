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

@test "profile sets GTK_THEME" {
    assert_file "$JAN_HOME/.profile"
    assert_file_contains "$JAN_HOME/.profile" 'GTK_THEME=Sweet-Dark-v40'
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
    assert_file_contains "$JAN_HOME/.config/user-dirs.dirs" 'XDG_DOCUMENTS_DIR="\$HOME/doc"'
}