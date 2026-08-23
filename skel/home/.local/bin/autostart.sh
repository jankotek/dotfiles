#!/bin/bash

# XFCE's one-time initialization is intentionally separate from the generic
# applications below. Plasma also runs this script, but must not receive
# xfconf, XRandR, or X11 keyboard settings in its Wayland session.
if [[ ${XDG_CURRENT_DESKTOP:-} == *XFCE* ]]; then
    inifile="$HOME/.local/bin/autoini.sh"
    if [[ -x $inifile ]]; then
        "$inifile"
        rm -f -- "$inifile"
    fi

    if [[ ${XDG_SESSION_TYPE:-x11} == x11 ]]; then
        # Disable Caps Lock and display blanking in the disposable VM desktop.
        setxkbmap -option caps:ctrl_modifier 2>/dev/null || true
        xset s off -dpms s noblank 2>/dev/null || true
    fi
fi

# give some time to desktop session to initialize
sleep 2


# This script is executed by both Plasma and XFCE.
# use async suffix '&' for desktop programs !!!

# Ordinary per-user desktop applications.
if command -v terminator >/dev/null 2>&1; then
    terminator &
fi

if command -v idea >/dev/null 2>&1; then
    idea &
fi
