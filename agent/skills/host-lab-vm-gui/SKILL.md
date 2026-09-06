---
name: host-lab-vm-gui
description: "Inspect and automate graphical VMs in this host's local libvirt lab using screenshots, window activation, mouse actions, typing, and keys. Use for local VM GUI work after the guest exists; do not use for VM bootstrap or command-line-only administration."
---

# Host Lab VM GUI

Resolve the repository root and identify the exact session VM before acting:

```bash
repo=/opt/jan
[[ -x $repo/usr/bin/vm-exec ]] || repo=$(git rev-parse --show-toplevel)
virsh -c qemu:///session list --all
virsh -c qemu:///session domstate "$vm"
```

This skill operates an existing guest. Use the CLI VM skill when the domain
must be cloned, provisioned, started, or diagnosed through QGA.

## Capture and inspect screenshots

Start the VM first, then capture its display to an explicit host path:

```bash
shot="/tmp/${vm}-$(date +%Y%m%d-%H%M%S).png"
"$repo/usr/bin/vm-gui" "$vm" screenshot "$shot"
```

Open the resulting local file with the available image-viewing tool. Report
the path when handing the image to the user. Keep successive screenshots under
distinct names when comparing state across actions.

A black or stale screenshot usually means the graphical session is not ready.
Wait briefly and capture again, or inspect the display manager through the CLI
VM skill; QGA readiness alone does not imply desktop readiness.

## Interact with the desktop

Use `vm-gui` for visible desktop actions:

```bash
"$repo/usr/bin/vm-gui" "$vm" start mousepad
"$repo/usr/bin/vm-gui" "$vm" activate Mousepad
"$repo/usr/bin/vm-gui" "$vm" click 400 300
"$repo/usr/bin/vm-gui" "$vm" type 'hello world'
"$repo/usr/bin/vm-gui" "$vm" key ctrl+s
```

Available operations are `screenshot`, `start`, `activate`, `click`,
`rightclick`, `doubleclick`, `drag`, `scroll`, `type`, `key`, `windowsize`,
`windowmove`, and `wait`.

Capture a screenshot before coordinate-based actions, use its actual dimensions
to choose coordinates, then capture another screenshot to verify the result.
Prefer window activation and keyboard navigation when coordinates would be
fragile. Do not infer success solely from a zero exit status when the expected
result is visual.

GUI actions currently assume the `jan` user, X11 display `:0`, and `xdotool`.
If the guest uses another user, display, or Wayland, stop using coordinate
automation and diagnose the session through the CLI VM skill.

All `vm-gui` guest arguments use `vm-exec` literal argv transport. Pass an
application and its arguments separately to `start`; do not wrap them in a
shell command string.

Treat text passed to `type` as keyboard input to the guest. Do not type secrets
or confirm destructive dialogs unless that exact action is authorized. Avoid
leaving sensitive information visible in screenshots.
