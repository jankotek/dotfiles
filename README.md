# opt-jan

Personal dotfiles and provisioning scripts for openSUSE Tumbleweed hosts and
Xubuntu/openSUSE virtual machines. Target systems normally check this repository
out at `/opt/jan`.

## Layout

- `skel/home/` — canonical user dotfiles, also installed into `/etc/skel`
- `setup/` — host and VM provisioning entry points
- `usr/` — commands and shared assets linked into `/usr/local`
- `agent/` — local model download and serving scripts
- `test/` — Bats checks for hosts, VMs, and utility fixtures
- `doc/` — operational notes

## Provisioning

Run the setup script matching the target system as root, for example:

```bash
sudo /opt/jan/setup/host-weed-kde
sudo /opt/jan/setup/vm-xub26
```

These scripts install/remove packages and change system configuration. Read the
selected script before running it on a machine with data you care about.

## Tests

```bash
/opt/jan/test/test-host.sh
/opt/jan/test/test-vm.sh
OPT_JAN="$PWD" bats test/utils/pod-subid-allocation.bats
```

The host and VM suites inspect provisioned systems. Tests under `test/utils/`
may be destructive unless their documentation explicitly says they are
fixture-only; see [test/README.md](test/README.md) for details.

## Utilities

- `vm-image-build` — build a fresh, verified Tumbleweed boot image from the
  original cloud download, then use canonical dotfiles provisioning.
  See [Build and test baseweed](doc/vm-image.md).
- `herdr-run COMMAND [ARGS...]` — associate a restart command and environment
  with the calling Herdr pane; `herdr-layout save` / `restore` recover its live
  arrangement. Layout and command-mapping edits autosave through Herdr events.
  `vm-tmux` starts existing session VMs and attaches to guest tmux.
  See [Herdr recovery and VM profiles](doc/herdr-layout.md).
- `host-doctor` — read-only host/VM health summary
- `opt-status` — list versions recorded under `/opt`
- `optupdate idea` — install/update IntelliJ IDEA and its shared official
  JetBrains plugins under `/opt/idea/plugins`: Python, Go, Rust, C/C++, native
  build/debug tools, CMake, Meson, compilation databases, Makefile, and INI.
  With an Ultimate subscription, IDEA also provides TypeScript, Spring Boot,
  Database Tools and SQL, Docker/Podman, Kubernetes/Helm, and Shell scripts.
  Every run checks Marketplace for the latest plugin releases compatible with
  the IDEA build. Plugin-only updates reuse the installed IDEA tree instead of
  downloading IDEA again; unchanged releases are skipped. A failed update leaves
  the previous IDEA and plugins in place. Python 3 parses Marketplace metadata;
  plugin versions/update IDs are recorded in `/opt/idea/.jetbrains-plugins`.
- `pod-doctor` — read-only pod subordinate IDs, linger, Quadlet, and cgroup delegation
- `sshd-audit` — read-only PermitRootLogin, password authentication, and host key/cert age
- `vm-list` — one line per session VM: state, base or overlay disk, size, and guest IPv4
- `kernel-zbook-build` — build and install the custom openSUSE ZBook kernel with AMD ISP4 capture; run as root from the newest official kernel-default
- `dotfiles-diff [USER|HOME|--skel]` — preview canonical skeleton changes
- `verified-download URL OUTPUT [SHA256]` — resumable aria2 download with optional verification
- `vm-smoke VM` — quick QGA, DHCP, DNS, and service checks
- `vm-reset [--yes] VM BASE_VM` — recreate one disposable VM from its base
- `clean-check [MIN_MIB]` — report large caches, backups, overlays, journals, podman storage, Hugging Face caches, and kernels

For a user whose home does not exist yet, run `sudo /opt/jan/skel/install`
before `useradd --create-home`. `create-user` performs this automatically.
