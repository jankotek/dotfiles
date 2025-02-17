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

$DIR/install-dotfiles.sh dotfiles

cp /home/jan /home/jan-backup-$(date +%Y-%m-%d-%H%M) -R

rsync -r --delete "$DIR/home/" /home/jan
rsync -r "$DIR/home-root/" /root

chmod 0700 /root/ /home/jan
chown jan:users -R /home/jan
chown root:root -R /root
#chmod 0711 -R /home/jan/desk/* /home/jan/.config/autostart/*
#chmod 0755 /home/jan/.local/bin* /home/jan/.local/share/applications/* /usr/local/share/applications/* -R

/usr/local/sbin/jan-bootstrap dotfiles
