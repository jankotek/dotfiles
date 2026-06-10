#!/bin/bash

inifile="/home/jan/.local/bin/autoini.sh"
if [ -f $inifile ]; then
    $inifile
    rm $inifile
fi

# disable caps lock
setxkbmap -option caps:ctrl_modifier
xset s off -dpms s noblank

# give some time to desktop session to initialize
sleep 2


# this script is executed when XFCE starts
# use async suffix '&' for desktop programs !!!

# auto-resize display when spice window is resized
if systemd-detect-virt -q -v 2>/dev/null; then
    jan-vm-resize-display-loop &
fi

# KDE/Plasma on a VM: plasmashell often starts before the virtio-gpu output
# is sized (the SPICE display only gets a real geometry once a viewer attaches)
# and strands the panel/taskbar on a nonexistent screen (-1). Self-heal: watch
# for ~5 min after login and, whenever a real screen is present but a panel is
# orphaned on screen -1, restart plasmashell once so it rebinds. No-op on XFCE.
if [ "$XDG_CURRENT_DESKTOP" = "KDE" ]; then
    (
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        ES=(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript)
        tries=0
        for _ in $(seq 1 60); do
            w=$("${ES[@]}" 'print(screenGeometry(0).width)' 2>/dev/null)
            orphan=$("${ES[@]}" 'var n=0,p=panels();for(var i=0;i<p.length;i++)if(p[i].screen<0)n++;print(n)' 2>/dev/null)
            if [[ "$w" =~ ^[0-9]+$ ]] && [ "$w" -gt 0 ] \
               && [[ "$orphan" =~ ^[0-9]+$ ]] && [ "$orphan" -gt 0 ] \
               && [ "$tries" -lt 2 ]; then
                systemctl --user restart plasma-plasmashell.service
                tries=$((tries + 1))
                sleep 10
            fi
            sleep 5
        done
    ) &
fi

# XFCE-only desktop apps (harmless no-ops if not installed, e.g. on KDE)
if command -v terminator >/dev/null 2>&1; then
    terminator &
fi

if command -v idea >/dev/null 2>&1; then
    idea &
fi
