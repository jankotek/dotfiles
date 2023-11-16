#!/bin/sh

konsole --noclose -e "$(rofi -threads 0 -width 100 -dmenu -i -p "exec:")"

