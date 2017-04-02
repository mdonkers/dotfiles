#!/bin/bash
set -e

# install.sh
#	This script installs my basic setup for a debian laptop

# get the user that is not root
# TODO: makes a pretty bad assumption that there is only one other user
USERNAME=$(find /home/* -maxdepth 0 -printf "%f" -type d)
export DEBIAN_FRONTEND=noninteractive

check_is_sudo() {
	if [ "$EUID" -ne 0 ]; then
		echo "Please run as root."
		exit
	fi
}

# sets up apt sources
# assumes you are going to use debian stretch
setup_sources() {
	apt-get update
	apt-get install -y \
		apt-transport-https \
		--no-install-recommends

	cat <<-EOF > /etc/apt/sources.list
	deb http://httpredir.debian.org/debian stretch main contrib non-free
	deb-src http://httpredir.debian.org/debian/ stretch main contrib non-free

	deb http://httpredir.debian.org/debian/ stretch-updates main contrib non-free
	deb-src http://httpredir.debian.org/debian/ stretch-updates main contrib non-free

	deb http://security.debian.org/ stretch/updates main contrib non-free
	deb-src http://security.debian.org/ stretch/updates main contrib non-free

	#deb http://httpredir.debian.org/debian/ jessie-backports main contrib non-free
	#deb-src http://httpredir.debian.org/debian/ jessie-backports main contrib non-free

	deb http://httpredir.debian.org/debian experimental main contrib non-free
	deb-src http://httpredir.debian.org/debian experimental main contrib non-free

	# hack for latest git (don't judge)
	deb http://ppa.launchpad.net/git-core/ppa/ubuntu wily main
	deb-src http://ppa.launchpad.net/git-core/ppa/ubuntu wily main

	# neovim
	deb http://ppa.launchpad.net/neovim-ppa/unstable/ubuntu wily main
	deb-src http://ppa.launchpad.net/neovim-ppa/unstable/ubuntu wily main

	# tlp: Advanced Linux Power Management
	# http://linrunner.de/en/tlp/docs/tlp-linux-advanced-power-management.html
	deb http://repo.linrunner.de/debian sid main
	EOF

	# add docker apt repo
	cat <<-EOF > /etc/apt/sources.list.d/docker.list
	deb https://apt.dockerproject.org/repo debian-stretch main
	deb https://apt.dockerproject.org/repo debian-stretch testing
	deb https://apt.dockerproject.org/repo debian-stretch experimental
	EOF

        # Google repo, because Chromium cannot play Netflix but Chrome can
        cat <<-EOF > /etc/apt/sources.list.d/google-chrome-beta.list
        deb https://dl.google.com/linux/chrome/deb/ stable main
        EOF

	# add keybase apt repo
	cat <<-EOF > /etc/apt/sources.list.d/keybase.list
        deb http://dist.keybase.io/linux/deb/repo/ stable main
	EOF

	# add docker gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

	# add the git-core ppa gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys E1DD270288B4E6030699E45FA1715D88E1DF1F24

	# add the neovim ppa gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 9DBB0BE9366964F134855E2255F96FCF8231B6DD

	# add the tlp apt-repo gpg key
	apt-key adv --keyserver pool.sks-keyservers.net --recv-keys CD4E8809

        # add the Google Chrome apt-repo gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 4CCA1EAF950CEE4AB83976DCA040830F7FAC5991
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796

	# turn off translations, speed up apt-get update
	mkdir -p /etc/apt/apt.conf.d
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99translations
}

dist_upgrade() {
	apt-get update
	apt-get -y upgrade
        apt-get dist-upgrade
}

# installs base packages
# the utter bare minimal shit
base() {
	apt-get update
	apt-get -y upgrade

	apt-get install -y \
		adduser \
		alsa-utils \
		apparmor \
		automake \
		bash-completion \
		bc \
		bridge-utils \
		bzip2 \
		ca-certificates \
		cgroupfs-mount \
		coreutils \
		curl \
		dnsutils \
		file \
		findutils \
		gcc \
		git \
		gnupg \
		grep \
		gzip \
		hostname \
		indent \
		iptables \
		jq \
		less \
		libapparmor-dev \
		libc6-dev \
		libltdl-dev \
		libseccomp-dev \
		locales \
		lsof \
                macfanctld \
		make \
                mc \
		mount \
                neovim \
		net-tools \
		network-manager \
                openconnect \
                stoken \
		openvpn \
                pulseaudio-module-bluetooth \
		rxvt-unicode-256color \
		silversearcher-ag \
		ssh \
		strace \
		sudo \
		tar \
		tree \
		tzdata \
		unzip \
		xclip \
		xcompmgr \
		xz-utils \
		zip \
		--no-install-recommends

	# install tlp with recommends
	apt-get install -y tlp tlp-rdw

	setup_sudo

        cleanup

	install_docker
	install_scripts
	#install_syncthing
}

cleanup() {
	apt-get autoremove
	apt-get autoclean
	apt-get clean
}

# setup sudo for a user
# because fuck typing that shit all the time
# just have a decent password
# and lock your computer when you aren't using it
# if they have your password they can sudo anyways
# so its pointless
# i know what the fuck im doing ;)
setup_sudo() {
	# add user to sudoers
	adduser "$USERNAME" sudo

	# add user to systemd groups
	# then you wont need sudo to view logs and shit
	gpasswd -a "$USERNAME" systemd-journal
	gpasswd -a "$USERNAME" systemd-network

	# set secure path
	{ \
		echo -e 'Defaults	secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"'; \
		echo -e 'Defaults	env_keep += "ftp_proxy http_proxy https_proxy no_proxy JAVA_HOME EDITOR"'; \
		echo -e "${USERNAME} ALL=(ALL) NOPASSWD:ALL"; \
		echo -e "${USERNAME} ALL=NOPASSWD: /sbin/ifconfig, /sbin/ifup, /sbin/ifdown, /sbin/ifquery"; \
	} >> /etc/sudoers

}

# installs docker master
# and adds necessary items to boot params
install_docker() {

	# create docker group
	sudo groupadd docker
	sudo gpasswd -a "$USERNAME" docker


	curl -sSL https://get.docker.com/builds/Linux/x86_64/docker-latest.tgz | tar -xvz \
		-C /usr/local/bin --strip-components 1
	chmod +x /usr/local/bin/docker*

	curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/systemd/system/docker.service > /etc/systemd/system/docker.service
	curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/systemd/system/docker.socket > /etc/systemd/system/docker.socket

	systemctl daemon-reload
	systemctl enable docker

	# update grub with docker configs and power-saving items
	sed -i.bak 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1 i915.enable_psr=0 pcie_asm=force i915.i915_enable_fbc=1 i915.i915_enable_rc6=7 i915.lvds_downclock=1 apparmor=1 security=apparmor hid_apple.fnmode=2"/g' /etc/default/grub
        echo
        echo ">>>>>>>>>>"
	echo "Docker has been installed. If you want memory management & swap"
	echo "run update-grub & reboot"
        echo "<<<<<<<<<<"
}

# install graphics drivers
install_graphics() {
	local system=$1

	if [[ -z "$system" ]]; then
		echo "You need to specify whether it's dell, mac or lenovo"
		exit 1
	fi

	local pkgs="nvidia-kernel-dkms bumblebee-nvidia primus"

	if [[ $system == "mac" ]] || [[ $system == "dell" ]]; then
		local pkgs="xorg xserver-xorg xserver-xorg-video-intel"
	fi

	apt-get install -y $pkgs --no-install-recommends
}

# install custom scripts/binaries
install_scripts() {
	# install acsciinema
	curl -sSL https://asciinema.org/install | sh

	# install speedtest
	curl -sSL https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py > /usr/local/bin/speedtest
	chmod +x /usr/local/bin/speedtest

	# install icdiff
	curl -sSL https://raw.githubusercontent.com/jeffkaufman/icdiff/master/icdiff > /usr/local/bin/icdiff
	curl -sSL https://raw.githubusercontent.com/jeffkaufman/icdiff/master/git-icdiff > /usr/local/bin/git-icdiff
	chmod +x /usr/local/bin/icdiff
	chmod +x /usr/local/bin/git-icdiff

	# install lolcat
	curl -sSL https://raw.githubusercontent.com/tehmaze/lolcat/master/lolcat > /usr/local/bin/lolcat
	chmod +x /usr/local/bin/lolcat

	# download syncthing binary
	#if [[ ! -f /usr/local/bin/syncthing ]]; then
	#	curl -sSL https://jesss.s3.amazonaws.com/binaries/syncthing > /usr/local/bin/syncthing
	#	chmod +x /usr/local/bin/syncthing
	#fi

	#syncthing -upgrade
}

# install syncthing
install_syncthing() {
	curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/systemd/system/syncthing@.service > /etc/systemd/system/syncthing@.service

	systemctl daemon-reload
	systemctl enable "syncthing@${USERNAME}"
}

# install wifi drivers
install_wifi() {
	local system=$1

	if [[ -z "$system" ]]; then
		echo "You need to specify whether it's broadcom or intel"
		exit 1
	fi

	if [[ $system == "broadcom" ]]; then
		local pkg="broadcom-sta-dkms wireless-tools"

		apt-get install -y $pkg
                # Unload conflicting modules and load the wireless module
                modprobe -r b44 b43 b43legacy ssb brcmsmac bcma
                modprobe wl
	else
		update-iwlwifi
	fi
}

# install stuff for i3 window manager
install_wmapps() {
	local pkgs="feh i3 i3lock i3status suckless-tools libanyevent-i3-perl scrot slim arandr network-manager-gnome google-chrome-beta"

	apt-get install -y $pkgs --no-install-recommends

	# update clickpad settings
	mkdir -p /etc/X11/xorg.conf.d/
        # Not for MAC
	# curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/X11/xorg.conf.d/50-synaptics-clickpad.conf > /etc/X11/xorg.conf.d/50-synaptics-clickpad.conf

	# add xorg conf
	curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/X11/xorg.conf > /etc/X11/xorg.conf

	# get correct sound cards on boot
	#curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/modprobe.d/intel.conf > /etc/modprobe.d/intel.conf

	# pretty fonts
	curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/fonts/local.conf > /etc/fonts/local.conf

        echo
        echo ">>>>>>>>>>"
	echo "Fonts file setup successfully now run:"
	echo "	dpkg-reconfigure fontconfig-config"
	echo "with settings: "
	echo "	Autohinter, Automatic, No."
	echo "Run: "
	echo "	dpkg-reconfigure fontconfig"
        echo "<<<<<<<<<<"
}

get_dotfiles() {
	# create subshell
	(
	cd "/home/$USERNAME"
        mkdir "/home/$USERNAME/.gnupg"

	# setup downloads folder as tmpfs
	# that way things are removed on reboot
	# i like things clean but you may not want this
	mkdir -p "/home/$USERNAME/Downloads"
	# echo -e "\n# tmpfs for downloads\ntmpfs\t/home/${USERNAME}/Downloads\ttmpfs\tnodev,nosuid,size=2G\t0\t0" >> /etc/fstab

	# install dotfiles from repo
        rm -rf "/home/$USERNAME/dotfiles"
	git clone git://github.com/mdonkers/dotfiles.git "/home/$USERNAME/dotfiles"
	cd "/home/$USERNAME/dotfiles"

	# installs all the things
	make

	# enable dbus for the user session
	# systemctl --user enable dbus.socket

	sudo systemctl enable i3lock
	sudo systemctl enable suspend-sedation.service
	sudo systemctl enable powertop.service

	cd "/home/$USERNAME"

	# install .vim files
	sudo ln -snf "/home/$USERNAME/.vim" /root/.vim
	sudo ln -snf "/home/$USERNAME/.vimrc" /root/.vimrc

	# alias vim dotfiles to neovim
	mkdir -p ${XDG_CONFIG_HOME:=$HOME/.config}
	ln -snf "/home/$USERNAME/.vim" $XDG_CONFIG_HOME/nvim
	ln -snf "/home/$USERNAME/.vimrc" $XDG_CONFIG_HOME/nvim/init.vim
	# do the same for root
	sudo mkdir -p /root/.config
	sudo ln -snf "/home/$USERNAME/.vim" /root/.config/nvim
	sudo ln -snf "/home/$USERNAME/.vimrc" /root/.config/nvim/init.vim

	# update alternatives to neovim
	sudo update-alternatives --install /usr/bin/vi vi /usr/bin/nvim 60
	sudo update-alternatives --config vi
	sudo update-alternatives --install /usr/bin/vim vim /usr/bin/nvim 60
	sudo update-alternatives --config vim
	sudo update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 60
	sudo update-alternatives --config editor
	)
}

install_facetimehd() {
        git clone https://github.com/patjak/bcwc_pcie.git /tmp/bcwc_pcie
        # create subshell
        (
        cd /tmp/bcwc_pcie/firmware
        make
        make install
        cd ..
        make
        make install
        depmod
        modprobe facetimehd
        )
}

install_keybase() {
        curl https://keybase.io/docs/server_security/code_signing_key.asc | gpg --import
        gpg --export 222B85B0F90BE2D24CFEB93F47484E50656D16C7 | sudo apt-key add -

        sudo apt-get update
        sudo apt-get install keybase
        
	# Login and get private key
        keybase login
        keybase pgp export -q 24046A96 | gpg --import
        keybase pgp export -q 24046A96 --secret | gpg --allow-secret-key-import --import
}

install_virtualbox() {
	# check if we need to install libvpx1
	PKG_OK=$(dpkg-query -W --showformat='${Status}\n' libvpx1 | grep "install ok installed")
	echo Checking for libvpx1: $PKG_OK
	if [ "" == "$PKG_OK" ]; then
		echo "No libvpx1. Installing libvpx1."
		jessie_sources=/etc/apt/sources.list.d/jessie.list
		echo "deb http://httpredir.debian.org/debian jessie main contrib non-free" > $jessie_sources

		apt-get update
		apt-get install -y -t jessie libvpx1 \
			--no-install-recommends

		# cleanup the file that we used to install things from jessie
		rm $jessie_sources
	fi

	echo "deb http://download.virtualbox.org/virtualbox/debian vivid contrib" >> /etc/apt/sources.list.d/virtualbox.list
	curl -sSL https://www.virtualbox.org/download/oracle_vbox.asc | apt-key add -

	apt-get update
	apt-get install -y \
		virtualbox-5.0
	--no-install-recommends
}

install_vagrant() {
	VAGRANT_VERSION=1.8.1

	# if we are passing the version
	if [[ ! -z "$1" ]]; then
		export VAGRANT_VERSION=$1
	fi

	# check if we need to install virtualbox
	PKG_OK=$(dpkg-query -W --showformat='${Status}\n' virtualbox | grep "install ok installed")
	echo Checking for virtualbox: $PKG_OK
	if [ "" == "$PKG_OK" ]; then
		echo "No virtualbox. Installing virtualbox."
		install_virtualbox
	fi

	tmpdir=`mktemp -d`
	(
	cd $tmpdir
	curl -sSL -o vagrant.deb https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_x86_64.deb
	dpkg -i vagrant.deb
	)

	rm -rf $tmpdir

	# install plugins
	vagrant plugin install vagrant-vbguest
}

install_dev() {
	mkdir -p /Development
        chown -R $USERNAME:$USERNAME /Development

        # add Java apt repo
	cat <<-EOF > /etc/apt/sources.list.d/webupd8team-java.list
        deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main
        deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main
	EOF

        # add Sbt apt repo
        cat <<-EOF > /etc/apt/sources.list.d/sbt.list
        deb https://dl.bintray.com/sbt/debian /
        EOF

        # add NodeJS apt repo
	cat <<-EOF > /etc/apt/sources.list.d/nodesource-nodejs.list
        deb https://deb.nodesource.com/node_7.x jessie main
        deb-src https://deb.nodesource.com/node_7.x jessie main
	EOF

        # add the Java webupd8team gpg key
        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886

        # add the Sbt gpg key
        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2EE0EA64E40A89B84B2DF73499E82A75642AC823

        # add the NodeSource NodeJS gpg key
        curl --silent https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -

        # Automatically accept license agreement
        echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections

	apt-get update
	apt-get install -y \
		oracle-java8-installer \
                sbt \
                nodejs \
                krb5-user \
                krb5-config \
                erlang \
                erlang-proper-dev \
                rebar \
                python3-pip \
                python3-setuptools \
                python3-wheel \
                wireshark-qt \
		--no-install-recommends

        cleanup

        # Install some Python plugins. Neovim adds a Python extension to NeoVIM
        pip3 install --system virtualenv maybe neovim
}



usage() {
	echo -e "install.sh\n\tThis script installs my basic setup for a debian laptop\n"
	echo "Usage:"
	echo "  sources                     - setup sources & install base pkgs"
        echo "  dist                        - setup sources & dist upgrade"
	echo "  wifi {broadcom,intel}       - install wifi drivers"
	echo "  graphics {dell,mac,lenovo}  - install graphics drivers"
	echo "  wm                          - install window manager/desktop pkgs"
        echo "  dotfiles                    - get dotfiles (!! as user !!)"
        echo "  scripts                     - install scripts (not needed)"
        echo "  syncthing                   - install syncthing (not needed)"
        echo "  vagrant                     - install vagrant and virtualbox (not needed)"
        echo "  dev                         - install development environment for Java"
        echo "  facetimehd                  - install facetimehd camera for Macbook"
        echo "  keybase                     - install keybase (!! as user !!)"
        echo "  cleanup                     - clean apt etc"
}

main() {
	local cmd=$1

	if [[ -z "$cmd" ]]; then
		usage
		exit 1
	fi

	if [[ $cmd == "sources" ]]; then
		check_is_sudo

		# setup /etc/apt/sources.list
		setup_sources

		base
	elif [[ $cmd == "dist" ]]; then
		check_is_sudo
		# setup /etc/apt/sources.list
		setup_sources
                dist_upgrade
	elif [[ $cmd == "wifi" ]]; then
		install_wifi "$2"
	elif [[ $cmd == "graphics" ]]; then
		check_is_sudo

		install_graphics "$2"
	elif [[ $cmd == "wm" ]]; then
		check_is_sudo

		install_wmapps
	elif [[ $cmd == "dotfiles" ]]; then
		get_dotfiles
	elif [[ $cmd == "scripts" ]]; then
		install_scripts
	elif [[ $cmd == "syncthing" ]]; then
		install_syncthing
	elif [[ $cmd == "vagrant" ]]; then
		install_vagrant "$2"
	elif [[ $cmd == "dev" ]]; then
		check_is_sudo

                install_dev
	elif [[ $cmd == "facetimehd" ]]; then
		check_is_sudo

		install_facetimehd
	elif [[ $cmd == "keybase" ]]; then
		install_keybase
	elif [[ $cmd == "cleanup" ]]; then
	        cleanup
	else
		usage
	fi
}

main "$@"
