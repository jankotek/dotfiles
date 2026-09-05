# Multiple displays in graphical VMs

This is the known-good configuration for X11/XFCE guests displayed through
SPICE and virt-viewer/virt-manager. It supports three resizable viewer windows,
keeps the first guest output primary, and permits manual layout changes with
ARandR.

## VM graphics settings

Use these settings when creating a graphical Linux VM:

- Display: SPICE, listening locally only.
- Video model: Virtio (`virtio-vga`).
- 3D acceleration: disabled.
- Blob resources: disabled.
- Video memory: 256 MiB.
- Outputs/heads: three.
- Input: USB tablet for absolute pointer coordinates.
- SPICE agent channel: `com.redhat.spice.0`.
- QEMU guest-agent channel: `org.qemu.guest_agent.0` (recommended for
  administration, but not required for display resizing).

The important libvirt XML is:

```xml
<graphics type='spice'>
  <listen type='none'/>
  <image compression='off'/>
</graphics>

<video>
  <model type='virtio'
         device='virtio-vga'
         vram='262144'
         heads='3'
         primary='yes'
         blob='off'>
    <acceleration accel3d='no'/>
  </model>
</video>

<input type='tablet' bus='usb'/>

<channel type='spicevmc'>
  <target type='virtio' name='com.redhat.spice.0'/>
</channel>
```

`vram` is expressed in KiB, so `262144` is 256 MiB. A change to the video
model, head count, or blob setting requires a complete VM power-off and start;
a guest reboot does not recreate QEMU's emulated GPU.

### Keep blob resources off

Do not enable `blob` for this non-3D SPICE configuration. With the Tumbleweed
guest and QEMU configuration tested here, `blob='on'` caused the host to log:

```text
virtio_gpu_create_udmabuf: UDMABUF_CREATE_LIST: Invalid argument
```

The guest then repeatedly logged virtio-gpu response `0x1205` for command
`0x104`. After resizing or switching virtual terminals, secondary viewer
windows retained a text console or cursor, Xorg stopped updating them, and a
later resize could wedge or crash the graphical session. Changing to
`blob='off'` eliminated those errors.

Blob resources are independent of shared VM memory. If the VM mounts host
directories with virtiofs, it can still need:

```xml
<memoryBacking>
  <source type='memfd'/>
  <access mode='shared'/>
</memoryBacking>
```

Keep that memory backing for virtiofs even though GPU blobs are disabled.

## Guest setup

Install these packages:

- `spice-vdagent`
- `xrandr`/the distribution's XRandR utilities
- `arandr`
- `qemu-guest-agent` when host-side guest administration is wanted

ARandR is included in every graphical VM bootstrap:

- `setup/vm-baseweed`
- `setup/vm-xub26`

The Xubuntu scripts install both SPICE and QEMU guest agents. The Tumbleweed
base image already contains them, so `vm-baseweed` deliberately avoids
reinstalling or upgrading them while a guest-agent provisioning session is in
progress.

The bootstraps also add this kernel command-line setting:

```text
initcall_blacklist=sysfb_init,simpledrm_platform_driver_init
```

Without it, `simpledrm`/`sysfb` can temporarily claim DRM card 0 and leave the
virtio GPU at card 1. Some spice-vdagent versions then fail to map the SPICE
monitor to the XRandR output. The healthy mapping has virtio-gpu at
`/dev/dri/card0` and outputs named `Virtual-1`, `Virtual-2`, and `Virtual-3`.

Do not start `spice-vdagentd` by hand. It is the system daemon and already owns
`/run/spice-vdagentd/spice-vdagent-sock`. The per-desktop process is
`spice-vdagent` and should be started by the graphical session.

## Enable all viewer displays

1. Start the VM and open its console in virt-manager.
2. In the viewer, enable displays 1, 2, and 3. Each enabled display opens a
   separate viewer window.
3. Leave the windows open while the guest initializes the outputs.

An extra viewer window can initially say `Display output is not active`. The
virtio GPU may expose an unused head as a disconnected XRandR output with no
advertised modes. Enabling a viewer display alone does not always activate the
corresponding guest output.

The desktop autostarts `jan-vm-resize-display-loop`. It waits for XRandR output
change events, allows 0.15 seconds for SPICE to publish the updated mode list,
then calls the one-shot `jan-vm-resize-display` command.

The one-shot command:

1. Reads every virtio XRandR output.
2. Seeds a head with the first display's preferred mode when the head has no
   modes (`xrandr --addmode`).
3. Chooses each output's preferred mode, or its first mode as a fallback.
4. Activates and positions all outputs from left to right in one `xrandr`
   invocation, avoiding overlapping intermediate layouts.
5. Marks the first output primary.

Only one resize loop should run in the graphical session. Competing resize
loops can repeatedly modeset the display, produce stale SPICE geometry, and
break absolute mouse-coordinate translation.

## ARandR layouts

ARandR can be used to change monitor positions after all outputs are active.
The automatic script has a preservation gate: if every output already uses its
preferred resolution, `jan-vm-resize-display` leaves the positions unchanged
and exits. It may still mark the first output primary.

Change positions only when using this gate. If a monitor is inactive or is no
longer at its preferred resolution, the next viewer resize deliberately
rebuilds the safe left-to-right layout so every output is visible.

## Problems caused by forcing outputs on

Forcing an output is a workaround for a SPICE/virtio head that has no modes; it
is not harmless in every graphics stack:

- The viewer head must be enabled first. Activating a guest output for which no
  viewer display exists can leave an empty or inaccessible desktop region.
- Repeated `--off`/`--mode` cycles create intermediate framebuffer layouts.
  SPICE can observe those transient layouts and retain stale head geometry.
- A tight resize loop can race spice-vdagent and QEMU. Symptoms include dark
  displays, `Display output is not active`, and mouse coordinates that are
  correct only in a small part of the window.
- Switching from Xorg to a text VT lets the console take the virtio scanouts.
  With the broken blob path described above, Xorg could not reclaim secondary
  scanouts and the text cursor remained visible after returning to VT7.
- XRandR can report a mode and CRTC as active even when a SPICE viewer window
  is stale. Do not assume that repeatedly issuing the same XRandR mode is a
  reliable recovery operation.

The resize scripts therefore seed only heads that lack modes, use one combined
layout command, avoid unnecessary modesets, and stop rearranging a healthy
preferred-resolution layout.

## Diagnostics

Guest output state:

```bash
xrandr --query
ls -l /dev/dri
journalctl -b -k | grep -Ei 'virtio_gpu|drm'
```

Expected XRandR state has all enabled heads with a current geometry, for
example:

```text
Virtual-1 connected primary 1920x1000+0+0
Virtual-2 connected 1920x1000+1920+0
Virtual-3 connected 1920x1000+3840+0
```

Host-side configuration and errors:

```bash
virsh -c qemu:///session dumpxml VM_NAME
grep -E 'UDMABUF|virtio_gpu' ~/.cache/libvirt/qemu/log/VM_NAME.log
```

Check the active QEMU process after a cold start if necessary. The known-good
device has `max_outputs=3` and `blob=false`.

If the guest reports that `/run/spice-vdagentd/spice-vdagent-sock` is already
in use, the system daemon is already running; start or repair the user-session
`spice-vdagent` instead. Mutter D-Bus warnings are expected under XFCE and are
not themselves a resize failure.

If displays become stuck on a text console and virtio-gpu invalid-resource or
UDMABUF errors are present, set `blob='off'` persistently and perform a full VM
power cycle. A guest reboot alone is insufficient.
