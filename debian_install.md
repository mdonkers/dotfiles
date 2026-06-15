# Install Debian on Dell XPS 16 (2026, DA16260)

Debian testing (forky), i3 / X11, dual-boot alongside Windows.

## Hardware
- CPU Intel Core Ultra (Panther Lake-H); GPU **Intel Arc B390 (Xe3)** -> in-kernel `xe`, needs **kernel >= 6.17**
- Wi-Fi/BT **Intel BE211** (Wi-Fi 7), `iwlwifi`
- Non-touch IPS panel (no OLED) -> X11/i3 is fine, no Wayland needed
- USB-C / Thunderbolt only (USB-A needs an adapter); no fingerprint reader; physical F-row
- Webcam Intel IPU7 (needs out-of-tree `intel_cvs`)

## Decisions
- LUKS2 (Argon2id) -> LVM -> 64 GiB swap LV + btrfs root (subvols + zstd). One unlock; snapshots + clean encrypted hibernation.
- Hibernation ON (swap >= RAM) -> **Secure Boot OFF** (kernel lockdown blocks hibernate).
- GRUB + `grub-btrfs` + `snapper`. Do **not** pin away kernel 7.x (Arc/audio/sensors want it).

## 1. Windows: free space (first)
- BitLocker: `manage-bde -status C:` (Win11 Home + local account = usually off; else save the key: `manage-bde -protectors -get C:`).
- Update the Dell BIOS to latest.
- `powercfg /h off` (kills Fast Startup + hibernation, frees space).
- Shrink `C:` in `diskmgmt.msc`. If blocked by "unmovable files": disable pagefile (`sysdm.cpl` -> Performance -> Advanced -> Virtual memory), disable System Protection + delete restore points, reboot, then shrink. Leave ~80-200 GB for Windows; **rest UNALLOCATED**. Re-enable pagefile/protection after.

## 2. BIOS / UEFI
- Elevated **cmd** (not PowerShell -- it eats the braces): `bcdedit /set {current} safeboot minimal`
- Reboot -> **F2**: SATA/NVMe Operation **RAID -> AHCI/NVMe**; **Secure Boot OFF**; UEFI mode.
- Windows boots Safe Mode -> `bcdedit /deletevalue {current} safeboot` -> reboot to normal Windows.

## 3. Create the install USB (on another Linux box)
```
curl -LO https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/debian-testing-amd64-netinst.iso
curl -LO https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing        # expect "...netinst.iso: OK"
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,LABEL        # USB = TRAN usb, matching size, NOT nvme0n1
sudo dd if=debian-testing-amd64-netinst.iso of=/dev/sdX bs=4M status=progress oflag=sync conv=fsync && sync
```
- Firmware is bundled; testing kernel (~6.19) is new enough for Arc. Write the **whole disk** (`sdX`), not a partition.
- MDM blocking USB? check `lsmod | grep usb_storage`, `/etc/modprobe.d/`, `usbguard`, `hexnode_agent`; lift temporarily, re-enable after.

## 4. Boot the installer
- USB in a **USB-C** port (USB-A -> adapter). Power on -> **F12** -> UEFI entry for the USB -> **Graphical install**.

## 5. Installer
- **Keyboard:** American English (plain US; accents via Compose = Right-Alt, set later).
- **Missing `intel/ish/ish_ptl_*` firmware:** **skip** -- sensor hub (auto-brightness/accelerometer), not needed to install; comes with `graphics intel`.
- **Wi-Fi (BE211) won't associate / no password prompt:** easiest = USB-tether a phone or USB-C Ethernet. Manual (console **Ctrl+Alt+F2**; no `iw`/`wpa_passphrase` present):
  ```
  cat > /tmp/wpa.conf <<'EOF'
  network={
      ssid="SSID"
      psk="PASSWORD"
  }
  EOF
  wpa_supplicant -B -i wlp0s20f3 -c /tmp/wpa.conf
  sleep 5; udhcpc -i wlp0s20f3; ip addr show wlp0s20f3
  ```
  Quoted `psk` = plaintext (hashed automatically). The BE211 works normally post-install. **Tip:** if the d-i network UI *does* take it (select `wlp0s20f3` first), it also configures Wi-Fi on the installed system -> auto-connects on first boot (see §7).

## 6. Partitioning (Manual)
Only ever touch the **FREE SPACE** + reuse the existing ESP. Never the Windows / MSR / Dell recovery (`WINRETOOLS`/`Image`/`DELLSUPPORT`) partitions.

1. Partitioning method -> **Manual**.
2. **/boot** -- select FREE SPACE -> *Create a new partition* -> **2 GB** -> Primary -> Beginning -> *Use as:* **Ext4**, *Mount point:* **/boot** -> *Done*. (Separate + unencrypted so GRUB needn't unlock LUKS -> we keep Argon2id.)
3. **Encrypted container** -- select remaining FREE SPACE -> *Create a new partition* -> **max** -> *Use as:* **physical volume for encryption** -> *Done*.
   - Cipher `aes` / `xts-plain64`, key size **256** (= AES-128-XTS; 512 = AES-256). **Erase data: No** (skips a multi-hour wipe).
4. Menu -> **"Configure encrypted volumes"** -> *Finish* -> write changes -> set **LUKS passphrase** twice (your at-boot unlock).
5. **LVM** -- a new `nvme0n1pX_crypt` device **must** now appear; select it -> *Use as:* **physical volume for LVM** -> *Done*. **If no `*_crypt` device shows up, step 4 didn't take -- redo it. Building LVM on the raw partition gives an UNENCRYPTED disk** (verify after install: `lsblk -f` shows a `crypto_LUKS` layer + `/etc/crypttab` exists + you get a passphrase prompt at boot).
6. Menu -> **"Configure the Logical Volume Manager"**:
   - *Create volume group* **vg0** on the crypt PV.
   - *Create logical volume* **swap** = **64 GB**.
   - *Create logical volume* **root** = **max**.
   - *Finish*.
7. **Format the LVs** -- you MUST set *Use as* on each, or Finish errors with "no root filesystem defined":
   - `LV root` -> *Use as:* **btrfs**, *Mount point:* **/** -> *Done*.
   - `LV swap` -> *Use as:* **swap area** -> *Done*.
8. **ESP** -- select the existing small **FAT32** partition -> *Use as:* **EFI System Partition**, **Format: No** (keeps Windows' boot files); mounts `/boot/efi`.
   - Note: this is *not* `/boot`. `/boot` = your ext4 kernel partition (step 2); the **ESP** holds the EFI loaders for both OSes (Windows Boot Manager + GRUB).
9. **Finish partitioning and write changes** -> review: format flags on **/boot, root, swap only**; ESP kept, Windows/Dell untouched -> confirm.
10. **GRUB** step: install to the disk; os-prober should add Windows (if not, fix post-install).

*(Post-install: refine btrfs subvolumes -> `@`, `@home`, `@snapshots` + `compress=zstd:1,noatime,ssd,discard=async`, qgroups off; set up snapper + grub-btrfs. Note the swap LV UUID for `resume=`.)*

## 7. First boot / setup
First boot is a **black screen** -- the Arc GPU firmware isn't installed yet (`xe` blanks the display) and a base install has no GUI. Boot once with **`nomodeset`** (GRUB menu -> `e` -> append `nomodeset` to the `linux` line -> Ctrl+X) for a visible console + the LUKS unlock prompt + a text login. The firmware is installed by `graphics intel` below (**no manual firmware step**); afterwards reboot **without** `nomodeset` and the display renders.

Bootstrap order on that console:
1. **Wi-Fi** (NetworkManager isn't installed yet -- see "Connect Wi-Fi" below); confirm with `ip a`.
2. `sudo apt install -y git`
3. `git clone --recursive https://github.com/mdonkers/dotfiles.git && cd dotfiles`
4. Run the sequence below -- `graphics intel` pulls the Arc + Wi-Fi firmware, then **reboot normally**.

**Connect Wi-Fi (first boot, before NetworkManager):**
- Easiest: configure Wi-Fi in the **installer's network step** (select `wlp0s20f3` -> SSID -> passphrase) -- d-i writes it to the installed system and installs `wpasupplicant`, so it **auto-connects on first boot** and you can skip the rest.
- Otherwise bring it up by hand (needs `wpasupplicant`; if missing, tether once to `apt install wpasupplicant`):
  ```
  cat > /tmp/wpa.conf <<'EOF'
  network={
      ssid="SSID"
      psk="PASSWORD"
  }
  EOF
  sudo ip link set wlp0s20f3 up
  sudo wpa_supplicant -B -i wlp0s20f3 -c /tmp/wpa.conf
  sudo dhclient wlp0s20f3        # or: sudo udhcpc -i wlp0s20f3
  ip a show wlp0s20f3            # confirm IP
  ```
- After `install.sh sources` installs NetworkManager: `nmtui`, `nmcli dev wifi connect 'SSID' password 'PW'`, or the `wifi-add` alias.

From the cloned dotfiles (root unless noted):
```
sudo ./bin/install.sh dist
sudo ./bin/install.sh sources
sudo ./bin/install.sh graphics intel     # Arc firmware (+ ISH sensors), microcode, Mesa, VA-API, update-initramfs
sudo ./bin/install.sh wm
./bin/install.sh dotfiles                 # as user
```
- Yubikey before `private`: `gpg --card-status`; `gpg --recv-keys 0x24046A96`; `gpg --edit-key 0x24046A96` -> `trust` -> `5`; then `pamu2fcfg -u $(whoami) ...` into `/etc/yubikey/u2f_keys`.
```
./bin/install.sh private
sudo ./bin/install.sh dev
./bin/install.sh golang
```
- After `sources`, Wi-Fi can drop when `systemd-resolved` installs: `nmcli d`; if needed remove the wifi line from `/etc/network/interfaces`, restart NetworkManager + systemd-resolved.
- Snapshot-boot: install `snapper` + `grub-btrfs` + enable `grub-btrfsd`; add an apt pre/post snapshot hook.
- **Validate hibernation** (hibernate with a marker open -> cold resume -> repeat -> closed-lid for days) before relying on it.
- **Webcam:** build the out-of-tree `intel_cvs` DKMS module (github.com/intel/vision-drivers); no MOK signing (Secure Boot off). Or wait for upstream.
- Slack/IntelliJ: install from `.deb`/tarball; IntelliJ to `/opt/idea-*`, then create a desktop entry.

## Misc / reference
- **Special chars (Compose = Right-Alt):** `setxkbmap -option compose:ralt`; e.g. `Compose " e` -> ë. Toggle Fn behaviour: `Fn+Esc`. Find keycodes: `xev`.
- **Wi-Fi via nmcli:** `nmcli dev wifi list`; `nmcli connection up <name>` (or the `wifi-add` alias).
- **Repair GRUB after a Windows update:** boot the install USB -> Advanced -> rescue; or from a live system `sudo grub-install /dev/nvme0n1 && sudo update-grub`. If the EFI `debian` entry is corrupted, recreate it from the ESP.
- **Mount a USB/SD:** `lsblk`; `sudo mount -o uid=miel,gid=miel /dev/sdX1 /mnt/sdcard`. Persistent: add a UUID line to `/etc/fstab`.
- **HP printer:** hplip (hplipopensource.com).
