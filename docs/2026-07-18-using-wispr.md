# Using Wispr Flow on Omarchy (Hyprland) — plan & postmortem

**Date:** 2026-07-18
**Status:** Draft plan. Wispr Flow was installed, wedged Hyprland, and was removed the same day. This doc captures *why* it broke and *how* a hardened install could work — nothing here is applied yet.

---

## TL;DR / recommendation

- Wispr Flow **has no official Linux build**. We used the unofficial port ([`wispr-flow-linux`](https://github.com/wispr-flow-linux/wispr-flow-linux), AUR `wispr-flow-appimage`).
- It injects text through an **in-process `/dev/uinput` virtual keyboard** and detects its hotkey by **passively reading `/dev/input`**. It does **not** exclusively grab the keyboard — so Omarchy already keeps control of every key. Your instinct ("catch a few keys, hand the rest to Omarchy") is basically how it already works; the danger isn't key-grabbing.
- **What actually wedged Hyprland:** before every injected paste, the helper *sweeps all input devices and force-releases/re-presses modifier keys through its virtual keyboard* to avoid corrupting the injected text. The project itself flags this as "compositor-dependent" (it "leans on the compositor's shared seat xkb-state"). On Hyprland that most likely left the seat with a **stuck modifier**, which makes the whole desktop behave as if Super/Ctrl/Alt is held down.
- **There is no external trigger** (no CLI, no D-Bus) to start/stop dictation, so we **cannot** use the clean Omarchy pattern of "Hyprland binds a key → toggles the dictation tool." Wispr must watch evdev itself.

**Recommendation:** For a genuinely clean Hyprland experience, prefer a **Wayland-native dictation tool** that Omarchy already anticipates (see [Path A](#path-a-recommended--wayland-native-dictation)). If you specifically want Wispr Flow, [Path B](#path-b--hardened-wispr-flow-install) is a hardened, reversible setup with a kill-switch — but treat it as experimental.

---

## What happened on 2026-07-18 (postmortem)

1. Installed AUR `wispr-flow-appimage`, then ran a migration that added the `/dev/uinput` udev rule, set `chrome-sandbox` setuid, and confirmed `input`-group membership. `wispr-flow --doctor` went all-green.
2. Launched Wispr Flow to sign in. Hyprland input became unusable ("really fucked up my hyprland").
3. Diagnosis: Hyprland (the compositor) was still alive. The culprit was **live**, not config:
   - The helper (`wispr-flow-linux-helper`) had created a virtual keyboard device **"Wispr Flow Linux Helper"** that had claimed the `kbd`/`sysrq`/`rfkill` handlers.
   - **No Hyprland config file was modified** — `grep -rin wispr ~/.config/hypr` was empty. Configs were intact.
4. Fix that worked: `pkill wispr` → the virtual keyboard device vanished and input returned instantly; `hyprctl reload` to refresh. Then the package + migration + udev rule were removed.

Recorded as memory `wispr-flow-wedges-hyprland`.

### Most likely root cause

From the port's own design notes ([`learnings/wayland-injection.md`](https://github.com/wispr-flow-linux/wispr-flow-linux/blob/main/docs/learnings/wayland-injection.md)):

> Right before a chord, the helper sweeps every readable `/dev/input/event*` with `EVIOCGKEY`, releases any modifier the user is physically holding, runs the chord, then restores it afterward… clearing a modifier held on *another* device through the virtual device leans on the compositor's shared seat xkb-state, so it's **compositor-dependent**.

On KWin (their primary validation target) this is tuned; on Hyprland the release/restore dance can desync the seat's xkb modifier state → a **stuck modifier** → every keypress behaves like it has Super/Ctrl/Alt held → keybindings misfire, typing breaks. That matches the symptom exactly, and it clears the instant the helper process dies.

Contributing factors: a second seat keyboard appearing mid-session, and the possibility of Wispr's default hotkey colliding with an Omarchy `SUPER`-combo (both see every key).

---

## How Wispr Flow works on Wayland/Hyprland

Understanding the mechanism is what makes the plan safe. Sources: the port's [`compatibility.md`](https://github.com/wispr-flow-linux/wispr-flow-linux/blob/main/docs/compatibility.md), [`configuration.md`](https://github.com/wispr-flow-linux/wispr-flow-linux/blob/main/docs/configuration.md), [`decisions.md`](https://github.com/wispr-flow-linux/wispr-flow-linux/blob/main/docs/decisions.md), and the [`helper`](https://github.com/wispr-flow-linux/helper) repo.

| Concern | Mechanism | Interaction with Hyprland |
|---|---|---|
| **Text injection** | In-process `/dev/uinput` virtual keyboard (like `ydotool`, but no daemon/root). Needs `/dev/uinput` write access. | Creates a virtual seat keyboard. The pre-chord **modifier sweep** is the risky part (see above). |
| **Paste** | Owns the clipboard via `ext-data-control`, then injects a `Ctrl+V` chord. | Fine, *except* the chord's cross-device modifier handling. |
| **Push-to-talk hotkey** | Helper/app **passively reads** `/dev/input/event*` (needs read access). **No `EVIOCGRAB`** — not an exclusive grab. | Both Hyprland and Wispr see every key. Wispr's key is *not* stolen from Hyprland. |
| **Active-app / selection** | AT-SPI on wlroots (Sway/Hyprland). Some apps (bare terminals) expose nothing. | Harmless; degrades to empty. |
| **Trigger dictation externally** | ❌ None. The helper only speaks a private stdio IPC with the Electron app. | We cannot bind a Hyprland key to "start Wispr dictation." |

The port lists **Hyprland (wlroots): wayland-uinput + AT-SPI ✓** as validated — but validation is clearly KWin-first, and the modifier-sweep caveat is exactly the wlroots-fragile bit.

---

## The design question: "catch a few keys, hand the rest to Omarchy"

Answered directly:

- **Wispr never takes exclusive control of the keyboard.** It only *listens* (passive evdev read) for its one configured shortcut. Every other key already goes straight to Omarchy/Hyprland. So there's nothing to "hand back" — that part is already true.
- **What we *can* control:** which single key Wispr listens for. Pick one that Hyprland does **not** bind and that types nothing on its own, and there's zero collision.
- **What we *cannot* do (the thing you were hoping for):** have Hyprland own the trigger and forward it to Wispr. Wispr has no external trigger API. Contrast with Omarchy's built-in dictation slot in `bindings.conf`:

  ```
  # bind = SUPER, H, exec, voxtype record toggle   # Dictation Button
  ```

  That clean model works because `voxtype` exposes a `record toggle` **command**. Wispr doesn't. This is the core architectural reason Wispr is a worse fit for Hyprland than a native tool.

---

## Path A (recommended) — Wayland-native dictation

If the goal is "dictation that behaves on Omarchy," use a tool designed for the Hyprland-bind model. These let **Hyprland own the key** and just run a command — no evdev monitoring, no cross-device modifier sweep, no rogue seat keyboard:

- **voxtype** — the tool Omarchy's own commented keybind references. `voxtype record toggle`.
- **[whisrs](https://github.com/y0sif/whisrs)** — "Linux-first voice-to-text for Wayland, X11, Niri, Hyprland & Sway," Rust.
- **[hyprwhspr-rs](https://github.com/better-slop/hyprwhspr-rs)** — "Wispr Flow alternative for Hyprland."

Wiring is a one-liner in `~/.config/hypr/bindings.conf`, e.g. uncommenting the `SUPER, H` slot and pointing it at the tool's toggle command. Text injection on these still uses uinput/`wtype`, but it's fired by *you* pressing a compositor-owned key, not by a background process poking the seat.

**This is the setup I'd build if you want it to "just work."** Say the word and I'll set one up.

---

## Path B — hardened Wispr Flow install

Only if you specifically want Wispr Flow's transcription. This is experimental; bring it up with the kill-switch already in place.

### B1. System prerequisites (idempotent — a migration)

Re-introduce a cleaned-up `migrations/00000000NN_install_wispr_flow.sh` (the earlier one, **minus** the redundant desktop entry that caused the walker duplicate). It should:

1. `yay -S --needed wispr-flow-appimage`
2. Install the `/dev/uinput` udev rule (`GROUP="input", MODE="0660", TAG+="uaccess"`) and apply live (`chgrp`/`chmod`/`setfacl`).
3. `chmod 4755` the setuid `chrome-sandbox`.
4. Ensure `wl-clipboard` is installed (**hard runtime dep** on Wayland — paste/selection fail without it).
5. **Do not** create a `.desktop` file (the package ships `/usr/share/applications/wispr-flow-appimage.desktop`).
6. **Do not** autostart it.

The exact script is in the [Appendix](#appendix-migration-script). It's ready to drop in when you decide to proceed.

### B2. Hyprland window rules (tame the recorder overlay)

Wispr's window class is `Wispr Flow` (it launches with `--class=Wispr Flow`). Add these at the **bottom of `~/.config/hypr/hyprland.conf`** (under "Add any other personal Hyprland configuration below"). Syntax is the Hyprland 0.53+ form Omarchy uses — modeled on `webcam-overlay.conf`:

```
# --- Wispr Flow: keep the recorder overlay from stealing focus / tiling ---
windowrule = float on,            match:class ^(Wispr Flow)$
windowrule = pin on,              match:class ^(Wispr Flow)$
windowrule = no_initial_focus on, match:class ^(Wispr Flow)$
windowrule = no_dim on,           match:class ^(Wispr Flow)$
# park it bottom-centre, out of the way (tweak to taste)
windowrule = move (monitor_w-window_w)/2 (monitor_h-window_h-60), match:class ^(Wispr Flow)$
```

> Verify the class/title once it's running: `hyprctl clients | grep -iA3 wispr`. If the recorder overlay has a distinct title from the settings window, split the rules by `match:title` so only the overlay gets `no_initial_focus`.

### B3. Kill-switch keybind (do this FIRST)

Before ever launching Wispr, add a panic button to `~/.config/hypr/bindings.conf` so a wedge is one chord away from fixed:

```
# Panic: kill Wispr Flow if it wedges input, then refresh the seat
bindd = SUPER SHIFT, ESCAPE, Kill Wispr Flow, exec, pkill -9 wispr; hyprctl reload
```

`hyprctl reload` after the kill helps re-sync input. (If a modifier still feels stuck, tap both Ctrl keys once.)

### B4. In-app settings (the "few keys" part)

In Wispr's **Settings → Shortcuts**:

- **Push-to-talk key: `Right Ctrl`.** It exists on the Vivobook, Omarchy binds nothing to it, and held alone it types nothing and triggers no Hyprland action — so it's inert to Omarchy but visible to Wispr's evdev reader. (Alternative: `Right Alt`/AltGr — free here because `grp:alts_toggle` is disabled in `input.conf`. Avoid anything in a `SUPER` combo.)
- **Disable hands-free / double-tap-to-toggle** if available — prevents accidental always-on activation.
- Keep it **push-to-talk** (hold → speak → release). Because injection happens *after* you release the key, the modifier sweep runs against a clean state, which minimizes the stuck-modifier risk.

### B5. Optional env knobs

- `WISPR_USE_WAYLAND=1` forces native Wayland (Ozone). Electron 42 auto-detects, so only set it if window/IME behaves oddly.
- `WISPR_DISABLE_GPU=1` if the window renders blank.
- Set persistently via `~/.profile` only after validation.

---

## Test protocol (safe bring-up)

Do these **in order**. The point is to never be more than one keystroke from recovery.

1. Add the **kill-switch** (B3) and reload: `hyprctl reload`. Confirm `SUPER SHIFT ESC` is live.
2. Keep a **TTY escape hatch** ready: `Ctrl+Alt+F2` gets you a text console where you can `pkill -9 wispr` if the GUI is fully unresponsive; `Ctrl+Alt+F1` returns.
3. Add the **window rules** (B2), reload.
4. Launch Wispr from a terminal so you see logs: `wispr-flow` (watch `~/.cache/wispr-flow/launcher.log`). Sign in.
5. Set the **hotkey to Right Ctrl** and disable hands-free (B4).
6. Focus a scratch text field. Hold **Right Ctrl**, say one short sentence, release. Watch for: (a) text injected correctly, (b) **no stuck modifier afterward** — type normally and confirm keys aren't behaving as if Super/Ctrl is held.
7. If anything feels off, hit **`SUPER SHIFT ESC`** immediately. That's a successful test of the escape path, not a failure.
8. Only after several clean cycles, consider leaving it running. **Do not autostart** until you trust it.

**Abort criteria:** if a stuck modifier recurs after the kill/reload, Wispr's uinput path is incompatible with this Hyprland build — stop and switch to Path A.

---

## Rollback / full removal (what we did today)

```bash
pkill -9 wispr                                   # kill live processes (removes the virtual keyboard)
hyprctl reload
sudo pacman -R wispr-flow-appimage               # uninstall the app
sudo rm -f /etc/udev/rules.d/99-uinput-wispr.rules
sudo udevadm control --reload-rules
rm -rf ~/.config/"Wispr Flow"                     # optional: wipe app data/login
# remove the migration from repo + ~/.local/share/omarchy/migrations/ + its state marker
# remove the B2/B3 blocks from hyprland.conf / bindings.conf
```

---

## Open questions / to verify when proceeding

- Exact **window class vs. title** of the recorder overlay vs. the settings window (`hyprctl clients` while running) — to scope `no_initial_focus` precisely.
- Whether Wispr's Linux build actually **honors the Settings → Shortcuts key** for evdev detection, or ships a fixed default. If fixed, we're stuck with whatever it picks (another Path-A argument).
- Does `chrome-sandbox` need re-`chmod 4755` after each **package update**? (The migration should be re-runnable to fix it; a pacman hook is the durable alternative.)
- Confirm no **hotkey collision**: whatever Wispr defaults to must not match a `SUPER`-combo in `bindings.conf`.

---

## Appendix: migration script

Cleaned-up version of the 2026-07-18 migration, **without** the desktop-entry step, **plus** a `wl-clipboard` check. Drop in as `migrations/00000000NN_install_wispr_flow.sh` when ready (setup.sh renumbers it). Kept out of the repo for now since Wispr is uninstalled.

```bash
#!/bin/bash
set -eEo pipefail
echo "melk: Install Wispr Flow + wire up for Wayland/Hyprland (see docs/2026-07-18-using-wispr.md)"

PKG="wispr-flow-appimage"; APPDIR="/opt/wispr-flow-appimage"

# 1. Package
pacman -Q "$PKG" &>/dev/null || { yay -S --noconfirm --needed "$PKG"; sudo updatedb; }

# 2. Text injection: /dev/uinput
RULE="/etc/udev/rules.d/99-uinput-wispr.rules"
echo 'KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"' \
  | sudo tee "$RULE" >/dev/null
sudo udevadm control --reload-rules
sudo usermod -aG input "$USER"
if [ -e /dev/uinput ]; then
  sudo chgrp input /dev/uinput; sudo chmod 0660 /dev/uinput
  command -v setfacl >/dev/null && sudo setfacl -m "u:${USER}:rw" /dev/uinput
fi

# 3. Electron sandbox (setuid). NOTE: a package update can reset this — re-run then.
SANDBOX="$APPDIR/usr/lib/wispr-flow/chrome-sandbox"
[ -f "$SANDBOX" ] && { sudo chown root:root "$SANDBOX"; sudo chmod 4755 "$SANDBOX"; }

# 4. Wayland clipboard — hard runtime dep (paste + selection)
pacman -Q wl-clipboard &>/dev/null || sudo pacman -S --noconfirm wl-clipboard

# 5. NO desktop entry (package ships /usr/share/applications/wispr-flow-appimage.desktop).
# 6. NO autostart. Launcher/window rules/kill-switch live in Hyprland config — see the doc.

wispr-flow --doctor || true
echo "Done. Read docs/2026-07-18-using-wispr.md before launching (kill-switch first!)."
```

---

*Sources: [`wispr-flow-linux`](https://github.com/wispr-flow-linux/wispr-flow-linux) docs (compatibility, configuration, decisions, learnings/wayland-injection), the [`helper`](https://github.com/wispr-flow-linux/helper) repo, and this machine's Omarchy config (`bindings.conf`, `windows.conf`, `webcam-overlay.conf`).*
