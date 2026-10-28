"""Offline boot prerequisites shared by the supported cloud-image builders."""

BOOTSTRAP = '''#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if command -v zypper >/dev/null 2>&1; then
    zypper -n install --no-recommends zypper-aptitude systemd-networkd systemd-resolved
    if rpm -q spice-vdagent >/dev/null 2>&1; then zypper -n remove spice-vdagent; fi
else
    apt -y update
    apt -y --no-install-recommends install qemu-guest-agent openssh-server tmux rsync python3 systemd-resolved
    if dpkg-query -W -f='${db:Status-Status}' cloud-initramfs-growroot 2>/dev/null | grep -qx installed; then
        apt -y purge cloud-initramfs-growroot
    fi
fi
getent group 1000 >/dev/null || groupadd -g 1000 jan
old_user=$(getent passwd 1000 | cut -d: -f1) || old_user=
if [[ -n $old_user && $old_user != jan ]]; then
    usermod -l jan -d /home/jan -m -g 1000 "$old_user"
elif ! id jan >/dev/null 2>&1; then
    useradd -m -u 1000 -g 1000 -s /bin/bash jan
fi
usermod -g 1000 jan
passwd -l jan >/dev/null
passwd -l root >/dev/null
mkdir -p /opt/jan /etc/systemd/network /etc/ssh/sshd_config.d /etc/cloud/cloud.cfg.d
if ! grep -q '^opt-jan ' /etc/fstab; then
    printf 'opt-jan /opt/jan virtiofs ro,nofail,x-systemd.automount 0 0\\n' >> /etc/fstab
fi
cat > /etc/systemd/network/05-jan-wired.network <<'NETWORK'
[Match]
Type=ether
[Network]
DHCP=yes
IPv6AcceptRA=yes
LinkLocalAddressing=ipv6
NETWORK
systemctl disable networking.service wicked.service wicked-nanny.service 2>/dev/null || true
systemctl enable systemd-networkd.service systemd-resolved.service qemu-guest-agent.service serial-getty@ttyS0.service
touch /etc/cloud/cloud-init.disabled
systemctl mask cloud-init.service cloud-init-local.service cloud-init-main.service cloud-init-network.service cloud-config.service cloud-final.service cloud-init.target jeos-firstboot.service jeos-firstboot-snapshot.service
printf '%s\\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' 'PermitRootLogin no' > /etc/ssh/sshd_config.d/00-dotfiles.conf
# Run before vendor sshd -t, which otherwise fails when sealed host keys are absent.
cat > /etc/systemd/system/golden-hostkeys.service <<'KEYS'
[Unit]
Description=Generate missing SSH host keys
Before=ssh.service sshd.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/ssh-keygen -A
[Install]
WantedBy=multi-user.target
KEYS
if command -v zypper >/dev/null 2>&1; then ssh_unit=sshd; else ssh_unit=ssh; fi
mkdir -p "/etc/systemd/system/$ssh_unit.service.d"
cat > "/etc/systemd/system/$ssh_unit.service.d/10-golden-hostkeys.conf" <<'DEPENDENCY'
[Unit]
Requires=golden-hostkeys.service
After=golden-hostkeys.service
DEPENDENCY
systemctl disable ssh.socket 2>/dev/null || true
systemctl enable golden-hostkeys.service "$ssh_unit.service"
touch /etc/growroot-disabled
printf 'growpart:\\n  mode: off\\nresize_rootfs: false\\n' > /etc/cloud/cloud.cfg.d/99-golden-no-autogrow.cfg
if command -v zypper >/dev/null 2>&1; then
    mkdir -p /etc/dracut.conf.d
    printf 'omit_dracutmodules+=" kiwi-repart "\\n' > /etc/dracut.conf.d/90-golden-no-autogrow.conf
fi
if command -v dracut >/dev/null 2>&1; then
    dracut --force --regenerate-all
elif command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u -k all
else
    echo 'ERROR: no supported initramfs builder found' >&2
    exit 1
fi
# Vendor GRUB may select gfxterm, which can reboot before the kernel when the
# text-only domain has no video device. Keep both local and serial consoles.
if command -v update-grub >/dev/null 2>&1; then
    mkdir -p /etc/default/grub.d
    cat > /etc/default/grub.d/99-golden-console.cfg <<'GRUB'
GRUB_TERMINAL_INPUT="console serial"
GRUB_TERMINAL_OUTPUT="console serial"
GRUB_GFXPAYLOAD_LINUX=text
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
GRUB
    # virt-resize can move the BIOS boot partition (Ubuntu has a separate /boot).
    # Reinstall the BIOS stage so its sector references match the new disk.
    grub-install --target=i386-pc --recheck /dev/sda
    update-grub
fi
systemctl set-default multi-user.target
'''


SEAL = """#!/bin/bash
set -euo pipefail
# Executed offline after the last shutdown: no daemon can recreate identity.
rm -f /etc/ssh/ssh_host_* /etc/machine-id /var/lib/dbus/machine-id
touch /etc/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
rm -f /var/lib/systemd/random-seed /var/lib/NetworkManager/secret_key
rm -rf /var/lib/cloud /var/lib/systemd/network /var/lib/wicked
find /home /root -type d -name .ssh -prune -exec rm -rf '{}' +
rm -f /root/.bash_history /home/*/.bash_history
find /var/log /tmp /var/tmp -mindepth 1 -delete
rm -f /etc/systemd/system/golden-provision.service
rm -rf /var/cache/zypp /var/cache/apt/archives /var/lib/apt/lists/*
mkdir -p /var/cache/zypp /var/cache/apt/archives/partial
"""
