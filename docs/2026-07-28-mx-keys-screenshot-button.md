# MX Keys S "screenshot" button → Hyprland screenshot

**Date:** 2026-07-28
**Status:** Applied on the Vivobook. User-space only (`~/.config/hypr/bindings.conf`) — survives `omarchy update`. **No omarchy migration** (local doc; see "Making it reproducible" below if you want one).
**Device:** Logitech MX Keys S (Bluetooth), Danish (`dk`) ISO layout — `event10`, HID `046d:b378`.

---

## TL;DR

The dedicated "screenshot" icon key on the MX Keys S does **not** send Print Screen. Without Logi Options+ (Windows/Mac only), it fires **`Super + Shift + S`** — the *Windows* "Snip" screenshot shortcut. Hyprland had no binding for that combo, so the modifiers were dropped and only a stray **`s`** leaked into the focused window (looked like "the button just types s and takes no screenshot").

Fix — bind `Super+Shift+S` to the screenshot command:

```conf
# ~/.config/hypr/bindings.conf  (in the "Logitech MX Keys" section)
bind = SUPER SHIFT, S, exec, omarchy-capture-screenshot       # Screenshot button (MX Keys S -> Super+Shift+S)
```

Then `hyprctl reload`. Binding it also stops the stray `s`, because Hyprland now consumes the combo. This opens the normal region selector (drag a box, or click a window) — same as the `Print` key. For an instant full-screen grab instead, append a mode: `... exec, omarchy-capture-screenshot fullscreen`.

> The Omarchy default `bindings.conf` already ships this exact line **commented out** under "Logitech MX Keys" — it just needs uncommenting. Sibling commented lines map the Dictation button to `Super+H` and the Emoji button to `Super+.` (see caveat below).

---

## How we found it (evdev capture)

There's no key labelled "PrtSc" on this board and pressing the icon key only typed `s`, so we read the keyboard's raw evdev stream while pressing it — below the compositor, so it shows exactly what the hardware emits regardless of focus.

Prereqs: user is in the `input` group and `/dev/input/event*` is `crw-rw---- root input`, so **no root needed**. Find the node with `grep -A4 'MX Keys' /proc/bus/input/devices` (→ `Handlers=... event10`).

Minimal multi-device reader (decode `EV_KEY` + raw `MSC_SCAN` HID usage; keycode→name from the kernel header). Reading **all** keyboard-capable nodes at once matters — special keys sometimes route through a separate consumer-control node:

```python
#!/usr/bin/env python3
import struct, select, time, re, os
DEVS = ["/dev/input/event2", "/dev/input/event7", "/dev/input/event10"]  # internal kbd, asus hotkeys, MX Keys
names = {}
hdr = "/usr/include/linux/input-event-codes.h"
if os.path.exists(hdr):
    defs = {}
    for line in open(hdr):
        m = re.match(r"\s*#define\s+((?:KEY|BTN)_\w+)\s+(\S+)", line)
        if m:
            try: defs[m.group(1)] = int(m.group(2), 0)
            except ValueError:
                if m.group(2) in defs: defs[m.group(1)] = defs[m.group(2)]
    for n, c in defs.items(): names.setdefault(c, n)
FMT = "llHHi"; SZ = struct.calcsize(FMT)
fds = {}
for p in DEVS:
    try: f = open(p, "rb"); fds[f.fileno()] = (f, os.path.basename(p))
    except Exception as e: print("skip", p, e)
end = time.time() + 30
while time.time() < end:
    for fn in select.select([f for f in fds], [], [], 0.5)[0]:
        f, dev = fds[fn]; d = f.read(SZ)
        if len(d) < SZ: continue
        _, _, t, code, val = struct.unpack(FMT, d)
        if t == 4 and code == 4: print(f"[{dev}] scancode 0x{val & 0xffffffff:06x}")
        elif t == 1: print(f"[{dev}] KEY {val} {names.get(code, code)} (kc {code})")
```

Pressing the button produced, cleanly and repeatably, on `event10`:

```
[event10] KEY DOWN KEY_LEFTMETA  (kc 125)
[event10] KEY DOWN KEY_LEFTSHIFT (kc 42)
[event10] KEY DOWN KEY_S         (kc 31)   scancode 0x070016  (HID usage 0x16 = 's')
[event10] KEY up   KEY_S ... LEFTSHIFT ... LEFTMETA
```

→ `Super+Shift+S`. Not `KEY_SYSRQ` (99, Print Screen).

## Gotchas that cost us time (read this before capturing a mystery key)

- **Capture only the target key.** Our first captures were polluted by the user's own typing (including a stray `Super+9` and, in one run, the actual **Menu** key — `KEY_COMPOSE`/kc 127) that we briefly mistook for "the button." Press *only* the key under test, a few times, slowly, and nothing else. We even shipped a wrong first fix (bound the Menu key) before a clean multi-device capture showed the real `Super+Shift+S`.
- **`pkill -f keycap.py` self-matches** and kills the capture job (its own command line contains the pattern) → job dies with exit 144. Don't pkill by script name; just let the fixed deadline expire.
- **Foreground `sleep` is blocked** in this harness — launch the capture as a background task and read its log file.
- **Bluetooth re-enumeration** changes the `inputNN` number (input16 → input18 here) but the `eventNN` handler stayed `event10`. Re-grep `/proc/bus/input/devices` if the device reconnects.

## Verify

```bash
hyprctl reload && hyprctl configerrors        # must be empty
hyprctl binds | awk 'BEGIN{RS="\n\n"} /omarchy-capture-screenshot/'
# expect a block with:  modmask: 65 (Super+Shift)   key: S
```

## Notes

- **The numpad/F-row icon keys are Logitech "smart" keys.** On Linux (no Options+) they emit canned Windows host shortcuts — here the Snip combo `Super+Shift+S`. There is no raw Print Screen scancode available from this board.
- **Sibling buttons** (commented in `bindings.conf`): Dictation → `Super+H`, Emoji → `Super+.`. Capture them the same way before trusting those mappings — the "screenshot = Menu" mistake shows the printed intent isn't always what's emitted.
- **Revert:** restore `~/.config/hypr/bindings.conf` from its `.bak.*` backup (or re-comment the `SUPER SHIFT, S` line) and `hyprctl reload`.

## Making it reproducible (optional migration)

This is a one-line user-space edit, so it's documented rather than migrated. To re-apply on a fresh `omarchy-fast` bootstrap, add a migration that ensures the `bind = SUPER SHIFT, S, ...` line is present (uncommented) in `~/.config/hypr/bindings.conf`, mirroring `0000000014_asus_touchpad_corner_right_click.sh`.
