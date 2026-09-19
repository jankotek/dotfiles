# ansible/ — phase 0 pilot

This tree is a **pilot**, not the provisioning path. `setup/host-weed-kde`,
`setup/vm-xub26`, `setup/vm-baseweed` and `setup/vm-ub26-xfce` are unchanged
and remain the supported way to provision a host or a VM. Nothing here is
called by them, by the bats suites, or by the deploy harnesses.

It exists to answer one question from the migration plan: do these roles cost
less to maintain than the shell they mirror, and is the change report useful?
Each role is measured against the helper it mirrors, and every role has been
compared against that helper on a pair of disposable Tumbleweed clones.

- `roles/primary_user` — shared primary-account discovery with
  `setup/vm-baseweed`'s semantics: regular login accounts rooted directly under
  `/home`, prefer `jan`, otherwise require exactly one, fail on ambiguity.
  Included dynamically (guarded by `primary_user_name is not defined`, inner
  tasks tagged `always`) by the roles that need the primary home, so it runs
  at most once per play.
- `roles/browser_vm` — `install-chrome-vm` and `install-brave-vm` as one
  data-driven role: a browser whose `/opt` tree is absent is skipped, a
  broken tree (missing launcher or icon) fails, otherwise the launcher is
  linked into `/usr/local/bin` and the desktop entry installed.
- `roles/xdg_user_dirs` — the `/etc/xdg/user-dirs.defaults` heredoc that
  appears verbatim in three scripts, and the `configure-user-dirs()` function
  copied between the two VM provisioners.
- `roles/skel` — `skel/install` (`skel/home` into `/etc/skel`, root:root,
  plus the empty directories Git cannot retain) and the home-sync block both
  VM provisioners run: `rsync -a` into the primary home without `--delete`,
  `rsync -r` of `home-root/` into `/root`, the `/home` and `/root` modes,
  the recursive ownership repair, and the family-specific cleanup
  (`~/.cache/sessions` and all-homes privacy on Debian only). The home sync
  excludes `.config/user-dirs.dirs`: the skeleton copy carries an
  xdg-generated header the provisioners' `configure-user-dirs` overwrites
  anyway, so `xdg_user_dirs` owns the home copy while `/etc/skel` keeps the
  full skeleton file — the same end state the shell sequence produces. The
  ownership repair runs with `follow: false` because skeleton symlinks (e.g.
  `~/.agents/skills/*`) point into `/opt/jan`, matching `chown -R`'s physical
  traversal; without it the repair would chown the checkout itself.
- `roles/kernel_cmdline` — a `command:` wrapper around
  `usr/sbin/setup-kernel-tweaks`, which stays bash. The provisioners' `||
  echo WARNING non-fatal` becomes a visible play failure; rerun with
  `--skip-tags kernel` to proceed without it. `changed` follows the helper's
  own "Already configured" output — on a guest whose GRUB setup takes the
  helper's always-rewrite drop-in branch there is no converged path, so the
  task truthfully keeps reporting changed there.
- `roles/systemd_units` — the "write a unit file, daemon-reload, enable"
  installers (`install-tty11-root`, `install-tty12-menu`,
  `install-guest-cleanup`, `install-tmp-clean`, the `console-font` unit and the
  four `install-laptop-power` units). Every unit text is byte-identical to what
  its installer writes. Each entry declares `enable` and `start` explicitly and
  may list retired units it supersedes, which are disabled and stopped before
  their files are removed.
- `roles/console_font` — `usr/sbin/console-font`.
- `roles/pkg_safety` — `usr/sbin/setup-pkg-safety`.
- `roles/vm_networkd` — `usr/sbin/setup-vm-networkd`. **Base-image contract:**
  `systemd-networkd` and `systemd-resolved` must already be installed. The role
  removes NetworkManager and masks the competing stacks, so it asserts both
  units exist before it touches anything and refuses to run otherwise. Neither
  it nor `setup/bootstrap` installs them; the shell provisioners install them
  earlier with the rest of the packages (`setup/vm-baseweed:55`,
  `setup/vm-xub26:124`).
- `roles/laptop_power` — `usr/sbin/install-laptop-power` (the `laptop-power`
  policy engine itself stays bash).

## Layout

```
ansible/
  ansible.cfg            inventory, roles_path; collections_path comes from the environment
  inventory.yml          named local hosts lab-vm and zbook (ansible_connection: local)
  requirements.yml       community.general and ansible.posix, pinned to exact versions
  group_vars/all.yml     CLI package list, XDG data, retired bin/sbin names
  vars/Debian.yml        selected by ansible_facts.os_family
  vars/Suse.yml
  pilot.yml              the pilot play (hosts: lab-vm)
  vm-helpers.yml         the roles the VM provisioners call, in their order
  host-helpers.yml       the roles no VM provisioner calls (opt-in, separate)
  roles/browser_vm/
  roles/console_font/
  roles/kernel_cmdline/
  roles/laptop_power/
  roles/pkg_safety/
  roles/primary_user/
  roles/skel/
  roles/systemd_units/
  roles/vm_networkd/
  roles/xdg_user_dirs/
```

`vm-helpers.yml` runs the roles in the order `setup/vm-xub26` and
`setup/vm-baseweed` call the helpers, with `vm_networkd` last because it
replaces the running network. It contains **only** what those provisioners
call — the apt/zypper install and purge lists themselves are not roles yet.
Every role carries a tag, so `--tags console_font` or
`--skip-tags vm_networkd` select a subset.

`host-helpers.yml` holds the helpers no VM provisioner calls —
`install-tty12-menu`, `install-tmp-clean`, `install-laptop-power` — and is a
separate play, not a tag. A tag does not make an unconditionally included role
opt-in: while `laptop_power` sat in the VM play, the documented default
invocation always failed at its final `laptop-power.service` start (that
command needs power/lid/CPU interfaces a lab guest does not have) and
`vm_networkd` never ran.

Var files are named after the `os_family` fact (`Debian`, `Suse`), not after
distribution names, because that is what `vars_files` resolves.

## Running it

Always through the supervisor, as root, inside a disposable VM:

```bash
/opt/jan/setup/bootstrap pilot
/opt/jan/setup/bootstrap vm-helpers
/opt/jan/setup/bootstrap vm-helpers --check --diff       # runtime must already be present
/opt/jan/setup/bootstrap vm-helpers --tags console_font
/opt/jan/setup/bootstrap host-helpers                    # opt-in, host-oriented
```

`setup/bootstrap`:

1. validates root and, for VM profiles, that `systemd-detect-virt --vm`
   reports `kvm` or `qemu` — the same allowlist the play asserts, enforced
   before any mutation;
2. accepts only `--check`/`-C`, `--diff`/`-D`, `--tags`/`-t LIST`,
   `--skip-tags LIST` and `-v`/`-vv`/`-vvv`, and exits 2 on anything else, so
   the supervisor and Ansible can never disagree about check mode;
3. lays down the `usr/` → `/usr/local` symlink farm and runs
   `setup/retire-path-util-names.sh`, exactly as the shell provisioners do;
4. acquires the guest-agent guard with its own `$$` **before any package
   work** and exports `JAN_QGA_GUARD_TOKEN` — or, when
   `JAN_QGA_GUARD_TOKEN` is already set, only verifies the inherited lease and
   leaves ownership (and the agent restore) with the outer supervisor, which is
   `setup/vm-ub26-xfce`'s nested-owner contract;
5. installs `python3` + `ansible-core` (+ `python3-apt` on the Debian family)
   with `--no-install-recommends` / `--no-recommends`;
6. compares every collection named in `requirements.yml` against the installed
   `MANIFEST.json` version and installs or repairs the pinned set in
   `/usr/local/lib/opt-jan-collections`, deliberately off the `/opt/jan` share,
   which may be a writable virtiofs passthrough of the host checkout;
7. runs `ansible-playbook -c local -i inventory.yml -l lab-vm pilot.yml` as a
   child, with output tee'd to `/var/log/opt-jan/`, and takes the play's status
   from `PIPESTATUS` so a failing `tee` cannot mask it;
8. releases the guard in an `EXIT` trap that preserves the child's exit status,
   then enables, starts and verifies `qemu-guest-agent.service`.

The supervisor is the only process that acquires or releases the guard: a
qga-guard lease is keyed on owner PID plus process start time, and an Ansible
task is a short-lived subprocess whose death would make the watchdog release
the lease mid-run. The play only verifies the inherited token, and never
touches `qemu-guest-agent.service` itself.

`--check` never installs software, never acquires or mutates the guard, and
never writes the `/usr/local` symlink farm, so it needs a machine that already
has the runtime and the pinned collections; it fails with the exact version
mismatch when they are absent or stale. The only write it makes is the run
record under `/var/log/opt-jan/`. A preview on a guest that has never been
provisioned works: the roles report the unit file, the enable/start and any
empty capitalised XDG directory as pending changes instead of failing on the
not-yet-existing unit.

## Conventions worth keeping

- Activation policy is one visible line per unit (`start: true` / `false`) and
  is required, not defaulted. There is no "restart on template change" handler:
  console units must never be restarted underneath a live login.
- **`tty11-root` is boot-only** (`start: false`): the pilot enables the unit and
  lets it come up at the next boot. `usr/sbin/install-tty11-root` restarts it
  on every run and the sketch permits an immediate start; the migration plan's
  step 0 asks for an explicit boot-only policy and that is the policy chosen
  here. A first provisioning run therefore leaves tty11 inactive until reboot —
  the deploy harness reboots anyway, and `test/vm/system.bats` asserts
  `is-enabled`, not `is-active`.
- The `rmdir` cleanup of the capitalised XDG directories reports `changed` only
  when the command actually ran and returned 0, and suppresses only the
  expected "Directory not empty" failure, so a second run can honestly report
  `changed=0`. Check mode predicts the same removals from two read-only `find`
  probes, because the command itself never runs there.
- The `systemd_units` handler is named for its role so a future role adding a
  reload handler cannot collide with it; handler names are global in a play.
- Every role is included with `apply: { tags: [...] }`. Tags on a plain
  `include_role` apply to the include task only, so `--tags console_font` would
  select the include and then skip every task inside it.
- Check mode reports what a real run would do even where the module cannot
  predict it: a unit whose file does not exist yet, an empty capitalised XDG
  directory, a missing zypper lock, `acpid` before its package is installed,
  and `/etc/default/console-setup` before `console-setup` is installed. What
  check mode still cannot describe on a fresh guest is console font selection,
  which can only see the fonts already present.
- Two tasks are honestly non-convergent, and so is the shell they mirror:
  `guest-cleanup.service` is a `Type=oneshot` without `RemainAfterExit` that
  `install-guest-cleanup` starts on every run, and `laptop-power.service` is
  the same shape. Expect `changed=1` per such unit on a converged run.
- The `skel` home sync reports two residual changes on a converged run:
  `rsync -a` keeps `-p`, so it re-applies the source directory's mode to the
  primary home and the 0700 policy task repairs it — the same reset+chmod
  loop the provisioners perform silently. Owner and group propagation is
  suppressed (`--no-owner --no-group`) because ownership policy lives in the
  explicit repair task; without it every file fights `og` metadata updates
  every run.
- The `kernel_cmdline` role turns the provisioners' `|| echo WARNING
  non-fatal` wrapper into a play failure: a broken tweak is visible, and
  `--skip-tags kernel` is the explicit way to proceed without it. This is
  the migration plan's replacement for the non-fatal call sites.
- Ansible caches, logs and collections stay off `/opt/jan`.

## CI

The `ansible` job in `.github/workflows/check.yml` runs `ansible-lint` and
`ansible-playbook --syntax-check` over this tree, with `ansible-core`,
`ansible-lint` and the Python version pinned to what the pilot was validated
against. `shellcheck` still covers `setup/bootstrap` through the existing
`shell` job.
