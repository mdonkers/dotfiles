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
# assumes you are going to use debian testing
setup_sources() {
	apt-get update
	apt-get install -y \
		apt-transport-https \
                dirmngr \
                gnupg \
                gnupg2 \
		--no-install-recommends

	cat <<-EOF > /etc/apt/sources.list.d/base.list
	# hack for latest git (don't judge)
	deb http://ppa.launchpad.net/git-core/ppa/ubuntu xenial main
	deb-src http://ppa.launchpad.net/git-core/ppa/ubuntu xenial main

	# neovim
	deb http://ppa.launchpad.net/neovim-ppa/unstable/ubuntu xenial main
	deb-src http://ppa.launchpad.net/neovim-ppa/unstable/ubuntu xenial main
	EOF

	# add the git-core ppa gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys E1DD270288B4E6030699E45FA1715D88E1DF1F24

	# add the neovim ppa gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 9DBB0BE9366964F134855E2255F96FCF8231B6DD

	# turn off translations, speed up apt-get update
	mkdir -p /etc/apt/apt.conf.d
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99translations
}

dist_upgrade() {
	apt-get update
	apt-get -y upgrade
        apt-get -y dist-upgrade
}

# installs base packages
# the utter bare minimal shit
base() {
	apt-get update
	apt-get -y upgrade

	apt-get install -y \
		adduser \
		automake \
		bash-completion \
		bc \
		bridge-utils \
		bzip2 \
		ca-certificates \
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
		indent \
		iptables \
		jq \
		less \
		libc6-dev \
		libltdl-dev \
		libseccomp-dev \
		locales \
		lsof \
		make \
                mc \
		mount \
                neovim \
		net-tools \
		network-manager \
		openvpn \
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
		xz-utils \
		zip \
		--no-install-recommends

        cleanup

	install_scripts
}

cleanup() {
	apt-get autoremove
	apt-get autoclean
	apt-get clean
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


get_dotfiles() {
	# create subshell
	(
	cd "/home/$USERNAME"
        mkdir "/home/$USERNAME/.gnupg"

	# install dotfiles from repo
        rm -rf "/home/$USERNAME/dotfiles"
	git clone git://github.com/mdonkers/dotfiles.git "/home/$USERNAME/dotfiles"

	# installs all the things
	cd "/home/$USERNAME/dotfiles"
        git checkout windows
	make

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

	apt-get update
	apt-get install -y \
		oracle-java8-installer \
                sbt \
                nodejs \
                erlang \
                erlang-proper-dev \
                rebar \
                elixir \
                python3-pip \
                python3-setuptools \
                python3-wheel \
                ansible \
                linux-perf \
                cmake \
                build-essential \
		--no-install-recommends

        # Packages linux-perf and cmake are installed to run Linux performance tests
        # Get the FlameGraph software here: https://github.com/brendangregg/FlameGraph

        cleanup

        # Install some Python plugins. Neovim adds a Python extension to NeoVIM
        pip3 install --system virtualenv maybe neovim
}



usage() {
	echo -e "install.sh\n\tThis script installs my basic setup for a debian laptop\n"
	echo "Usage:"
	echo "  sources                     - setup sources & install base pkgs"
        echo "  dist                        - setup sources & dist upgrade"
        echo "  dotfiles                    - get dotfiles (!! as user !!)"
        echo "  scripts                     - install scripts (not needed)"
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
	elif [[ $cmd == "dotfiles" ]]; then
		get_dotfiles
	elif [[ $cmd == "scripts" ]]; then
		install_scripts
	elif [[ $cmd == "dev" ]]; then
		check_is_sudo

                install_dev
	elif [[ $cmd == "cleanup" ]]; then
	        cleanup
	else
		usage
	fi
}

main "$@"
