# VM boot images and text-only golden images

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

## Debian 13 and Ubuntu 26.04

From the checkout, these commands fetch the pinned cloud input, prepare its boot
prerequisites, then bake and test the same three-disk golden-image bundle:

```sh
usr/bin/vm-image-build --golden --distro debian
usr/bin/vm-image-build --golden --distro ubuntu
```

These builders target x86-64 guests booting through BIOS in `qemu:///session`.

To build only the intermediate boot image, omit `--golden`. The inputs are Debian
13's **generic** cloud qcow2 (full driver coverage for virtiofs and optional GUI)
and Ubuntu 26.04's amd64 server cloud `.img` (verified as qcow2). Pins live in
`usr/share/vm-image/debian.toml` and `ubuntu.toml`. Each config binds the artifact
name, exact digest, release, architecture and publisher URL.

Ubuntu checksum manifests are authenticated with the pinned Canonical signing
key. Current Debian cloud images do **not** publish checksum signatures: they are
downloaded through HTTPS and checked against the exact pinned SHA512 and matching
upstream manifest entry. That difference is recorded explicitly in the boot
manifest's `verification` field; Debian is never described as publisher-signed.
See the [Debian cloud index](https://cloud.debian.org/images/cloud/) and
[Canonical artifact documentation](https://ubuntu.com/docs/public-images/public-images-reference/artifacts/).

Debian and Ubuntu use their release's normal signed APT repositories, including
security updates; the output manifest records installed package versions.
Tumbleweed retains its exact dated repository snapshot. Boot-image outputs live
in `~/.local/share/libvirt/images/dotfiles-cloud`. Large downloads use resumable
aria2 transfers and are verified before libguestfs opens them.

All distributions configure DHCP/DNS and QGA before cloud-init is disabled.
A dedicated systemd unit generates missing SSH host keys before the packaged
sshd configuration check. Initramfs regeneration is distro-specific, and cloud
root-growth hooks are disabled. Golden images use `jan` with UID/GID 1000.
Debian/Ubuntu GRUB uses console and serial output so a video device is optional.
Their BIOS bootloader is reinstalled after resizing to refresh its disk-sector
references; the [virt-resize documentation](https://libguestfs.org/virt-resize.1.html)
describes this requirement for guests whose bootloader no longer starts.

## Bake a text-only golden image

Work in the checkout you want to install. The host's `/opt/jan` is not used:

```sh
usr/bin/vm-image-build --golden --base /path/printed/by/vm-image-build.qcow2
```

`--repo PATH` explicitly selects another checkout; the default is the current
working directory. Host provisioning installs `libguestfs`, `guestfs-tools`,
`libguestfs-appliance`, `libguestfs-xfs`, `virtiofsd`, and `passt` for this pipeline.
The builder mounts that checkout read-only at `/opt/jan`
inside disposable session-libvirt guests. It runs `setup/vm-cli` in an independent
systemd service. This installs common command-line tools through `apt`, deploys
the canonical skeleton, and configures networking and a text boot target. No Go
compiler, Zim, desktop, browser, or display manager is installed. The existing
`setup/vm-baseweed` graphical profile layers its extra packages over this shared
CLI setup; `setup/vm-workstation USER` is the smaller promotion route below.

The supported package-name baseline is Debian 13, Ubuntu 26.04 (main + universe),
and Tumbleweed. Common tool names agree. Differences are `xz-utils` versus `xz`,
networkd coming from Debian/Ubuntu's `systemd` versus SUSE's `systemd-networkd`,
and `console-setup fonts-terminus` versus `terminus-bitmap-fonts`. `python3` is a
SUSE provider capability for the current Python package. The SUSE bootstrapping
stage installs `zypper-aptitude`; its `apt` needs `--without-recommends` before
the action, while Debian/Ubuntu use `--no-install-recommends`. Go is optional and is not installed by the shared baseline or promotion script.

Package names were checked against the distribution indexes on 2026-10-28:
[Debian 13](https://deb.debian.org/debian/dists/trixie/main/binary-amd64/Packages.xz),
[Ubuntu 26.04 main](https://archive.ubuntu.com/ubuntu/dists/resolute/main/binary-amd64/Packages.xz),
[Ubuntu universe](https://archive.ubuntu.com/ubuntu/dists/resolute/universe/binary-amd64/Packages.xz),
and the [pinned Tumbleweed repository](https://download.opensuse.org/history/20261026/tumbleweed/repo/oss/repodata/repomd.xml).
The compatibility flags follow the [upstream apt frontend](https://github.com/openSUSE/zypper/blob/master/tools/aptitude).
The golden-image path supports Tumbleweed, Debian 13 and Ubuntu 26.04.

The golden account is `jan` with UID/GID 1000. After clean shutdown, offline sealing removes machine IDs, SSH host keys,
random seeds, temporary credentials, DHCP/cloud state and build logs. A systemd
SSH pre-start action regenerates missing host keys. Discard is attempted in the
guest; `virt-sparsify` compacts bounded intermediate disks before their virtual
capacities are expanded. No zero-fill or temporary allocation of the large
unpartitioned tails is performed.

Each result is a private directory containing three standalone qcow2 files and
`manifest.json`. All three files form one golden image:

| File | Virtual disk | Initial partition/filesystem | Remaining space |
|---|---:|---|---|
| `root.qcow2` | 100 GiB | Preserved boot partitions + 4 GiB root | Unpartitioned |
| `home.qcow2` | 2100 GiB | 6 GiB ext4 mounted at `/home` | Unpartitioned |
| `swap.qcow2` | 1 GiB | GPT swap partition, about 1022 MiB usable | None beyond alignment |

GPT supports the home disk's capacity above 2 TiB. The source root filesystem (XFS on Tumbleweed, ext4 on Debian/Ubuntu) is
recreated at 4 GiB. Its files are migrated while
preserving its UUID, numeric ownership, hard links, ACLs and extended attributes.
Boot sectors, all non-root boot partition contents, GPT numbers and partition
GUIDs are preserved, including Debian/Ubuntu partition-number gaps. The
KIWI initramfs repartition module is omitted and the initrd rebuilt, so booting
does not consume the reserved expansion space. Cloud-init growth is disabled too.
The home and root partitions can be grown deliberately later; they never grow
just because the virtual disk has spare capacity.

A VM definition attaches root/home/swap as `vda`/`vdb`/`vdc`. Clone both root and
home with private qcow2 overlays. Create fresh swap for each VM rather than
inheriting old swap pages. The bundled swap disk is a clean template; tests verify
all parent image hashes remain unchanged.

Two new overlay clones must pass text-only/package checks, network/DNS/QGA,
tmux and real SSH authentication. They verify the exact disk/partition capacities,
active swap, persistent host mounts and a normal-user document write. They must
have distinct machine IDs and SSH
host keys. Guest root must be unable to write the shared checkout even after a
remount attempt. Input and candidate image hashes must remain unchanged.

Outputs are in `~/.local/share/libvirt/images/dotfiles-golden`. The private
manifest records the actual checkout input digest (including uncommitted inputs),
the executing builder/helper digest, boot manifest, package versions, clone
identities and compaction measurements. These fingerprints remain separate when
`--repo` selects a checkout different from the executing builder's checkout.
Failed builds retain private diagnostic directories. No current/approved pointer,
publication, rotation or automated image deletion is performed. Existing matching
artifacts are verified and reused. A changed checkout during building rejects the
result; rerun after editing is finished.

The fstab host-share section contains these virtiofs tags:

```fstab
host-opt  /opt           virtiofs ro,nofail,x-systemd.automount 0 0
opt-jan   /opt/jan       virtiofs ro,nofail,x-systemd.automount 0 0
host-docs /home/jan/doc  virtiofs rw,nofail,x-systemd.automount 0 0
```

The VM definition supplies host `/opt` as `host-opt`, the selected checkout as
`opt-jan`, and the selected host document directory as `host-docs`. The checkout
mount is nested over `/opt/jan`, so it uses the current worktree even when host
`/opt/jan` contains another checkout. The read-only host `/opt` export must already
contain a `jan` directory for that nested mountpoint; the builder checks this and
does not modify host `/opt`.

For writable documents, the filesystem's libvirt `idmap` maps guest UID/GID 1000
to the invoking host user's UID/GID. Build and integration tests export a private
fixture document directory, never the operator's actual documents. Normal VM
launches can supply their chosen host document directory using the same tag and
mapping. No host files are copied into the image. Shared provisioning changes
ownership only on managed skeleton files and does not recurse through a mounted
host document share.

Explicit later expansion inside a disposable/retained guest, when desired:

```sh
root_device=$(findmnt -n -o SOURCE --target /)
root_number=$(cat "/sys/class/block/${root_device##*/}/partition")
growpart /dev/vda "$root_number"
case "$(findmnt -n -o FSTYPE --target /)" in
    xfs) xfs_growfs / ;;
    ext4) resize2fs "$root_device" ;;
esac
growpart /dev/vdb 1
resize2fs /dev/vdb1
```

These are manual operations; automatic expansion is disabled.

## Promote a CLI VM to a minimal workstation

Inside an existing VM with its checkout mounted at `/opt/jan`, run as root:

```sh
/opt/jan/setup/vm-workstation jan
reboot
```

Select an existing regular user. The script installs individual XFCE/Xorg
components, Thunar, Terminator, Mousepad, LightDM and SPICE integration, without a
desktop metapackage or development compiler. It configures automatic XFCE
autologin for that user. Identity, credentials and existing home files are kept.
On Debian/Ubuntu it installs `lightdm-autologin-greeter`. Tumbleweed does not ship
that package in the pinned repository: its packaged LightDM PAM autologin is
used with `lightdm-gtk-greeter` as the logout fallback.
The plugin uses its [packaged one-second delay](https://sources.debian.org/patches/lightdm-autologin-greeter/1.0-5/1004_set-autologin-timeout.patch/)
so logging out can start a fresh session;
Tumbleweed's built-in autologin uses zero delay. Managed settings sort after
the Debian package's placeholder autologin-user configuration.

Offline and opt-in live checks:

```sh
OPT_JAN="$PWD" bats test/utils/vm-golden.bats
GOLDEN_TEST_BOOT_BASE=/path/to/boot.qcow2 OPT_JAN="$PWD" bats test/utils/vm-golden-live.bats
GOLDEN_TEST_BASE=/path/to/golden-cli-BUNDLE OPT_JAN="$PWD" bats test/utils/vm-golden-live.bats
```

The promotion test checks actual XFCE processes after reboot and Debian/Ubuntu
automatic relogin after session exit, unchanged guest identity/project data,
working repository symlinks, absence of Go, and an unchanged golden base.
Success removes its own clone. Failure stops the disposable guest and retains
its private overlay disks and logs for diagnosis.

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
