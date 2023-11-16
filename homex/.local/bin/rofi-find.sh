#!/bin/sh
xdg-open "$(find /home -not -path '*/.*' | rofi -threads 0 -width 100 -dmenu -i -p "find:")"
