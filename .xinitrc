#!/bin/sh
#
## ~/.xsessionrc
#
## Executed by startx (loading some variables for all Xsessions)

if [ -d /etc/X11/xinit/xinitrc.d ]; then
	for f in /etc/X11/xinit/xinitrc.d/*; do
	    # shellcheck source=/dev/null
		[ -x "$f" ] && . "$f"
	done
	unset f
fi

# run Xprofile
# shellcheck source=/dev/null
[ -f ~/.Xprofile ] && . ~/.Xprofile

# run Xmodmap
[ -f ~/.Xmodmap ] && xmodmap ~/.Xmodmap

# run local xhost
xhost local:root

# If not using a login (display) manager, you might want to create
# the ~/.xsession file and move below contents there to start a specific
# Window Manager.
# Priority is as follows:
# - Run session as provided by Display Manager
# - Run "~/.xsession" or "~/.Xsession" and start Window Manager from there
# - Run "/usr/bin/x-window-manager", which can be configured via "update-alternatives --config x-window-manager"

##
# Propogate DISPLAY vars to Systemd, for more info see this
#  https://wiki.archlinux.org/index.php/Systemd/User#Environment_variables
#
systemctl --user import-environment DISPLAY XAUTHORITY

# Make apps detect the WM correctly
export XDG_CURRENT_DESKTOP=i3

# See also "man i3", start i3 Window Manager directly from "~/.xsession"
# exec i3 -V >> ~/.i3/logfile 2>&1
exec i3 >> ~/.i3-logfile 2>&1
