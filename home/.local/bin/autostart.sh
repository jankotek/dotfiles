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


terminator &

idea &
