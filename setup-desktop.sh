#!/bin/bash

if [ $(id -u) -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi



rm /home/jan/* /root* -r -f

rsync -r home/ /home/jan
rsync -r homex/ /home/jan
rsync -r root/ /root
rsync -r usrlocal/ /usr/local

mkdir /home/jan/vbox
mkdir /home/jan/media


chown jan:users /home/jan/ -R
chown root:root /root/  -R
chmod 0700 /root/ /home/jan
chmod 0711 -R /home/jan/desk/* /home/jan/.config/autostart/*
chown root:root /usr/local/ /etc/systemd/  -R
chmod 0755 /usr/local/bin/* /home/jan/.local/bin* /home/jan/.local/share/applications/* /usr/local/share/applications/* -R
chmod 0700 /usr/local/sbin/  -R

/usr/local/sbin/setup-tty12-menu

/usr/local/sbin/setup-ipv6-disable

REM="wicked pipewire wireplumber  pipewire-tools"
zypper remove -y  "*wireplumber*" $REM
zypper addlock  $REM

setup-tools-cli
setup-tools-gui


zypper install -y  audacious  geeqie  xfce4-screenshooter xfce4-screensaver  file-roller unrar \
            xfce4-pulseaudio-plugin xfce4-power-manager thunar-plugin-archive thunar-plugin-vcs syncthing

usermod -aG audio jan


untar-all-in-dir /home/jan/.icons/
untar-all-in-dir /home/jan/.themes/
rm /home/jan/.icons/*.tar.xz /home/jan/.themes/*.tar.xz


chown jan:users /home/jan -R

zypper install -y virtualbox

usermod -a -G vboxusers jan
