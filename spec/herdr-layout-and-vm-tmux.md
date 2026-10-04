# Herdr layout recovery and remote tmux attachment

Status: implemented in the local `dotfiles/` checkout, with Bats fixture and real Herdr/VM integration coverage. See `../doc/herdr-layout.md` for operational instructions and current recovery limits.

## Scope and agreed workflow

Implement utilities in the local `dotfiles/` checkout. Follow its deployment conventions: commands under `usr/bin/`, shared implementation under `usr/lib/`, documentation under `doc/`, and matching Bats fixture tests under `test/utils/`. Commands must work through `/usr/local/bin` symlinks. Python is the proposed implementation language, with no requirement for third-party packages.

The user creates, splits, rearranges, renames, and closes panes and tabs through Herdr itself. Inside a pane, the user runs `herdr-run COMMAND [ARGS...]`. The launcher associates a restart command with that pane, records its working directory and explicit launch environment, then runs it. The association is per pane, because a tab can contain multiple independently launched programs.

`herdr-layout save` captures the actual live workspace/tab/pane arrangement. `herdr-layout restore` reconstructs the saved arrangement and launches its mapped commands. Restoring a local program restarts it; it does not recover process memory or unsaved editor buffers.

Examples:

```sh
herdr-run htop
herdr-run mc
herdr-run nano /some/file/to/edit
herdr-run ssh -t devbox codex
herdr-run vm-tmux attach dev --session claude
herdr-run --agent codex vm-tmux attach dev

herdr-layout save
herdr-layout restore
```

VM panes restore in menu-first mode. Layout restoration must not automatically start all VMs or rerun a missing agent session's launch command.

## Public interfaces

### herdr-run

```text
herdr-run [--agent claude|codex|none] [--env NAME=VALUE ...] [--] COMMAND [ARGS...]
```

Launcher options precede the command; arguments after the command belong to the command. `--` handles ambiguous command names and is recommended for scripts. Preserve the original argument vector. Never execute a reconstructed string with `eval` or a host shell.

Require valid caller pane context, resolving the calling pane rather than the UI-focused pane. Create an opaque mapping ID and associate it through Herdr pane metadata. Persist the mapping before launching ordinary commands. For `vm-tmux new`, keep creation intent unpublished until creation succeeds; only then persist and bind an immutable attachment mapping. A capture during pending creation sees an unmapped pane, never a mutable `new` record. Use a supervisor process if needed to keep the association valid while the child runs and to clear agent hints when the child exits. Do not assume that exporting a variable inside a wrapper changes the environment of an existing ancestor process.

Record a mapping ID, command argument array, absolute host working directory, explicit launch environment, inferred agent kind, and launch kind (`local`, `ssh`, or `vm-tmux`). The mapping ID is independent of editable titles and ephemeral Herdr pane IDs. Saved layout leaves embed the mapping ID; capture resolves it from live pane metadata. A private restore-launch entry point accepts an existing mapping ID, binds it to the newly created calling pane, and launches its saved argv/environment without rerunning detection or allocating a new mapping. Mapping records referenced by retained snapshot generations remain available after the live launcher exits. Verify association behavior when panes move between workspaces and receive new IDs.

An unmapped pane restores as a clearly labelled unavailable-command placeholder. Missing mapping records or working directories likewise produce visible recoverable placeholders, rather than guessing another command or directory. Never infer an executable from terminal output, a title, or a foreground process.

### herdr-layout

```text
herdr-layout [--session NAME] save [--file PATH]
herdr-layout [--session NAME] restore [--file PATH]
herdr-layout [--session NAME] restore --recover [--file PATH]
herdr-layout [--session NAME] open [--file PATH]
herdr-layout [--session NAME] autosave [--background] [--file PATH]
```

Select one explicit Herdr session/socket. Capture all workspaces and tabs in that session, their order and labels, split directions and ratios, pane mappings, working directories, focused workspace/tab/pane, and zoom state.

Store versioned snapshots and keep the previous valid generation. Default state lives under `${XDG_STATE_HOME:-$HOME/.local/state}/herdr-layout/`; trusted configuration lives under `${XDG_CONFIG_HOME:-$HOME/.config}/herdr-layout/`. Use private directories and files. Exact file names and generation retention count are implementation choices.

Enumerate and validate a complete capture before atomically replacing the latest snapshot. Retry boundedly if the hierarchy changes mid-capture. A failed API request is not an empty layout. Suspend snapshot publication during restoration, including concurrent capture processes.

Restore with one owner: this utility owns replay of its snapshots; coordinate Herdr native restoration so it cannot duplicate managed panes or start remote agents on the host. Never edit Herdr private state files as an API. Track restore progress by snapshot generation and target server instance using stable application identities. Repeating a completed generation in the same server is a no-op, including after the user closes or edits restored panes; restoring those panes again requires a deliberate new restore operation. After a server restart, a new server instance allows replay. A repeat or interrupted restore must not duplicate previously restored objects. A crash after Herdr creation but before journaling is handled by discovery of an atomically assigned application identity if the target API supports it; otherwise stop with an explicit uncertain-operation report and require reconciliation before retrying. Never claim crash-safe exactly-once creation without a supported primitive. Do not close or replace unrelated live workspaces during restore. Refuse ambiguous conflicts rather than guessing.

### vm-tmux

```text
vm-tmux attach PROFILE [--session NAME] [--menu-first] [--reclaim]
vm-tmux new PROFILE [--session NAME] [--cwd GUEST_PATH] -- COMMAND [ARGS...]
```

The first version starts an existing VM; disposable VM creation is outside this specification. Default tmux session name is `main`. This is an application convention, not reliance on tmux's most-recent-session selection.

Each named profile provides:

```json
{
  "schema_version": 1,
  "domain_uuid": "9c454452-26ce-46c6-95b8-ef753842186b",
  "libvirt_uri": "qemu:///session",
  "ssh_host": "127.0.0.1",
  "ssh_port": 23117,
  "ssh_user": "jan",
  "ssh_host_key_alias": "dev-vm-incarnation-123",
  "ssh_identity_file": "~/.ssh/lab-operator",
  "ssh_known_hosts_file": "~/.config/herdr-layout/known_hosts",
  "tmux_session": "main",
  "agent": "codex"
}
```

Profiles use JSON so the proposed implementation needs no YAML dependency. An optional `tmux_socket` selects an absolute guest socket path. The designated known-hosts file contains approved host keys or host-CA entries; checking remains strict.

Each VM mapping also stores its resolved domain UUID/incarnation, verified host identity, guest user, tmux socket, and exact session name, independently of profile defaults. Profile edits must retain compatible identity and target or require explicit remapping; changed defaults cannot redirect a restored pane. Profiles bind a particular VM UUID/incarnation to a verified SSH identity; endpoint reuse must not redirect old mappings to a replacement VM. Expand `~` only in designated host path fields. Credentials remain in trusted local files, not layout snapshots. Validate IDs, enum values, argument lengths, paths, and profile ownership.

Query `qemu:///session` under the invoking Unix user for observed state. Running requires no transition; paused requires resume; stopped without saved state requires start; managed-saved requires start from saved state. Unknown states or failed transitions are explicit errors. Serialize lifecycle transitions with a brief per-VM lock and recheck state after acquiring it. Never hold that lock for SSH attachment or menu interaction.

Wait boundedly for the intended SSH endpoint. Enforce host verification, approved identity files, no SSH agent forwarding, and no silent trust-on-first-use fallback. Authentication or identity failure must not cause a lifecycle retry or relaxed checks.

Attach over SSH with a PTY to the exact guest tmux session and optional socket. Remote SSH commands must quote each argument correctly: local argument arrays alone do not prevent remote shell interpretation. Use a reviewed fixed remote helper or a carefully encoded remote argument vector. The remote helper replaces its shell with the tmux client.

Ordinary attachment does not detach other clients. `--reclaim` explicitly requests tmux detach-other-clients. After any tmux detach, including a successful SSH exit, return to a menu instead of automatically reconnecting. Menu actions include attach, explicit reclaim, start/resume, refresh, and exit. A menu-first launch performs no guest startup or attachment until the user chooses an action.

`new` explicitly creates a session with the supplied guest command and working directory, then attaches immediately, and refuses to replace an existing exact-name session. Concurrent creates use tmux's exact-name creation result: only one succeeds and neither replaces the other. After successful creation, publish the durable mapping as `attach` to the resolved session; its restore command is `attach ... --menu-first`, never `new` and never the original workload command. `attach` reports a missing session without creating one. Closing a Herdr pane never destroys or shuts down the VM or terminates its guest tmux workload.

## Remote agent detection and environment restoration

Use one trusted, user-editable Bash script for detection, not a rule engine or TOML rule configuration. The launcher invokes the script with the original command arguments. The script examines a printable command representation using Bash regex matching and emits a small allowlisted environment result. It does not execute the supplied command.

Example `agent-env` script:

```bash
#!/usr/bin/env bash
set -euo pipefail
command_text="$*"
if [[ $command_text =~ ^(vm-tmux[[:space:]]+attach|ssh)[[:space:]] ]]; then
    if [[ $command_text =~ (^|[[:space:]])claude($|[[:space:]]) ]]; then
        printf '%s\n' 'HERDR_AGENT=claude'
    elif [[ $command_text =~ (^|[[:space:]])codex($|[[:space:]]) ]]; then
        printf '%s\n' 'HERDR_AGENT=codex'
    fi
fi
```

This is intentionally a simple heuristic. It can match an agent name in a session name or argument and does not prove what process actually runs remotely. It covers examples such as `ssh -t devbox codex` and `vm-tmux attach dev --session claude`. If a user enters an interactive SSH shell and later types `codex`, the initial command cannot reveal that change. Explicit `--agent` and a profile's agent field cover opaque commands such as `vm-tmux attach dev`.

Parse the script's output as data, never `eval` or source it. Initially accept only `HERDR_AGENT=claude` or `HERDR_AGENT=codex`; empty output means no hint. Reject malformed output, unsupported values, duplicate assignments, or a nonzero script exit before launching. Resolve the script from trusted host configuration, outside guest-writable project trees. A future need for more output variables can add explicit names without introducing a generic rule engine.

Precedence is explicit launcher environment/agent override, then script output, then profile agent fallback. Explicit `--agent none` suppresses script inference and profile fallback, is persisted, and removes any inherited agent hint. Reject contradictory explicit `--agent` and explicit `HERDR_AGENT` values. Persist only explicitly selected launch variables, not the entire inherited environment or secrets. Store resolved values, so restore does not rerun the detection script or reinterpret old mappings after the script changes. An explicit remap can adopt updated detection.

Herdr documents `HERDR_AGENT=claude` or `HERDR_AGENT=codex` on the host-visible foreground wrapper, allowing its existing screen manifests to classify remote output. Setting the hint only inside a guest does not expose it to the host. Do not export it globally into unrelated commands.

For VM wrappers, a known agent kind does not mean an agent is actively displayed while the wrapper is in its menu. Suppress the hint during menu/error states and apply it during actual guest attachment, using a supported API or appropriately scoped child environment. Verify foreground-process inspection on Linux with the chosen supervisor structure.

Saved pane launch environments must be passed through Herdr's supported layout launch environment or the trusted launcher. Regenerate Herdr caller context (`HERDR_PANE_ID`, workspace/tab/session/socket information) for new panes; never replay stale inherited context. Store desired VM agent intent separately from the menu process environment. VM restore launches the saved attachment target with `--menu-first` and without `HERDR_AGENT` on its menu/supervisor process; supply the saved hint only during actual SSH attachment and remove it again on detach or failure. A VM mapping originally created by `new` restores this same attachment form.

## Capability checks and current evidence

The inspected host has Herdr 0.8.0, bundled API protocol 19. Its schema contains `layout.export`, `layout.apply`, recursive split/pane nodes, and pane command arrays and environment maps. Layout export is per tab; complete recovery requires enumerating workspaces and tabs. There is currently no running default Herdr server. No VM was started during investigation.

Target the Herdr release the user upgrades to. The currently installed version is historical inspection evidence, not a compatibility constraint or blocker. Use that target release's public API and agent hints, record its schema/version for integration tests, and report actual unsupported capabilities clearly. Do not spend implementation effort supporting obsolete installed releases.

Primary reference: <https://herdr.dev/docs/agents/>. Design context: the original disposable VM design dossier, chapters `05-herdr-and-recovery.md` and `04-vm-lifecycle-and-sessions.md` (outside this repository).

## Verification and acceptance criteria

Use fixture tests for persistence, validation, Bash detection-script output, argument preservation, environment precedence, snapshot failure handling, interrupted restore, and mocked lifecycle transitions. Tag Bats fixture and manual suites according to dotfiles policy. Run meaningful real integration checks in a separate named Herdr session; only remove resources created by those checks.

1. Create panes through Herdr, launch htop, mc, and nano through `herdr-run`, rearrange/rename/close panes, save, and restore the final layout with the correct argument arrays and working directories.
2. Demonstrate stable mappings after pane moves, new Herdr IDs, and server restart. A deliberately closed pane remains absent.
3. Preserve workspace/tab order, split topology/ratios, focus, and zoom to the fidelity supported and tested by the API; report unsupported fields rather than claim full fidelity.
4. Kill capture midway or fail a tab export: the previous valid generation remains intact. Concurrent capture cannot publish a partial restore.
5. Repeat and interrupt restore: no duplicate managed objects and no deletion of unrelated live workspaces.
6. Test quoted filenames, spaces, shell metacharacters, and hostile labels: no unintended host execution, and exact arguments reach the intended guest command.
7. Match remote Claude/Codex commands, verify `HERDR_AGENT` classification on the upgraded target release, and restore the recorded hint even after the detection script changes.
8. Ordinary local programs and VM menus are not classified as agents. Exercise menu → attach → detach → menu and SSH failure with the actual foreground-process group. Verify `--agent none` suppresses false matches and remains suppressed after restore. Launcher exit removes stale live associations/hints without deleting already saved snapshots.
9. Running, paused, managed-saved, stopped, missing VM, unavailable SSH, expired/wrong identity, and missing tmux session produce distinct usable outcomes.
10. Two panes requesting startup serialize one effective lifecycle transition. A detach returns to menu; only explicit reclaim evicts other clients.
11. Layout restore leaves VM panes menu-first. Closing them leaves VMs and guest sessions available.
12. Snapshot inspection shows only explicit launch environment, no inherited secrets or stale Herdr context.
13. Save → restore → save retains mapping identities. A changed profile session default or VM replacement cannot redirect an old saved connection.
14. A mapped `new` restores only attachment, with both existing and missing guest sessions; neither case reruns creation.
15. Inject a crash between Herdr object creation and journal commit: discover the object safely or refuse uncertain replay without creating a duplicate.
16. Concurrent `new` calls, overlapping session-name prefixes, terminal resize, Ctrl-C, pane closure, and detach/error cleanup preserve exact targeting and usable terminal state.

Before starting or stopping qci, inspect only play1-owned qci processes, user-systemd units, and `virsh -c qemu:///session` domains. Never stop another Unix user's qci or VM resources. This implementation does not require qci by default.

## Implementation order and outstanding decisions

1. Verify target Herdr capabilities, agent hint support, and cold-recovery ownership in an isolated named session.
2. Implement `herdr-run`, private mapping storage, and the simple Bash environment script.
3. Implement full capture and idempotent restore; validate with local example programs.
4. Implement existing-VM profiles and `vm-tmux` lifecycle/SSH/tmux menu behavior.
5. Integrate VM mappings and verify menu-first recovery and agent hint scoping.

Snapshot retention, native restore coordination and the first VM/profile were settled during implementation. Event-driven autosaving was added as a follow-up; periodic timers remain outside scope.

## Review record

Reviewed by an Astra subagent on 2026-10-03. Incorporated its findings on restoring `new` as attachment, pinning resolved VM/session identities, rebinding saved mappings, handling uncertain restore crash windows, scoping agent hints to attachment, an explicit no-agent override, terminal/concurrent-session tests, standard-library JSON profiles, and unmapped-pane placeholders. The review approved the simple Bash detector approach and targeting the upgraded Herdr release. No utilities or live resources were changed by this specification work.

## Implementation and validation record

Implemented `herdr-run`, `herdr-layout`, and `vm-tmux` with Python standard-library modules, plus the simple editable Bash `agent-env` detector. The implementation keeps one previous valid snapshot. Unmapped/missing targets become placeholders. Initial external restoration uses a fresh named Herdr target and refuses original/native-restored workspace collisions; it does not edit native persistence. `restore --recover` recovers native-restored idle shells using source identities embedded in the capture, or a completed replay journal for the latest recovered identities. Saving a new generation in the same session remains recoverable without prior external replay. Every remaining native tab is revalidated on retry; Linux pidfds and temporary shell stops guard against starting a command between the idle check and replacement. `open` starts the target server if needed, performs that recovery, and opens the UI. Bare Herdr startup restores topology as shells and does not invoke external command replay. Uncertain create/apply crash windows refuse replay and require reconciliation or a fresh target. Journals are scoped by target socket and server instance.

Read the qdistro development/provisioning guide at `/home/play1/qdistro/qdistro/doc/dev.md`. Cloned the current Herdr source alongside the dossier at `../herdr/` (0.9.3, commit `5da0a01`) for authoritative public API documentation. The local installed Herdr was left unchanged; a temporary 0.9.3 binary, checked against the GitHub release asset SHA256 digest, was used for isolated integration checks.

Validation on 2026-10-03: 18 offline Bats fixtures plus 25 existing repository-policy checks passed. The real Herdr suite passed htop/mc/nano layout recovery, move/swap/rename, tab closure, focus/zoom, mapping rebinding, explicit environment persistence, and repeated restore. The opt-in disposable BIOS qdistro VM suite passed QGA-anchored SSH identity, exact guest tmux creation/attachment, detach/menu/reclaim, timeout to menu during pause, resume, managed save/start with the same guest process PID, and wrong-host-key rejection. The test-created VM/overlay were removed. No qci run was started or stopped. The VM profile had no virtiofs mounts, so these results do not establish virtiofs save/restore support.

Validation on 2026-10-04: reproduced loss of wrappers after native server restart, added cold recovery, and passed the 18 fixture tests plus the expanded real Herdr test. The live test now checks actual htop/mc/nano foreground processes before and after server restart, rejects recovery over a running sleep command, and tests `open` through a real PTY after another restart. Recovered the user's four VM panes in `recovery-test`, attached them to main/monitor/files/notes, and verified guest htop PID 1138, mc PID 1146, and nano PID 1141 remained unchanged. The persistent demo VM and attached recovery session remain running.

Follow-up Astra implementation review found four issues: original save/reopen and new saved generations lacked recovery ownership; interrupted cold retries skipped validation; SSH control timeouts escaped menu handling; capture during VM creation could retain a mutable `new` record. Fixed all four. Validation: 21 fixture Bats tests (including five targeted Python regression cases using isolated real shells), one expanded real Herdr integration test, and 25 repository-policy tests passed. The live test verifies original same-session recovery, a new generation saved after replay, repeated cold recovery via `open`, and actual htop/mc/nano processes. SSH control timeouts become handled errors, with creation outcome explicitly uncertain and no retry; pending VM creation publishes no mapping until a finalized attachment record can be bound. User sessions and the persistent VM were not stopped or modified during these fixes.

Fresh base validation on 2026-10-04: built a standalone boot image directly from the original signed openSUSE Tumbleweed cloud download with `vm-image-build`, without a qdistro-built disk. Ran canonical `setup/vm-baseweed` in an independent guest systemd service, rebooted, and passed four network/home checks. The real Herdr test saved four VM panes, restarted the server, restored attachment menus, attached, and verified unchanged htop/mc/nano guest PIDs. The immutable reusable image currently contains boot prerequisites; full canonical provisioning runs in the test VM. Fully provisioned golden-image sealing/publication remains future work. See `../doc/vm-image.md`.

Final Astra review on 2026-10-04 fixed stale-socket startup by probing the public API and waiting for a responsive replacement server. Offline tests preserve live/inaccessible listeners; the real test kills a server after a deterministic native persistence checkpoint and recovers htop/mc/nano through `open`. A crash before native persistence can leave topology identities inconsistent with the recovery journal; recovery safely refuses that mismatch and requires a fresh named target. The immutable-image fixture now uses a current test snapshot independently of production pins, so it does not expire with the checked-in cloud pin.

Autosaving follow-up: `herdr-run` starts a watcher after mapping registration, including new VM attachments and finalized `new` mappings. `open` starts one after recovery. A public event subscription tracks topology, focus and mapping changes, debounces bursts and skips unchanged captures. Watchers are unique per session/destination and stop with their server instance; they reuse manual save's locking, restore guards, validation and atomic retention. Real Herdr tests cover wrapper-triggered VM mapping/environment capture and automatic tab/split/closure updates. Offline tests protect unchanged generations, incomplete recovery and replacement-server boundaries.
