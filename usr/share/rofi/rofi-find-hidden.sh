#!/bin/sh
sel=$(find "$HOME" | rofi -threads 0 -width 100 -dmenu -i -p "find:")
[ -n "$sel" ] && xdg-open "$sel"
