#!/bin/bash
set -e
set -o pipefail

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
# assumes you are going to use debian testing
setup_sources() {
	apt update
	apt install -y \
		apt-transport-https \
                dirmngr \
                gnupg \
                gnupg2 \
		--no-install-recommends

	cat <<-EOF > /etc/apt/sources.list
	deb http://httpredir.debian.org/debian testing main contrib non-free
	deb-src http://httpredir.debian.org/debian/ testing main contrib non-free

	deb http://httpredir.debian.org/debian/ testing-updates main contrib non-free
	deb-src http://httpredir.debian.org/debian/ testing-updates main contrib non-free

	deb http://security.debian.org/ testing/updates main contrib non-free
	deb-src http://security.debian.org/ testing/updates main contrib non-free

	#deb http://httpredir.debian.org/debian/ jessie-backports main contrib non-free
	#deb-src http://httpredir.debian.org/debian/ jessie-backports main contrib non-free

	deb http://httpredir.debian.org/debian experimental main contrib non-free
	deb-src http://httpredir.debian.org/debian experimental main contrib non-free

	# hack for latest git (don't judge)
	deb http://ppa.launchpad.net/git-core/ppa/ubuntu xenial main
	deb-src http://ppa.launchpad.net/git-core/ppa/ubuntu xenial main

	# neovim
	deb http://ppa.launchpad.net/neovim-ppa/unstable/ubuntu xenial main
	deb-src http://ppa.launchpad.net/neovim-ppa/unstable/ubuntu xenial main

	# tlp: Advanced Linux Power Management
	# http://linrunner.de/en/tlp/docs/tlp-linux-advanced-power-management.html
        deb http://ppa.launchpad.net/linrunner/tlp/ubuntu xenial main
	EOF

	# add docker apt repo
	cat <<-EOF > /etc/apt/sources.list.d/docker.list
	deb https://apt.dockerproject.org/repo debian-stretch main
	deb https://apt.dockerproject.org/repo debian-stretch testing
	deb https://apt.dockerproject.org/repo debian-stretch experimental
	EOF

	# add docker gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

	# add the git-core ppa gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys E1DD270288B4E6030699E45FA1715D88E1DF1F24

	# add the neovim ppa gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 9DBB0BE9366964F134855E2255F96FCF8231B6DD

	# add the tlp apt-repo gpg key
        apt-key adv --keyserver pool.sks-keyservers.net --recv-keys 02D65EFF

	# turn off translations, speed up apt update
	mkdir -p /etc/apt/apt.conf.d
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99translations
}

dist_upgrade() {
	apt update
	apt -y upgrade
        apt -y dist-upgrade
}

# installs base packages
# the utter bare minimal shit
base() {
	apt update
	apt -y upgrade

	apt install -y \
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
                fuse \
		gcc \
		git \
		gnupg \
                gnupg2 \
		grep \
		gzip \
		hostname \
                i8kutils \
		indent \
		iptables \
		jq \
		less \
		libapparmor-dev \
		libc6-dev \
		libltdl-dev \
		libseccomp-dev \
                linux-headers-amd64 \
                lm-sensors \
		locales \
		lsof \
		make \
                mc \
		mount \
                neovim \
		net-tools \
		network-manager \
                openresolv \
		openvpn \
                pulseaudio \
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
	apt install -y tlp tlp-rdw

	setup_sudo

        cleanup

        # Load the i8k module for controlling the fans
        modprobe i8k force=1

	# update grub with system specific and docker configs and power-saving items
        # acpi_rev_override=5                 -> necessary for bbswitch / bumblebee to disable discrete NVidia GPU
        # acpi_osi=Linux                      -> tell ACPI we're running Linux
        # pci=noaer                           -> disable Advanced Error Reporting because sometimes flooding the logs
        # enable_psr=1 disable_power_well=0   -> powersaving options for i915 kernel module (if screen flickers, remove these)
        # nmi_watchdog=0                      -> disable NMI Watchdog to reboot / shutdown without problems
	sed -i.bak 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1 acpi_rev_override=5 acpi_osi=Linux pci=noaer nmi_watchdog=0 apparmor=1 security=apparmor page_poison=1 slab_nomerge vsyscall=none"/g' /etc/default/grub
        update-grub
        echo
        echo ">>>>>>>>>>"
	echo "To make kernel parameters effective;"
	echo "run update-grub & reboot"
        echo "<<<<<<<<<<"

	install_docker
	install_scripts
}

cleanup() {
	apt autoremove
	apt autoclean
	apt clean
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
		echo -e "Defaults	secure_path=\"/usr/local/go/bin:/home/${USERNAME}/.go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""; \
		echo -e 'Defaults	env_keep += "ftp_proxy http_proxy https_proxy no_proxy JAVA_HOME GOPATH EDITOR"'; \
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


        ### --- Section is basically a copy of htotheizzo --- ###

        # get the binary
	local tmp_tar=/tmp/docker.tgz
	local binary_uri="https://download.docker.com/linux/static/edge/x86_64"
	local docker_version
	docker_version=$(curl -sSL "https://api.github.com/repos/docker/docker-ce/releases/latest" | jq --raw-output .tag_name)
	docker_version=${docker_version#v}
	# local docker_sha256
	# docker_sha256=$(curl -sSL "${binary_uri}/docker-${docker_version}.tgz.sha256" | awk '{print $1}')
	(
	set -x
	curl -fSL "${binary_uri}/docker-${docker_version}.tgz" -o "${tmp_tar}"
	# echo "${docker_sha256} ${tmp_tar}" | sha256sum -c -
	tar -C /usr/local/bin --strip-components 1 -xzvf "${tmp_tar}"
	rm "${tmp_tar}"
	docker -v
	)
	chmod +x /usr/local/bin/docker*

        ### --- end of copy --- ###

	curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/systemd/system/docker.service > /etc/systemd/system/docker.service
	curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/systemd/system/docker.socket > /etc/systemd/system/docker.socket

	systemctl daemon-reload
	systemctl enable docker
}

# install graphics drivers
install_graphics() {
	local system=$1

	if [[ -z "$system" ]]; then
		echo "You need to specify whether it's dell or mac"
		exit 1
	fi

	if [[ $system == "mac" ]]; then
		local pkgs=""
        else
                local pkgs="nvidia-kernel-dkms nvidia-smi bumblebee-nvidia primus"
	fi

        local pkgs="xorg xserver-xorg xserver-xorg-video-intel ${pkgs}"

	apt install -y $pkgs --no-install-recommends
}

# install custom scripts/binaries
install_scripts() {
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
        
        local scripts=( have light )

	for script in "${scripts[@]}"; do
		curl -sSL "https://misc.j3ss.co/binaries/$script" > "/usr/local/bin/${script}"
		chmod +x "/usr/local/bin/${script}"
	done
}

# install syncthing
install_syncthing() {
        sudo apt update
        sudo apt install -y syncthing --no-install-recommends

	curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/systemd/system/syncthing@.service > /etc/systemd/system/syncthing@.service

	systemctl daemon-reload
	systemctl enable "syncthing@${USERNAME}"
}

# install wifi drivers
install_wifi() {
	local system=$1

	if [[ -z "$system" ]]; then
		echo "You need to specify whether it's broadcom or other"
		exit 1
	fi

	if [[ $system == "broadcom" ]]; then
		local pkg="broadcom-sta-dkms wireless-tools"

		apt install -y $pkg
                # Unload conflicting modules and load the wireless module
                modprobe -r b44 b43 b43legacy ssb brcmsmac bcma
                modprobe wl
	else
		local pkg="wireless-tools"

		apt install -y $pkg
	fi
}

# install stuff for i3 window manager
install_wmapps() {
        # Google repo, because Chromium cannot play Netflix but Chrome can
        cat <<-EOF > /etc/apt/sources.list.d/google-chrome-beta.list
        deb https://dl.google.com/linux/chrome/deb/ stable main
	EOF

        # add the Google Chrome apt-repo gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 4CCA1EAF950CEE4AB83976DCA040830F7FAC5991
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796

        apt update

	local pkgs="feh i3 i3lock i3status suckless-tools libanyevent-i3-perl scrot slim arandr network-manager-gnome xinput google-chrome-beta firefox-esr"
	apt install -y $pkgs --no-install-recommends

        local sound_pkgs="pulseaudio-module-bluetooth pulseaudio-utils pavucontrol bluez-firmware blueman"
        apt install -y ${sound_pkgs} --no-install-recommends

        # update Pulse audio settings (replaces entire line)
        sed -i.bak '/flat-volumes/c\flat-volumes = no' /etc/pulse/daemon.conf

	# update clickpad settings
	mkdir -p /etc/X11/xorg.conf.d/
        # Not for MAC
	# curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/X11/xorg.conf.d/50-clickpad.conf > /etc/X11/xorg.conf.d/50-clickpad.conf
	# curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/X11/xorg.conf.d/70-keyboard.conf > /etc/X11/xorg.conf.d/70-keyboard.conf

	# add xorg conf
	# curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/X11/xorg.conf > /etc/X11/xorg.conf

	# get correct sound cards on boot
	# curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/master/etc/modprobe.d/intel.conf > /etc/modprobe.d/intel.conf

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

	# installs all the things
	cd "/home/$USERNAME/dotfiles"
	make

	# enable dbus for the user session
	# systemctl --user enable dbus.socket

        sudo systemctl enable "i3lock@${USERNAME}"
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

install_keybase() {
        curl -o /tmp/keybase_amd64.deb https://prerelease.keybase.io/keybase_amd64.deb
        # if you see an error about missing `libappindicator1`
        # from the next command, you can ignore it, as the
        # subsequent command corrects it
        sudo dpkg -i /tmp/keybase_amd64.deb
        sudo apt install -f
	# Login and get private key
        keybase login
        keybase pgp export -q 24046A96 | gpg --import
        keybase pgp export -q 24046A96 --secret | gpg --allow-secret-key-import --import

        # Install also my 'private' dotfiles repo
        rm -rf "/home/$USERNAME/dotfiles-private"
	git clone git@gitlab.com:mdonkers/dotfiles-private.git "/home/$USERNAME/dotfiles-private"

        sudo ln -snf "/home/$USERNAME/dotfiles-private/bin/vpn-home" /usr/local/bin/vpn-home
}

install_virtualbox() {
	echo "deb http://download.virtualbox.org/virtualbox/debian stretch contrib" >> /etc/apt/sources.list.d/virtualbox.list
	curl -sSL https://www.virtualbox.org/download/oracle_vbox_2016.asc | apt-key add -

	apt update
	apt install -y \
		virtualbox-5.1 \
                --no-install-recommends
}

install_vagrant() {
	VAGRANT_VERSION=1.9.7

	# if we are passing the version
	if [[ ! -z "$1" ]]; then
		export VAGRANT_VERSION=$1
	fi

	# check if we need to install virtualbox
	PKG_OK=$(dpkg-query -W --showformat='${Status}\n' virtualbox-5.1 | grep "install ok installed") || echo ""
	echo Checking for virtualbox: $PKG_OK
	if [ "" == "$PKG_OK" ]; then
		echo "No virtualbox. Installing virtualbox."
		install_virtualbox
	fi

	tmpdir=`mktemp -d`
	(
	cd $tmpdir
        echo "Downloading Vagrant to $tmpdir"
	curl -sSL -o vagrant.deb https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_x86_64.deb
	dpkg -i vagrant.deb
	)

	rm -rf $tmpdir

	# install plugins
	vagrant plugin install vagrant-vbguest vagrant-disksize
}

# install/update golang from source
install_golang() {
	export GO_VERSION
	GO_VERSION=$(curl -sSL "https://golang.org/VERSION?m=text")
	export GO_SRC=/usr/local/go

	# if we are passing the version
	if [[ ! -z "$1" ]]; then
		GO_VERSION=$1
	fi

	# purge old src
	if [[ -d "$GO_SRC" ]]; then
		sudo rm -rf "$GO_SRC"
		sudo rm -rf "$GOPATH"
	fi

	GO_VERSION=${GO_VERSION#go}

	# subshell
	(
	curl -sSL "https://storage.googleapis.com/golang/go${GO_VERSION}.linux-amd64.tar.gz" | sudo tar -v -C /usr/local -xz
	local user="$USER"
	# rebuild stdlib for faster builds
	sudo chown -R "${user}" /usr/local/go/pkg
	CGO_ENABLED=0 go install -a -installsuffix cgo std
	)

	# get commandline tools
	(
	set -x
	set +e
	go get github.com/golang/lint/golint
	go get golang.org/x/tools/cmd/cover
	go get golang.org/x/review/git-codereview
	go get golang.org/x/tools/cmd/goimports
	go get golang.org/x/tools/cmd/gorename
	go get golang.org/x/tools/cmd/guru
	)
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
        deb https://deb.nodesource.com/node_9.x jessie main
        deb-src https://deb.nodesource.com/node_9.x jessie main
	EOF

        # add Erlang / Elixir apt repo
        cat <<-EOF > /etc/apt/sources.list.d/erlang-solutions.list
        deb https://packages.erlang-solutions.com/ubuntu trusty contrib
	EOF

        # add Ansible apt repo
        cat <<-EOF > /etc/apt/sources.list.d/ansible.list
        deb http://ppa.launchpad.net/ansible/ansible/ubuntu xenial main
	EOF

        # add the Java webupd8team gpg key
        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886

        # add the Sbt gpg key
        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2EE0EA64E40A89B84B2DF73499E82A75642AC823

        # add the NodeSource NodeJS gpg key
        curl --silent https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -

        # add the Erlang Solutions gpg key
        curl --silent https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | apt-key add -

        # add the Ansible gpg key
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367

        # Automatically accept license agreement
        echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections

	apt update
	apt install -y \
		oracle-java8-installer \
                sbt \
                erlang \
                erlang-proper-dev \
                rebar \
                elixir \
                python3-pip \
                python3-setuptools \
                python3-wheel \
                wireshark-qt \
                awscli \
                ansible \
                linux-perf \
                cmake \
                build-essential \
                postgresql-client \
		--no-install-recommends

        # Packages linux-perf and cmake are installed to run Linux performance tests
        # Get the FlameGraph software here: https://github.com/brendangregg/FlameGraph

        cleanup

        # Add user to group Wireshark for capturing permissions
        dpkg-reconfigure wireshark-common
	sudo gpasswd -a "$USERNAME" wireshark

        # Install some Python plugins. Neovim adds a Python extension to NeoVIM
        pip3 install --system virtualenv maybe neovim j2cli
}



usage() {
	echo -e "install.sh\n\tThis script installs my basic setup for a debian laptop\n"
	echo "Usage:"
	echo "  sources                     - setup sources & install base pkgs"
        echo "  dist                        - setup sources & dist upgrade"
	echo "  wifi {broadcom,other}       - install wifi drivers"
	echo "  graphics {dell,mac}         - install graphics drivers"
	echo "  wm                          - install window manager/desktop pkgs"
        echo "  dotfiles                    - get dotfiles (!! as user !!)"
        echo "  scripts                     - install scripts (not needed)"
        echo "  syncthing                   - install syncthing"
        echo "  keybase                     - install keybase and private repo (!! as user !!)"
        echo "  vagrant                     - install vagrant and virtualbox"
        echo "  dev                         - install development environment for Java"
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
		check_is_sudo

		install_vagrant "$2"
	elif [[ $cmd == "dev" ]]; then
		check_is_sudo

                install_dev
	elif [[ $cmd == "golang" ]]; then
		install_golang "$2"
	elif [[ $cmd == "keybase" ]]; then
		install_keybase
	elif [[ $cmd == "cleanup" ]]; then
	        cleanup
	else
		usage
	fi
}

main "$@"
