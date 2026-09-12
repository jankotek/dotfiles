#!/bin/bash
# Remove retired PATH util names. `cp -s` into /usr/local never deletes
# the previous basename, so old checkouts leave dangling symlinks.
set -euo pipefail

retired_bin=(
    jan-clean-check
    jan-doctor
    jan-dotfiles-diff
    jan-download
    jan-greetd-session
    jan-plasma-session
    jan-start-xfce
    jan-vm-reset
    jan-vm-resize-display
    jan-vm-resize-display-loop
    jan-vm-smoke
    setup-pkg-largest
    simple-file-replace
    vm-start-and-wait
)

retired_sbin=(
    create-cleanup-service.sh
    jan-console-font
    jan-console-font-apply
    jan-console-framebuffer
    jan-create-lab-users
    jan-create-user
    jan-fix-virtman-scaling
    jan-host-monitors-fix-amdgpu
    jan-host-monitors-fix-edid
    jan-host-monitors-fix-groups
    jan-host-monitors-fix-kwin
    jan-install-brave
    jan-install-brave-origin
    jan-install-chrome
    jan-install-vivaldi
    jan-opensuse-weed-codecs
    jan-pod-destroy
    jan-pod-manage
    jan-pod-setup
    jan-qga-guard
    jan-randomize-user-passwords
    jan-scramble-user-password
    jan-setup-agetty
    jan-setup-greetd
    jan-setup-kernel-tweaks
    jan-setup-kernel-zbook
    jan-setup-pkg-safety
    jan-setup-strix-halo
    jan-setup-vm-networkd
    jan-sshd-cert-regenerate
    jan-sshd-disable-password-login
    jan-sshd-enable-root-login
    jan-systemd-tmp-clean
    jan-systemd-tty11-root
    jan-systemd-tty12-menu
    jan-systemd-vm-cleanup
    jan-ubuntu-remove-older-kernel
    jan-update-opt
    jan-upgrade
    install-brave-origin
    install-vivaldi
    vm-cleanup
)

for name in "${retired_bin[@]}"; do
    rm -f "/usr/local/bin/$name"
done
for name in "${retired_sbin[@]}"; do
    rm -f "/usr/local/sbin/$name"
done
