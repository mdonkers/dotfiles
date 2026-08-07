# Hibernate debugging — state & recovery notes

**STATUS: RESOLVED 2026-07-17.** Hibernate works. Root cause: the hardening kernel
params `slab_nomerge init_on_free=1` broke the image restore (hard hang at the jump,
no logs). User chose to keep BOTH off rather than bisect (init_on_free=1 is the likely
sole culprit if ever revisited — same class as 2019 commit 18451f9f9e58).

Finalized 2026-07-18:
- suspend-then-hibernate active: logind Handle{PowerKey,LidSwitch,LidSwitchExternalPower}
  =suspend-then-hibernate + sleep.conf HibernateDelaySec=30min.
- `resume=` removed from GRUB again — provably a no-op on LUKS (kernel processes it
  before the volume is unlocked); /etc/initramfs-tools/conf.d/resume does the actual
  resume. install.sh no longer touches GRUB_CMDLINE_LINUX, only sanity-checks that file.
- /etc/default/grub.bak-hibernate removed. linux-pm report drafted (Gmail auth expired;
  text at scratchpad/linux-pm-report.txt).
- LESSON: `systemctl restart systemd-logind` KILLS the X11 session on this machine —
  apply logind.conf changes at reboot instead.

Final config:
- `/etc/default/grub`: `GRUB_CMDLINE_LINUX="resume=/dev/mapper/vg0-lv0swap"`,
  `GRUB_CMDLINE_LINUX_DEFAULT="quiet"` (restored). Pre-testing backup (with hardening
  params, no resume=): `/etc/default/grub.bak-hibernate`.
- `etc/systemd/sleep.conf` (repo, hard-linked): `HibernateMode=shutdown`. Note:
  `platform` mode was never retested without the hardening params — it may work too,
  but `shutdown` is proven and kept.
- Uncommitted in the dotfiles repo: modified `etc/systemd/sleep.conf` + this file.
- Open ideas: validate a few more cycles (marker app, cold overnight), consider
  suspend-then-hibernate for lid/power key (logind.conf), report the init_on_free
  restore regression to linux-pm / regressions@lists.linux.dev.

Machine: Dell XPS 16 (DA16260), Panther Lake, Arc B390 (xe driver), BIOS 1.5.1, 62 GiB RAM.
Session started: 2026-07-17. Claude Code session lives in `~/.claude/projects/-home-miel-dotfiles/`.
To resume the debugging session after a reboot/crash: `cd ~/dotfiles && claude --resume` and pick the hibernate session.

## If the system fails to boot after a hibernate test — RECOVERY

1. Force power off: hold the power button ≥ 10 s.
2. Power on. At the GRUB menu, press `e` on the default entry, find the line
   starting with `linux`, append ` noresume` to it, then press `Ctrl-X` (or F10)
   to boot. This boots fresh and ignores the hibernation image.
3. After booting with `noresume`, swap will fail to activate (its signature
   still says "S1SUSPEND"). Re-initialise it, keeping the same UUID:

       sudo mkswap -U d62d4066-b261-45a1-9aad-dc7e15386f80 /dev/mapper/vg0-lv0swap
       sudo swapon -a

   (`mkswap` on the swap LV only destroys the stale hibernation image — nothing else.)
4. If GRUB never appears at all (stuck at Dell logo / black screen): this is a
   firmware-level S4 problem, not an OS one. Try holding power 30 s (Dell EC
   reset), or unplug AC + hold power 30 s, then boot normally.
5. `cd ~/dotfiles && claude --resume` to continue the session.

## System facts (verified 2026-07-17)

- Swap: `/dev/mapper/vg0-lv0swap`, 72 GiB LV inside LUKS (`nvme0n1p8_crypt`) → LVM `vg0`. RAM 62 GiB, so size is fine.
- `/etc/initramfs-tools/conf.d/resume`: `RESUME=/dev/mapper/vg0-lv0swap` — present in both installed initrds, resume script + cryptsetup included. Resume-check works (every boot logs `PM: Image not found (code -22)` after unlocking LUKS = it looks at the right device).
- Kernel cmdline: `root=/dev/mapper/vg0-lv1root ro rootflags=subvol=@rootfs slab_nomerge init_on_free=1 quiet` — **no `resume=`** (not strictly needed with initramfs-tools, but we plan to add it).
- Secure Boot: disabled. Kernel lockdown: `[none]`. `CanHibernate` → yes. ACPI supports S4. `/sys/power/disk` = `[platform] shutdown ...`.
- No out-of-tree/DKMS modules (IPU7 webcam stack is in-tree; GPU = xe).
- `/etc/systemd/sleep.conf` and `logind.conf` are **hard links** to `~/dotfiles/etc/systemd/*` (Makefile `ln -f`). sleep.conf is currently all defaults.
- logind: power key & lid = suspend (s2idle) — no accidental hibernate paths.

## What happened on the failed attempt (from journal forensics)

- Boot `-2` ended Jun 23 13:40:38 with `PM: hibernation: hibernation entry` (manual hibernate, kernel 7.0.12, HibernateMode=platform). Image write & poweroff apparently completed.
- Next journal entry is a **fresh** boot at 13:56 (also 7.0.12) with no resume messages → the resume attempt(s) in the 16-minute gap hung/crashed before any logging is possible (restore happens before journald), user force-cycled. Same kernel on both sides, so it was NOT a kernel-version mismatch.
- Leading suspects: (a) xe/Panther Lake restore bug in 7.0.x, (b) Dell firmware ACPI-S4 (platform mode) handoff.

## Trap discovered (would corrupt the next test)

Kernel `7.1.3+deb14` was installed 2026-07-17 15:14 while running `7.0.12`. GRUB default (entry 0) now boots 7.1.3. Hibernate under 7.0.12 + power-on into 7.1.3 = image silently discarded (equivalent to power loss). **Always reboot into the current default kernel before testing hibernate.**

## Plan (pending user approval)

1. Reboot into 7.1.3 (new default; also newest Panther Lake fixes).
2. `/etc/default/grub`: add `resume=/dev/mapper/vg0-lv0swap` to `GRUB_CMDLINE_LINUX`; temporarily drop `quiet` from `GRUB_CMDLINE_LINUX_DEFAULT` for visible resume progress; `sudo update-grub`.
   Rollback: restore previous values (`GRUB_CMDLINE_LINUX="slab_nomerge init_on_free=1"`, `GRUB_CMDLINE_LINUX_DEFAULT="quiet"`) + `sudo update-grub`.
3. `etc/systemd/sleep.conf` (repo, hard-linked): set `HibernateMode=shutdown` under `[Sleep]` (bypasses Dell ACPI-S4 platform handoff — common fix). Rollback: re-comment.
4. Test: close work, `sync`, `echo 1 | sudo tee /sys/power/pm_debug_messages`, then `sudo systemctl hibernate` from a terminal. Power on, enter LUKS passphrase, watch console output.
5. If it works: repeat once with an open marker app; later consider `HibernateMode=platform` A/B, re-add `quiet`, and `suspend-then-hibernate` for lid/power key.

## Log of actions taken

- 2026-07-17: investigation; created this file.
- 2026-07-17: user confirmed the June 23 failure hung **after** LUKS unlock → kernel
  image-restore hang (xe/Panther Lake suspect), not firmware.
- 2026-07-17 (all approved by user):
  - `etc/systemd/sleep.conf`: set `HibernateMode=shutdown`; re-hard-linked into
    /etc (editors break the link — run `sudo ln -f` or `make etc` after editing).
  - `/etc/default/grub`: added `resume=/dev/mapper/vg0-lv0swap` to `GRUB_CMDLINE_LINUX`;
    removed `quiet` (temporary, for visible resume progress). Backup saved at
    `/etc/default/grub.bak-hibernate`. Ran `update-grub`; default entry boots 7.1.3;
    all 5 kernel lines carry `resume=`.
- 2026-07-17 ~16:21: **Test #2 failed the same way** (kernel 7.1.3, HibernateMode=shutdown):
  image loaded to **100%** on screen, then black. Journal of the hibernating boot ends at
  `PM: hibernation: hibernation entry` — nothing logged after the restore jump, so the
  restored kernel died/wedged during **device re-init**, before userspace thawed.
  Both `platform` (June) and `shutdown` modes fail identically → not the firmware handoff.
  Suspend (s2idle) works daily → specifically the S4 restore path of the display stack.
- Evidence pointing at the panel/display: current boot logs
  `xe ... Selective fetch area calculation failed in pipe A` (PSR selective-fetch glitch).
  xe is NOT in the initramfs (image-load text renders via firmware framebuffer), so no
  boot-kernel GPU interference — restored xe resumes from cold hardware.

## Test #3 result (2026-07-17 ~17:02) — FAILED, same signature

- `xe.enable_psr=0 xe.enable_dc=0` did NOT help: image loaded to 100%, black screen,
  **Caps Lock LED dead** → kernel hard-hung during device re-init (not display-only).
- Journal again ends at `PM: hibernation: hibernation entry`; nothing after the jump.
- Correction: the `Selective fetch area calculation failed in pipe A` warning still
  appears every boot even with PSR off (earlier "gone" observation was a bad grep).

## Root-cause lead (web research)

- basecamp/omarchy#5573: Dell **XPS 14 DA14260, same GPU device 8086:b080** — xe
  regression between 6.19.13 and 7.0.3: **DSB (Display State Buffer) deadlocks**
  (`DSB 0 poll error`, `DSB 0 timed out waiting for idle`), same selective-fetch
  warning. Their machine deadlocks at boot; ours boots but likely deadlocks in the
  DSB during the display resume commit after image restore.
- Debian kernel has **no /sys/power/pm_trace** (CONFIG_PM_TRACE_RTC off) → RTC
  device-blame diagnostic unavailable.

## Test #4 (2026-07-17 ~17:3x, user approved): `xe.enable_dsb=0`

- Added to GRUB_CMDLINE_LINUX (now: `... resume=... xe.enable_psr=0 xe.enable_dc=0
  xe.enable_dsb=0`), update-grub run. Awaiting reboot + hibernate test.
- If it WORKS: strip psr/dc params one at a time to find the minimal set.
- If it FAILS: test #5 = replace xe.* params with `xe.probe_display=0` (display
  engine untouched by xe; console stays on firmware framebuffer → restore messages
  VISIBLE; degraded graphics for that boot only). If that resumes fine → xe display
  is the culprit; if still hangs → suspects move to GT/GuC, NVMe, Intel ISH, IPU7.

## Test #4 result (2026-07-17 ~17:5x) — FAILED, same signature

- `xe.enable_dsb=0` did not help. 100% load → black. Caps Lock dead, keyboard
  backlight dead, device never appeared on the router (no network → no SSH).
- Insight: Caps Lock death does NOT prove a full CPU hang — the LED needs the
  keyboard driver already resumed; a resume stuck on any earlier device looks identical.

## Test #5 (user approved): diagnostic boot with `xe.probe_display=0`

- GRUB_CMDLINE_LINUX now: `slab_nomerge init_on_free=1 resume=/dev/mapper/vg0-lv0swap
  xe.probe_display=0` (psr/dc/dsb removed — moot without display probe).
- xe skips the display engine → console stays on firmware framebuffer (simpledrm)
  through the whole restore → with pm_debug_messages + pm_print_times + pm_async=0
  the restored kernel prints each device resume ON SCREEN, serialized.
- Expected: graphical session won't start this boot; run test from TTY.
- Outcome A: resume works → xe display resume is the culprit. Next: try params
  enable_flipq=0 / enable_fbc=0 / enable_panel_replay=0 / enable_dmc_wl, newer
  kernel (Debian experimental), or upstream bug report (cf. omarchy#5573).
- Outcome B: hang with device name visible → photograph screen, targeted fix.
- Rollback after test: restore previous GRUB_CMDLINE_LINUX (psr/dc/dsb or clean)
  + update-grub. Full original backup still at /etc/default/grub.bak-hibernate.

## Test #5 attempt (xe.probe_display=0) — ABORTED: breaks normal boot

- With `xe.probe_display=0` the machine hangs during a NORMAL boot (console stopped
  around network/bluetooth init; likely GPU-coupled components — SOF HDMI audio,
  mei_gsc_proxy — deadlock when the display engine is absent). User recovered by
  editing the GRUB entry at boot. Param removed from /etc/default/grub again.
  **Do not retry probe_display=0 on this platform.**

## Research status (2026-07-17 evening)

- Debian: 7.1.3 is the newest kernel in testing AND unstable; nothing newer in
  experimental → no packaged-kernel escape hatch.
- drm/xe GitLab issue tracker blocks anonymous fetching (Access Denied) — check
  manually in a browser if needed: https://gitlab.freedesktop.org/drm/xe/kernel/-/issues
- User confirms s2idle suspend works reliably on 7.1.3 → xe suspend/resume healthy;
  failure is specific to the S4 restore jump.

## Test #5 (user approved): remove hardening params

- Theory: `init_on_free=1` (with `slab_nomerge`) corrupts the restore — same class as
  the historic 2019 bug (commit 18451f9f9e58, "PM: hibernate: fix crashes with
  init_on_free=1"). Explains: instant hard hang at jump, both kernels affected, immune
  to all xe params, works-for-everyone-else, healthy s2idle.
- GRUB_CMDLINE_LINUX now: `resume=/dev/mapper/vg0-lv0swap` (hardening params removed
  FOR TESTING; restore after verdict — that's a security trade-off the user decides).
- If resume WORKS: bisect — re-add `slab_nomerge` alone (likely innocent), test again;
  then decide keep-or-drop `init_on_free` (hibernate vs hardening) and consider
  reporting the regression to linux-pm.
- If it FAILS: next = one boot with `modprobe.blacklist=xe` (session on firmware
  framebuffer, software rendering; should boot OK unlike probe_display=0) + hibernate
  test → decisively convicts/exonerates xe entirely. After that: mainline/self-built
  7.2-rc kernel, device-exclusion tests (IPU7, SOF), upstream bug report.

## Test #5 result (2026-07-17 23:16–23:18) — **SUCCESS** 🎉

- Without `slab_nomerge init_on_free=1`: full hibernate round-trip on kernel 7.1.3,
  HibernateMode=shutdown. Journal: `hibernation entry` 23:16:47 → power off →
  `hibernation exit` / `Restarting tasks: Done` 23:18:55, same boot continuing.
- ROOT CAUSE (modulo final bisect): the hardening kernel params — almost certainly
  `init_on_free=1` — corrupt the restore, hard-hanging at the jump. Same failure class
  as the 2019 bug fixed by commit 18451f9f9e58; evidently regressed on 7.x kernels.
  All the xe/display theories were red herrings.
- Remaining: bisect (re-add `slab_nomerge` alone + one more hibernate test), then
  decide trade-off for `init_on_free` (hibernate vs zero-on-free hardening), restore
  `quiet`, consider reporting regression to linux-pm / regressions@lists.linux.dev.

## Old plan notes (test #3)

- APPLIED 2026-07-17 ~16:45 (user approved): `xe.enable_psr=0 xe.enable_dc=0` added to
  `GRUB_CMDLINE_LINUX`, update-grub run. Awaiting reboot + hibernate test.
- Add `xe.enable_psr=0 xe.enable_dc=0` to `GRUB_CMDLINE_LINUX` (disable Panel Self
  Refresh + display C-states — the two classic "resume works but panel black" culprits).
  Cost: slightly higher idle power. Rollback: remove params + `update-grub`.
- Proof-of-life protocol if the screen goes black again (BEFORE force-cycling):
  1. From the other machine: `ssh codepaper` (sshd is enabled+active). If it answers,
     the system is alive and it's display-only → grab `dmesg`/journal immediately,
     then `sudo systemctl reboot`.
  2. Toggle Caps Lock — LED toggling = kernel alive.
  3. Only then force power-off (hold ≥10 s).
