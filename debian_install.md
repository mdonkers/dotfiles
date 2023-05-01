# Install Debian on Dell XPS 15 #

This manual assumes (at least) the following versions:
- Dell XPS 15 - 9510 model from 2022 - BIOS version 1.19.0
- Debian Bookworm (Testing)

## Resources used ##
- https://cdimage.debian.org/cdimage/unofficial/non-free/cd-including-firmware/
- https://www.debian.org/releases/stable/i386/ch04s03.html.en
- https://wiki.archlinux.org/index.php/Dell_XPS_15_9560
- https://github.com/rcasero/doc/wiki/Ubuntu-linux-on-Dell-XPS-15-(9560)


## Preparations ##

### Download Debian distro and create bootable USB ###
Download the Debian Testing DVD-installer ISO from https://www.debian.org/devel/debian-installer/.
Make sure to get the *non-free including firmware* ISO from the link above, because we need
the non-free drivers for the WiFi.

The following steps assume a *nix environment.

Insert the USB drive and check which device is added. Either via `dmesg` or `lsblk`.
Under Linux this will presumably be `/dev/sdb`, under MacOS `/dev/disk2`.

The images can be simply copied to the device:

    cp debian-<version>.iso /dev/sdb
    sync

Remove the USB stick again.


### Resize current partition ###
Open the Windows Disk Util to update the partitions.

Decrease the size for the Windows partition to make space available for Debian. You will approx need the following free room
- 100 Gb for Debian
- 1x the size of your RAM for SWAP (32 Gb RAM -> 32 Gb SWAP)


### Setup Safe Mode ###
Login into Windows 10, and set up Safe Mode: "Change advanced Startup Options" -> "Restart Now"
  -> "Troubleshoot" -> "Advanced options" -> "Startup Settings" -> "Restart"

Disable "Fast Boot" in the "Power Options" menu, look for "Turn on fast startup"

Now reboot to get into the BIOS menu.


## UEFI Boot Settings ##
Some UEFI settings and other BIOS parameters need to be configured to work correctly with Linux.
Change the following settings by pressing F2 repeatedly when booting:

- Change the SATA Mode from the default "RAID" to "AHCI". This will allow Linux to detect the NVME SSD.
- Change Fastboot to "Thorough" in "POST Behaviour". This prevents intermittent boot failures.
- Disable secure boot to allow Linux to boot.

Save and restart. Initially Windows will not boot, but after some time will get into the Recovery Mode again. Navigate to
"Troubleshoot" -> "Advanced options" -> "Startup Settings" -> "Restart" -- Then after restarting choose "F4 - Safe Mode".

When in Windows, check the "IDE ATA/ATAPI controller" is "Intel(R) 100 Series/C230 Chipset Family SATA AHCI Controller", via "Start" -> "Windows System" -> "Control Panel" -> "Device Manager". Restart.


## Install Debian ##
Shutdown the laptop and insert the USB with Debian installer. Startup, repeatedly pressing F12 for the one-time boot menu.

Boot the Debian installer, easiest is to opt for the graphical **expert** installer.

For the modules, add those for disk **partitioning** and **dm-crypt** (encrypted disk)

### Disk Configuration ###

Create one partition for 'boot' of about 1G, using "ext4" and "/boot" as mountpoint
Additionally partitions for `/` (root) and swap are needed.

To create an encrypted disk, follow these steps:
- Select "Configure encrypted volumes", take the entire remaining free space (reserved for Debian)
- Select "Logical Volume Manager", using the encrypted partition (asks to format which is fine)
- First create a "Volume Group" and name this e.g. "vg-1"
- Then create 2 logical volumes, for root and swap (same size as RAM)
- For every volume, setup the partition correctly and define the mount-points (/ and swap). Make root as "ext4".

Finish the installation.
If Windows does not show up in the Grub start menu afterwards, this will be fixed during remaining installation (due to OS Prober being disabled).


## Setup Debian ##
Enable Wifi if not directly connected. First making sure the device is enabled, then set the password and connect it
with a network (only needed first few times, until we have NetworkManager / `nmcli` installed):

    ip link set dev <device> up
    iwlist <device> scan | grep ESSID
    wpa_passphrase <network ssid> >> /etc/wpa_supplicant.conf
    wpa_supplicant -B -D wext -i <device> -c /etc/wpa_supplicant.conf
    dhclient <device>


Remove the DVD install media from `/etc/apt/sources.list`

Install git to fetch our `dotfiles` repository

    apt-get install --no-install-recommends git

Fetch the dotfiles repo

    git clone https://github.com/mdonkers/dotfiles.git "/tmp/dotfiles"


## Continue Debian configuration ##
Now we can start installing tools to work as intended. First we'll install them and then setup one by one.
(might need to fetch the `dotfiles` repo again)
**Note**: After running `install.sh sources` WiFi might break as `systemd-resolved` is installed. To resolve, try:

- run nmcli to check if a WiFi device is found and available: `nmcli d`
- if WiFi is unavailable, remove the WiFi device from `/etc/network/interfaces`
- run `systemctl stop wpa_supplicant`
- run `service NetworkManager restart`
- run `systemctl restart systemd-resolved`
- check if the WiFi device now is available and connect to a network

List of install steps:

    cd /tmp/dotfiles
    bin/install.sh dist
    bin/install.sh sources
    bin/install.sh graphics gforce
    bin/install.sh wm

As user, **not as root** !

    bin/install.sh dotfiles


**Before** installing `private`, make sure the Yubikey is working properly. Follow below steps:

    gpg --card-status
    gpg --recv-keys 0x24046A96
    gpg --edit-key 0x24046A96

Then type `trust` followed by `5` to give it full trust. Then `quit`.

To allow logins / sudo via the Yubikey, first execute:

    pamu2fcfg -u `whoami` -opam://`hostname` -ipam://`hostname`

If a PIN is asked, this is the 'numeric' PIN set for the Yubikey.
Copy the results to the file `/etc/yubikey/u2f_keys`


Follow up with the remaining installation:

    ./bin/install.sh private
    sudo ./bin/install.sh dev
    ./bin/install.sh golang


## Remaining Software ##

To install **Slack**, first download the Debian package. Then the following commands:

    sudo apt-get update
    sudo dpkg -i path/to/deb/file

There might be some missing dependencies (e.g. `libnotify4`). KDE dependencies should **not** be needed. Install missing dependencies separately, then complete installation as:

    sudo apt install --no-install-recommends trash-cli libnotify4
    sudo apt-get install -f

Limit Slack log output by adding the `-s` flag to the Desktop entry in `/usr/share/applications/slack.desktop`.

To install **IntelliJ**, download the package and extract. Move to the following location:

    /opt/idea-IU-<version>

Install the desktop shortcut by starting IntelliJ and from the _Configure_ menu select _Create Desktop Entry_.
This will put a `.desktop` entry in `~/.local/share/applications/jetbrains-idea.desktop`.
Install global desktop shortcuts to the following location (optional):

    /usr/share/applications/

To fix keyboard input problems caused by IBus and accessibility warnings, update the `Exec` command and prefix with: `env XMODIFIERS= NO_AT_BRIDGE=1 `.


# Misc Information

Use `arandr` as graphical interface to `xrandr` to configure the screen resolution. A resolution of 1440x900 works for me (1680x1050 if you like small fonts).

## Mounting

For simple mounting, first get the drive and then mount:

    lsblk
    sudo mount -t vfat /dev/sda1 /mnt/sdcard/ -o dmask=0022,fmask=0133,uid=miel,gid=miel

To be able to mount e.g. USB devices quickly (adding to fstab), first connect the device and get the UUID for mounting:

    sudo mkdir -p /media/usb
    sudo fstab -l
    ll /dev/disk/by-uuid/

Having the correct UUID, add the following line to `/etc/fstab`

    UUID=<ID...>  /media/usb	vfat defaults,noauto,users,noatime,nodiratime,dmask=0022,fmask=0133 0 0

Then simply mount the device with `mount /media/usb`


## Use of FN-key
With the Dell keyboard its easy to switch between FN-key behaviour. Simply press Fn+Esc

To find keycodes for any key pressed, use the following command (the second prints the full keymap):

    xev | sed -n 's/^.*keycode *\([0-9]\+\).*$/keycode \1 = /p'
    xmodmap -pke


## Special characters
Special characters can be typed in two ways, with the 'compose' key or by typing the unicode character.
To set the 'compose' key to Right-Alt / AltGr, first check if it is available, then do the mapping:

    grep "compose:" /usr/share/X11/xkb/rules/base.lst
    setxkbmap -option compose:ralt

Typing characters with the compose key works e.g. by `compose+", e` which results in ë.
Unicode characters can also be entered directly using the combination; `ctrl+shift+u` followed by
the numeric code of the character.


## Some useful key commands

- Switch between terminals:                 ALT+F1/F6
- Switch between terminals from X:          CTRL+ALT+F1/F6
- Scroll up/down:                           FN+SHIFT+UP/DOWN
- Copy/paste from application:              CTRL+C/V
- Copy/paste from RXVT Terminal:            CTRL+ALT+C/V


## Cleanup unused wifi connections
Cleanup unused connections in:

    /etc/NetworkManager/system-connections


## Connect to WiFi via cli
Using the `nmcli` tool it's also possible to connect instead of using the applet.
Here are the relevant commands.

See list of all WiFi networks and the currently connected network:

    nmcli dev wifi list

Add new connection:

    nmcli connection add con-name <Name> ifname wlan0 type wifi ssid <SSID_Name> wifi-sec.key-mgmt wpa-psk wifi-sec.psk <Password>

See list of all locally know connections:

    nmcli connection show

Connect to a network:

    nmcli connection up <Name>



## Repair GRUB

### Grub Rescue Mode
When you enter Grub Rescue Mode after (or during) Windows updates, it might be that partitions changed. Use the following
steps to get a working bootloader again.

See which partition is currently being used to boot from (look for the `prefix=(hd0,...)/boot/grub`)

    set

See which partitions there are and use this to find the 'new' boot partition:

    ls
    ls (hd0,gpt5)/boot/

Set the new boot partition:

    set prefix=(hd0,...)/boot/grub
    insmod normal
    normal

Now you should be able to boot into Windows to continue updates, or boot to Debian again. From Debian, do
a `sudo grub-install` to install Grub again into the correct partition.

### Grub disabled / corrupted
If GRUB becomes disabled / corrupt because of Windows updates, this can be repaired with the Debian install disk.

- Boot the install disk from USB.
- Choose "Advanced setup"
- Repair GRUB -> enter disk `/dev/nvme0n1`

If this fails, the `debian` entry in the EFI boot sector might have become corrupted. Follow these steps:

- Boot into Windows
- Open a Powershell with Admin rights
- Run the following commands:

    diskpart
    sel disk 0
    list vol

- Pick the EFI partition, probably the only one with FAT32 filesystem:

    sel vol <number of volume>
    assign letter=z:
    exit

- Now run `chkdsk` to repair the Debian directory:

    chkdsk z:\EFI\debian /R

- This should confert the directory to a file. Remove the file `del debian`
- Exit, and follow the steps at the top of this section to reinstall GRUB


## HP Printer installation
Follow guidelines here: http://hplipopensource.com/hplip-web/install/manual/distros/debian.html


## Disabled Speedstep

For some reason the XPS might jump into some kind of "safe" mode where all cores are locked to 800 MHz.
The machine feels a bit slow and the CPU temp never gets above 50 C (no fans spinning). To double check use
this command:

    watch grep \"cpu MHz\" /proc/cpuinfo

Speedstep can be enabled again by disconnecting the battery. For more information, see here;
https://www.reddit.com/r/Dell/comments/5uh6wo/fixing_your_dell_xps_cpu_stuck_at_minimum/

