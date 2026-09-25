# opt-jan

Personal dotfiles and system provisioning repo. Checked out at `/opt/jan` on target systems.

## Two deployment modes

1. **Fresh install** — clone repo to `/opt/jan`, run the matching setup script as root
2. **VM with host mount** — host's `/opt` is mounted into the guest; tools are already available

## Directory layout

| Path | Purpose | Deployment |
|------|---------|------------|
| `skel/home/` | Canonical user dotfiles and new-user defaults | Installed into `/etc/skel`; VM provisioners also sync it into disposable VM homes |
| `usr/bin/` | User utilities | Symlinked into `/usr/local/bin` |
| `usr/sbin/` | Admin scripts (run as root) | Symlinked into `/usr/local/sbin` |
| `usr/share/` | Fonts, icons, themes, cursors | Symlinked into `/usr/local/share` |
| `dist/` | Bundled theme assets (Sweet, candy-icons, xfwm, cursors) and their `justfile` updater | Referenced by `usr/share/` links |
| `setup/` | Per-machine provisioning scripts; `setup/host` is a minimal distro-agnostic hardening pass that installs no packages | Idempotent; safe to re-run |
| `test/` | Bats suites for host, VM, and fixture checks | See Testing below |
| `doc/` | Operational notes; `doc/todo/` holds open work | Not deployed |
| `agent/` | Local GGUF download scripts, `llama-models.ini` presets, `serve-all.sh` | Run by hand on the model machine; downloads are gitignored |
| `agent/skills/` | Canonical skill packages (repo-specific and general) | Not scanned by harnesses; source of truth |
| `.agents/skills/` | Codex/Grok/Pi shared discovery | Real directory of per-skill symlinks into `agent/skills/` |
| `.claude/skills/` | Claude Code discovery | Same per-skill symlink shape |
| `.grok/skills/` | Grok native discovery | Same per-skill symlink shape |
| `.pi/skills/` | Pi project discovery | Same per-skill symlink shape |


## Key conventions

- `usr/` is symlinked into `/usr/local` (not copied) — file paths must work as symlinks
- `skel/home/` is the single source for user dotfiles. Host provisioning only
  installs `/etc/skel`; VM provisioners sync it without `--delete` into their
  disposable VM homes
- New homes get real `~/.agents/skills`, `~/.claude/skills`, `~/.grok/skills`,
  and `~/.pi/agent/skills` directories of per-skill links to
  `/opt/jan/agent/skills/<name>`
- PATH commands in `usr/bin/` and `usr/sbin/` use domain-first kebab-case stems
  (`vm-gui`, `pod-setup`, `distro-upgrade`); no `jan-` brand prefix and no
  `.sh` suffix. Do not vendor third-party binaries; use a distro package or
  `optupdate`
- `optupdate` downloads portable tools into `/opt/` with `.version` file tracking
  and publisher checksums; `opt-status` lists what is installed
- `distro-upgrade` is distro-agnostic: handles zypper (openSUSE), dnf (Fedora), apt (Ubuntu)
- Setup scripts must check `systemd-detect-virt` before doing VM-specific operations
- Shell configs exist for both bash (`.bashrc`) and fish (`config.fish`) — keep them in sync

## User environment

| | Host (`setup/host-weed-kde`) | VMs (`setup/vm-xub26`, `vm-baseweed`, `vm-ub26-xfce`) |
|---|---|---|
| OS | openSUSE Tumbleweed | Xubuntu 26.04, Ubuntu 26.04 cloud, or Tumbleweed |
| Desktop | KDE Plasma 6 on Wayland, started from agetty on tty2-10 (tty1 stock) | XFCE on X11; the Ubuntu VMs autologin, `vm-baseweed` configures no login |
| Terminal | Konsole | Terminator |
| GUI editor | Kate / KWrite | Mousepad |

Shared: Sweet-dark colors with Sweet-Purple/candy icons, JetBrains Mono,
Bash + Fish with Starship (distro package), mcedit, and `optupdate` dev tools
(IntelliJ IDEA, Corretto JDKs, Gradle, Maven, Kubernetes CLIs, coding agents).

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core): four test directories, two launchers, and automated VM deploy scripts.

### Scenarios

| Directory | Runs on | What it verifies |
|-----------|---------|-----------------|
| `test/basic/` | everywhere | `/opt/jan` structure, CLI tools (fish, htop, ncdu, aria2c, yq, java, maven, go, ...), JetBrains Mono and console fonts, kernel tweaks, package safety locks, `/etc/skel` contents |
| `test/host/` | host only | Plasma/Wayland, KDE apps (kdenlive, krita, kdiff3, ...), virt tools, stock tty1 plus managed agetty on tty2-10, GDK_BACKEND=x11 patches, monitor fixes, Strix Halo GPU parameters |
| `test/vm/` | VM only | Deployed dotfiles (.bashrc, fish, git, user-dirs), XFCE/X11, terminator, rofi, autologin (xfce4-panel + xfdesktop running as jan), spice/qemu agents (installed + running), display resize loop, symlinks into /usr/local, purged packages (snapd, xfce4-terminal), systemd services |
| `test/utils/` | CI / manual | Fixture tests, network installs, and opt-in destructive integration tests; each file declares its CI category (below) |

### Launchers

```bash
# on the host (Plasma/Wayland/openSUSE):
/opt/jan/test/test-host.sh        # runs basic/ + host/

# inside a VM (XFCE/X11/Xubuntu):
/opt/jan/test/test-vm.sh          # runs basic/ + vm/
```

### Automated VM deploy-and-test

```bash
/opt/jan/test/test-vm-deploy.sh          # clone xub26 -> provision -> reboot -> test -> destroy
/opt/jan/test/test-vm-deploy.sh --keep   # same, but keep VM for debugging
/opt/jan/test/test-vm-xub26-deploy.sh    # clone xub26 -> setup/vm-xub26 -> test -> destroy
/opt/jan/test/test-vm-baseweed-deploy.sh # same flow for the Tumbleweed VM base
/opt/jan/test/test-vm-idempotency.sh     # provision twice and check user data survives
```

The deploy script:
1. Shuts down the base VM (default `xub26`; override with `BASE_VM`)
2. Creates a qcow2 overlay (copy-on-write, fast)
3. Clones the VM XML (new name `test-YYMMDD-HHMM`, new MAC, same virtiofs share)
4. Starts the clone, waits for the guest agent
5. Runs the setup script (default `setup/vm-xub26`; override with `SETUP_SCRIPT`)
6. Reboots, waits for desktop session (autologin + XFCE)
7. Runs `test-vm.sh` (Bats is installed by provisioning)
8. On exit: destroys VM and deletes overlay (unless `--keep`)

### Design principles

- `helpers.bash` provides shared assertions: `assert_file`, `assert_command`, `assert_executable`, `assert_symlink`, `assert_file_contains`
- `JAN_HOME` auto-detects: `/home/jan` in VM, `$HOME` on host
- Tests that need a running desktop (autologin, spice agent, resize loop) verify processes via `pgrep`, not env vars — because tests run via `vm-exec` (qemu guest agent), not inside an X session
- VM tests run as root via guest agent; host tests run as the current user
- When adding a new utility or setup script, add matching tests in the appropriate subdirectory
- Every `test/utils/*.bats` has a `# ci: <category>` line after the shebang.
  CI runs `fixture` files (offline, unprivileged, stubbed commands) on every
  push and `portable-tools` files in the network job; `manual` files need
  root, a VM, or heavy downloads. `repo-policy.bats` rejects untagged files
- `sbin` tools live in `/usr/sbin` which may not be in user PATH — use `assert_executable /usr/sbin/...` instead of `assert_command`

## When editing scripts

- Admin scripts (`usr/sbin/`) expect to run as root — they should check `$EUID`
- Use `set -euo pipefail` in bash scripts
- CI runs `bash -n` and `shellcheck --severity=warning` on every tracked shell
  script. Under `set -e`, split `local x=$(cmd)` into `local x` plus
  `x=$(cmd)`; add `|| true` only where the next line handles an empty result
- Prefer `apt-get` over `apt` in scripts (non-interactive stability)
- Version-managed tools use the pattern: check `.version` file, skip if current, download to `_temp` dir, swap in place
