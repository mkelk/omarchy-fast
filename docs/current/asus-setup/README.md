# ASUS VivoBook — Omarchy setup notes

Hardware-specific notes for getting Omarchy running well on this ASUS
VivoBook. Kept separate from `migrations/` because this is
troubleshooting/reference material, not a repeatable install step.

## Status: WiFi working, Bluetooth not (updated 2026-07-10)

WiFi is up via the `morrownr/mt76` driver — see "The fix that worked" below,
plus two later gotchas: the TX-power clamp and an intermittent no-DHCP-after-boot
wedge (both documented below with fixes). Bluetooth has **never** worked on
this install and is not fixable by driver fiddling — see the Bluetooth
section for why and for the paths to getting it.

## After future Omarchy/pacman updates

`morrownr/mt76` registers properly via `dkms add/build/install`, so Arch's
`dkms` package pacman hook auto-rebuilds it whenever `linux-headers` gets
updated alongside a kernel bump — normal `pacman -Syu` / Omarchy updates
should carry the driver forward with no manual steps.

Still, **before rebooting after any update that bumps the kernel**, check:
```bash
dkms status
```
Confirm the mt76 module shows built+installed for the *new* kernel version,
not just the old one. If it's missing for the new version, run
`sudo dkms autoinstall` and confirm it succeeds before rebooting — otherwise
you'll boot into a kernel with no wifi module again (same failure mode we
hit offline, just self-inflicted this time by skipping the check).

Real risk window: an update interrupted mid-transaction (network drop,
power loss), or a kernel jump past the range `morrownr/mt76` currently
supports (6.12–7.x as of this writing) before the repo catches up.

## Hardware identified

- **Model**: ASUS VivoBook
- **WiFi chip**: MediaTek MT7902 802.11ax, marketing name "Filogic 310"
  - Board/OEM: AzureWave, subsystem device `5520`
  - PCI ID `14c3:7902`
  - Confirmed via: `lspci -k | grep -A3 -i network`
- **Kernel at time of fix**: `7.0.9-arch2-1` (x86_64)

## The problem

Fresh Omarchy install boots fine, but the WiFi menu (Impala, launched from
a floating terminal overlay) blinks open and immediately closes. Running
`impala` directly in a terminal shows: `cannot access the iwd service:
No adapter found`.

Root cause: **the MT7902 has no driver in the mainline Linux kernel.**
MediaTek only submitted upstream patches to the kernel mailing list in
February 2026, targeting a future release (referenced as Linux 7.1) — not
available in any shipping kernel yet, including Omarchy's. This is a
hardware/driver gap, not a config issue.

Confirmed via Arch forum thread ([bbs.archlinux.org/viewtopic.php?id=299471](https://bbs.archlinux.org/viewtopic.php?id=299471)):
a moderator confirmed there's no support and suggested replacing the card.

## The fix that worked: `morrownr/mt76`

[morrownr/mt76](https://github.com/morrownr/mt76) — a well-maintained,
actively updated out-of-tree driver fork (based on OpenWrt's mt76, adapted
for standalone DKMS builds). Explicitly lists MT7902 as supported under the
MT7921 family (`mt7921e`), bundles firmware in-repo, kernel range 6.12–7.x.

This is what actually worked, after two other community drivers failed —
see "What we tried first" below for why those didn't pan out.

### How we got it installed

The VivoBook had no wifi (that was the whole problem) and no ethernet
cable, so we USB-tethered an Android phone to get it online directly —
far simpler than the offline USB-stick approach we started with (that
approach still works and is documented below/in `scripts/`, if tethering
isn't an option next time):

1. Phone → VivoBook via USB cable, then on the phone: **Settings → Network
   & Internet → Hotspot & Tethering → USB tethering** → on. This uses
   standard in-kernel USB networking (`usb0`), no wifi driver involved at
   all.
2. Verified with `ip link show` (new `usb0`-ish interface) and
   `ping -c3 1.1.1.1`. NetworkManager auto-connected it.
3. **Did not run `pacman -Syu`** — a full upgrade risked pulling a newer
   kernel and invalidating the exact-matched `linux-headers` already
   installed from the earlier offline attempt (see below), which would
   break DKMS again. Only synced what was needed:
   ```bash
   sudo pacman -Sy bc   # install-driver.sh needs `bc`, wasn't preinstalled
   ```
4. Cloned and ran the installer directly — it makes **zero further network
   calls**, everything else (dkms, matching linux-headers, gcc, make,
   patch, pahole, git) was already on the system from the earlier offline
   attempts:
   ```bash
   git clone https://github.com/morrownr/mt76.git
   cd mt76
   sudo sh install-driver.sh
   sudo reboot
   ```
5. After reboot: new wireless interface showed up in `ip link show` /
   `iwctl device list`, Impala worked normally.

## Slow uploads / clamped TX power (mt7921 CLC on DFS channels)

Discovered 2026-07-09: connections *from* this ASUS to other hosts
(`omarchy-dell`, `win-fw16`) were crawling. It was **not** power-save
(`iw dev wlan0 get power_save` → off; already handled by migration
`0000000013`). The real cause was a badly one-sided link:

```
rx bitrate: ~290 Mbit/s          ✅ downloads fine
tx bitrate: ~20-27 Mbit/s        🔴 uploads collapsed
tx retries: 544k  (vs 405k pkts) 🔴 >100% retry rate
tx failed:  16.5k
txpower:    0.00 dBm             🔴 (regdom DK/ETSI allows 26 dBm here)
```

Root cause: the **MediaTek mt7921/mt7925 CLC (Country Location Control)
bug**. On a DFS "radar detection" 5GHz channel (we were on ch108 /
5540 MHz), the card clamps its own TX power to ~0 dBm. RX is unaffected,
so it looks like a healthy connection until you try to *send*. Because
MT7902 rides the `mt7921e` driver, this ASUS is affected.

**Diagnose** (the tells, in order):
```bash
iw dev wlan0 link | grep -E 'freq|bitrate'   # DFS chan + low tx bitrate?
iw dev wlan0 info | grep txpower              # 0.00 dBm == clamped
iw dev wlan0 station dump | grep -E 'tx retries|tx failed|txpower'
iw phy phy0 channels | grep -A2 <freq>        # "Radar detection" == DFS chan
```

**Fix** — load the driver with `disable_clc=Y`. The morrownr/mt76 installer
writes `/etc/modprobe.d/mt76_git.conf` with `disable_clc=N` by default, **and
regenerates it on every driver (re)install/DKMS rebuild** — so this is
re-asserted idempotently by migration
`0000000016_wifi_disable_clc.sh` rather than left as a manual edit. That
migration flips both the `mt7921_common_git` and `mt7925_common_git` lines to
`=Y` and reloads the driver.

Trade-off: `disable_clc` disables a regulatory-conformance feature (community-
standard workaround; stays within the domain's own advertised power limits).
The no-flag alternative is to move the *AP* to a non-DFS channel (36/40/44/48),
which sidesteps the clamp entirely — do that instead when you control the AP.

**Verify after reboot/reconnect:** `iw dev wlan0 info | grep txpower` should
no longer read `0.00 dBm`, and `tx retries` in `station dump` should grow far
more slowly relative to `tx packets`.

## WiFi associates but never gets DHCP after boot (intermittent)

Discovered 2026-07-10: after a boot, wifi *looks* connected but nothing
works. The tells:

```bash
iwctl station wlan0 show      # State: connected, good RSSI, but
                              # "No IP addresses  Is DHCP client configured?"
networkctl                    # wlan0 stuck in "degraded (configuring)" forever
```

Layer 2 is genuinely fine — `ping -6 ff02::1%wlan0` (all-nodes multicast)
got replies from the AP and other hosts — but the DHCPv4 exchange never
completes. Not the firewall: zero UFW blocks on ports 67/68 in the journal.
Meanwhile networkd DHCP on other interfaces (USB ethernet) works instantly,
so it's the mt76 data path for the DHCP exchange specifically that's wedged.

**Fix — reload the driver:**

```bash
sudo modprobe -r mt7921e_git mt7921_common_git
sudo modprobe mt7921e_git
```

DHCP completes within seconds of the reload. Two side effects, both harmless:

- The interface can come back as `wlan1` instead of `wlan0` (the old
  netdev's teardown stalls — `page_pool_release_retry` in dmesg). Fine
  because `20-wlan.network` matches `wl*`; the name reverts next reboot.
- The Bluetooth function re-probes and fails again — irrelevant, it was
  already broken (see below).

Intermittent: hit on the 2026-07-10 16:01 boot; the very next boot got its
lease with no intervention. Note that `omarchy-restart-wifi` only does
`rfkill unblock` — it does **not** fix this; you need the modprobe reload.

## Bluetooth: dead on every boot — NOT the wifi driver's fault

Investigated 2026-07-10. Symptom: `bluetoothctl` shows no controller;
kernel logs `Bluetooth: hci0: Opcode 0x0c03 failed: -110` — that's the HCI
Reset command timing out, the very first thing btusb sends, before any
firmware load is even attempted. BT is the USB function (`13d3:3579`) of
the same MT7902 combo card.

What we established, in order:

- It fails on **every single boot** — journal shows 12/12 boots failed back
  to 2026-07-08 (the whole life of this install). Not a wedge, not
  power-state flakiness: it has simply never worked here.
- Not missing firmware — `BT_RAM_CODE_MT7902_1_1_hdr.bin` is present in
  linux-firmware. The failure happens before firmware would be loaded.
- **Not `morrownr/mt76`'s fault.** Every soft reset fails (rfkill cycle,
  `btusb` reload, USB `authorized` 0→1 toggle, BT re-probe with
  `mt7921e_git` unloaded), and decisively: a full boot with `mt7921e_git`
  blacklisted (module confirmed absent from `lsmod`) still failed with the
  identical `-110`. The chip doesn't answer HCI Reset even when nothing has
  touched the wifi side at all.

Conclusion: **MT7902 Bluetooth is unsupported by btusb/btmtk as of kernel
7.0.x.** Don't burn time on resets or driver experiments; it's a kernel
support gap, same story as the wifi side was.

**Paths to working BT**, best first:

1. **Wait for mainline.** MediaTek's Feb 2026 patchset targets Linux 7.1
   for wifi, with the btusb/btmtk Bluetooth patches expected in 7.1/7.2.
   Re-test BT after each kernel bump (`bluetoothctl list`). ⚠️ **When
   mainline MT7902 support lands, remove the morrownr DKMS driver**
   (`sudo dkms remove mt76/1.0 --all`) so it doesn't shadow the in-kernel
   driver.
2. **[bupd/bt-driver-mt7902](https://github.com/bupd/bt-driver-mt7902)** —
   patched btusb/btmtk as a DKMS package, explicitly lists this exact USB
   ID (`13d3:3579`, tested on ASUS Vivobooks). Caveat: as of July 2026 only
   tested up to kernel 6.19; may need patching to build on 7.0.x.
3. **USB BT dongle** — zero-effort fallback; any Realtek/CSR one works out
   of the box.

## What we tried first (didn't work, kept for reference)

Two other community drivers were tried before finding `morrownr/mt76`,
fully offline via USB stick (no tethering set up yet at that point):

1. **[abdullaabdullazade/mt7902_driver](https://github.com/abdullaabdullazade/mt7902_driver)**
   — DKMS-based, looked solid on paper. Built successfully but **failed its
   own post-install health check** and auto-rolled itself back (removed
   `gen4-mt7902`, regenerated initramfs/UKI). Its own automatic fallback
   path then tried to `git clone` a fallback repo, which correctly failed
   offline.
2. **[hmtheboy154/mt7902](https://github.com/hmtheboy154/mt7902)** — the
   fallback the above driver tries to auto-clone. Its own README admits
   it's a work-in-progress: *"completes the WPA2 handshake but fails to
   get an IP... sometimes briefly connects."* Not viable even if built
   successfully. Also has no top-level `Makefile`/`make install` — the
   real build lives in `src/`, driven by a `load.sh` that does `insmod`
   directly (non-persistent), and needs proprietary firmware manually
   extracted from an **Acer** Windows driver package. A first draft of an
   offline install script for this assumed the wrong repo layout entirely
   — don't reuse `scripts/02-fallback-manual.sh` as-is without checking
   the actual repo structure first if this is ever revisited.

## Offline install method (no network at all — fallback approach)

If tethering isn't available next time, this is the method we built and
validated up through package installation (before switching to tethering
+ `morrownr/mt76` for the actual driver build):

1. Run `scripts/00-gather-info.sh` on the offline machine (no network
   needed) — dumps kernel version, what's already installed, wifi
   hardware IDs, and rfkill state to `system-report.txt`.
2. Bring that report to an internet-connected machine. From it, determine
   the **exact** kernel version (`uname -r` / `pacman -Q linux`) and fetch
   matching packages:
   - `linux-headers` **must match the exact running kernel version** — if
     the live Arch/Omarchy mirror has since moved on, pull the exact
     build from the [Arch Linux Archive](https://archive.archlinux.org/packages/l/linux-headers/)
     instead (`https://archive.archlinux.org/packages/l/linux-headers/linux-headers-<version>-x86_64.pkg.tar.zst`).
   - `dkms`, `patch`, `pahole` (all `dkms` deps not in the base install —
     `pahole` specifically is a dependency of `linux-headers` itself and is
     easy to miss; its Arch package filename contains a `:` epoch prefix,
     e.g. `pahole-1:1.31-2-x86_64.pkg.tar.zst`, which **NTFS/Windows can't
     store** — save it locally with the colon swapped for `_` instead;
     pacman reads package metadata from inside the archive, not the
     filename, so this is safe)
   - the driver source itself, downloaded as a zip
     (`archive/refs/heads/main.zip`) from GitHub rather than `git clone`,
     since the target has no network to clone with
3. `scripts/01-install.sh` installs the local `.pkg.tar.zst` files via
   `pacman -U` (pure local install, no sync DB needed), then extracts and
   builds the driver **in `/tmp`, not on the USB stick itself** — FAT/exFAT
   (what the USB was formatted as) doesn't support Unix file ownership, so
   extracting/building directly on it fails every `chown` with "Operation
   not permitted." Copy the source zip into `/tmp` first, build there.
   The script also patches out the upstream installer's own
   `install_deps()` call (`pacman -S --needed --noconfirm ...`), which
   needs synced repo databases and would hard-fail offline.
4. `scripts/02-fallback-manual.sh` — written for the `hmtheboy154/mt7902`
   fallback specifically; per the note above, verify the actual repo
   structure before trusting this script if reused later.

The actual `.pkg.tar.zst` files and driver source zips are **not**
committed here (large binaries, versions go stale) — refetch them per the
steps above when needed again.

## Scripts

See `scripts/` in this folder:
- `00-gather-info.sh` — run first, offline, dumps system state to a report
- `01-install.sh` — installs local packages, builds a driver in `/tmp`
  (references exact package filenames from the July 2026 fix — update
  filenames/kernel version if redoing this later; also references the
  `abdullaabdullazade/mt7902_driver` repo specifically, not
  `morrownr/mt76` — would need updating to target the driver that actually
  worked if reused)
- `02-fallback-manual.sh` — manual fallback build; needs a rewrite against
  the actual `hmtheboy154/mt7902` repo layout (see above) before reuse

## Other useful references

- [morrownr/mt76](https://github.com/morrownr/mt76) — the driver that
  worked
- [MediaTek MT7902 wireless chipset finally gets a Linux driver — CNX Software](https://www.cnx-software.com/2026/02/20/mediatek-mt7902-wireless-chipset-finally-gets-linux-drivers/) —
  status of the upstream kernel patches (target: Linux 7.1, not yet
  released as of this writing)
- [iwd - ArchWiki](https://wiki.archlinux.org/title/Iwd)
- [basecamp/omarchy troubleshooting manual](https://learn.omacom.io/2/the-omarchy-manual/88/troubleshooting)
- General wifi troubleshooting flow (for future hardware, not MT7902-specific):
  `rfkill list` → `sudo rfkill unblock all` → `systemctl status iwd` →
  `journalctl -k | grep -iE "wlan|wifi|80211|firmware"`
- USB tethering as a no-driver-needed way to get a machine online when
  wifi itself is the thing that's broken: enable on the phone under
  Settings → Network & Internet → Hotspot & Tethering → USB tethering,
  standard in-kernel USB networking (`usb0`), no drivers to install
