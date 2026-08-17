# Hibernate on the Dell XPS 16

## Current status

**Not yet reliable as of 2026-08-17.**

The machine has completed five successful hibernate/resume round trips since
2026-07-19, including restoration of an approximately 24 GiB image. Long s2idle
suspends have also resumed successfully. However, a later hibernate exposed a
`btintel_pcie` D3-transition bug and the subsequent retry hung during restore.

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
- `systemd-hibernate.service` has a local drop-in that calls
  `bin/hibernate-device-hook`. It unbinds the Intel Bluetooth PCIe device before
  hibernation and rebinds it after either restore or rollback, avoiding the
  driver's unreliable hibernation callback. The sysfs unbind is synchronous,
  and the hook additionally waits for both driver symlinks to disappear; if
  that postcondition is not reached, `ExecStartPre` fails and hibernation is
  aborted before an image is written.

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

### Bluetooth D3 failure and consumed image (2026-08-17)

The first hibernate attempt wrote a complete compressed image, but
`btintel_pcie` then timed out waiting for its D3 alive interrupt and returned
`-EBUSY`. The kernel rolled hibernation back, with Bluetooth reprobe failures
and IPU7 firmware-authentication errors during recovery. A second hibernate was
requested about three minutes later. Its first restore attempt hung and was
force-reset; the following cold boot correctly found no `S1SUSPEND` signature,
because Linux clears that signature as soon as it accepts an image for restore.

Upstream [patchwork entry 14560272](https://patchwork.kernel.org/project/bluetooth/patch/20260507203426.128975-1-vladimirkondratyev2@gmail.com/)
documents a matching unmerged driver bug: when the alive interrupt is missed,
`btintel_pcie_set_dxstate()` checks a stale cached boot stage and can falsely
return `-EBUSY`. The local workaround unbinds PCI device `0000:00:14.7` before
`systemd-sleep` invokes the kernel hibernation path. Do not retry hibernation
after a rollback; reboot first so all affected devices start from a clean
state.

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
