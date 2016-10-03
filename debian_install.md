# Install Debian on MacBook #

This manual assumes (at least) the following versions:
- rEFInd 0.10.3
- Debian Jessie 8.4.0 (with upgrade to Stretch / Testing)

## Resize current osx partition ##

Open diskutil and select the 'partition' option

Decrease the size for the osx partition to make space available for Debian. You will approx need the following free room
- 20 Gb for Debian
- 1.5x the size of your RAM for SWAP (16 Gb RAM -> 24 Gb SWAP)

## Install rEFInd boot manager ##
Download rEFInd boot manager as binary zip file and unzip

Restart your MacBook and hold `cmd+R` to enter recovery mode

Open a Terminal

Find the location where rEFInd was unzipped;

    cd /Volumes/Macbook\ HD/Users/miel/Downloads/refind/

Run the rEFInd installer

    ./refind-install

By default the timeout during boot is set to 20 seconds, to change this mount the EFI partition. You can use the rEFInd shell script for this.

    ./mountesp

Open the config file under `/Volumes/ESP/EFI/refind/refind.conf` with VI and edit accordingly

Reboot and you should now see the rEFInd boot manager

## Download Debian distro and create bootable USB ##
Download the Debian net-installer ISO

Convert .iso to .img

    hdiutil convert -format UDRW -o debian.img debian-<...>.iso

Rename as osx adds the .dmg extension

    mv debian.img.dmg debian.img

Insert the USB stick and check (double check) the disk number (should be something like `/dev/disk2`)

    diskutil list

Unmount the USB device if necessary

    diskutil unmountDisk /dev/disk2

Create the bootable USB

    sudo dd if=debian.img of=/dev/disk2

Eject the USB via the pop-up or via the following command

    diskutil eject /dev/disk2

## Install Debian ##
Shutdown the MacBook. Make sure to insert the USB with Debian installer _and_ the Thunderbolt adapter with network cable

Boot the Debian installer, easiest is to opt for the graphical installer

When arriving at the partitioning step, delete - if needed - the unused HFS+ partition. Make sure _NOT_ to touch the EFI, OSX Recovery and existing OSX install partition (/dev/sda1, /dev/sda2 and /dev/sda3).
Create at least the SWAP and EXT4 partition.

Continue with the installation until the GRUB boot loader installation step (choose 'back' option). Skip this, we'll set it up later manually.
Finish the installation.

If you don't have the option to enter into a Terminal window before the installation finishes, reboot and enter the Debian installer from USB again. Choose 'Recovery mode' and boot into the Debian installation, probably /dev/sda5 or /dev/sda6.

## Manually setup GRUB boot loader ##
Make sure you are root (you are if you have a 'Recovery mode' Terminal)

Install GRUB2 EFI (assuming a 64 bit system, the following should install `grub-efi-amd64` as dependency)

    apt-get install grub-efi

Remove `grub-pc` if necessary

Mount the EFI partition

    mkdir /boot/efi
    mount /dev/sda1 /boot/efi

Check you have rEFInd and APPLE directories inside the mounted EFI partitions

Create a Debian directory and install GRUB into it

    mkdir /boot/efi/EFI/debian
    grub-install --target=x86_64 --directory=/usr/lib/grub/x86_64-efi /dev/sda1

Verify the debian directory now contains the `grubx64.efi` file. Rename it so that rEFInd can show a nice icon

    cd /boot/efi/EFI/debian
    mv grubx64.efi e.efi

Set the graphics correct for GRUB and some other config for stability etc

    vi /etc/default/grub

    ...
    GRUB_VIDEO_BACKEND="efi-uga"

    GRUB_CMDLINE_LINUX_DEFAULT="quit libata.force=noncq"
    GRUB_CMDLINE_LINUX=""
    ...

Update GRUB and then reboot

    update-grub
    shutdown -r now


## Setup Debian ##
Some quick setup to make our live easier with further setup and configuration.

Get a bigger font-size in the console

    dpkg-reconfigure console-setup

Choose font `Terminus` with size `14x28`.

Select the correct keyboard layout.

    dpkg-reconfigure keyboard-configuration

Choose `apple laptop` type keyboard. In some cases this might only have the tilde (~) and paragraph (§) keys exchanged.

Install git to fetch our `dotfiles` repository

    apt-get install --no-install-recommends git

Fetch the dotfiles repo

    git clone git://github.com/mdonkers/dotfiles.git "/tmp/dotfiles"


## Dist upgrade to Stretch ##
We need to do the dist-upgrade because for some reason 'Stretch' won't install directly. Hopefully at some point not needed anymore.
Check the status of packages, you should see no warnings or either fix them

    dpkg --audit

Run the following commands to do the upgrade:

    cd /tmp/dotfiles/bin
    install.sh dist

Because the kernel is upgraded, GRUB also needs to be updated to boot the correct stuff. Re-run the `mount` and `grub-install` steps to fix GRUB before rebooting.

Now you're ready to reboot! Cross your fingers...


## Continue Debian configuration ##
Now we can start installing tools to make the MacBook work as intended. First we'll install them and then setup one by one.
(might need to fetch the `dotfiles` repo again)

    cd /tmp/dotfiles
    bin/install.sh sources
    bin/install.sh wifi broadcom
    bin/install.sh graphics mac
    bin/install.sh wm

As user, **not as root** !

    bin/install.sh dotfiles

Verify wlan is working

    iwconfig

Cleanup

    bin/install.sh cleanup






### Installing the graphical environment i3 ###
Install more stuff

    apt-get install xorg xserver-xorg-video-intel
    apt-get install dunst feh i3 i3lock i3status scrot suckless-tools
    apt-get install arandr network-manager-gnome rxvt-unicode chromium

A reboot might be welcome. After that you can start the i3 window manager with the `startx` command. The first time the user is asked which modifier key is wanted (I prefer the CMD key) and an i3 config file is created.

Use `arandr` as graphical interface to `xrandr` to configure the screen resolution. A resolution of 1440x900 works for me (1680x1050 if you like small fonts).

To easily configure the wifi you may use the Gnome network manager as applet under i3. Add the following line to your i3 config file `~/.i3/config`:

    exec --no-startup-id nm-applet

The applet will show up in the status bar after i3 is restarted.

