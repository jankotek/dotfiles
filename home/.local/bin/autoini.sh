#!/bin/sh

inifile2="/home/jan/.config/dconf-import.ini"
if [ -f $inifile2 ]; then
    dconf load / < $inifile2
    rm $inifile2
fi



xfconf-query -c xfce4-session -np '/shutdown/ShowSuspend' -t 'bool' -s 'false'
xfconf-query -c xfce4-session -np '/shutdown/ShowHibernate' -t 'bool' -s 'false'
xfconf-query -c xfce4-session -np '/shutdown/ShowHybridSleep' -t 'bool' -s 'false'


xfconf-query -c xfce4-session -np '/backdrop/screen0/xinerama-stretch' -t 'bool' -s 'true'

xdg-settings set default-web-browser browser-helper.desktop


rm -rf /home/jan/Desktop/