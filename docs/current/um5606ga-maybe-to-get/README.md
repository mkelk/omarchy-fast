# ASUS Zenbook S16 UM5606**GA** — Omarchy compatibility notes (candidate machine)

> **Status: MAYBE TO GET — researched 2026-07-24, not purchased.**
> Prospective replacement/second machine. This is desk research against the
> ArchWiki + community reports, *not* hands-on. The one thing to verify on a
> real unit before buying is the **internal microphone** (see below).

The model under consideration is the **UM5606GA** (2026 refresh: AMD **Ryzen AI 7
445** / also sold as **Ryzen AI 9 465**, Strix Point, Radeon 890M, 16" 3K OLED
120 Hz touch, WiFi 7). Note the suffix: most ArchWiki/community docs describe the
older **UM5606WA** (Ryzen AI 9 365 / HX 370). **The GA is a newer silicon/BIOS
revision and behaves differently for audio** — see the audio section.

## TL;DR verdict

Meaningfully **friendlier than the Vivobook M1505YA**, but not hassle-free. The
Vivobook's *catastrophic* problems are all absent here:

- **WiFi works** (MediaTek MT7925, in-kernel `mt7925e`) — **no card swap** like the
  MT7902 needed. Same vendor family, so occasional instability, but it functions.
- **Touchpad enumerates as PS/2**, not I2C-HID → the I2C-bus-wedge failure mode
  that plagues the Vivobook [[trackpad-i2c-wedge]] **structurally cannot happen**.
- **USB-C video works** — USB4 with DP-alt mode (Vivobook had none [[usbc-no-video]]).

What's left is a set of documented one-time tweaks (perfect migration fodder) plus
one manual BIOS flash — and one genuine open question (the mic).

## Hardware compatibility (ArchWiki table — primarily the WA variant)

| Component | ID | Works? |
|---|---|---|
| Touchpad / touchscreen / keyboard | PS/2 | Yes |
| GPU (Radeon 890M) | 1002:150e | Yes |
| NPU (XDNA) | 1022:17f0 | Yes (but userspace WIP) |
| Webcam | 3277:0059 | Yes |
| Ambient Light Sensor | — | Yes |
| Bluetooth | 13d3:3608 | Yes (resume quirk, below) |
| SD-card reader | 17a0:9755 | Yes |
| Audio | 1022:15e3 | **Yes on WA / needs quirk on GA (below)** |
| Wireless MT7925 | 14c3:7925 | Yes (may be unstable) |
| Thunderbolt/USB4 | 1022:151c | Yes |
| TPM | 1022:17e0 | Yes |
| Fans | — | Yes (4 profiles via `asus-5606-fan-state-git`) |

No fingerprint-reader row → this chassis has none (Windows Hello is IR-camera).

## ⚠️ Audio on the GA is NOT plug-and-play (differs from ArchWiki/WA)

The ArchWiki says "audio fully working on Linux ≥6.13" — **that is the WA**. On the
**GA**, the BIOS sets `acp-audio-config-flag = 0x10`
(`FLAG_AMD_LEGACY_ONLY_DMIC`), which forces the ACP into a legacy DMIC-only I2S
path and **never starts the SoundWire bus where the speaker amps live**. Result on
a stock kernel (confirmed Fedora 44, kernel **7.0.4**, May 2026): *no internal
audio device at all* — `"No matching ASoC machine driver found"`.

**Fix (speakers): a one-line DMI quirk** adding the UM5606GA to the kernel's
`acp70_acpi_flag_override_table` so it takes the SoundWire path. Yiin packages
this as a **DKMS module** (survives kernel updates, trivial to remove once
upstream): https://gist.github.com/Yiin/8308c3ba6e5badab1098a7378f9f807f
— tested Linux **7.0.9**, June 2026, gist last active **17 Jul 2026**. Not yet
upstream as of this research.

## ⚠️ Internal microphone — the open question (deep-dive, see mic-research.md)

**Bottom line: unconfirmed on the GA. Verify on a real unit before buying if you
rely on the built-in mic** (relevant given the dictation interest —
[[wispr-flow-wedges-hyprland]]).

- The internal mic is a **Digital Mic Array (DMIC) wired to the AMD ACP/NPU**.
  This is a **generation-wide Strix Point (ACP 7.0) gap**, not UM5606-specific:
  the ACP inits but no PCM capture device is created because **UCM profiles for
  ACP 7.0 are missing** (`alsa-ucm-conf` #745), and firmware doesn't broadcast
  the expected ACPI ID.
- On the **WA**, `alsa-ucm-conf` #561 reports the **digital Mic1 dead**, but an
  **analog Mic2 works** as "Internal Stereo Microphone" — i.e. *some* internal
  mic works there.
- On the **GA**, the same BIOS `LEGACY_ONLY_DMIC` flag is in play. Once the
  SoundWire quirk (above) is applied, the mic *may* come up too — but **no source
  found definitively confirms a working internal mic on the GA** as of Jul 2026.
  The DKMS gist only verifies speakers.
- Upstream trajectory is positive: Linux **6.17** added ACP **7.2** DMIC/machine-
  driver plumbing (dmic-codec, SoundWire 4-mic array, VAD), but **ACP 7.0**
  (what the GA has) still trails on UCM profiles.

**Worst case:** no internal mic → use BT/USB mic. **Likely case:** mic works after
the same SoundWire quirk or via an analog path, but treat as unverified.

## Other one-time workarounds (all scriptable → migration TODO)

1. **Stability kernel param:** `amdgpu.dcdebugmask=0x200` to disable PSR2-SU
   (Strix Point freeze bug persists even on new kernels until disabled-by-default
   upstream). Use `0x600` to fully disable PSR if issues remain. Add
   `amdgpu.sg_display=0` if driving external monitors. Also needed on the install
   ISO (`amdgpu.dcdebugmask=0x600`) to avoid freeze during setup.
2. **WiFi may be unstable:** switch to **iwd** (already our stack) + a device-
   dependency `iwd.service` drop-in keyed on the wlan device path (find via
   `readlink -f /sys/class/net/wlan0`). Powersave-off migration `0000000013`
   still applies.
3. **Bluetooth dies after resume** (MT7925 BT on USB): udev rule setting
   `power/control=on` for the BT device (`13d3:3602`-ish) to stop USB autosuspend
   killing it on wake. If it deadlocks (repeated `error -110`), a **cold boot** is
   required (power off, unplug, hold power 20–30 s). Matters for the Logitech MX +
   built-in BT [[wireless-card-intel-swap]].
4. **120 Hz destroys battery** unless fixed: at 2880×1800@120 Hz the tight vblank
   pins MCLK/FCLK high (~800 MHz vs 400 idle). Custom-EDID modeline (vblank 24→40,
   pixel clock 657.984 MHz) via `drm.edid_firmware=eDP-1:edid/...bin` + initramfs
   drops idle to ~6–8 W. Panel-model-gated (ATNA60CL10-0) — verify before applying.
   Fiddly but one-time.
5. **BIOS update (manual):** apply via EZ Flash (the "for ASUS EZ Flash Utility"
   file, *not* the Windows one) — fixes the touchpad 1–2 s freeze quirk + power
   behavior. `asus-5606-firmware-check-git` (AUR) can auto-check for updates.
6. **Lid-wake / suspend power:** optional `acpi_mask_gpe=0x04` (block lid-switch
   wake) + USB autosuspend udev rules per ArchWiki.

## Migration TODO (if purchased)

- [ ] `install_um5606ga_audio_dkms.sh` — Yiin SoundWire DKMS quirk
- [ ] `um5606ga_amdgpu_params.sh` — `amdgpu.dcdebugmask=0x200` (+`sg_display=0`)
- [ ] `um5606ga_wifi_iwd_dependency.sh` — iwd device-dependency drop-in
- [ ] `um5606ga_bt_resume_fix.sh` — BT USB autosuspend udev rule
- [ ] `um5606ga_edid_120hz_battery.sh` — custom EDID (panel-gated, guard on model)
- [ ] Manual/local-setup: BIOS EZ-Flash update; **verify internal mic**

## Sources

- ArchWiki — ASUS Zenbook UM5606: https://wiki.archlinux.org/title/ASUS_Zenbook_UM5606
- GA speaker DKMS quirk (Yiin): https://gist.github.com/Yiin/8308c3ba6e5badab1098a7378f9f807f
- Fedora Discussion — UM5606GA no internal audio (kernel 7.0.4, May 2026):
  https://discussion.fedoraproject.org/t/internal-audio-speakers-mic-not-detected-asus-zenbook-s-16-um5606ga-ryzen-ai-9-465-fedora-44/191141
- alsa-ucm-conf #561 — UM5606 DMIC dead, analog Mic2 works:
  https://github.com/alsa-project/alsa-ucm-conf/issues/561
- alsa-ucm-conf #745 — Missing UCM profile for ACP 7.0 DMIC:
  https://github.com/alsa-project/alsa-ucm-conf/issues/745
- Phoronix — Linux 6.17 ACP 7.2 sound support:
  https://www.phoronix.com/news/Linux-6.17-Sound
- Install writeup (chaos-reins, WA): https://chaos-reins.com/2024-09-04-zenbook-s16/
