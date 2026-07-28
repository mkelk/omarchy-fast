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
- **Client** (omarchy-asus): an `omarchy-dell` command (mirror of
  `omarchy-fw16-windows`) driving `xfreerdp3` — fullscreen, H.264, `/sound`,
  `+clipboard`, `/dynamic-resolution`, keyring password, Walker launcher.

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
- **Capture:** `--capture-mode wlr` (hypr-rdp default). If a future Hyprland drops
  wlr-screencopy, switch to `ext` (`RDP_CAPTURE=ext`).
- **Encode:** VA-API H.264. omarchy-dell is Intel CometLake UHD → `intel-media-driver`
  (iHD). Missing the driver only means slower OpenH264 software encode, not failure.
- **Session:** hypr-rdp mirrors the **live** output, so you see exactly what's on
  omarchy-dell's screen. `/dynamic-resolution` on the client asks the session to
  match the client window. If the physical monitor flickers on resize, drop
  `/dynamic-resolution` (add `/smart-sizing:on` instead) or serve a headless
  virtual output — see "Variants" below.

## What the migrations do

**`0000000020_install_omarchy_dell_rdp.sh` (client, runs on omarchy-asus):**
- Ensures `freerdp` is installed (already present here).
- Writes `~/.local/bin/omarchy-dell` (+ `dell` alias) — `xfreerdp3` to
  `100.116.131.117` (`--lan` → `192.168.68.51`), fullscreen by default
  (`--windowed` to opt out), `/gfx:AVC444 /sound /microphone +clipboard
  /dynamic-resolution /network:lan +auto-reconnect`, password from keyring service
  `omarchy-dell`.
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
