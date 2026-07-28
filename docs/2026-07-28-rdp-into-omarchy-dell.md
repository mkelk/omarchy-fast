# RDP into omarchy-dell — full-fidelity Omarchy over the wire

**Date:** 2026-07-28
**Status:** Migrations authored (`0000000020` client, `0000000021` server). Client
installed on omarchy-asus; server pending the one-time build + password on omarchy-dell.
**Goal:** "RDP" from omarchy-asus → omarchy-dell and get *as full a visual Omarchy
as possible* — the real live Hyprland desktop (theme, waybar, wallpaper, animations),
smooth, with audio and clipboard.

---

## TL;DR

Omarchy is Hyprland (Wayland), so classic X11 RDP (`xrdp`) doesn't apply. The best
current answer for a **native, high-fidelity RDP into a Hyprland box** is
**[hypr-rdp](https://github.com/MuNeNiCK/hypr-rdp)** — a purpose-built RDP server
for Hyprland that captures the live session and streams it as **VA-API hardware
H.264**, with PipeWire audio and bidirectional clipboard. This is what the official
[Omarchy RDP guide](https://github.com/basecamp/omarchy/discussions/3350) now
recommends (it deprecated the old `xrdp → wayvnc` bridge in favour of it).

- **Server** (omarchy-dell): `hypr-rdp`, autostarted with the Hyprland session,
  bound to the **Tailscale IP only**, password from the login keyring.
- **Client** (omarchy-asus): an `omarchy-dell` command driving the **native
  Wayland** client `sdl-freerdp3` — H.264, `/sound`, `+clipboard`,
  `/dynamic-resolution`, keyring password, Walker launcher, fullscreened via
  Hyprland. (Started from the `xfreerdp3`/XWayland mirror of `omarchy-fw16-windows`,
  but XWayland can't take Wayland keyboard focus under Hyprland — see Keyboard below.)

Because both ends sit on the tailnet, connect to `100.116.131.117:3389` from
anywhere; no port is ever exposed to the LAN or internet.

---

## Why hypr-rdp (options considered)

| Option | Protocol | Fidelity | Setup on Hyprland | Verdict |
|--------|----------|----------|-------------------|---------|
| **hypr-rdp** | true RDP | High — VA-API H.264, audio, clipboard | AUR pkg + autostart | ✅ **Chosen** — literal "RDP", fullest desktop, purpose-built |
| Sunshine + Moonlight | game-stream | Highest — GPU, lowest latency | Brittle: Sunshine dropped Hyprland headless; needs EDID/GRUB hacks, window-closing rituals, waybar instability | Overkill for desktop work |
| wayvnc (+ Tailscale) | VNC | Moderate | Simple, rock-solid | Good fallback if hypr-rdp misbehaves |
| xrdp → wayvnc bridge | RDP→VNC | Moderate | Build-from-source, "dynamic resolution causes instability" | Deprecated upstream — skip |

We also already had the **`omarchy-fw16-windows`** precedent (RDP into the FW16
Windows boot over Tailscale). Reusing that exact shape — keyring password, Walker
`.desktop` launcher, short alias, SIGABRT-tolerant logging — keeps the client half
consistent and boring.

## Architecture

```
 omarchy-asus (client)                         omarchy-dell (server)
 ─────────────────────                         ─────────────────────
 omarchy-dell  ──► xfreerdp3 ──RDP/H.264──►  hypr-rdp  ──► live Hyprland session
   (keyring: service omarchy-dell)   Tailscale     (keyring: service hypr-rdp)
                                  100.116.131.117:3389   exec-once @ login
```

- **Transport:** Tailscale. hypr-rdp binds to `$(tailscale ip -4):3389`, never
  `0.0.0.0`. The tailnet + the RDP password are the entire security model — there
  is no LAN/WAN exposure and no firewall rule to manage.
- **Capture:** `--capture-mode ext` (ext-image-copy-capture-v1). hypr-rdp defaults
  to `wlr`, but wlr-screencopy **stalls every ~2s on Hyprland 0.56** (`WLR frame
  stalled` in the log → very sluggish), so we default to `ext`. `RDP_CAPTURE=wlr`
  falls back if needed.
- **Encode:** VA-API H.264, **AVC420** (client `/gfx:AVC420`). AVC444 works but is
  ~4× the data and heavier to decode; AVC420 is much snappier with only slightly
  softer text. omarchy-dell is Intel CometLake UHD → `intel-media-driver` (iHD);
  missing the driver only means slower OpenH264 software encode, not failure.
- **Latency:** `--max-frames-in-flight 2` on the server — few unacknowledged frames
  buffered, so the picture (and cursor) tracks close to real-time. `1` is snappiest
  but choppy; the hypr-rdp default buffers more and feels laggy/trailing.
- **Display fill:** `/dynamic-resolution` matches the remote to the client window,
  and **`SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=1`** makes SDL render at the monitor's
  native pixels so the remote is asked for the full physical size and fills the
  screen. Without it SDL draws at 1:1 logical px and leaves a margin under fractional
  scaling (1.25 ultrawide / 1.5 laptop). Scale-agnostic → **robust across the
  ultrawide and the laptop-only screen**, no hardcoded res. (`/smart-sizing` would
  also fill but is **mutually exclusive** with `/dynamic-resolution` in FreeRDP3, and
  we want dynamic-resolution so the remote matches each monitor's aspect.)
- **Session:** hypr-rdp serves a **headless output** it creates (doesn't disturb
  dell's physical monitor), sized to the client via `/dynamic-resolution`.

## What the migrations do

**`0000000020_install_omarchy_dell_rdp.sh` (client, runs on omarchy-asus):**
- Ensures `freerdp` is installed (provides `sdl-freerdp3`; already present here).
- Writes `~/.local/bin/omarchy-dell` (+ `dell` alias) — `sdl-freerdp3` to
  `100.116.131.117` (`--lan` → `192.168.68.51`), `SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=1`
  + `/gfx:AVC420 /dynamic-resolution /sound +clipboard /network:lan +auto-reconnect`,
  password from keyring service `omarchy-dell`. Runs **windowed** at the focused
  monitor's pixel size, then Hyprland-fullscreens the window (`--windowed` to opt out).
- Adds a Walker `.desktop` launcher (absolute path — Walker's uwsm PATH excludes
  `~/.local/bin`).
- Detects a missing keyring password and prints the one-time `secret-tool` step.

**`0000000021_install_hypr_rdp_server.sh` (server, runs on omarchy-dell):**
- Checks Hyprland ≥ 0.54 (dell is 0.56 ✓).
- Installs the matching **VA-API driver** (Intel→`intel-media-driver`,
  AMD→`libva-mesa-driver`) + runtime deps + `hypr-rdp` from the AUR.
- Writes `~/.local/bin/omarchy-rdp-server` — reads the keyring password (service
  `hypr-rdp`), binds to the tailnet IP, kills any prior instance, launches
  `hypr-rdp` (fps 60, codec auto, capture wlr, audio redirect), logs to
  `~/.local/state/hypr-rdp.log`.
- Adds an idempotent `exec-once = ~/.local/bin/omarchy-rdp-server` to
  `~/.config/hypr/autostart.conf`.
- **Self-gates on the keyring password**: no password → doesn't serve. So this same
  migration is safe on every machine; a box becomes a target only where you store
  the password. (This is why building `hypr-rdp` on omarchy-asus too is harmless —
  it just never listens there.)

## First-time setup

Both halves need **one manual secret step each** (migrations can't type passwords).
See [`current/local-setup.md`](current/local-setup.md) for the exact commands.
Order:

1. **omarchy-dell (server):** pull this branch → `./setup.sh` → `omarchy-migrate`
   (needs sudo, run in dell's own terminal; Rust build takes a few minutes) →
   `secret-tool store --label="hypr-rdp server" service hypr-rdp` →
   `omarchy-rdp-server &` (or log out/in).
2. **omarchy-asus (client):** the `omarchy-dell` command is already installed →
   `secret-tool store --label="omarchy-dell RDP" service omarchy-dell` (same
   password) → run `omarchy-dell`.

## Everyday use

```bash
omarchy-dell            # fullscreen over Tailscale (Ctrl+Alt+Enter toggles fullscreen)
omarchy-dell --lan      # force the home-LAN IP (192.168.68.51)
omarchy-dell --windowed # resizable window
dell                    # short alias
```

Or launch **omarchy-dell (RDP)** from Super+Space.

## Variants / knobs

- **Headless virtual output** (don't disturb dell's physical monitor, or when dell
  runs lid-closed): create a headless Hyprland output and point hypr-rdp at it with
  `--output`. Lets the remote resolution match the client without changing the
  physical mode. Not wired up by default; add if the live-mirror resize proves
  disruptive.
- **Server tunables** (env in `~/.local/bin/omarchy-rdp-server`): `RDP_FPS`,
  `RDP_CODEC` (`auto|avc444|avc420`), `RDP_CAPTURE` (`wlr|ext`), `RDP_AUDIO`,
  `RDP_PORT`. A `~/.config/hypr-rdp/config.toml` is also read if present.
- **Client tunables** (edit `~/.local/bin/omarchy-dell`): `SCALE`, `GFX`, host IPs.

## Notes / gotchas

- **Keyboard / why the Wayland client:** the XWayland client (`xfreerdp3`) displays
  fine but never receives Wayland keyboard focus under Hyprland, so every keystroke
  (even after focusing/fullscreening) leaked to the local compositor. `sdl-freerdp3`
  is a **native Wayland** window, so Hyprland delivers it keyboard focus. In
  fullscreen it grabs the keyboard, so **all keys including SUPER** go to the remote
  Omarchy (the full experience). **Escape hatch: Right Shift + G** toggles the
  keyboard/mouse grab back to local — a client shortcut, always intercepted locally,
  so you can never get trapped (`pkill sdl-freerdp3` is the last resort).
- **No `/f` on the SDL client:** its own fullscreen mis-probes the monitor as 96×96
  under Wayland **fractional scaling** (asus is 1.25/1.5) and pre-connect fails. We
  run windowed at the focused monitor's pixel size and fullscreen via `hyprctl`.
- **hypr-rdp maturity:** young project (Rust, MIT, ~100 commits). It's the right,
  purpose-built tool, but if it regresses, **wayvnc + Tailscale** is the reliable
  fallback (see the acrogenesis Omarchy guide).
- **Keyring at login:** the server launcher reads the keyring from an `exec-once`,
  which runs after the PAM-unlocked graphical login — so the secret is available.
- **Two secrets, one password:** the client and server keyring entries are separate;
  keep the **same** password in both or you get `LOGON_FAILURE`.
- **Wi-Fi power-save** already disabled by migration `0000000013` — relevant here
  too, as an idle RDP link is exactly what power-save used to sleep.
- **omarchy-dell must have a live Hyprland session** for hypr-rdp to capture. It
  currently auto-lands in one; if you ever set it fully headless, add autologin.

## References

- Omarchy: [Guide — Connect to Hyprland via RDP (#3350)](https://github.com/basecamp/omarchy/discussions/3350) ·
  [RDP to an Omarchy VM (#3273)](https://github.com/basecamp/omarchy/discussions/3273)
- [hypr-rdp](https://github.com/MuNeNiCK/hypr-rdp) (native Hyprland RDP server)
- [Remote access to Omarchy with wayvnc + Tailscale](https://acrogenesis.com/remote-access-to-omarchy-with-wayvnc-and-tailscale/) (fallback)
- Sibling: `migrations/0000000012_install_fw16_rdp.sh` (the `omarchy-fw16-windows` precedent)
