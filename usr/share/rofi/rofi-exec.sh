#!/bin/bash

CMD=$(rofi -threads 0 -width 100 -dmenu -i -p "exec:")
[ -n "$CMD" ] || exit 0
terminator -T "$CMD" -x "$CMD;fish"

