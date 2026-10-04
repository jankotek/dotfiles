# Build baseweed from the original cloud image

From the dotfiles checkout, run as your normal host user:

```sh
usr/bin/vm-image-build
```

The builder downloads the original openSUSE Tumbleweed cloud qcow2 and its
signed checksum into `~/.cache/dotfiles/vm-images`. It verifies the pinned
openSUSE signing key, signature, artifact name and SHA-256 before opening the
disk. It requires curl, GnuPG, qemu-img and libguestfs tools (`guestfish`,
`virt-cat`, `virt-resize`, `virt-customize`). It uses no qdistro image or checkout.

The versioned output under `~/.local/share/libvirt/images/dotfiles-baseweed`
is a standalone 25 GiB qcow2 with a private build manifest. Its boot prerequisites
include QGA, SSH, tmux, Python and a locked `worker` account; it has no operator
key installed. The development profile uses permissive SELinux. The image has
no backing file, SSH host keys or preassigned machine identity. Repeating the
same recipe verifies and returns the existing immutable artifact.

The pins live in `usr/share/vm-image/tumbleweed.toml`. Update the snapshot and
digest together when refreshing the base; builds reject pins older than 14 days
and reject a changed upstream artifact. Package repositories use that exact
openSUSE history snapshot.

## Provision and test Herdr

This boot image is the input to canonical `setup/vm-baseweed` provisioning.
The integration test copies it, stages the current dotfiles checkout at
`/opt/jan`, installs a temporary SSH identity, and runs the setup script in an
independent guest systemd service. A guest-agent or network restart cannot
terminate that provisioning service. After provisioning, it reboots and checks
networking and canonical home files.

```sh
HERDR_BASEWEED_TEST_BASE=/path/printed/by/vm-image-build.qcow2 \
  HERDR_BASEWEED_TEST_KEEP=1 OPT_JAN="$PWD" \
  bats test/utils/herdr-baseweed-live.bats
```

The test creates four guest tmux sessions: a shell, htop, mc, and nano editing
`/home/worker/workspace/notes.txt`. It saves four Herdr mappings, stops its own
Herdr server, recovers the layout into attachment menus, chooses attach, and
verifies that all three original application PIDs survived. Repeating restore
must leave exactly four panes. SSH host trust comes through QGA.

With `HERDR_BASEWEED_TEST_KEEP=1`, success prints a Herdr command and leaves the
test VM and recovered session running. Without it, the test removes its own
resources. Failure stops its own VM/session and preserves the private disk and
logs for diagnosis. Manifests are in `~/.local/state/herdr-layout`; each records
the new UUID, profile, base manifest and checkout payload digest. The test uses
only the current user's `qemu:///session` domains and creates no shared mount.

Offline builder checks:

```sh
OPT_JAN="$PWD" bats test/utils/vm-image-build.bats
```
