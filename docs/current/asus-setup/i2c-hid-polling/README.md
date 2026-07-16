# i2c-hid-polling — trackpad IRQ-wedge workaround

Fixes the ASUS Vivobook trackpad (PixArt `093A:3003`, ACPI `ASUP1303:00`)
dying mid-session. Root cause: its `amd_gpio` interrupt (IRQ 80, `pinctrl_amd`
pin 16) silently wedges — the chip stays alive on the I2C bus, but the driver
never gets told there's data. See the full diagnosis in
[`../README.md`](../README.md) ("Trackpad dies mid-session — SOLVED").

This is the stock **kernel 7.0** i2c-hid driver with a `polling_mode` module
parameter added, packaged as a DKMS module so it rebuilds on kernel updates.
When enabled it reads the touchpad on an 8 ms timer instead of waiting for the
dead interrupt.

## What's here

| file | it is |
|------|-------|
| `i2c-hid-core.c` | stock 7.0 core **+ our polling changes** (the only patched file) |
| `i2c-hid-acpi.c`, `i2c-hid-dmi-quirks.c`, `i2c-hid.h`, `hid-ids.h` | pristine 7.0, vendored so it builds in a flat dir |
| `polling-mode.patch` | our change *in isolation* (+75/−11), against pristine `v7.0` core — the re-port artifact |
| `Makefile`, `dkms.conf` | out-of-tree / DKMS build glue |

## Install (durable)

```bash
sudo cp -r docs/current/asus-setup/i2c-hid-polling /usr/src/i2c-hid-polling-7.0
sudo dkms add     -m i2c-hid-polling -v 7.0
sudo dkms build   -m i2c-hid-polling -v 7.0
sudo dkms install -m i2c-hid-polling -v 7.0
echo 'options i2c_hid polling_mode=1 polling_interval_ms=8' | \
  sudo tee /etc/modprobe.d/i2c-hid-polling.conf
dkms status i2c-hid-polling      # expect: installed
```

The modules land in `updates/`, which depmod prefers over the in-tree drivers.
Not in the initramfs/UKI (`MODULES=()`, not on the root path), so no
`mkinitcpio` rebuild is needed — verified with `lsinitcpio`.

## Recover a live wedge without rebooting

```bash
sudo rmmod i2c_hid_acpi i2c_hid
sudo insmod /usr/src/i2c-hid-polling-7.0/i2c-hid.ko polling_mode=1 polling_interval_ms=8
sudo insmod /usr/src/i2c-hid-polling-7.0/i2c-hid-acpi.ko
```
Success looks like: `polling mode enabled (8 ms); IRQ 80 bypassed` in `dmesg`.

## Uninstall (e.g. if a future kernel fixes this upstream)

```bash
sudo dkms remove -m i2c-hid-polling -v 7.0 --all
sudo rm -f /etc/modprobe.d/i2c-hid-polling.conf /usr/src/i2c-hid-polling-7.0 -r
```

## Re-port after a MAJOR kernel bump (7.0 → 7.1 …)

This ships a frozen copy of the 7.0 driver. Point releases (7.0.x) rebuild
automatically. A major bump can break the build if i2c-hid's internals
changed — `dkms status` will show it failed/missing, and the trackpad will
wedge again on the stock driver. Re-port:

```bash
# 1. fetch the NEW kernel's pristine i2c-hid sources (match `uname -r`'s tag)
cd /tmp && mkdir report && cd report
TAG=v7.1   # <-- set to the new kernel version
BASE=https://raw.githubusercontent.com/torvalds/linux/$TAG/drivers/hid/i2c-hid
for f in i2c-hid-core.c i2c-hid-acpi.c i2c-hid-dmi-quirks.c i2c-hid.h; do curl -sO $BASE/$f; done
curl -so hid-ids.h https://raw.githubusercontent.com/torvalds/linux/$TAG/drivers/hid/hid-ids.h

# 2. apply our polling change to the new core
patch -p1 < .../i2c-hid-polling/polling-mode.patch
#    If it rejects, hand-merge the ~12 hunks: they only ADD a poll workqueue +
#    two module params, short-circuit the reset wait, and swap
#    enable/disable/free_irq(client->irq) for i2c_hid_*_irq_or_poll(ihid).
#    Nothing structural — a 10-minute merge.

# 3. flat-dir include fixup, then rebuild the DKMS package with a bumped version
sed -i 's#\.\./hid-ids.h#hid-ids.h#' i2c-hid-core.c i2c-hid-dmi-quirks.c
```

## Config-only prevention (investigated 2026-07-16 — unproven, future work)

Web research points at the mechanism being the long-known **pinctrl-amd
level-triggered IRQ bug**: the touchpad holds its GPIO level-low to signal
data, but pinctrl-amd stops re-firing the threaded/oneshot handler (an EOI
isn't sent at the right point), so input stalls silently. That matches our
symptoms exactly (IRQ 80 frozen, chip alive on the bus, nothing logged). It's
been patched kernel-side over the years (`IRQCHIP_EOI_THREADED`, honoring the
BIOS trigger type), so its persistence on 7.0 is likely a residual/variant.

The only **no-compiled-module** candidate that could eventually replace this
DKMS module is disabling the touchpad's runtime-PM autosuspend — some i2c-hid
touchpads wedge across a PM suspend/resume transition:

    # /etc/udev/rules.d/99-i2c-hid-no-autosuspend.rules
    ACTION=="add", SUBSYSTEM=="i2c", KERNEL=="i2c-ASUP1303:00", ATTR{power/control}="on"

**Status: hypothesis only.** It's a general i2c-hid mitigation, not proven
against this AMD pinctrl-amd wedge, and the community threads found no
config-only fix (their "workaround" is just a module reload, which doesn't
even recover our stickier wedge). Worse, it can't be validated cheaply now:
polling mode has *removed* the symptom, so testing means reverting to the
stock interrupt driver + this rule and daily-driving for a week to see if it
still wedges — reintroducing the risk we just eliminated. So: only try it
opportunistically, e.g. during a future kernel re-port, as an A/B before
deciding whether to drop this module.

## Honest robustness note

A full-driver-fork DKMS module is the *pragmatic* fix, not the most robust
possible one — it survives routine updates automatically but needs the manual
re-port above on major kernel jumps, and it diverges from upstream over time.
More robust long-term options, neither available today: (a) a config-only way
to *prevent* the GPIO wedge (no compiled module), or (b) getting a
`polling_mode` param accepted upstream so future kernels have it built in. When
a new kernel lands, first check whether the `pinctrl_amd` bug was fixed —
if so, uninstall this entirely.
