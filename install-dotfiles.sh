#!/bin/bash

if [ "$1" != "dotfiles" ]; then
  echo "Installs this dotfiles folder into local system. "
  echo "Warning, it overwrites and deletes!!"
  echo "The first parameter must be 'dotfiles'."

  exit 1
fi


# Print the last command that failed
set -e
trap 'echo "Error occurred in: $BASH_COMMAND"; exit 1' ERR


# basedir
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$DIR/xz" ]]; then
  echo "Error: dir does not exist, something wrong."
  exit 1
fi

#
# copy to /usr/local
#

cp -rf "$DIR/local" /usr/
chown root:root /usr/local/  -R

chmod 0700 /usr/local/sbin/  -R
chmod 0755 /usr/local/bin/  -R

#
#  local XZ
#
JANXZ="$DIR/xz"
unxz -c $JANXZ/ublite.ttf.xz > /usr/share/fonts/ublite.ttf

rm -rf /usr/share/themes/Sweet-Dark-Compact-Outline-XFWM
tar -C /usr/share/themes/ -xJf "$JANXZ/Sweet-Dark-Compact-Outline-XFWM.tar.xz"

rm -rf /usr/share/themes/Totem
tar -C /usr/share/themes/ -xJf "$JANXZ/Totem.tar.xz"

rm -rf /usr/share/themes/Sweet-Dark-v40
tar -C /usr/share/themes/ -xJf "$JANXZ/Sweet-Dark-v40.tar.xz"

rm -rf /usr/share/icons/Sweet-Purple
tar -C /usr/share/icons/  -xJf "$JANXZ/Sweet-Purple.tar.xz"

rm -rf /usr/share/icons/DMZhaloG
tar -C /usr/share/icons/  -xJf "$JANXZ/DMZhaloG.tar.xz"

rm -rf /usr/share/icons/RareAeroW7
tar -C /usr/share/icons/  -xJf "$JANXZ/RareAeroW7.tar.xz"

mkdir -p /usr/share/aurorae/themes/
rm -rf /usr/share/aurorae/themes/Sweet-Dark
tar -C /usr/share/aurorae/themes/  -xJf "$JANXZ/Sweet-Dark-kwin.tar.xz"
