# Herdr command mappings, layout recovery, and VM tmux

The three commands use Python 3's standard library. `herdr-run` records what to
restart, `herdr-layout` saves/reconstructs the live arrangement, and `vm-tmux`
starts an existing session-libvirt VM and attaches through verified SSH.
The environment detector is a small editable Bash script. No daemon or rule
engine is required.

## Commands in ordinary Herdr panes

Create tabs and splits through Herdr as usual, then run:

```sh
herdr-run htop
herdr-run mc
herdr-run nano /some/file/to/edit
herdr-run ssh -t devbox codex
herdr-run vm-tmux attach dev --session coding
```

The association belongs to the calling **pane**, rather than the whole tab or
the UI-focused pane. Moving, swapping, or renaming the pane preserves its
mapping. Closing it removes it from the next saved layout. When the mapped
program exits, its live association is cleared; earlier snapshots still retain
their restart records. Re-run `herdr-run` to associate another command.

Explicit launcher flags precede the command:

```sh
herdr-run --agent codex ssh -t devbox tmux attach -t coding
herdr-run --agent none ssh -t devbox echo codex
herdr-run --env EDITOR=nano mc
```

Only explicit launch variables and the resolved agent hint are saved. The
inherited environment, provider tokens, and old Herdr pane/socket IDs are not
copied into snapshots. Avoid specifying secrets with `--env`, because these
explicit values are persisted. Arguments are retained as arrays; the launcher
does not reinterpret shell text. For pipelines, explicitly request a shell:
`herdr-run bash -c 'your pipeline'`.

## Save and restore

```sh
herdr-layout save
herdr-layout --session recovered restore --file \
  ~/.local/state/herdr-layout/layout-SOURCE_SESSION_HASH.json
```

`save` prints the actual snapshot path. To select your own path, first create a
private directory and use `save --file ~/.local/state/my-layout/latest.json`.
Snapshots and mappings live under `$XDG_STATE_HOME/herdr-layout`, defaulting to
`~/.local/state/herdr-layout`. Files are 0600 and their storage directories must
be owned by you with mode 0700. The previous successful snapshot is retained as
`<filename>.previous`. Failed or changing API reads never replace a good capture.

Restore requires a running target Herdr server. Start a fresh headless target
with `herdr server --session recovered`, run the restore from another terminal,
then attach the UI with `herdr --session recovered`. Starting headlessly avoids
creating a default workspace that might collide with a saved workspace label.
`restore` operates on the running server. After stopping that target server,
use the following command to start it, recover mapped programs, and open the UI:

```sh
herdr-layout --session recovered open --file \
  ~/.local/state/herdr-layout/layout-SOURCE_SESSION_HASH.json
```

Bare `herdr --session recovered` restores native topology as shells; it does
not replay these command mappings. If you already opened it that way, use
`herdr-layout --session recovered restore --recover --file SNAPSHOT` from another
terminal. Your original session can also recover its own saved snapshot; an
external replay is not required. Saving again after rearranging panes publishes
a new generation with the current native identities. For a normal same-session
restart, use `herdr-layout --session NAME save --file SNAPSHOT`, stop that server,
then `herdr-layout --session NAME open --file SNAPSHOT`.

`open` probes the public API before deciding whether to start a server, so a
stale socket left by a crash does not count as a live instance. If a crash
occurs before Herdr persists the latest topology, its native identities can
disagree with the saved capture or recovery journal. Recovery then refuses
replacement; restore the snapshot into a fresh named target session instead.

Cold recovery uses the snapshot's source identities, or a completed replay
journal for the latest recovered identities. It checks workspace/tab identities, titles, split topology and pane
identities, and refuses to replace running programs or shells with background
children. Every remaining tab is checked again on retry. On Linux, pidfds pin
the checked shell processes; recovery briefly stops those shells, verifies they
have not started a command, then applies the replacement. A failed check resumes
all surviving shells. Recover before opening the UI so edits to the layout do
not race recovery. Changed or closed tabs require a fresh snapshot or target. This protects
later work from being replaced by an old snapshot. VM panes open their recovery
menu; choose `a` to attach to the existing guest session.

Herdr native recovery and this utility must not both replay the same workspace.
Use a **fresh named target session** for external recovery, and disable native
agent launching in the Herdr configuration:

```toml
[session]
resume_agents_on_restore = false
```

Initial restore refuses the original live session and collisions with original or
native-restored workspace labels. It creates new workspaces while preserving
unrelated workspaces. It restores workspace/tab order, split topology/ratios,
labels, remembered tab focus, pane focus, and zoom. Unmapped panes and unavailable
commands/directories become visible placeholders. Programs restart; an unsaved
nano buffer is not a checkpoint.

Restore is journalled per target socket/server instance. Repeating the same
completed generation leaves later user edits and closures intact. Retry of an
interrupted restore continues only from confirmed operations. An uncertain
create/apply operation is refused, because the public API cannot atomically
commit a Herdr object and a local journal. The error identifies the need for
reconciliation; use a fresh named target session for a safe new attempt.
Do not remove a pending journal and blindly replay into its partially restored
session. Capture is blocked while that session's restore is incomplete.

## Simple agent environment script

The default script is `usr/share/herdr-layout/agent-env`. To customize:

```sh
install -d -m 700 ~/.config/herdr-layout
install -m 600 /opt/jan/usr/share/herdr-layout/agent-env \
  ~/.config/herdr-layout/agent-env
nano ~/.config/herdr-layout/agent-env
```

It receives the original command arguments. It examines `$*` with Bash regexes
and prints either nothing, `HERDR_AGENT=claude`, or `HERDR_AGENT=codex`. Its output
is parsed as data, never sourced or evaluated. Invalid output and nonzero exit
fail before launching the command. Explicit `--agent`/environment choices take
precedence over the script; a VM profile's agent is the fallback. `--agent none`
suppresses both automatic sources.

Matching is intentionally heuristic. An agent-named argument may be a false
positive, and a program typed later inside an interactive SSH shell is invisible
to the initial command. Use `--agent` for those cases. Restore uses saved resolved
values without rerunning a subsequently edited script.

`HERDR_AGENT` is placed on the host-visible SSH/attachment child so Herdr can
apply its agent screen patterns. VM menus and readiness probes do not inherit
that hint. Guests receive no host Herdr control socket.

## Existing VM profiles

`vm-tmux` manages only your `qemu:///session` domains. It does not provision,
clone, reset, destroy, or delete a VM. Create a private JSON profile at
`~/.config/herdr-layout/vms/dev.json`:

```json
{
  "schema_version": 1,
  "domain_uuid": "9c454452-26ce-46c6-95b8-ef753842186b",
  "libvirt_uri": "qemu:///session",
  "ssh_host": "127.0.0.1",
  "ssh_port": 23117,
  "ssh_user": "jan",
  "ssh_host_key_alias": "dev-incarnation-123",
  "ssh_identity_file": "~/.ssh/lab-operator",
  "ssh_known_hosts_file": "~/.config/herdr-layout/known_hosts",
  "tmux_session": "main",
  "agent": "codex"
}
```

Use `virsh -c qemu:///session domuuid VM_NAME` for the domain UUID. Install guest
tmux and SSH through your VM provisioner. Obtain the guest's host public key via
a trusted provisioning channel such as `vm-exec VM --argv cat
/etc/ssh/ssh_host_ed25519_key.pub`, then place it in the designated known-hosts
file as `dev-incarnation-123 ssh-ed25519 PUBLIC_KEY`. A scoped `@cert-authority`
entry can instead trust the guest host certificate's principal. Do not populate
this file by blindly trusting `ssh-keyscan`. Profile, identity, and known-hosts
files must be private and current-user-owned.

Optional `tmux_socket` selects an absolute **guest** socket path. Saved mappings
pin the resolved VM UUID, host alias, guest user, socket, and exact session.
Changing a profile's endpoint can repair routing while retaining identity;
changing its identity requires an explicit new mapping. Later session-default
changes cannot redirect the saved target.

```sh
vm-tmux attach dev                      # main/profile default
vm-tmux attach dev --session coding
vm-tmux attach dev --menu-first         # no startup until you choose
vm-tmux attach dev --reclaim            # explicit detach of other clients
vm-tmux new dev --session monitor -- htop
vm-tmux new dev --session notes --cwd /home/jan/project -- nano notes.txt
```

`new` creates a session and attaches; it never replaces an existing session.
Mapping a successful `new` records an **attachment** for future recovery, not the
workload creation command. Pending creation has no published mapping; saving
during boot/creation captures that pane as unmapped. After successful creation,
save again to capture its immutable attachment mapping. Every restored VM mapping opens menu-first. A missing
guest session is reported without recreating it or replaying an agent prompt.

The menu offers attach, explicit reclaim, start/resume, refresh, and exit.
Ordinary attachment allows other clients. Detach and SSH failure return to the
menu, including successful tmux detach. Paused VMs use `resume`; stopped and
managed-saved VMs use `start`. Lifecycle locks cover only the transition.
SSH host verification is strict, agent forwarding is disabled, and per-user SSH
config is deliberately bypassed for VM profiles. Authentication failures never
relax verification. `--timeout SECONDS` bounds boot/endpoint readiness (1–600,
default 120). SSH keepalives release a paused/lost connection back to the menu.
Control SSH commands have a 15-second limit; attachment checks return timeout
errors to the menu. A creation timeout reports an uncertain outcome and exits
without retrying: inspect the exact guest session before requesting another
creation or attach to it if creation succeeded.
Closing the pane leaves the VM and guest workload available.

## Tests

For a fresh Tumbleweed base built directly from the original cloud image using
dotfiles scripts, see [Build and test baseweed](vm-image.md). That integration
test runs canonical setup before exercising cold Herdr recovery with guest
htop, mc and nano.

```sh
OPT_JAN="$PWD" bats test/utils/herdr-tools.bats
OPT_JAN="$PWD" bats test/utils/herdr-tools-live.bats
HERDR_TEST_BINARY=/path/to/upgraded/herdr OPT_JAN="$PWD" \
  bats test/utils/herdr-tools-live.bats
HERDR_VM_TEST_BASE=/path/to/trusted/baseweed-baked.qcow2 OPT_JAN="$PWD" \
  bats test/utils/vm-tmux-live.bats
```

Fixtures are offline and unprivileged. The real Herdr suite runs isolated
headless sessions, with htop/mc/nano and a deterministic agent-hint demonstration.
The opt-in VM suite creates a fresh BIOS qcow2 overlay with QGA and passt SSH
forwarding, provisions its test account through QGA, anchors host trust there,
and tests tmux handoff, pause/resume, managed save/start, and wrong-host rejection.
Missing tmux/SSH packages are installed **in the disposable guest** with zypper.
Cleanup touches only the test-created UUID and overlay, leaving the base intact.
It needs KVM and a compatible qdistro base; it never starts or stops qci.
The VM suite does not claim virtiofs save/restore support because its test profile
has no shared filesystem.
