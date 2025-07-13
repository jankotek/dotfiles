#!/bin/sh
xdg-open "$(find /home/jan  | rofi -threads 0 -width 100 -dmenu -i -p "find:")"
