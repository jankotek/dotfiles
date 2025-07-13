#!/bin/sh
xdg-open "$(find /home -type d -not -path '*/.*' | rofi -threads 0 -width 100 -dmenu -i -p "find:")"
