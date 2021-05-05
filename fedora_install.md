# Install Fedora on Lenovo Thinkpad T14 #

This manual assumes (at least) the following versions:
- Lenovo Thinkpad T14 (gen1)
- Fedora 34



## Preparations ##

### Download Fedora 34 distro and create bootable USB ###
Follow the guidelines on the Fedora website to create the bootable USB


### Install Fedora ###
Shutdown the laptop and insert the USB with Fedora installer. Startup, repeatedly pressing F12 for the one-time boot menu.
Regularly install Fedora. When asked about partitions, size as follows:

- 1x the size of your RAM for SWAP (32 Gb RAM -> 32 Gb SWAP)
- Let the installer create the other partitions (might remove `/home` and just stick with `/`)

Create at least the SWAP and EXT4 partition.
Finish the installation.


## Setup Fedora ##

Fedora always installs a graphical environment (Gnome), so we're going to assume most software is available, and
installation is done from the graphical environment. Then later disable Gnome to be able to switch to i3.

Install git to fetch our `dotfiles` repository

    dnf install -y git

Fetch the dotfiles repo

    git clone git://github.com/mdonkers/dotfiles.git "/tmp/dotfiles"


## Continue Fedora configuration ##
Now we can start installing tools to make the laptop work as intended. First we'll install them and then setup one by one.
(might need to fetch the `dotfiles` repo again)

    cd /tmp/dotfiles
    bin/install.sh sources
    bin/install.sh wifi other
    bin/install.sh graphics
    bin/install.sh wm

As user, **not as root** !

    bin/install.sh dotfiles

Verify wlan is working

    iwconfig

Now disable Gnome and restart via the menu (afterwards login and run `startx`)

    sudo systemctl set-default multi-user.target


**Before** installing `private`, make sure the Yubikey is working properly. Follow below steps:

    gpg --card-status
    gpg --recv-keys 0x24046A96
    gpg --edit-key gpg 0x24046A96

Then type `trust` followed by `5` to give it full trust. Then `quit`.

To allow logins / sudo via the Yubikey, first execute:

    pamu2fcfg -u `whoami` -opam://`hostname` -ipam://`hostname`

Copy the results to the file `/etc/yubikey/u2f_keys`
Then continue installation (or manually add the two lines to the top of `/etc/pam.d/sudo` and `/etc/pam.d/login`):

    ./bin/install.sh private



## Remaining Software ##

To install Slack, first download the Debian package. Then the following commands:

    sudo apt-get update
    sudo dpkg -i path/to/deb/file
    sudo apt-get install -f

To install IntelliJ, download the package and extract. Move to the following location:

    /usr/local/share/idea-IU-<version>

Install the desktop shortcut by starting IntelliJ and from the _Configure_ menu select _Create Desktop Entry_.
This will put a `.desktop` entry in `~/.local/share/applications/jetbrains-idea.desktop`.
Install global desktop shortcuts to the following location (optional):

    /usr/share/applications/

To fix keyboard input problems caused by IBus, update the `Exec` command and prefix with: `env XMODIFIERS= `.

Cleanup

    bin/install.sh cleanup





## High kworker CPU usage & Suspending

After all setup is done, check CPU usage with `top`. If `kworker` shows high usage,
typically > 70%, something might be wrong with ACPI interrupts. To check, execute:

    grep . -r /sys/firmware/acpi/interrupts/

If one of the interrupts stands out and has high interrupts, it can be disabled (as root):

    echo disable > /sys/firmware/acpi/interrupts/gpeXX

Permanently (as root):

    crontab -e
    @reboot echo "disable" > /sys/firmware/acpi/interrupts/gpe[XX]

Before and after, check there are no errors using `dmesg`.

Also if suspend is not working correctly, this might be due to the bluetooth driver triggering
a wakeup. First check wich devices may trigger a wakeup:

    cat /proc/acpi/wakeup

If anything else besides `LID0` is `*enabled` this might prevent sleeping. Temporarily disable (as root):

    echo XHC1 > /proc/acpi/wakeup

Permanently (as root):

    crontab -e
    @reboot echo "XHC1" > /proc/acpi/wakeup

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


## Misc stuff

Use `arandr` as graphical interface to `xrandr` to configure the screen resolution. A resolution of 1440x900 works for me (1680x1050 if you like small fonts).

## Mounting

To mount e.g. USB devices, first connect the device and get the UUID for mounting:

    sudo mkdir -p /media/usb
    sudo fstab -l
    ll /dev/disk/by-uuid/

Having the correct UUID, add the following line to `/etc/fstab`

    UUID=<ID...>  /media/usb	vfat defaults,noauto,users,noatime,nodiratime,dmask=0022,fmask=0133 0 0

Then simply mount the device with `mount /media/usb`


## HP Printer installation
Follow guidelines here: http://hplipopensource.com/hplip-web/install/manual/distros/debian.html


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


## Some useful key commands

- Switch between terminals:                 ALT+F1/F6
- Switch between terminals from X:          CTRL+ALT+F1/F6
- Scroll up/down:                           FN+SHIFT+UP/DOWN
- Copy/paste from application:              CTRL+C/V
- Copy/paste from RXVT Terminal:            CTRL+ALT+C/V


## Disabled Speedstep

For some reason the XPS might jump into some kind of "safe" mode where all cores are locked to 800 MHz.
The machine feels a bit slow and the CPU temp never gets above 50 C (no fans spinning). To double check use
this command:

    watch grep \"cpu MHz\" /proc/cpuinfo

Speedstep can be enabled again by disconnecting the battery. For more information, see here;
https://www.reddit.com/r/Dell/comments/5uh6wo/fixing_your_dell_xps_cpu_stuck_at_minimum/


