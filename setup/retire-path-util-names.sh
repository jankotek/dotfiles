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
    host-optupdate
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
    install-podman-clean-sockets
    install-vivaldi
    setup-kernel-zbook
    vm-cleanup
)

for name in "${retired_bin[@]}"; do
    rm -f "/usr/local/bin/$name"
done
for name in "${retired_sbin[@]}"; do
    rm -f "/usr/local/sbin/$name"
done

# install-podman-clean-sockets wrote this unit. Its cleanup ran a root
# rm -rf under /var/pods (and the last version could expand to /*).
clean_unit=/etc/systemd/system/podman-clean-sockets.service
if [[ -f $clean_unit ]] && grep -q 'Cleanup stale Podman sockets in /var/pods' "$clean_unit"; then
    systemctl disable --now podman-clean-sockets.service 2>/dev/null || true
    rm -f "$clean_unit"
    systemctl daemon-reload
    systemctl reset-failed podman-clean-sockets.service 2>/dev/null || true
fi

# Starship was once vendored as usr/bin/starship; the distro package now
# provides /usr/bin/starship. Drop only the dangling repo symlink, never a
# locally installed binary.
if [[ -L /usr/local/bin/starship && ! -e /usr/local/bin/starship ]]; then
    rm -f /usr/local/bin/starship
fi
