#!/bin/bash

inifile="/home/jan/.local/bin/autoini.sh"
if [ -f $inifile ]; then
    $inifile
    rm $inifile
fi

# disable caps lock
setxkbmap -option caps:ctrl_modifier

# give some time to desktop session to initialize
sleep 2


# this script is executed when XFCE starts
# use async suffix '&' for desktop programs !!!

# auto-resize display when spice window is resized
if systemd-detect-virt -q -v 2>/dev/null; then
    jan-vm-resize-display-loop &
fi

# KDE/Plasma on a VM: plasmashell can start before the virtio-gpu output is
# ready and bind to a nonexistent screen (-1), leaving the panel/taskbar
# invisible. If that race happened this session, restart plasmashell once so
# the panel binds to the now-present screen. No-op on XFCE.
if [ "$XDG_CURRENT_DESKTOP" = "KDE" ]; then
    (
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        # wait for plasmashell's D-Bus iface to come up
        for _ in $(seq 1 30); do
            qdbus6 org.kde.plasmashell /PlasmaShell \
                org.kde.PlasmaShell.evaluateScript 'print(1)' &>/dev/null && break
            sleep 1
        done
        sleep 2
        if journalctl --user -b _COMM=plasmashell 2>/dev/null \
             | grep -q "unexisting screen geometry -1"; then
            systemctl --user restart plasma-plasmashell.service
        fi
    ) &
fi

# XFCE-only desktop apps (harmless no-ops if not installed, e.g. on KDE)
terminator &

idea &
