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
