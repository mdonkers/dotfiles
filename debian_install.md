# Install Debian on Dell XPS 16 #

This manual assumes (at least) the following:
- Dell XPS 16 - DA16260 model from 2026
- Debian Forky (Testing)
- i3 / X11 window manager, dual-boot alongside Windows

## Hardware ##
- CPU Intel Core Ultra (Panther Lake-H); GPU **Intel Arc B390 (Xe3)** -- driven by the in-kernel `xe` driver, which needs **kernel >= 6.17**.
- Wi-Fi / Bluetooth **Intel BE211** (Wi-Fi 7), `iwlwifi` driver.
- Non-touch IPS panel (no OLED), so plain **X11 / i3** is fine -- no need for Wayland.
- USB-C / Thunderbolt only (USB-A needs an adapter); no fingerprint reader; physical F-row.
- Webcam Intel IPU7 -- still needs the out-of-tree `intel_cvs` module (see below).

## Decisions ##
- **Disk:** LUKS2 (Argon2id) -> LVM -> a 64 GiB swap LV + btrfs root (subvolumes + zstd compression). One passphrase at boot unlocks everything, btrfs gives snapshots, and a swap LV inside the encrypted container means clean encrypted hibernation.
- **Hibernation ON** (so swap must be >= RAM) -> **Secure Boot OFF**. Kernel lockdown (which Secure Boot enables) blocks hibernation; the problem was never *entering* hibernate but *resuming* from it.
- **Bootloader:** GRUB + `grub-btrfs` + `snapper` (not Limine -- that's an Omarchy thing). Do **not** pin away the 7.x kernel; the Arc GPU, audio (SOF), and sensors all want it.

## Resources used ##
- https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/ (firmware-included weekly testing build)
- https://wiki.archlinux.org/title/Dell_XPS_16 (general Dell XPS Linux notes)
- https://github.com/intel/vision-drivers (IPU7 webcam / `intel_cvs`)
- https://github.com/intel/intel-lpmd (Panther Lake low-power daemon)


## Preparations ##

### Windows: free up space (do this first) ###
- **BitLocker:** check with `manage-bde -status C:`. On Win11 Home with a local account it's usually off; if it's on, save the recovery key first: `manage-bde -protectors -get C:`.
- **Update the Dell BIOS** to the latest version while still in Windows.
- Turn off Fast Startup + hibernation, which also frees the space they reserve:

        powercfg /h off

- Shrink `C:` in `diskmgmt.msc`. If it's blocked by "unmovable files", disable the things that pin them, reboot, and try again:
  - Disable the pagefile: `sysdm.cpl` -> Performance -> Advanced -> Virtual memory.
  - Disable System Protection and delete restore points.
  - Reboot, then shrink.
- Leave roughly **80-200 GB** for Windows; leave the **rest UNALLOCATED** (don't create a partition for it -- the Debian installer will). Re-enable the pagefile / System Protection afterwards if you want them.

### BIOS / UEFI settings ###
A few firmware settings need changing for Linux. The trick below boots Windows straight into Safe Mode so the AHCI driver change doesn't blue-screen it.

- In an **elevated cmd** (not PowerShell -- it eats the braces):

        bcdedit /set {current} safeboot minimal

- Reboot and tap **F2** to enter BIOS, then:
  - SATA / NVMe Operation: change **RAID -> AHCI / NVMe** (so Linux sees the NVMe SSD).
  - **Secure Boot OFF** (required for hibernation; see Decisions).
  - Confirm **UEFI** boot mode.
- Windows boots into Safe Mode. Clear the safeboot flag and reboot back to normal Windows:

        bcdedit /deletevalue {current} safeboot

### Create the install USB (on another Linux box) ###
Download the firmware-included weekly testing netinst, verify it, and write the **whole disk** (not a partition):

    curl -LO https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/debian-testing-amd64-netinst.iso
    curl -LO https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/SHA256SUMS
    sha256sum -c SHA256SUMS --ignore-missing        # expect "...netinst.iso: OK"
    lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,LABEL         # USB = TRAN usb, matching size, NOT nvme0n1
    sudo dd if=debian-testing-amd64-netinst.iso of=/dev/sdX bs=4M status=progress oflag=sync conv=fsync && sync

Firmware is bundled in this image, and the testing kernel (~6.19) is new enough for the Arc GPU. If corporate device management blocks USB access, check `lsmod | grep usb_storage`, `/etc/modprobe.d/`, `usbguard`, and any agent like `hexnode_agent`; lift the block temporarily and re-enable it afterwards.


## Install Debian ##
Insert the USB into a **USB-C** port (USB-A needs an adapter), power on, and tap **F12** for the one-time boot menu. Pick the UEFI entry for the USB and choose **Graphical install**.

- **Keyboard:** American English (plain US; accents come later via the Compose key = Right-Alt).
- **Missing `intel/ish/ish_ptl_*` firmware:** **skip** it. That's the sensor hub (auto-brightness / accelerometer) -- not needed to install, and it arrives later with `graphics intel`.
- **Wi-Fi (BE211) won't associate / never prompts for a password:** the easy path is to USB-tether a phone or use a USB-C Ethernet adapter. To do it by hand, switch to a console (**Ctrl+Alt+F2**; note `iw` / `wpa_passphrase` aren't present in the installer):

        cat > /tmp/wpa.conf <<'EOF'
        network={
            ssid="SSID"
            psk="PASSWORD"
        }
        EOF
        wpa_supplicant -B -i wlp0s20f3 -c /tmp/wpa.conf
        sleep 5; udhcpc -i wlp0s20f3; ip addr show wlp0s20f3

  The quoted `psk` is plaintext (hashed automatically). The BE211 works normally after install. **Tip:** if the installer's own network step *does* accept the network (select `wlp0s20f3` first), it also configures Wi-Fi on the installed system, so it auto-connects on first boot and you can skip the manual steps in Setup below.

### Disk Configuration ###
Only ever touch the **FREE SPACE** you created in Windows, plus reuse the existing ESP. Never touch the Windows / MSR / Dell recovery partitions (`WINRETOOLS` / `Image` / `DELLSUPPORT`).

1. Partitioning method -> **Manual**.
2. **/boot** -- select the FREE SPACE -> *Create a new partition* -> **2 GB** -> Primary -> Beginning -> *Use as:* **Ext4**, *Mount point:* **/boot** -> *Done*. Keeping `/boot` separate and unencrypted means GRUB doesn't have to unlock LUKS, so we can keep the strong Argon2id KDF on the root container.
3. **Encrypted container** -- select the remaining FREE SPACE -> *Create a new partition* -> **max size** -> *Use as:* **physical volume for encryption** -> *Done*.
   - Cipher `aes` / `xts-plain64`, key size **256** (= AES-128-XTS; 512 would be AES-256). Set **Erase data: No** to skip a multi-hour wipe.
4. Menu -> **"Configure encrypted volumes"** -> *Finish* -> write the changes -> set the **LUKS passphrase** twice. This is your at-boot unlock passphrase.
5. **LVM** -- a new `nvme0n1pX_crypt` device **must** now appear. Select it -> *Use as:* **physical volume for LVM** -> *Done*.
   - **If no `*_crypt` device shows up, step 4 didn't take -- redo it.** Building LVM directly on the raw partition gives an **UNENCRYPTED** disk. Verify after install: `lsblk -f` should show a `crypto_LUKS` layer, `/etc/crypttab` should exist, and you should get a passphrase prompt at boot.
6. Menu -> **"Configure the Logical Volume Manager"**:
   - *Create volume group* **vg0** on the crypt PV.
   - *Create logical volume* **swap** = **64 GB**.
   - *Create logical volume* **root** = **max**.
   - *Finish*.
7. **Format the logical volumes** -- you must set *Use as* on each, or Finish errors with "no root filesystem defined":
   - `LV root` -> *Use as:* **btrfs**, *Mount point:* **/** -> *Done*.
   - `LV swap` -> *Use as:* **swap area** -> *Done*.
8. **ESP** -- select the existing small **FAT32** partition -> *Use as:* **EFI System Partition**, **Format: No** (this keeps Windows' boot files); it mounts at `/boot/efi`.
   - Note this is *not* `/boot`. `/boot` is your ext4 kernel partition from step 2; the **ESP** holds the EFI loaders for both operating systems (Windows Boot Manager + GRUB).
9. **Finish partitioning and write changes** -> review: format flags should be on **/boot, root, and swap only**; the ESP kept and Windows / Dell partitions untouched -> confirm.
10. **GRUB** step: install it to the disk. os-prober should add Windows (if it doesn't, fix it post-install -- see Repair GRUB).

Finish the installation. (Post-install, refine the btrfs subvolumes to `@`, `@home`, `@snapshots` with mount options `compress=zstd:1,noatime,ssd,discard=async` and qgroups off, then set up snapper + grub-btrfs. Note the swap LV UUID for the kernel `resume=` parameter.)


## Setup Debian ##
The **first boot is a black screen** -- the Arc GPU firmware isn't installed yet (`xe` blanks the display) and a base install has no GUI anyway. Boot once with **`nomodeset`**: at the GRUB menu press `e`, append `nomodeset` to the `linux` line, then Ctrl+X. That gives a visible console, the LUKS unlock prompt, and a text login. The firmware is installed by `graphics intel` below (there is **no manual firmware step**); afterwards reboot **without** `nomodeset` and the display renders normally.

On that first console, the bootstrap order is:
1. Bring up **Wi-Fi** (NetworkManager isn't installed yet -- see below); confirm with `ip a`.
2. Install git: `sudo apt install -y git`
3. Clone the dotfiles: `git clone --recursive https://github.com/mdonkers/dotfiles.git && cd dotfiles`
4. Run the install sequence (next section). `graphics intel` pulls the Arc + Wi-Fi firmware, after which you **reboot normally**.

**Connecting Wi-Fi on first boot (before NetworkManager is installed):**
- Easiest: configure Wi-Fi back in the installer's network step (select `wlp0s20f3` -> SSID -> passphrase). The installer writes it to the installed system and installs `wpasupplicant`, so it auto-connects on first boot and you can skip the rest.
- Otherwise bring it up by hand (needs `wpasupplicant`; if it's missing, tether once to `apt install wpasupplicant`):

        cat > /tmp/wpa.conf <<'EOF'
        network={
            ssid="SSID"
            psk="PASSWORD"
        }
        EOF
        sudo ip link set wlp0s20f3 up
        sudo wpa_supplicant -B -i wlp0s20f3 -c /tmp/wpa.conf
        sudo dhclient wlp0s20f3        # or: sudo udhcpc -i wlp0s20f3
        ip a show wlp0s20f3            # confirm an IP

- Once `install.sh sources` has installed NetworkManager, connect with `nmcli dev wifi connect 'SSID' password 'PW'` (or the `wifi-add` alias), then `systemctl restart systemd-resolved` to make sure DNS works.


## Continue Debian configuration ##
Now run the install steps from the cloned dotfiles (as root unless noted):

    sudo ./bin/install.sh dist
    sudo ./bin/install.sh sources
    sudo ./bin/install.sh graphics intel     # Arc firmware (+ ISH sensors), microcode, Mesa, VA-API, update-initramfs
    sudo ./bin/install.sh wm

As user, **not as root**:

    ./bin/install.sh dotfiles

**Wi-Fi drops during `sources`.** Installing NetworkManager + systemd-resolved orphans the first-boot ifupdown / wpa_supplicant Wi-Fi. The fix that works is to move Wi-Fi onto NetworkManager:

- Comment the `wlp0s20f3` stanza out of `/etc/network/interfaces`.
- `sudo systemctl restart NetworkManager`
- `nmcli dev wifi connect 'SSID' password 'PW'` (NetworkManager then feeds DNS to systemd-resolved).

If only DNS is wedged and you just need to finish an apt run, temporarily point `/etc/resolv.conf` at `nameserver 1.1.1.1`.

**Before** installing `private`, make sure the Yubikey is working. First import and trust the GPG key:

    gpg --card-status
    gpg --recv-keys 0x24046A96
    gpg --edit-key 0x24046A96

Then type `trust` followed by `5` to give it full trust, then `quit`.

To allow logins / sudo via the Yubikey (U2F), generate the registration line:

    pamu2fcfg -u `whoami` -opam://`hostname` -ipam://`hostname`

If a PIN is asked, it's the numeric PIN set for the Yubikey. Copy the resulting line into the file `/etc/yubikey/u2f_keys`.

Then finish the remaining installation:

    ./bin/install.sh private
    sudo ./bin/install.sh dev                 # Java env + CLI tools (gh, kubectl, terraform via signed apt repos)
    ./bin/install.sh golang

A few things to do / verify afterwards:
- **Snapshot-boot:** install `snapper` + `grub-btrfs`, enable `grub-btrfsd`, and add an apt pre/post snapshot hook.
- **Validate hibernation** before relying on it: hibernate with a marker file/app open, do a cold resume, repeat, then leave it closed-lid for a few days.
- **Webcam:** build the out-of-tree `intel_cvs` DKMS module from github.com/intel/vision-drivers. No MOK signing is needed (Secure Boot is off). Or wait for upstream support.


## Remaining Software ##

To install **Slack**, download the Debian package, then:

    sudo apt-get update
    sudo dpkg -i path/to/deb/file

There may be missing dependencies (e.g. `libnotify4`); KDE dependencies should **not** be needed. Install the missing ones and complete:

    sudo apt install --no-install-recommends trash-cli libnotify4
    sudo apt-get install -f

Limit Slack's log output by adding the `-s` flag to the Desktop entry in `/usr/share/applications/slack.desktop`.

To install **IntelliJ**, download the package and extract it to:

    /opt/idea-IU-<version>

Start IntelliJ and, from the _Configure_ menu, select _Create Desktop Entry_ -- this writes `~/.local/share/applications/jetbrains-idea.desktop` (use `/usr/share/applications/` for a global entry). To fix keyboard-input problems caused by IBus and accessibility warnings, prefix the `Exec` command with: `env XMODIFIERS= NO_AT_BRIDGE=1 `.

Several CLI tools have **no signed apt repo**, so install them manually and verified (never `curl | bash`):
- **aws-cli v2:** download `awscli-exe-linux-x86_64.zip` + its `.sig` from awscli.amazonaws.com, import AWS's PGP key, `gpg --verify`, unzip, then `sudo ./aws/install` (provides `aws`).
- **bun:** no upstream signature, so the safest option is the GitHub release zip from `oven-sh/bun` checked against its `SHASUMS256.txt` (integrity only), dropped in `/Development/tools` and symlinked. Review before trusting, or just install it when actually needed.
- **sops + age:** in `dotfiles-private`, run `make deps` (installs `age` via apt + `sops` via a checksum-verified `.deb`). Used to decrypt the private repo's `secrets/` via `make secrets`.
- **helm:** the baltocdn apt repo was decommissioned (it now returns `OK` for every path). Download `helm-vX.Y.Z-linux-amd64.tar.gz` + its `.sha256sum` from github.com/helm/helm/releases, run `sha256sum -c`, and extract `linux-amd64/helm` to `/usr/local/bin` (current: v4.2.2).

Optionally, **`intel-lpmd`** (the Panther Lake low-power daemon) is *not* in Debian: build it from github.com/intel/intel-lpmd and enable the service -- it noticeably improves idle battery life.


# Misc Information

Use `arandr` as a graphical front-end to `xrandr` to configure screen resolution and external displays.

## Mounting

For a quick one-off mount, find the drive and mount it:

    lsblk
    sudo mount -t vfat /dev/sda1 /mnt/sdcard/ -o dmask=0022,fmask=0133,uid=miel,gid=miel

To mount a device quickly via `/etc/fstab`, connect it and get its UUID:

    sudo mkdir -p /media/usb
    ll /dev/disk/by-uuid/

Then add the following line to `/etc/fstab` and mount with `mount /media/usb`:

    UUID=<ID...>  /media/usb  vfat defaults,noauto,users,noatime,nodiratime,dmask=0022,fmask=0133 0 0


## Use of FN-key
The XPS 16 has a physical F-row. To switch whether F1-F12 are function keys or media keys by default, toggle Fn-Lock with **Fn+Esc** (look for the lock icon on Esc). The boot default can also be set in BIOS under **POST Behavior -> Function Key Behavior** (set to *Function Key*).

To find keycodes for any key pressed (the second command prints the full keymap):

    xev | sed -n 's/^.*keycode *\([0-9]\+\).*$/keycode \1 = /p'
    xmodmap -pke


## Special characters
Special characters can be typed with the 'compose' key or by entering the unicode codepoint. To set the compose key to Right-Alt / AltGr, first check it's available, then map it:

    grep "compose:" /usr/share/X11/xkb/rules/base.lst
    setxkbmap -option compose:ralt

Typing then works as e.g. `compose + " + e` -> ë. Unicode characters can also be entered directly with `ctrl+shift+u` followed by the numeric code.


## Some useful key commands

- Switch between terminals:                 ALT+F1/F6
- Switch between terminals from X:          CTRL+ALT+F1/F6
- Scroll up/down:                           FN+SHIFT+UP/DOWN
- Copy/paste from application:              CTRL+C/V
- Copy/paste from RXVT Terminal:            CTRL+ALT+C/V


## Cleanup unused wifi connections
Remove unused connection profiles from:

    /etc/NetworkManager/system-connections


## Connect to WiFi via cli
Besides the applet, `nmcli` can manage Wi-Fi from the command line.

See all networks and the currently connected one:

    nmcli dev wifi list

Connect to a network directly (creates the profile if needed):

    nmcli dev wifi connect <SSID_Name> password <Password>

Add a connection explicitly:

    nmcli connection add con-name <Name> ifname wlp0s20f3 type wifi ssid <SSID_Name> wifi-sec.key-mgmt wpa-psk wifi-sec.psk <Password>

List locally known connections, and bring one up:

    nmcli connection show
    nmcli connection up <Name>


## Repair GRUB

### Grub Rescue Mode
If you drop into Grub Rescue Mode after (or during) Windows updates, partitions may have shifted. Recover a working bootloader like this.

See which partition GRUB currently boots from (look for `prefix=(hd0,...)/boot/grub`):

    set

List partitions and find the new boot partition:

    ls
    ls (hd0,gpt5)/boot/

Set the new boot partition and continue:

    set prefix=(hd0,...)/boot/grub
    insmod normal
    normal

You should now be able to boot into Windows (to finish its updates) or into Debian. From Debian, reinstall GRUB into the correct disk with `sudo grub-install /dev/nvme0n1 && sudo update-grub`.

### Grub disabled / corrupted
If GRUB becomes disabled / corrupt because of Windows updates, repair it with the Debian install USB:

- Boot the install USB.
- Choose "Advanced options".
- Repair GRUB -> enter disk `/dev/nvme0n1`.

If that fails, the `debian` entry in the EFI boot partition may be corrupted. Repair it from Windows:

- Boot into Windows and open a PowerShell with admin rights.
- Identify the EFI partition (the FAT32 one):

        diskpart
        sel disk 0
        list vol

- Select it and assign a drive letter:

        sel vol <number of volume>
        assign letter=z:
        exit

- Run `chkdsk` to repair the Debian directory:

        chkdsk z:\EFI\debian /R

- This converts the directory to a file; remove it with `del debian`, exit, and reinstall GRUB as in the Rescue Mode section above.

