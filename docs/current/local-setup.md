# Local setup (outside of migrations)

Some setup steps **cannot** live in a migration and must be done by hand, once,
on each machine. Migrations run non-interactively (often piped, no TTY), so they
can never:

- prompt for a **secret** (password, token, passphrase) — secrets must never be
  committed to this repo either, and
- do anything that needs **interactive input** or a running desktop session.

Migrations install the tooling and the commands; the steps below wire in the
per-machine secrets/state that make them actually work. If something installed by
a migration "does nothing," check here first.

---

## Framework 16 — Windows RDP (`omarchy-fw16-windows`)

Installed by `migrations/0000000012_install_fw16_rdp.sh`. The command RDPs into
the FW16 Windows boot (`win-fw16`) over Tailscale. It reads the Windows password
from the login keyring so it never prompts and needs no terminal — but you have
to put the password there yourself.

### One-time: save the Windows password to the keyring

```bash
secret-tool store --label="FW16 Windows RDP" service fw16-windows
```

Type the **FW16 Windows account password** (local user `morten`) when prompted.
That's it — the launcher and both `omarchy-fw16-windows` / `fw16-win` will now
connect with no prompts.

### Managing / fixing the saved password

```bash
# Check whether a password is stored
secret-tool lookup service fw16-windows >/dev/null && echo stored || echo missing

# Re-store (overwrites) — do this if login is rejected
secret-tool store --label="FW16 Windows RDP" service fw16-windows

# Remove it
secret-tool clear service fw16-windows
```

### Symptoms & fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Launcher does nothing, no window | Wrong password → `ERRCONNECT_LOGON_FAILURE`, or none stored | Re-store the password (above). A failure now also raises a mako notification. |
| Notification "No saved password" | Keyring entry missing | Run the `secret-tool store` command above |
| Login still rejected after re-storing | Account is a **Microsoft** account, not local | Edit `~/.local/bin/omarchy-fw16-windows`: set `DOMAIN="MicrosoftAccount"` and `USER_DEFAULT` to the account email |
| Everything too small / too big | HiDPI scaling | Edit `~/.local/bin/omarchy-fw16-windows`: set `SCALE` to `100`, `140`, or `180` |
| Session drops after a few minutes, esp. when the RDP window is not active | Wi-Fi power-save sleeps the NIC on an idle link | Disabled by `migrations/0000000013_disable_wifi_powersave.sh`. `+auto-reconnect` in the command also self-heals brief blips. Immediate manual fix: `sudo iw dev wlan0 set power_save off` |

### Verify from a terminal

To see the real error (instead of a headless notification), run it directly:

```bash
omarchy-fw16-windows          # over Tailscale
omarchy-fw16-windows --lan    # force home-LAN IP
```

---

## omarchy-dell — RDP into its Hyprland (`omarchy-dell` + hypr-rdp)

Installed by two migrations: `0000000020_install_omarchy_dell_rdp.sh` (the
**client** command `omarchy-dell`, on omarchy-asus) and
`0000000021_install_hypr_rdp_server.sh` (the **hypr-rdp server**, on omarchy-dell).
Full design: [`../2026-07-28-rdp-into-omarchy-dell.md`](../2026-07-28-rdp-into-omarchy-dell.md).

There is **one shared secret**: the RDP password. It must be stored on *both*
ends (the server runs hypr-rdp with it; the client sends it). Pick any strong
password and use the same one in both places.

### One-time on omarchy-dell (server) — activate it as an RDP target

```bash
secret-tool store --label="hypr-rdp server" service hypr-rdp
```

Until this is stored, `omarchy-rdp-server` refuses to start (safe default — a
machine only serves once you opt it in). After storing, either log out/in or run
inside the Hyprland session:

```bash
omarchy-rdp-server &        # starts hypr-rdp, bound to the tailnet IP :3389
```

### One-time on omarchy-asus (client) — save the same password

```bash
secret-tool store --label="omarchy-dell RDP" service omarchy-dell
```

Then connect (no prompts): `omarchy-dell` (or `dell`), or launch **omarchy-dell
(RDP)** from Super+Space.

### Managing / fixing the saved passwords

```bash
# server (dell): is it stored? re-store? remove?
secret-tool lookup service hypr-rdp >/dev/null && echo stored || echo missing
secret-tool store  --label="hypr-rdp server" service hypr-rdp
secret-tool clear  service hypr-rdp

# client (asus): same three, service name "omarchy-dell"
secret-tool lookup service omarchy-dell >/dev/null && echo stored || echo missing
secret-tool store  --label="omarchy-dell RDP" service omarchy-dell
secret-tool clear  service omarchy-dell
```

### Symptoms & fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Client window never appears, "Login rejected" | Passwords don't match on the two ends | Re-store the **same** password in both keyrings (above) |
| "Could not reach …" notification | dell offline, Tailscale down, or hypr-rdp not running | Check `tailscale status`; on dell see the server is up (`pgrep -a hypr-rdp`), or on home wifi try `omarchy-dell --lan` |
| hypr-rdp on dell exits immediately | No password stored, or launched outside the Hyprland session (no Wayland env) | Store the password; run `omarchy-rdp-server` from a terminal **inside** the session, check `~/.local/state/hypr-rdp.log` |
| **Keystrokes go to local Omarchy, not the remote session** | The XWayland client (`xfreerdp3`) can't receive Wayland keyboard focus under Hyprland, so keys leaked to the compositor. | Fixed: `omarchy-dell` uses the **native Wayland client** (`sdl-freerdp3`), which Hyprland gives real keyboard focus — typing (and SUPER) reach the remote. |
| **How do I get out? The remote grabs every key (incl. SUPER)** | In fullscreen the SDL client grabs the keyboard, forwarding all keys to the remote (this is what you want for a full session). | Press **Right Shift + G** to release the keyboard/mouse grab back to the local machine (press again to recapture). It's a client shortcut, always intercepted locally — you can't get trapped. `Ctrl+Alt+Enter` toggles fullscreen; last resort `pkill sdl-freerdp3`. |
| Client fails instantly: `ERRCONNECT_PRE_CONNECT_FAILED` / "virtual desktop width must be 200 <= 96" | `sdl-freerdp3`'s own fullscreen (`/f`) mis-probes the monitor as 96×96 under Wayland **fractional scaling** | Already handled — `omarchy-dell` runs **windowed** at the focused monitor's pixel size (`/w`/`/h` from `hyprctl monitors`) and fullscreens via Hyprland instead. If you hand-edit the command, do **not** add `/f`. |
| Black screen / capture fails | Hyprland doesn't expose the default capture protocol | On dell: `RDP_CAPTURE=ext omarchy-rdp-server &` (and set `RDP_CAPTURE=ext` in the launcher) |
| Everything too small / too big on the client | HiDPI scaling | Edit `~/.local/bin/omarchy-dell`: set `SCALE` to `100`/`140`/`180` |
| Choppy / high latency | Software encode (missing VA-API driver) or wifi power-save | Confirm `intel-media-driver` on dell (`vainfo`); wifi power-save is disabled by migration 0000000013 |
| **Sluggish / laggy / trailing cursor** | (1) `wlr` capture stalls every ~2s on Hyprland 0.56; (2) too many frames buffered; (3) heavy codec | Handled by defaults: capture `ext`, `--max-frames-in-flight 2` (server), AVC420 (client). Tune on dell: `RDP_MAX_FRAMES` (1=snappiest but choppy, 2=sweet spot), `RDP_FPS`. The `ext` capture is the big one — check `~/.local/state/hypr-rdp.log` for "frame stalled". |
| **Remote doesn't fill the screen (margin on right/bottom)** | SDL draws the remote buffer at 1:1 physical px, ignoring the monitor's fractional scale (1.25/1.5) | Fixed by `/smart-sizing` in `omarchy-dell` — scales the remote to fill the window on **any** monitor/scale (works the same on the ultrawide and the laptop-only screen). Don't add `/f` (mis-probes the monitor as 96×96). |

### Verify from a terminal

```bash
omarchy-dell            # over Tailscale, fullscreen (Ctrl+Alt+Enter toggles)
omarchy-dell --lan      # force home-LAN IP
omarchy-dell --windowed # resizable window instead of fullscreen
```

---

## Chromium — full Google account (`omarchy-install-chromium-google-account`)

Stock Chromium ships **without** Google's OAuth client credentials, so it can't
sign in to a Google account at all — which means no sync, and none of your
Google-saved payment methods / passwords / addresses autofill. (This is why
autofill "just worked" in Chrome on Windows but not in Chromium here.) Omarchy
bundles a helper that adds the credentials, after which Chromium does sign-in +
sync like Chrome — **without installing Chrome**. This is the way to get the full
Google-account experience while staying on plain Chromium.

### One-time: enable Google sign-in (automatable)

```bash
omarchy-install-chromium-google-account
```

Appends `--oauth2-client-id=…` / `--oauth2-client-secret=…` to
`~/.config/chromium-flags.conf`. Idempotent — safe to re-run; it only adds lines
that aren't already there. Requires `~/.config/chromium-flags.conf` to exist,
which it does on a normal Omarchy install.

### One-time: sign in (interactive — can't be a migration)

1. Fully quit Chromium so it re-reads the flags: `killall chromium`
2. Reopen → **profile icon** (top-right) → **Turn on sync…** → sign in with the
   same Google account you used on Windows.
3. Verify at `chrome://settings/payments` — saved cards appear and autofill at
   checkout (first sync can take a minute).

### Notes / gotchas

| Thing you'll see | Meaning |
|------------------|---------|
| Banner: "browser isn't managed by Google" / "sync may be unavailable" | Normal for Chromium — sign-in and sync still work. |
| Checkout still prompts for the card **CVC** | Expected for Google-account cards (same as Chrome), not a misconfig. |
| Helper prints nothing / no effect | `~/.config/chromium-flags.conf` is missing — create it (or reinstall Chromium), then re-run. |

Verify the credentials are present:

```bash
grep oauth2-client ~/.config/chromium-flags.conf
```

> Not yet captured as a migration — the helper is a built-in Omarchy command run
> by hand. If you want it reproducible on a fresh install, add a migration that
> runs `omarchy-install-chromium-google-account` and points here for the sign-in
> step.

---

## Adding a new local-setup step

When you add a migration that depends on a secret or interactive step:

1. Put the automatable part in the migration (install tooling, write the command).
2. Make the migration **detect** the missing manual state and print exactly what
   to run (see the `secret-tool lookup` check at the end of migration `0000000012`).
3. Document the manual step here so it's discoverable without reading the migration.
