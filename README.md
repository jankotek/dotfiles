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

- `jan-doctor` — read-only host/VM health summary
- `jan-dotfiles-diff [USER|HOME|--skel]` — preview canonical skeleton changes
- `jan-download URL OUTPUT [SHA256]` — resumable aria2 download with optional verification
- `jan-vm-smoke VM` — quick QGA, DHCP, DNS, and service checks
- `jan-vm-reset [--yes] VM BASE_VM` — recreate one disposable VM from its base
- `jan-clean-check [MIN_MIB]` — report large caches, backups, overlays, and kernels

For a user whose home does not exist yet, run `sudo /opt/jan/skel/install`
before `useradd --create-home`. `jan-create-user` performs this automatically.
