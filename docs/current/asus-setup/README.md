# ASUS VivoBook — Omarchy setup notes

Hardware-specific notes for getting Omarchy running well on this ASUS
VivoBook. Kept separate from `migrations/` because this is
troubleshooting/reference material, not a repeatable install step.

## Status: WiFi working but episodically unstable, Bluetooth not (updated 2026-07-11)

WiFi is up via the `morrownr/mt76` driver — see "The fix that worked" below,
plus later gotchas: the TX-power clamp, an intermittent no-DHCP-after-boot
wedge, and (2026-07-11) **episodic 5GHz channel collapse** traced to
co-channel congestion — see that section for the diagnosis and what was
ruled out. Bluetooth has **never** worked on
this install and is not fixable by driver fiddling — see the Bluetooth
section for why and for the paths to getting it (a BT-only USB dongle was
ordered 2026-07-11). The trackpad occasionally
dies mid-session — **do not suspend while it's dead**, that hangs the whole
machine; see the trackpad section.

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

**On mainline 7.1 (in-kernel driver):** migration `0000000016` targets the
`_git` module names and the morrownr `mt76_git.conf`, both of which cease to
exist after the switch — so the migration goes dead. Whether the clamp itself
persists in the mainline `mt7921` driver is unknown (the `disable_clc` param
exists there too). **Re-test on a DFS channel first** (see the switch-plan
section); only if it recurs, re-assert against the non-`_git` module in a fresh
file: `echo 'options mt7921_common disable_clc=Y' | sudo tee
/etc/modprobe.d/mt7921-clc.conf`. Otherwise retire migration 16.

**Verify after reboot/reconnect:** `tx retries` in `station dump` should grow
far more slowly relative to `tx packets`, and tx bitrate should sit near rx
bitrate. ⚠️ **Do NOT use the `txpower` reading as the telltale** — established
2026-07-11: on this driver `iw dev wlan0 info` reads `txpower 0.00 dBm`
*constantly*, including when the link is pristine and even right after
`sudo iw dev wlan0 set txpower fixed 2000`. The reading is cosmetically
broken; only the retry ratio and bitrate asymmetry are trustworthy.

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

**On mainline 7.1:** drop the `_git` suffix — the modules are `mt7921e` /
`mt7921_common`. If the wedge recurs on the in-kernel driver, the reload is
`sudo modprobe -r mt7921e mt7921_common; sudo modprobe mt7921e`.

## Episodic 5GHz channel collapse (2026-07-11) — congestion, not (only) the driver

Symptom: wifi shows "connected" but nothing loads, or works fine and then
collapses for a stretch. A reboot *seems* to help sometimes — coincidence,
the bad phases are episodic and a reboot just lands you in a good one.

The measured pattern (pings to own gateway `192.168.x.1`, signal -60 dBm,
ch40 / 5200 MHz / 80 MHz, only ~5 m from the AP):

- Oscillates between **pristine** (8 ms RTT, 0% loss, ~0 retries) and
  **catastrophic** (up to 96% ping loss, RTT 0.5–4 s, tx retry rate >1000%)
  in phases lasting tens of seconds to minutes.
- During bad phases **both directions degrade** — rx byte flow collapses
  alongside tx — so the *medium* is jammed, not just our tx queue.
- tx bitrate craters (MCS 8 → MCS 2) while rx bitrate stays high. Looks
  exactly like the CLC clamp from the outside; it isn't.

Ruled out, in the order tested:

- **DHCP wedge** — the boot under test got its lease in 9 s.
- **Power save** — off (migration 13 holding).
- **CLC conf regeneration** — `mt76_git.conf` still had `disable_clc=Y` and
  the live module parameter agreed.
- **iwd background scanning** — zero nl80211 events (`iw event -t`) during a
  bad window.
- **Firmware deep-sleep / runtime PM** — sparse pings after 15 s of idle were
  the cleanest of the whole session (8 ms avg, 1 ms jitter). A dozing chip
  would show the opposite.
- **TX power clamp** — `sudo iw dev wlan0 set txpower fixed 2000` changed
  nothing (and the `txpower 0.00 dBm` reading is cosmetically broken on this
  driver — see the warning in the CLC section).

Root cause, best supported: **co-channel congestion on ch40.** A fresh scan
(`iwctl station wlan0 scan`, then `iw dev wlan0 scan dump`) showed FOUR
BSSes on 5200 MHz:

- both Deco nodes' 5GHz fronthaul (two BSSes sharing the Deco OUI)
- a third hidden BSS whose MAC was a *locally-administered* twin of the main
  node's (the U/L bit flipped) — almost certainly the 5GHz mesh backhaul
- **an old wifi extender of ours (a `*_5G_EXT` SSID) at -76 dBm**, sitting
  by the heating system. Unplugged 2026-07-11 mid-diagnosis; it vanished
  from the next scan. A range extender retransmits every relayed frame, and
  from inside a metal-heavy boiler corner it would relay at low rate = an
  airtime hog exactly matching the bursty minutes-long collapses.

EU regulatory context: ch36–48 is the **only** non-DFS 80MHz block, so every
"auto" consumer AP piles onto it. mt76 then amplifies congestion into outage
(retry storm, rate collapse) instead of degrading gracefully.

Post-unplug observations (same day): the extender stayed absent across
three scans. The laptop then roamed to the home SSID's **6GHz** BSS
(6135 MHz — so MT7902 does WiFi 6E) and showed the
same episodic pattern there: ~1 min of retry-storm, then the cleanest link
of the whole session (1.7–5 ms RTT while sustaining several MB/s). The
6GHz channel also carries a second locally-administered Deco BSS
— likely the mesh backhaul, i.e. the same
fronthaul-shares-air-with-backhaul situation as on 5GHz. The extender
can't explain 6GHz badness; Deco backhaul bursts remain the suspect there.

**Still open / next steps:**

1. Re-test on the home SSID's 5GHz now the extender is gone — reconnect and run the
   probe below; if the bad phases are gone, case closed.
1a. **Preferably first: upgrade to the mainline 7.1 driver** (see the
   hardware-exit section) so any further diagnosis tests the driver that
   will actually be kept.
2. If still bad: move the Deco's 5GHz to a DFS channel (emptier air), or
   bias this laptop to 2.4GHz: `[Rank] BandModifier5GHz=0.5` (or lower) in
   `/etc/iwd/main.conf`, restart iwd. The 2.4GHz BSS was -48 dBm and its channel
   didn't overlap the neighbors'.
3. Hardware exit if the fight isn't worth it — see the next section.

**The probe** (run for a couple of minutes; healthy = single-digit RTT and
`dretry` near 0; bad phase = `LOST` rows with `dretry` in the hundreds):

```bash
GW=$(ip route | awk '/default/{print $3; exit}')   # your default gateway
prev_tx=0; prev_re=0; prev_rx=0
for i in $(seq 1 60); do
  t=$(date +%H:%M:%S)
  rtt=$(ping -c1 -W1 "$GW" 2>/dev/null | grep -oP 'time=\K[0-9.]+' || echo LOST)
  read tx re rx <<< $(iw dev wlan0 station dump | awk '/tx packets/{tp=$3} /tx retries/{tr=$3} /rx bytes/{rb=$3} END{print tp, tr, rb}')
  [ $i -gt 1 ] && echo "$t rtt=${rtt}ms dtx=$((tx-prev_tx)) dretry=$((re-prev_re)) drx_kB=$(( (rx-prev_rx)/1000 ))"
  prev_tx=$tx; prev_re=$re; prev_rx=$rx
  sleep 1
done
```

## Hardware exit: replacing the MT7902 (or bypassing it over USB)

Decision notes from 2026-07-11, when the fighting got old:

- **Best: swap the internal M.2 card for an Intel AX210** (~150–200 DKK,
  buy the `AX210NGW` from a reputable seller — fakes exist). This machine is
  a **Vivobook M1505YA** (AMD platform): the MT7902 enumerates as PCIe
  `14c3:7902`, so the slot is standard M.2 2230 A+E with PCIe — no Intel
  CNVio complications possible on AMD. AX210 = in-kernel `iwlwifi` (since
  5.10) + BT over `btusb`, firmware in `linux-firmware`, WiFi 6E. Fixes wifi
  AND bluetooth permanently, uses the internal antennas.
  **Socketed/replaceable: CONFIRMED 2026-07-11 by opening the laptop** — the
  stock card is an **AzureWave AW-XB552NF** (MT7902; WF MAC carries the
  AzureWave OUI `c0:bf:be:…` and matches the running system), a single-screw
  M.2 2230 module
  with two push-on antenna leads (Main = black, Aux = white). So an AX210
  (same 2230 A+E form factor, two antennas) physically drops in. Remaining
  risks now only: (a) ASUS consumer BIOS whitelist — historically absent on
  Vivobooks, very low; (b) antenna connector type — stock leads look MHF4
  (what AX210 also uses); if they're the older U.FL/MHF1 you'd need cheap
  adapter pigtails. Buy a genuine `AX210NGW` (fakes exist). Confidence is now
  ~98%, not 100% only because of (a)/(b) above.
  After the swap: `sudo dkms remove mt76/1.0 --all`.
  **Where to buy (DK, checked 2026-07-11):** Proshop stocks the correct bare
  **M.2 2230 "Without vPro"** card for ~100 kr incl. VAT (genuine — reputable
  retailer; get the non-vPro, vPro is irrelevant here). Compumail also carries
  it. ⚠️ **Elgiganten only sells the desktop *PCIe* AX210** (NÖRDIC, external
  antennas) — wrong form factor, won't fit the laptop M.2 slot. Reuse the
  laptop's existing Main/Aux antenna leads, so a bare card (no antennas) is
  what you want.
- **USB combo dongle that "just works"**: only MediaTek **MT7921AU**-based
  ones (e.g. ALFA AWUS036AXML, Comfast CF-953AX) — WiFi 6 + BT 5.2 with
  in-kernel `mt7921u` + `btusb` since ~5.19, zero DKMS. Avoid Realtek USB
  wifi (out-of-tree DKMS = the same fight, different chip).
- **BT-only dongle** (ordered 2026-07-11): fine, works out of the box, solves
  the dead-BT problem independently of all of the above.
- **Cheapest — and now real: Linux 7.1 (shipped 2026-07-04) has mainline
  MT7902 wifi support**, confirmed working by an M1505YA owner
  ([EndeavourOS forum](https://forum.endeavouros.com/t/no-wifi-on-vivobook-m1505ya-realtek-mt7902-driver-n-a/77117):
  "the 7.1 kernel now has the fix for the MEDIATEK MT7902 driver").
  7.0.x is EOL upstream, so Arch/Omarchy will carry 7.1 imminently. This is
  the current plan — full staged procedure in the next section. Keep the
  AX210 as plan B if the mainline driver disappoints.

## Switching to mainline 7.1 and stripping the chipset fixes (the plan)

Goal (decided 2026-07-11): get onto stock 7.1 with the **in-kernel** mt7921
driver, remove *every* custom chipset fix for a clean baseline, then redo only
the fixes the mainline driver actually still needs.

⚠️ **Why order matters:** on the current 7.0.x kernel the morrownr driver is
the *only* thing giving wifi at all — removing it before 7.1 is running = no
wifi on any kernel. And `mt76_git.conf` **blacklists the in-kernel modules**,
so the driver swap only takes effect once that file is gone *and* you've
rebooted into 7.1.

⚠️ **Availability gate — this is an Omarchy channel thing, not Arch.** This
machine syncs from **one** mirror, `stable-mirror.omarchy.org` (see
`/etc/pacman.d/mirrorlist`), because it's on Omarchy's **stable** channel.
Omarchy curates its stable mirror and promotes upstream Arch on its own
(lagged) schedule, so `pacman -Syu` returns "nothing to do" and stays on
7.0.10 even though Arch `core` already ships `linux 7.1.3` (confirmed
2026-07-11). Channels are switched with `omarchy-channel-set <stable|rc|edge|
dev>` — each just swaps the mirror (`stable`→stable-mirror, `rc`→rc-mirror,
`edge`→mirror.omarchy.org which tracks Arch closest) and its omarchy git
branch, then runs a full `pacman -Syyuu`. So three ways to actually get 7.1:
1. **Wait** for Omarchy to promote 7.1 to *stable* — zero risk, on-brand,
   just slower. Poll with `pacman -Sy && pacman -Si linux`.
2. **`omarchy-channel-set edge`** — the ONLY channel that currently carries
   7.1. Per-channel `linux` versions checked 2026-07-11 (pulled each mirror's
   `core.db`): stable = `7.0.10`, **rc = `7.0.9`** (older than stable!), edge
   (`mirror.omarchy.org`) = `7.1.3`. So **rc is not a gentler route to 7.1** —
   it snapshots the next Omarchy *release*, not the newest kernel. `edge`
   moves the WHOLE system to near-Arch-current, not just the kernel. Going
   back (`omarchy-channel-set stable`) runs `pacman -Syyuu` to downgrade
   everything to stable versions — supported/reversible, but a whole-system
   downgrade can occasionally need a manual pacman nudge. Big hammer for one
   kernel.
3. **Surgical `pacman -U`** of just `linux` + `linux-headers` 7.1.3 fetched
   from a real Arch mirror, staying on stable for everything else — most
   targeted, but off Omarchy's sanctioned path (mind partial-upgrade caveats;
   the dkms hook will still rebuild mt76 against the new headers).

Prefer (1) unless impatient. Everything below assumes 7.1 has become
installable by one of those routes.

**Step 0 — safety net (do NOT skip).** Have a non-wifi path online ready in
case the mainline driver misbehaves and you must reinstall morrownr: phone
**USB tethering** (`usb0`, no driver needed — see end of this doc) is the
proven one. Confirm `dkms status` shows `mt76/1.0` installed so the rollback
source is intact.

**Phase 1 — upgrade the kernel, keep all fixes (safety checkpoint).**
```bash
sudo pacman -Syu                 # pulls linux 7.1.x + matching headers
dkms status                      # confirm mt76/1.0 rebuilt for the NEW 7.1.x
                                 # (if missing: sudo dkms autoinstall)
sudo reboot
```
After reboot: `uname -r` shows 7.1.x and wifi still works — **via morrownr**
(its blacklist still keeps the in-kernel driver out). This separates "did the
kernel bump boot cleanly" from "does the mainline driver work," so a failure
here can't be mistaken for a driver-swap failure.

**Phase 2 — strip the fixes, switch to the in-kernel driver.**
```bash
sudo dkms remove mt76/1.0 --all                          # drop out-of-tree driver
sudo rm /etc/modprobe.d/mt76_git.conf                    # remove blacklist + disable_clc
sudo rm /etc/udev/rules.d/81-wifi-powersave-off.rules    # migration 13 (see table)
sudo mkinitcpio -P                                       # flush any baked-in blacklist
sudo reboot
```

**Phase 3 — verify plain 7.1.**
```bash
uname -r                                  # 7.1.x
lsmod | grep mt7921                       # mt7921e / mt7921_common — NO _git suffix
iw dev wlan0 info                         # interface came up on the in-kernel driver
bluetoothctl list                         # BT may now enumerate (mainline btmtk)
```
Then run **the probe** (in the congestion section) on the home SSID's 5GHz for a clean
baseline of the mainline driver in this RF environment.

**Phase 4 — redo fixes selectively, only if the baseline shows the need.**

| Fix | Redo action | When |
| --- | --- | --- |
| Power-save off (migration 13) | re-run `migrations/0000000013_*.sh` | almost certainly — it fixed a real RDP drop unrelated to the chip; mainline `mt7921e` also defaults power-save on |
| CLC / TX clamp (migration 16) | `echo 'options mt7921_common disable_clc=Y' \| sudo tee /etc/modprobe.d/mt7921-clc.conf` — **non-`_git` name, fresh file, NOT the morrownr conf** | only if the DFS clamp reproduces on mainline (re-test first) |
| DHCP-wedge reload | ad-hoc `sudo modprobe -r mt7921e mt7921_common; sudo modprobe mt7921e` | only if the wedge recurs on mainline |

**Repo bookkeeping** (so migrations don't misfire on a future replay/reset):
- **Migration 13** — keep; driver-agnostic (udev rule on `wlan*`), works
  identically on the in-kernel driver.
- **Migration 16** — dead as written (targets `_git` names + the morrownr
  conf). Retire it, or rewrite against `mt7921_common` in its own conf file,
  gated on the clamp actually reproducing. Decide once Phase 3 tells us
  whether mainline still clamps.

**Rollback** if mainline wifi is worse: get online via USB tether, then
`git clone https://github.com/morrownr/mt76.git && cd mt76 && sudo sh
install-driver.sh` (rewrites `mt76_git.conf`, re-blacklists the in-kernel
modules), and re-run migrations 13 + 16 — back to today's setup.

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

## Trackpad dies mid-session — and takes suspend down with it

Seen twice as of 2026-07-11: the trackpad — PixArt `093A:3003`, ACPI
`ASUP1303:00`, an I2C-HID device on the AMD I2C controller
(`AMDI0010:03`) — stops responding mid-session. The controller chip wedges
on the I2C bus and, like the Bluetooth chip, keeps standby power through
soft resets, so once wedged it stays wedged until real power removal.

The dangerous part: **suspending while the trackpad is dead hangs the
entire machine** — screen off, no response, only holding the power button
gets you out. Suspend is cooperative: the kernel asks every device to
sleep, and the i2c-hid sleep command to the wedged chip never completes,
so s2idle entry stalls partway through. Confirmed in both directions:
both total-hang incidents were suspends attempted with a dead trackpad,
and **suspend works fine when the trackpad is healthy** (the earlier
"suspend is just broken on this laptop" conclusion was wrong).

Recovery when the trackpad dies, in order:

1. Driver rebind — free, takes seconds (untested so far, may not help if
   the chip itself needs power cut):
   ```bash
   sudo modprobe -r i2c_hid_acpi && sudo modprobe i2c_hid_acpi
   ```
2. Full shutdown → power on. This is what has worked both times. (A warm
   `reboot` may not cut the chip's standby power — untested.)
3. **Never suspend as a recovery step.**

Root cause not yet investigated. Next time it dies, before rebooting,
capture the evidence:

```bash
journalctl -k | grep -iE 'i2c_hid|ASUP1303|pinctrl|irq'
```

Prime suspect on these AMD platforms: a GPIO interrupt issue
(`pinctrl_amd`) killing the touchpad's interrupt line. With that log we
could pursue a real fix (IRQ polling mode, GPIO quirk) instead of
power-cycling.

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
  status of the upstream kernel patches (landed: Linux 7.1, released
  2026-07-04)
- [iwd - ArchWiki](https://wiki.archlinux.org/title/Iwd)
- [basecamp/omarchy troubleshooting manual](https://learn.omacom.io/2/the-omarchy-manual/88/troubleshooting)
- General wifi troubleshooting flow (for future hardware, not MT7902-specific):
  `rfkill list` → `sudo rfkill unblock all` → `systemctl status iwd` →
  `journalctl -k | grep -iE "wlan|wifi|80211|firmware"`
- USB tethering as a no-driver-needed way to get a machine online when
  wifi itself is the thing that's broken: enable on the phone under
  Settings → Network & Internet → Hotspot & Tethering → USB tethering,
  standard in-kernel USB networking (`usb0`), no drivers to install
