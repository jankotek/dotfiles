# Monitor Power Cycling on TTY Switch

## Problem

Multiple users on different TTYs (KDE Wayland / KWin, SDDM display manager).
When switching between TTYs, monitors turn on/off repeatedly until they stabilize.

## Current Setup

- GPU: AMD Radeon Strix Halo (amdgpu)
- Displays:
  - eDP-1: 1920x1200 @ 60Hz (laptop panel, scale 1.25)
  - HDMI-A-1: 3840x2160 @ 60Hz (LG, scale 1.5, rotated 90)
  - DP-8: 3840x2160 @ 60Hz (LG, MST path -1, scale 1.5)
  - DP-9: 3840x2160 @ 60Hz (LG, MST path -2, scale 1.5, rotated 90)
- DP-8 and DP-9 are daisy-chained via DisplayPort MST
- Config file: `~/.config/kwinoutputconfig.json`

## Root Cause

When switching TTYs, the kernel revokes DRM master from the current compositor
and grants it to the new one. The new compositor then:

1. Re-probes all outputs (EDID re-read)
2. Re-applies modesetting
3. Each monitor sees a new signal and power cycles

MST (DisplayPort daisy-chain) makes it worse because MST link renegotiation
adds extra cycles.

## Fix 1: adam user permissions (immediate)

The `adam` user is missing `render` and `video` group membership, causing
modeset failures and retries which amplify the flickering:

```bash
sudo usermod -aG render,video adam
```

Adam needs to log out and back in for this to take effect.

## Fix 2: Disable EDID re-probing via kernel firmware cache (most effective)

Force the kernel to cache EDID so monitors aren't re-probed on every switch.

Extract current EDID for each output:

```bash
cat /sys/class/drm/card1-eDP-1/edid > /tmp/edid-eDP-1.bin
cat /sys/class/drm/card1-HDMI-A-1/edid > /tmp/edid-HDMI-A-1.bin
cat /sys/class/drm/card1-DP-8/edid > /tmp/edid-DP-8.bin
cat /sys/class/drm/card1-DP-9/edid > /tmp/edid-DP-9.bin
```

Place files in firmware directory:

```bash
sudo mkdir -p /lib/firmware/edid
sudo cp /tmp/edid-*.bin /lib/firmware/edid/
```

Add to kernel command line in `/etc/default/grub` (`GRUB_CMDLINE_LINUX`):

```
drm.edid_firmware=eDP-1:edid/edid-eDP-1.bin,HDMI-A-1:edid/edid-HDMI-A-1.bin,DP-8:edid/edid-DP-8.bin,DP-9:edid/edid-DP-9.bin
```

Then regenerate grub and reboot:

```bash
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

## Fix 3: Matching KWin output config for both users

Copy the working monitor layout to adam so both compositors apply the same
mode on resume (avoiding unnecessary mode changes):

```bash
sudo mkdir -p /home/adam/.config
sudo cp /home/playai/.config/kwinoutputconfig.json /home/adam/.config/
sudo chown adam:adam /home/adam/.config/kwinoutputconfig.json
```

## Fix 4: Disable DPMS in KWin

Prevents KWin from sending power-off signals during the handoff.
Add to each user's `~/.config/kwinrc`:

```ini
[Effect-dpms]
LockAfterLockScreen=false

[Wayland]
DpmsLockAfterLockScreen=false
```

## Fix 5: amdgpu display core option

```bash
echo "options amdgpu dc=1 dpm=1" | sudo tee /etc/modprobe.d/amdgpu.conf
```

Ensures Display Core is explicitly enabled for consistent mode restoration.

## Priority

1. Fix adam's group membership (Fix 1) - immediate, no reboot
2. EDID firmware cache (Fix 2) - most effective, requires reboot
3. Copy KWin config (Fix 3) - quick
4. DPMS and amdgpu tweaks (Fix 4, 5) - supplementary
