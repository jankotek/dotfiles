#!/bin/bash

CMD=$(rofi -threads 0 -width 100 -dmenu -i -p "exec:")
terminator -T "$CMD" -x "$CMD;fish"

