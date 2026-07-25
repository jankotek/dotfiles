# Tests

All tests use [bats-core](https://github.com/bats-core/bats-core). Shared assertions are in `helpers.bash`.

## Launchers

```bash
test/test-host.sh              # runs basic/ + host/     (on the host)
test/test-vm.sh                # runs basic/ + vm/       (inside a VM)
test/test-vm-deploy.sh             # clone xub -> provision -> reboot -> test -> destroy
test/test-vm-deploy.sh --keep      # same, but keep VM for debugging
test/test-vm-xub26-deploy.sh       # clone xub26 -> setup/vm-xub26 -> test -> destroy
```

`test-vm-deploy.sh` can also be pointed at another base with `BASE_VM`,
`BASE_DISK`, `SETUP_SCRIPT`, and `VM_NAME_PREFIX`.

## Test directories

### basic/ — all systems

| File | What it checks |
|------|---------------|
| `cli.bats` | Common CLI tools: git, curl, mc, htop, fish, nano, ncdu, starship, iotop, powertop, pwgen, telnet, jdupes, just, bats, zim, JetBrains Mono font |
| `optjan.bats` | `/opt/jan` directory structure, key scripts exist in repo |
| `zswap.bats` | zswap enabled with zstd compressor in boot params and at runtime |

### host/ — Plasma/Wayland/openSUSE host only

| File | What it checks |
|------|---------------|
| `plasma.bats` | plasmashell, kwin_wayland, Wayland session active, not a VM, konsole, dolphin, virt-manager/remote-viewer GDK_BACKEND=x11 patches, no /home/* user auto-suspends on AC power (powerdevilrc AutoSuspendAction) |
| `greetd.bats` | greetd + tuigreet installed, per-tty configs (tty3-9), services enabled, getty masked, no other DM enabled/running |
| `packages.bats` | KDE apps (kdenlive, kdiff3, kfind, krename, krita, kstars, ksystemlog, ktorrent, kwrite, filelight, partitionmanager), virt tools (virt-manager, virt-install, virt-viewer, podman, lima), dev tools (go, maven, node, tsc, java, yq) |
| `strix-halo.bats` | AMD Strix Halo GPU params: amdgpu.gttsize, iommu=pt, amd_iommu=on, amdgpu.noretry=0, GTT >= 110GB, fixed VRAM <= 512MB. Skips on non-Strix Halo systems |

### vm/ — XFCE/X11/Xubuntu VM only

| File | What it checks |
|------|---------------|
| `dotfiles.bats` | Deployed dotfiles: .bashrc (EDITOR, VISUAL, starship), fish config, .profile (GTK_THEME), git config (name, email, defaultBranch), user-dirs (lowercase folders) |
| `xfce.bats` | xfce4-session, Xorg, autologin (xfce4-panel + xfdesktop running as jan), jan-vm-resize-display-loop running, terminator config (font, fish, titlebar), rofi, XFCE panel/xfwm4/xsettings XML, autostart entry, desktop shortcuts |
| `agents.bats` | Running inside VM, spice-vdagent installed + service enabled + process running as jan, spice-vdagentd running, qemu-guest-agent installed + enabled |
| `system.bats` | /opt/jan/usr symlinked into /usr/local, terminator/rofi/mousepad installed, home owned by jan with 0700, snapd/xfce4-screensaver/xfce4-terminal removed, snapd blocked from reinstall, tty11-root service enabled |

### utils/ — manual integration tests

Not triggered by any launcher. Run individually; tests that modify system state
must be run as root.

| File | What it checks |
|------|---------------|
| `update-opt.bats` | Downloads Herdr into a temporary `JAN_OPT`, verifies the binary and version tracking, then checks an idempotent re-run |
| `pod-security.bats` | Creates a temporary pod user via `jan-pod-setup`, verifies all security hardening layers (nologin shell, locked password, nogroup, 0700 home, sudo denied, cron denied, filesystem ACLs blocking /home /root /tmp /var/log /etc/ssh /var/spool, /var/pod not listable, podman configs, linger, cgroup delegation, sysctl port restriction), then deletes everything |

```bash
OPT_JAN="$PWD" bats test/utils/update-opt.bats
sudo bats test/utils/pod-security.bats
```
