# Hibernate on the Dell XPS 16

## Current status

**Resolved and stable as of 2026-08-14.**

The machine has completed five successful hibernate/resume round trips since
2026-07-19, including restoration of an approximately 24 GiB image. Long s2idle
suspends have also resumed successfully.

Current verified setup:

- Machine: Dell XPS 16 DA16260, Panther Lake, BIOS 1.8.2.
- Kernel when last audited: `7.1.7+deb14-amd64`.
- RAM: approximately 62 GiB.
- Swap: `/dev/mapper/vg0-lv0swap`, approximately 71 GiB.
- `/etc/initramfs-tools/conf.d/resume` contains
  `RESUME=/dev/mapper/vg0-lv0swap` and is responsible for locating the image
  after the encrypted volume is unlocked.
- The kernel command line does not need an early `resume=` argument for this
  encrypted LVM layout.
- `HibernateMode=platform shutdown`. systemd tries the listed values in order;
  this machine accepts and uses `platform`, which has worked repeatedly.
- The power key hibernates directly. Closing the lid suspends using s2idle.
  Suspend-then-hibernate is deliberately not enabled.

Do not re-add `init_on_free=1`. On kernels 7.0 and 7.1 it reproducibly caused a
hard hang immediately after the hibernation image reached 100% during restore.
The machine resumed once `slab_nomerge init_on_free=1` were removed. They were
removed together rather than bisected, so `init_on_free=1` is the strongest
suspect but not independently proven.

## Relevant repository configuration

- `etc/systemd/sleep.conf`: hibernation disk mode.
- `etc/systemd/logind.conf`: power-button and lid actions.
- `bin/install.sh`: verifies that the initramfs resume configuration exists and
  documents why the problematic kernel hardening arguments remain absent.

Apply changes to logind at reboot. Restarting `systemd-logind` terminates the
active X11 session on this machine.

## Recovery after a failed resume

1. Hold the power button for at least 10 seconds to power the machine off.
2. At the next GRUB menu, edit the default entry and append `noresume` to its
   `linux` line, then boot with Ctrl-X or F10. This ignores the saved image and
   starts a fresh system.
3. After booting, check the configured swap device in `/etc/fstab` and
   `/etc/initramfs-tools/conf.d/resume`, then try `sudo swapon -a`.
4. If the swap LV still carries a stale suspend image, verify its device and
   UUID with `sudo blkid /dev/mapper/vg0-lv0swap`. Only after confirming both,
   recreate the swap signature with
   `sudo mkswap -U <verified-uuid> /dev/mapper/vg0-lv0swap`, followed by
   `sudo swapon -a`. This destroys the stale hibernation image.
5. If the system cannot reach GRUB, perform a Dell EC reset: disconnect power,
   hold the power button for approximately 30 seconds, then boot normally.

Never restore the old UUID formerly recorded in this document without first
checking the live swap configuration.

## Historical diagnosis

Initial failures occurred on kernels 7.0.12 and 7.1.3. The image loaded to 100%,
then the restored kernel hard-hung before journald could record anything. Both
`platform` and `shutdown` modes failed.

Several display-oriented experiments were useful for exclusion but did not fix
the problem:

- `xe.enable_psr=0 xe.enable_dc=0`
- `xe.enable_dsb=0`
- `xe.probe_display=0` (this also broke a normal boot and must not be retried)

Removing `slab_nomerge init_on_free=1` produced the first successful round trip
on 2026-07-17. The normal quiet kernel command line was restored afterward, and
subsequent successful cycles established the current baseline.

When testing after a kernel upgrade, reboot into that kernel before hibernating.
Booting a different kernel after writing the image can discard it like a power
loss and invalidates the test.
