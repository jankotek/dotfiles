---
name: host-lab-vm-cli
description: "Operate command-line VMs in this host's local libvirt lab: bootstrap disposable guests, start them through QGA, execute commands, and run health checks. Use for local CLI VM work in this repository; do not use for GUI automation, cloud VMs, or production virtualization."
---

# Host Lab VM CLI

Use the repository's helpers instead of rebuilding libvirt or QEMU Guest Agent
calls. Resolve the repository root first:

```bash
repo=/opt/jan
[[ -x $repo/usr/bin/vm-exec ]] || repo=$(git rev-parse --show-toplevel)
```

The lab uses `qemu:///session`. Keep that URI explicit in direct `virsh`
calls; a domain under `qemu:///system` is a different VM.

## Inspect before acting

```bash
virsh -c qemu:///session list --all
virsh -c qemu:///session domstate "$vm"
virsh -c qemu:///session domblklist "$vm" --details
```

Treat base domains and disks as reusable, read-only parents. A base must be
shut off before creating its qcow2 overlay. Only force-stop, undefine, or
delete a verified disposable target. Resolve disks through `domblklist` and
check that another domain does not use them before deletion.

## Bootstrap

Prefer an end-to-end harness for a clean bootstrap test. It creates an
overlay, provisions and reboots the guest, runs tests, and cleans up:

```bash
"$repo/test/test-vm-deploy.sh"                 # Ubuntu 26 / xub26
"$repo/test/test-vm-baseweed-deploy.sh"        # Tumbleweed / baseweed
```

The Ubuntu harness accepts `BASE_VM`, `BASE_DISK`, `SETUP_SCRIPT`, and
`VM_NAME_PREFIX`. The Tumbleweed harness accepts `BASE_VM` and `BASE_DISK`.
Use `--keep` only when the user wants the provisioned VM retained.

To recreate a named disposable VM from an existing base:

```bash
"$repo/usr/bin/vm-reset" "$vm" "$base_vm"
```

This verifies the overlay relationship and asks for the target VM name before
deletion. Do not pass `--yes` unless unattended destructive reset is explicitly
intended. Reset creates the clone but does not provision it.

If a required base domain or disk is absent, identify the image-specific base
builder. Do not improvise an installer workflow or substitute another image.

## Start and execute

Start the guest and wait up to 120 seconds for QGA:

```bash
"$repo/usr/bin/vm-wait" "$vm"
```

Prefer literal argv execution, especially for user-provided arguments:

```bash
"$repo/usr/bin/vm-exec" "$vm" --argv uname -a
"$repo/usr/bin/vm-exec" "$vm" --argv --user jan -- id
```

Use shell mode only for guest-side pipelines, redirections, globbing, or
environment assignment:

```bash
"$repo/usr/bin/vm-exec" "$vm" 'ip route show default | grep -q .'
```

Commands run as root by default. Preserve and report the guest exit status.
Long package transactions may emit only periodic waiting messages; do not
launch the same command while its QGA execution is active.

After reboot, allow the old QGA connection to disappear before waiting:

```bash
virsh -c qemu:///session reboot "$vm"
sleep 5
"$repo/usr/bin/vm-wait" "$vm"
```

QGA readiness does not guarantee DHCP or DNS readiness. Run the lightweight,
non-mutating smoke check when network health matters:

```bash
"$repo/usr/bin/vm-smoke" "$vm"
```

After disposable work, confirm the target domain and overlay are gone and the
base remains shut off. For a retained VM, report its name, state, and backing
base. Do not shut down a retained VM unless the request calls for it.
