#!/bin/bash

BASE=$1
PORT=$((RANDOM % 55001 + 10000))
VM=test-${BASE}-${PORT}
PWFILE=/home/jan/vbox/meta/$BASE/pw-jan.txt

# Check if the port is open, we may ssh to machine that already exists
nc -z localhost $PORT
if [ $? -eq 0 ]; then
    echo "Port $PORT is open"
    exit 1
fi

VBoxManage clonevm $BASE --snapshot=fresh  --options=Link    --name="$VM"  --register
VBoxManage modifyvm "$VM" --natpf1 "guestssh,tcp,,$PORT,,22"

#VBoxManage sharedfolder add  "$VM" --name=shared-mnt --hostpath="$HOME/vbox/shared-mnt" --readonly --automount --auto-mount-point=/mnt/shared

VBoxManage startvm $VM


ssh2() {
    sshpass -f "$PWFILE" ssh -p "$PORT" -o StrictHostKeyChecking=no  jan@localhost $@
}



vboxrun() {
  VBoxManage guestcontrol "$VM" --username=root --password="$PW"  run  --wait-stdout --wait-stderr -- $@
}

sleep 10

METADIR="/home/jan/vbox/meta/$VM"
mkdir "$METADIR"
echo $PORT > "$METADIR/port.txt"
echo $PW > "$METADIR/pw-jan.txt"
echo $PW > "$METADIR/pw-root.txt"


ssh2 echo "SSH HELLO"
ssh2 "echo '$(cat $PWFILE)' | sudo -S sh -c 'hostnamectl hostname $VM'"

ssh2 mkdir /tmp/upgrade3
sshpass -f "$PWFILE" scp -P "$PORT" -o StrictHostKeyChecking=no -r "$(pwd)" jan@localhost:/tmp/upgrade3
ssh2 mv /tmp/upgrade3/* /tmp/upgrade3/dot

ssh2 chmod +x  /tmp/upgrade3/dot/setup-vm.sh
ssh2 "echo '$(cat $PWFILE)' | sudo -S sh -c 'cd /tmp/upgrade3/dot  && ./setup-vm.sh'"

sleep 1
VBoxManage controlvm $VM acpipowerbutton
sleep 20
VBoxManage startvm $VM


exit 1
vboxrun  /usr/bin/systemctl stop display-manager

vboxrun  /usr/bin/hostnamectl hostname "$VM"

vboxrun  /usr/bin/systemctl start ssh
vboxrun  /usr/bin/systemctl enable ssh

vboxrun  /bin/rm /home/jan/ /root/ -r -f
vboxrun  /usr/bin/mkdir /mnt/shared /home/jan /root

vboxgs copyto --recursive "$PWD/home/"  --target-directory=/home/jan
vboxgs copyto --recursive "$PWD/homex/"  --target-directory=/home/jan

vboxgs copyto --recursive "$PWD/root/"  --target-directory=/root
vboxgs copyto --recursive "$PWD/usrlocal/"  --target-directory=/usr/local


vboxrun  /usr/bin/chmod 0755 /mnt/shared
vboxrun  /usr/bin/mkdir /home/jan/.ssh
vboxrun  /usr/bin/mkdir /root/.ssh
vboxgs copyto $HOME/.ssh/id_rsa.pub  /home/jan/.ssh/authorized_keys
vboxgs copyto $HOME/.ssh/id_rsa.pub  /root/.ssh/authorized_keys
vboxrun  /bin/chown jan:users /home/jan/ -R
vboxrun  /bin/chown root:root /root/  -R
vboxrun  /bin/chmod 0700 /root/ /home/jan
vboxrun  /bin/chmod 0711 -R /home/jan/desk /home/jan/.config/autostart
vboxrun  /bin/chown root:root /usr/local/ /etc/xdg/ /etc/systemd/  -R
vboxrun  /bin/chmod 0755 /usr/local/bin/ /home/jan/.local/bin /usr/local/share/applications/ -R
vboxrun  /bin/chmod 0700 /usr/local/sbin/  -R


vboxrun /usr/bin/systemctl disable accounts-daemon
vboxrun /usr/bin/systemctl disable upower
vboxrun /usr/bin/systemctl disable auditd
vboxrun /usr/bin/systemctl disable chronyd
vboxrun /usr/bin/systemctl disable nscd
vboxrun /usr/bin/systemctl disable lvm2-monitor

vboxrun /usr/local/sbin/setup-sshd-cert-regenerate
vboxrun /usr/local/sbin/setup-ipv6-disable

vboxrun /usr/local/sbin/setup-tty12-menu
vboxrun /usr/local/sbin/setup-tty11-root
vboxrun /usr/local/sbin/setup-vm-cleanup

vboxrun /usr/local/sbin/setup-vm-xfce
#vboxrun /usr/local/sbin/setup-brave
#vboxrun /usr/local/sbin/setup-upgrade

vboxrun /usr/sbin/reboot

sleep 10

thunar ssh://jan@localhost:$PORT/home/jan/
