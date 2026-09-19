# ansible/ — phase 0 pilot

This tree is a **pilot**, not the provisioning path. `setup/host-weed-kde`,
`setup/vm-xub26`, `setup/vm-baseweed` and `setup/vm-ub26-xfce` are unchanged
and remain the supported way to provision a host or a VM. Nothing here is
called by them, by the bats suites, or by the deploy harnesses.

It exists to answer one question from the migration plan: do two real roles in
Ansible cost less to maintain than the shell they replace, and is the change
report useful? The two roles cover work that is duplicated today:

- `roles/xdg_user_dirs` — the `/etc/xdg/user-dirs.defaults` heredoc that
  appears verbatim in three scripts, and the `configure-user-dirs()` function
  copied between the two VM provisioners. Primary-account discovery uses
  `setup/vm-baseweed`'s semantics: regular login accounts rooted directly under
  `/home`, prefer `jan`, otherwise require exactly one, fail on ambiguity.
- `roles/systemd_units` — the "write a unit file, daemon-reload, enable"
  installers. The first unit is `tty11-root`, with the unit text taken
  byte-for-byte from `usr/sbin/install-tty11-root`.

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
  roles/xdg_user_dirs/
  roles/systemd_units/
```

Var files are named after the `os_family` fact (`Debian`, `Suse`), not after
distribution names, because that is what `vars_files` resolves.

## Running it

Always through the supervisor, as root, inside a disposable VM:

```bash
/opt/jan/setup/bootstrap pilot
/opt/jan/setup/bootstrap pilot --check --diff     # requires the runtime already present
```

`setup/bootstrap`:

1. validates root and, for VM profiles, that `systemd-detect-virt --vm`
   reports `kvm` or `qemu` — the same allowlist the play asserts, enforced
   before any mutation;
2. classifies the forwarded `ansible-playbook` arguments so the supervisor and
   Ansible can never disagree about check mode (`--check`, `-C`, and any short
   cluster containing `C` such as `-CD` or `-vvC`), rejecting argument forms it
   cannot classify;
3. lays down the `usr/` → `/usr/local` symlink farm so `qga-guard` is on PATH;
4. acquires the guest-agent guard with its own `$$` **before any package
   work** and exports `JAN_QGA_GUARD_TOKEN`;
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
- Ansible caches, logs and collections stay off `/opt/jan`.

## CI

The `ansible` job in `.github/workflows/check.yml` runs `ansible-lint` and
`ansible-playbook --syntax-check` over this tree, with `ansible-core`,
`ansible-lint` and the Python version pinned to what the pilot was validated
against. `shellcheck` still covers `setup/bootstrap` through the existing
`shell` job.
