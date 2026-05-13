# vm-gui — GUI automation for VMs

Interact with the VM's graphical desktop from the host CLI. Uses `xdotool` inside the guest (via `vm-exec`) and `virsh screenshot` for visual feedback.

## Prerequisites

- VM must have `xdotool` installed (`apt install xdotool`)
- A SPICE viewer must be connected (e.g. `virt-manager --show-domain-console <vm>`) for the display to be active
- Guest agent must be running

## Commands

```bash
vm-gui <vm> screenshot [file]              # Capture display (default: /tmp/vm-screenshot.png)
vm-gui <vm> start <command>                # Launch a GUI app (waits 2s for startup)
vm-gui <vm> activate <title>               # Focus window by title (wildcard match)
vm-gui <vm> click <x> <y>                  # Left-click at pixel coordinates
vm-gui <vm> rightclick <x> <y>             # Right-click (context menu)
vm-gui <vm> doubleclick <x> <y>            # Double-click (open files)
vm-gui <vm> drag <x1> <y1> <x2> <y2>      # Drag and drop
vm-gui <vm> scroll <up|down> [clicks]      # Mouse wheel (default: 3 clicks)
vm-gui <vm> type <text>                    # Type text (100ms between keystrokes)
vm-gui <vm> key <key> [key...]             # Send key combo: Return, Tab, ctrl+c, alt+F4
vm-gui <vm> windowsize <title> <w> <h>     # Resize window by title
vm-gui <vm> windowmove <title> <x> <y>     # Move window by title
vm-gui <vm> wait [seconds]                 # Sleep (default: 2)
```

## Sample script: type in Mousepad

```bash
#!/bin/bash
VM=test-260401-1810

# Open mousepad
vm-gui $VM start mousepad
vm-gui $VM activate Mousepad

# Type a message
vm-gui $VM type "Hello World from vm-gui!"
vm-gui $VM key Return
vm-gui $VM type "This is line two."
vm-gui $VM key Return Return
vm-gui $VM type "Goodbye!"

# Save the file
vm-gui $VM key ctrl+shift+s          # Save As
vm-gui $VM wait 2
vm-gui $VM type "/home/jan/doc/test.txt"
vm-gui $VM key Return

# Take a screenshot to verify
vm-gui $VM screenshot /tmp/mousepad-result.png
```

## More examples

### Navigate Thunar file manager

```bash
vm-gui $VM start thunar
vm-gui $VM activate Thunar
vm-gui $VM doubleclick 200 150       # open a folder
vm-gui $VM wait 1
vm-gui $VM rightclick 300 200        # context menu
vm-gui $VM screenshot /tmp/thunar.png
```

### Resize and move windows

```bash
vm-gui $VM windowsize Mousepad 800 600
vm-gui $VM windowmove Mousepad 100 50
vm-gui $VM screenshot /tmp/resized.png
```

### Scroll through a document

```bash
vm-gui $VM activate Mousepad
vm-gui $VM scroll down 10
vm-gui $VM wait 1
vm-gui $VM scroll up 5
```

### Drag and drop

```bash
vm-gui $VM drag 100 600 400 300      # drag desktop icon to new position
```

### Keyboard shortcuts

```bash
vm-gui $VM key ctrl+c                # copy
vm-gui $VM key ctrl+v                # paste
vm-gui $VM key ctrl+z                # undo
vm-gui $VM key alt+F4                # close window
vm-gui $VM key ctrl+shift+t          # new terminal tab
vm-gui $VM key super                 # open app menu
```

## Supported characters for `type`

Letters (auto-shifted for uppercase), digits, and:

| Character | Key name |
|-----------|----------|
| space | `space` |
| `.` `,` `/` `-` `=` `;` `'` `` ` `` `[` `]` | literal |
| `!` `@` `#` `$` `%` `^` `&` `*` `(` `)` | shift+digit |
| `_` `+` `:` `"` `<` `>` `?` `~` | shift+key |

## How it works

1. `vm-gui` runs on the **host**
2. It calls `vm-exec` which sends commands to the **guest agent** (QEMU guest agent over virtio-serial)
3. Inside the guest, commands run as `jan` with `DISPLAY=:0` via `xdotool`
4. `virsh screenshot` captures the SPICE framebuffer from the host side

## Screenshot resolution

By default, the VM renders at whatever size the SPICE viewer window is (often small). For readable screenshots, set a fixed resolution first:

```bash
vm-gui $VM start "xrandr --output Virtual-1 --mode 1920x1080"
vm-gui $VM screenshot /tmp/hires.png
```

This works even with a SPICE viewer connected. The `jan-vm-resize-display-loop` autostart script only reacts to spice client resize events — setting resolution via xrandr inside the guest does **not** trigger it. However, if the user resizes the virt-manager window while you're working, the resize loop will override your resolution back to match the viewer.

To avoid interference: don't resize the virt-manager window during automated screenshot sequences.

## Limitations

- **SPICE viewer required**: without a connected viewer, `virsh screenshot` shows "Display output is not active". Open the VM in virt-manager first: `virt-manager --show-domain-console <vm>`
- **No OCR**: screenshots are images — coordinates must be known or estimated
- **Typing speed**: 100ms per keystroke; fast enough for automation, slow enough for apps to keep up
- **JSON escaping**: `vm-exec` passes commands via QEMU guest agent JSON protocol — some special characters in arguments may need escaping
- **Resize loop interference**: the VM's `jan-vm-resize-display-loop` auto-matches resolution to the spice viewer window size. It won't fight your xrandr calls, but resizing the viewer window will override them

## Adding xdotool to VM setup

Add `xdotool` to the package list in `setup/vm-xub24` if you want it available on all test VMs.
