# UM5606GA internal microphone — deep research (2026-07-24)

Focused follow-up on the one unresolved item from `README.md`: **does the
built-in microphone work on Linux on the UM5606GA?** Matters because of the
dictation workflow ([[wispr-flow-wedges-hyprland]]) — a dead internal mic is the
one thing here that no migration can fix.

## Answer in one line

**Not confirmed working on the GA as of Jul 2026.** It's a generation-wide AMD
Strix Point (ACP 7.0) DMIC gap, being actively worked upstream but not fully
landed. Plan for "maybe no internal mic; carry a BT/USB mic" until verified on a
real unit.

## Why it's broken — the chain

1. **Hardware:** the internal mic is a **Digital Mic Array (DMIC)** routed to the
   **AMD ACP** (Audio Co-Processor, part of the NPU complex), *not* a normal
   HD-Audio codec mic. Strix Point uses **ACP 7.0**.
2. **BIOS:** on the GA the firmware sets `acp-audio-config-flag = 0x10`
   (`FLAG_AMD_LEGACY_ONLY_DMIC`), forcing a legacy DMIC-only I2S path and not
   starting SoundWire. (Same flag that kills the speakers until the DKMS quirk.)
3. **Kernel/ALSA:** even when the ACP inits, **no PCM capture device is created**
   for the internal DMIC because **UCM profiles for ACP 7.0 are missing**
   (`alsa-ucm-conf` #745), and the firmware doesn't broadcast the ACPI ID string
   the generic `snd_acp_mach` path expects.

## Evidence by variant (they differ — don't conflate)

- **UM5606WA** (older, Ryzen AI 9 365/HX 370) — `alsa-ucm-conf` **#561** (May
  2025): digital **Mic1 dead** (stays high when toggled), but an **analog Mic2
  works** as "Internal Stereo Microphone." So on the WA there *is* a usable
  internal mic, just not the digital array. The mic-mute LED wrongly tracks the
  dead DMIC.
- **UM5606GA** (the candidate, Ryzen AI 7 445 / AI 9 465) — Fedora 44 thread
  (kernel **7.0.4**, May 2026): *no* internal audio device at all out of box
  (`"No matching ASoC machine driver found"`). Speakers fixed by the SoundWire
  DKMS quirk (Yiin, kernel 7.0.9, Jun 2026) — **but that gist verifies speakers
  only; mic status after the quirk is unstated.**

## Upstream trajectory (reason for cautious optimism)

- **Linux 6.17** added AMD **ACP 7.2** enablement: I2S + **DMIC support in the
  machine driver**, the generic **dmic-codec**, SoundWire management of a
  4-channel mic array with beam-forming, and a VAD pipeline. (Phoronix.)
- BUT 6.17's work targets **ACP 7.2** (next-gen). The GA is **ACP 7.0**, which
  still lags on UCM profiles (#745 open). So the plumbing is arriving; the GA
  specifically may need the profile/quirk backfill to benefit.

## Plausible outcomes on the GA (ranked)

1. **Likely:** after the SoundWire DKMS quirk, an internal mic (analog path like
   the WA's Mic2, or the DMIC once a UCM profile exists) becomes usable — but
   currently **unverified**.
2. **Possible:** DMIC still produces no capture device pending ACP 7.0 UCM
   profiles; workaround = BT/USB mic.
3. **Time-fixes-it:** a DMI quirk + UCM profile lands upstream (the speaker quirk
   already exists out-of-tree; mic likely follows the same route).

## Open question posted (2026-07-24) — awaiting answer

Asked directly on Yiin's gist (as `mkelk`, comment id `6273884`) whether the
internal mic works after the SoundWire quirk, requesting `arecord -l` /
`wpctl status` evidence:
https://gist.github.com/Yiin/8308c3ba6e5badab1098a7378f9f807f

@-mentioned **P4r4d0x42**, who confirmed in an earlier comment (2026-07-17)
that they run the **exact GA model** (UM5606GA-ZB, Ryzen AI 9 465) with the
quirk applied — note their tip: the setup script needed `KREF=v7.0 ./setup.sh`
on kernel 7.0 due to a kernel-structure mismatch.

Replies land in GitHub notifications (commenting auto-subscribes). **When
answered, record the verdict here** and update the TL;DR + README accordingly.

## Pre-purchase verification checklist (on a real/store unit, live USB)

```bash
# boot a recent live ISO (kernel ≥7.0), then:
arecord -l                      # any capture card listed?
wpctl status                    # PipeWire: is a "Source" (mic) present?
# apply Yiin SoundWire DKMS quirk, reboot, re-check arecord -l / wpctl status
dmesg | grep -iE 'acp|dmic|soundwire|sof|ASoC'   # machine-driver / DMIC errors
```

If after the quirk `arecord -l` shows a capture device and `wpctl status` lists a
working Source, the internal mic is fine. If not → BT/USB mic is the fallback.

## Sources

- alsa-ucm-conf #561 (WA, analog Mic2 works): https://github.com/alsa-project/alsa-ucm-conf/issues/561
- alsa-ucm-conf #745 (ACP 7.0 UCM profile missing): https://github.com/alsa-project/alsa-ucm-conf/issues/745
- Fedora Discussion (GA, kernel 7.0.4, May 2026): https://discussion.fedoraproject.org/t/internal-audio-speakers-mic-not-detected-asus-zenbook-s-16-um5606ga-ryzen-ai-9-465-fedora-44/191141
- Yiin SoundWire DKMS quirk (GA speakers, Jul 2026): https://gist.github.com/Yiin/8308c3ba6e5badab1098a7378f9f807f
- Phoronix — Linux 6.17 ACP 7.2 sound: https://www.phoronix.com/news/Linux-6.17-Sound
- Arch forum — acp6x DMIC/ALC25 internal mic: https://bbs.archlinux.org/viewtopic.php?id=311093
