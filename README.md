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
