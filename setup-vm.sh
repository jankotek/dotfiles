#!/bin/bash

if [ $(id -u) -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

CLITOOLS="rsync nano tar curl wget"
apt-get install -y $CLITOOLS
zypper install -y $CLITOOLS
dnf install -y $CLITOOLS


# Ubuntu cleanup

apt-get purge -y unattended-upgrades snapd packagekit vim emacs joe
apt-mark hold snapd
apt-get autoremove -y
systemctl stop unattended-upgrades

rm /home/jan/* /root* -r -f

rsync -r home/ /home/jan
rsync -r homex/ /home/jan
rsync -r root/ /root
rsync -r usrlocal/ /usr/local

chown jan:users /home/jan/ -R
chown root:root /root/  -R
chmod 0700 /root/ /home/jan
chmod 0711 -R /home/jan/desk/* /home/jan/.config/autostart/*
chown root:root /usr/local/ /etc/systemd/  -R
chmod 0755 /usr/local/bin/* /home/jan/.local/bin* /home/jan/.local/share/applications/* /usr/local/share/applications/* -R
chmod 0700 /usr/local/sbin/  -R

/usr/local/sbin/setup-tty11-root
/usr/local/sbin/setup-tty12-menu
/usr/local/sbin/setup-ipv6-disable
#TODO /usr/local/sbin/setup-sshd-cert-regenerate
/usr/local/sbin/setup-vm-cleanup


# opensuse xf86-video-amdgpu
apt-mark hold xserver-xorg-video-amdgpu xserver-xorg-video-ati  xserver-xorg-video-intel xserver-xorg-video-nouveau xserver-xorg-video-qxl xserver-xorg-video-radeon

apt-mark hold tumbler pulseaudio pipewire xfce4-screensaver colord xiccd xscreensaver light-locker yelp

SUSEREM="tumbler pulseaudio pipewire pipewire-modules
         xfce4-screensaver colord xiccd xscreensaver light-locker yelp
            patterns-xfce-xfce_office package-update-indicator opensuse-welcome
            vim emacs joe postfix
            patterns-fonts-fonts    patterns-base-documentation patterns-base-sw_management patterns-yast-yast2_basis
            kernel-firmware kernel-firmware-all kernel-default-optional
            gnome-online-accounts gstreamer-plugins-bad gstreamer-plugins-ugly
            wallpaper-branding-openSUSE"
zypper remove -y $SUSEREM
zypper addlock $SUSEREM



# fedora cleanup
dnf remove -y linux-firmware
echo "
exclude=vim emacs joe pipewire lightdm-gtk pipewire tracker    linux-firmware
" >> /etc/dnf/dnf.conf


PKG="lightdm   xfce4-session   xfce4-panel xfwm4
       thunar  xfce4-appfinder  mousepad       baobab rofi  gitg tig meld
         xfce4-fsguard-plugin xfce4-systemload-plugin  xfce4-taskmanager
          terminator rofi
       mc htop git-core  fish iftop iotop w3m sshpass ncdu
          "


apt-get install  -y "$PKG"  \
  xserver-xorg-video-vmware xserver-xorg virtualbox-guest-x11 \
  virtualbox-guest-utils x11-utils xfdesktop4 fonts-firacode xarchiver \
  lightdm-autologin-greeter
dnf install -y @base-x $PKG xfdesktop  fira-code-fonts \
   virtualbox-guest-additions xorg-x11-drv-vmware default-fonts-core-emoji \
   xfce4-settings xarchiver \
   lightdm-autologin-greeter

zypper install -y $PKG xorg-x11-server fira-code-fonts  \
    virtualbox-guest-tools libgthread-2_0-0 xkill thunar-plugin-archive \
    sysvinit-tools

echo "[Seat:*]
autologin-user=jan
autologin-session=xfce
">/etc/lightdm/lightdm.conf.d/lightdm-autologin-greeter.conf

# used by opensuse leap
echo "
DISPLAYMANAGER_AUTOLOGIN=jan
">/etc/sysconfig/displaymanager

systemctl enable lightdm
systemctl enable display-manager
systemctl set-default graphical.target


/usr/local/bin/untar-all-in-dir /home/jan/.icons/
/usr/local/bin/untar-all-in-dir /home/jan/.themes/
rm /home/jan/.icons/*.tar.xz /home/jan/.themes/*.tar.xz
find /home/jan/.icons -name 'chrome*' -type f -delete
find /home/jan/.icons -name 'brave*' -type f -delete
find /home/jan/.icons -name 'chromium*' -type f -delete

usermod -a -G users jan

chown jan:users /home/jan -R
