# opt-jan

Personal dotfiles and system provisioning repo. Checked out at `/opt/jan` on target systems.

## Two deployment modes

1. **Fresh install** — clone repo to `/opt/jan`, run a setup script (e.g. `setup/vm-xub24`)
2. **VM with host mount** — host's `/opt` is mounted into the guest; tools are already available

## Directory layout

| Path | Purpose | Deployment |
|------|---------|------------|
| `home/` | User dotfiles for `jan` | `rsync --delete` to `/home/jan` |
| `home-root/` | Root dotfiles | `rsync --delete` to `/root` |
| `usr/bin/` | User utilities | Symlinked into `/usr/local/bin` |
| `usr/sbin/` | Admin scripts (run as root) | Symlinked into `/usr/local/sbin` |
| `usr/share/` | Fonts, icons, themes, cursors | Symlinked into `/usr/local/share` |
| `dist/` | Bundled theme assets (xfwm, cursors) | Referenced by themes |
| `setup/` | Per-machine provisioning scripts | Run once on fresh install |

## Key conventions

- `usr/` is symlinked into `/usr/local` (not copied) — file paths must work as symlinks
- `home/` is rsynced with `--delete` — every file here replaces what's on target
- Scripts in `usr/sbin/` are prefixed `jan-` for namespacing (e.g. `jan-upgrade`, `jan-install-chrome`)
- `jan-update-opt` downloads portable tools into `/opt/` with `.version` file tracking
- `jan-upgrade` is distro-agnostic: handles zypper (openSUSE), dnf (Fedora), apt (Ubuntu)
- Setup scripts must check `systemd-detect-virt` before doing VM-specific operations
- Shell configs exist for both bash (`.bashrc`) and fish (`config.fish`) — keep them in sync

## User environment

- **Desktop**: XFCE, Sweet-Dark theme, JetBrains Mono font
- **Terminal**: Terminator, Starship prompt
- **Shells**: Bash + Fish (parallel configs)
- **Editors**: mcedit (terminal), mousepad (GUI)
- **Dev tools**: IntelliJ IDEA, Corretto JDKs, Gradle, Maven, Kubernetes tooling

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core). Three test scenarios, two launchers, one automated deploy script.

### Scenarios

| Directory | Runs on | What it verifies |
|-----------|---------|-----------------|
| `test/basic/` | everywhere | `/opt/jan` structure, CLI tools (fish, htop, ncdu, yq, java, maven, go, ...), JetBrains Mono font |
| `test/host/` | host only | Plasma/Wayland, KDE apps (kdenlive, krita, kdiff3, ...), virt tools, stock tty1 plus managed agetty on tty2-10, GDK_BACKEND=x11 patches |
| `test/vm/` | VM only | Deployed dotfiles (.bashrc, fish, git, user-dirs), XFCE/X11, terminator, rofi, autologin (xfce4-panel + xfdesktop running as jan), spice/qemu agents (installed + running), display resize loop, symlinks into /usr/local, purged packages (snapd, xfce4-terminal), systemd services |
| `test/utils/` | manual only | Destructive integration tests (e.g. pod-security: creates a pod user, verifies ACLs/hardening, then deletes it). NOT run by test-host.sh or test-vm.sh. Run individually: `sudo bats test/utils/pod-security.bats` |

### Launchers

```bash
# on the host (Plasma/Wayland/openSUSE):
/opt/jan/test/test-host.sh        # runs basic/ + host/

# inside a VM (XFCE/X11/Xubuntu):
/opt/jan/test/test-vm.sh          # runs basic/ + vm/
```

### Automated VM deploy-and-test

```bash
/opt/jan/test/test-vm-deploy.sh          # clone xub -> provision -> reboot -> test -> destroy
/opt/jan/test/test-vm-deploy.sh --keep   # same, but keep VM for debugging
/opt/jan/test/test-vm-xub26-deploy.sh    # clone xub26 -> setup/vm-xub26 -> test -> destroy
```

The deploy script:
1. Shuts down the base VM (default `xub`; override with `BASE_VM`)
2. Creates a qcow2 overlay (copy-on-write, fast)
3. Clones the VM XML (new name `test-YYMMDD-HHMM`, new MAC, same virtiofs share)
4. Starts the clone, waits for the guest agent
5. Runs the setup script (default `setup/vm-xub24`; override with `SETUP_SCRIPT`)
6. Reboots, waits for desktop session (autologin + XFCE)
7. Installs bats, runs `test-vm.sh`
8. On exit: destroys VM and deletes overlay (unless `--keep`)

### Design principles

- `helpers.bash` provides shared assertions: `assert_file`, `assert_command`, `assert_executable`, `assert_symlink`, `assert_file_contains`
- `JAN_HOME` auto-detects: `/home/jan` in VM, `$HOME` on host
- Tests that need a running desktop (autologin, spice agent, resize loop) verify processes via `pgrep`, not env vars — because tests run via `vm-exec` (qemu guest agent), not inside an X session
- VM tests run as root via guest agent; host tests run as the current user
- When adding a new utility or setup script, add matching tests in the appropriate subdirectory
- `sbin` tools live in `/usr/sbin` which may not be in user PATH — use `assert_executable /usr/sbin/...` instead of `assert_command`

## When editing scripts

- Admin scripts (`usr/sbin/`) expect to run as root — they should check `$EUID`
- Use `set -euo pipefail` in bash scripts
- Prefer `apt-get` over `apt` in scripts (non-interactive stability)
- Version-managed tools use the pattern: check `.version` file, skip if current, download to `_temp` dir, swap in place
