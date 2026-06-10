#!/usr/bin/env bats
# Verify XFCE + X11 desktop configuration in VM

load ../helpers

@test "xfce4-session is installed" {
    assert_command xfce4-session
}

@test "Xorg is installed" {
    assert_command Xorg
}

@test "autologin: xfce4-panel is running as jan" {
    pgrep -u jan xfce4-panel
}

@test "autologin: xfdesktop is running as jan" {
    pgrep -u jan xfdesktop
}

@test "jan-vm-resize-display-loop is running" {
    pgrep -f jan-vm-resize-display-loop
}

@test "xfce4 helpers.rc sets terminal to terminator" {
    assert_file "$JAN_HOME/.config/xfce4/helpers.rc"
    assert_file_contains "$JAN_HOME/.config/xfce4/helpers.rc" 'TerminalEmulator=terminator'
}

@test "terminator config exists" {
    assert_file "$JAN_HOME/.config/terminator/config"
}

@test "terminator uses JetBrains Mono font" {
    assert_file_contains "$JAN_HOME/.config/terminator/config" 'JetBrains Mono'
}

@test "terminator uses fish shell" {
    assert_file_contains "$JAN_HOME/.config/terminator/config" 'custom_command = /usr/bin/fish'
}

@test "terminator hides titlebar" {
    assert_file_contains "$JAN_HOME/.config/terminator/config" 'show_titlebar = False'
}

@test "rofi config exists" {
    assert_file "$JAN_HOME/.config/rofi/config.rasi"
    assert_file_contains "$JAN_HOME/.config/rofi/config.rasi" 'DarkBlue.rasi'
}

@test "xfce4 panel config exists" {
    assert_file "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
}

@test "xfce4 panel plugins are installed" {
    dpkg -s xfce4-systemload-plugin
    assert_file /usr/lib/x86_64-linux-gnu/xfce4/panel/plugins/libsystemload.so
    assert_file_contains "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" 'value="systemload"'
}

@test "xfwm4 config exists" {
    assert_file "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
}

@test "xsettings config exists" {
    assert_file "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
}

@test "display power management is disabled" {
    assert_file "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml"
    assert_file_contains "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" 'name="dpms-enabled" type="bool" value="false"'
    assert_file_contains "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" 'name="blank-on-ac" type="int" value="0"'
    assert_file_contains "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" 'name="inactivity-on-ac" type="uint" value="14"'
    assert_file_contains "$JAN_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" 'name="inactivity-sleep-mode-on-ac" type="int" value="0"'
    assert_file_contains "$JAN_HOME/.xsessionrc" 'xset s off -dpms s noblank'
    assert_file_contains "$JAN_HOME/.xsessionrc" '/xfce4-power-manager/dpms-on-ac-off'
}

@test "autostart desktop entry exists" {
    assert_file "$JAN_HOME/.config/autostart/autostart.desktop"
    assert_file "$JAN_HOME/.config/autostart/xfce4-panel.desktop"
    assert_file "$JAN_HOME/.config/autostart/xfdesktop.desktop"
    assert_file "$JAN_HOME/.config/autostart/user-dirs-update-gtk.desktop"
}

@test "desktop shortcuts exist" {
    assert_file "$JAN_HOME/desk/htop.desktop"
    assert_file "$JAN_HOME/desk/mc.desktop"
    assert_file "$JAN_HOME/desk/taskmanager.desktop"
}
