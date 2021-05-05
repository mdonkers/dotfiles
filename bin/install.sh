#!/bin/bash
set -e
set -o pipefail

# install.sh
#	This script installs my basic setup for a debian laptop

# get the user that is not root
# TODO: makes a pretty bad assumption that there is only one other user
USERNAME=$(find /home/* -maxdepth 0 -printf "%f" -type d)

check_is_sudo() {
  if [ "$EUID" -ne 0 ]; then
	echo "Please run as root."
	exit
  fi
}

# installs base packages
# the utter bare minimal shit
base() {
  dnf update -y

  dnf install -y \
	automake \
	bash-completion \
	bc \
	bind-utils \
	bridge-utils \
	bzip2 \
	ca-certificates \
	container-selinux \
	coreutils \
	curl \
	dnf-plugins-core \
	fail2ban \
	file \
	findutils \
	fwupd \
	gcc \
	git \
	git-lfs \
	gnupg2 \
	gnutls-utils \
	grep \
	gzip \
	hostname \
	inotify-tools \
	iproute \
	iptables \
	jq \
	less \
	light \
	lm_sensors \
	lsof \
	make \
	mc \
	neovim \
	net-tools \
	NetworkManager \
	openresolv \
	openvpn \
	openssh \
	openssl \
	opensc \
	pam-u2f \
	pamu2fcfg \
	pcsc-tools \
	pcsc-lite \
	perl-libwww-perl \
	picom \
	procps \
	rxvt-unicode \
	the_silver_searcher \
	strace \
	sudo \
	tar \
	tree \
	tzdata \
	unzip \
	whois \
	xclip \
	xz \
	zip

  setup_sudo

  install_docker
  install_scripts

  cleanup
}

cleanup() {
  dnf autoremove -y
  dnf clean -y all
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
  usermod -aG wheel "$USERNAME"

  # add user to systemd groups
  # then you wont need sudo to view logs and shit
  gpasswd -a "$USERNAME" systemd-journal
  gpasswd -a "$USERNAME" systemd-network

  # set secure path
  { \
	echo -e "Defaults	secure_path=\"/usr/local/go/bin:/home/${USERNAME}/.go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""; \
	echo -e 'Defaults	env_keep += "ftp_proxy http_proxy https_proxy no_proxy JAVA_HOME GOPATH EDITOR"'; \
	echo -e "# Possibly allow 'sudo' to be used without password."; \
	echo -e "#${USERNAME} ALL=(ALL) NOPASSWD:ALL"; \
	echo -e "# When using U2F with Yubikey, need to use passwords (configured to only request Yubikey in PAM) but exclude some commands from needing password."; \
	echo -e "${USERNAME} ALL=(ALL) ALL"; \
	echo -e "${USERNAME} ALL=NOPASSWD: /sbin/ifconfig, /sbin/ifup, /sbin/ifdown, /sbin/ifquery, /usr/bin/light, /usr/bin/nsenter"; \
  } >> /etc/sudoers

  echo -e "\\n# binfmt for executing e.g. JAR files directly\\nnone\\t/proc/sys/fs/binfmt_misc\\tbinfmt_misc\\tdefaults\\t0\\t0" >> /etc/fstab
}

# installs docker master
# and adds necessary items to boot params
install_docker() {

  # Remove potential old Docker installs
  dnf remove -y docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-selinux \
                  docker-engine-selinux \
                  docker-engine


  # create docker group
  sudo groupadd docker || true
  sudo gpasswd -a "$USERNAME" docker

  dnf config-manager \
    --add-repo \
    https://download.docker.com/linux/fedora/docker-ce.repo
  dnf config-manager --set-enabled docker-ce-test
  rpm --import https://download.docker.com/linux/fedora/gpg

  dnf install -y docker-ce docker-ce-cli containerd.io

  systemctl daemon-reload
  systemctl enable docker
  sleep 5
  systemctl start docker

  docker -v
}

# install graphics drivers
install_graphics() {
  local system=$1

  local pkgs=( xorg-x11-server-common xorg-x11-server-Xorg xorg-x11-drv-libinput )

  case $system in
	"intel")
	  pkgs+=( xserver-xorg-video-intel )
	  ;;
	"geforce")
	  pkgs+=( nvidia-driver )
	  ;;
	"optimus")
	  pkgs+=( nvidia-kernel-dkms bumblebee-nvidia primus )
	  ;;
	*)
	  echo "No system specified, assuming graphics drivers present"
	  ;;
  esac

  dnf update -y || true

  dnf install -y "${pkgs[@]}"
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

	apt install -y "$pkg"
	# Unload conflicting modules and load the wireless module
	modprobe -r b44 b43 b43legacy ssb brcmsmac bcma
	modprobe wl
  else
	local pkg="wireless-tools"

	dnf install -y "$pkg"
  fi
}

# install stuff for i3 window manager
install_wmapps() {

  # Add Google Chrome repository
  dnf install -y fedora-workstation-repositories
  dnf config-manager --set-enabled google-chrome

  dnf update -y
  dnf install -y \
	feh \
	i3 \
	i3lock \
	i3status \
	dmenu \
	ImageMagick \
	arandr \
	network-manager-applet \
	xinput \
	google-chrome-beta \
	firefox

  dnf install -y \
	pipewire \
	pipewire-alsa \
	pipewire-pulseaudio \
	pipewire-utils \
	pavucontrol \
	blueman

  # update Pulse audio settings (replaces entire line)
  #sed -i.bak '/flat-volumes/c\flat-volumes = no' /etc/pulse/daemon.conf

  # update clickpad settings
  mkdir -p /etc/X11/xorg.conf.d/

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
  git clone --recursive git://github.com/mdonkers/dotfiles.git "/home/$USERNAME/dotfiles"

  # installs all the things
  cd "/home/$USERNAME/dotfiles"
  make

  sudo systemctl enable "i3lock@${USERNAME}"
  systemctl --user enable slack-status.timer

  cd "/home/$USERNAME"

  # install .vim files
  sudo ln -snf "/home/$USERNAME/.vim" /root/.vim
  sudo ln -snf "/home/$USERNAME/.vimrc" /root/.vimrc

  # alias vim dotfiles to neovim
  mkdir -p "${XDG_CONFIG_HOME:=$HOME/.config}"
  ln -snf "/home/$USERNAME/.vim" "$XDG_CONFIG_HOME/nvim"
  ln -snf "/home/$USERNAME/.vimrc" "$XDG_CONFIG_HOME/nvim/init.vim"
  # do the same for root
  sudo mkdir -p /root/.config
  sudo ln -snf "/home/$USERNAME/.vim" /root/.config/nvim
  sudo ln -snf "/home/$USERNAME/.vimrc" /root/.config/nvim/init.vim

  # update alternatives to neovim
  sudo update-alternatives --install /usr/bin/vi vi "$(command -v nvim)" 60
  sudo update-alternatives --config vi
  sudo update-alternatives --install /usr/bin/vim vim "$(command -v nvim)" 60
  sudo update-alternatives --config vim
  sudo update-alternatives --install /usr/bin/editor editor "$(command -v nvim)" 60
  sudo update-alternatives --config editor
  )
}

install_private() {
  # Install also my 'private' dotfiles repo
  rm -rf "/home/$USERNAME/dotfiles-private"
  git clone git@gitlab.com:mdonkers/dotfiles-private.git "/home/$USERNAME/dotfiles-private"

  # installs all the things (in subshell because we cd)
  (
  cd "/home/$USERNAME/dotfiles-private"
  make
  )

  # Setup PAM to use the Yubikey for 2F authentication
  # Note! For 'sudo' the line is added before 'common-auth' as its sufficient for authentication. For 'login' after the include
  sudo sed -i "\\|common-auth|i \\auth       sufficient   pam_u2f.so  authfile=/etc/yubikey/u2f_keys cue nouserok" /etc/pam.d/sudo
  sudo sed -i "\\|common-auth|a \\auth       required     pam_u2f.so  authfile=/etc/yubikey/u2f_keys cue nouserok" /etc/pam.d/login
}

install_virtualbox() {
  echo "deb http://download.virtualbox.org/virtualbox/debian buster contrib" >> /etc/apt/sources.list.d/virtualbox.list
  curl -sSL https://www.virtualbox.org/download/oracle_vbox_2016.asc | apt-key add -

  apt update
  apt install -y \
	virtualbox-6.1 \
	--no-install-recommends
}

install_vagrant() {
  VAGRANT_VERSION=2.2.14

  # if we are passing the version
  if [[ -n "$1" ]]; then
	export VAGRANT_VERSION=$1
  fi

  # check if we need to install virtualbox
  PKG_OK=$(dpkg-query -W --showformat='${Status}\n' "virtualbox*" | grep "install ok installed") || echo ""
  echo "Checking for virtualbox: $PKG_OK"
  if [ "" == "$PKG_OK" ]; then
	echo "No virtualbox. Installing virtualbox."
	install_virtualbox
  fi

  tmpdir=$(mktemp -d)
  (
  cd "$tmpdir"
  echo "Downloading Vagrant to $tmpdir"
  curl -sSL -o vagrant.deb "https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_x86_64.deb"
  dpkg -i vagrant.deb
  )

  rm -rf "$tmpdir"

  # install plugins
  vagrant plugin expunge --force
  vagrant plugin install vagrant-vbguest vagrant-disksize
}

# install/update golang from source
install_golang() {
  export GO_VERSION
  GO_VERSION=$(curl -sSL "https://golang.org/VERSION?m=text")
  export GO_SRC=/usr/local/go

  # if we are passing the version
  if [[ -n "$1" ]]; then
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

  go get github.com/cbednarski/hostess
  go get github.com/google/go-jsonnet/cmd/jsonnet
  go get github.com/mikefarah/yq/v4
  go get sigs.k8s.io/kind
  )
}

install_dev() {
  mkdir -p /Development
  mkdir -p /Development/{misc,projects,tools,workspaces}
  chown -R "$USERNAME:$USERNAME" /Development

  # add Java apt repo
  cat <<-EOF > /etc/apt/sources.list.d/webupd8team-java.list
	deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main
	deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main
	EOF

  # add Azul Zulu Java apt repo
  cat <<-EOF > /etc/apt/sources.list.d/azul-java.list
	deb http://repos.azulsystems.com/debian stable main
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

  # add the Azul Zulu Java gpg key
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0xB1998361219BD9C9

  # add the Erlang Solutions gpg key
  curl --silent https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | apt-key add -

  # add the Ansible gpg key
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367

  # Automatically accept license agreement
  echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections

  apt update
  apt install -y \
	openjdk-8-jdk \
	openjdk-8-dbg \
	erlang \
	erlang-proper-dev \
	rebar \
	elixir \
	python3-pip \
	python3-setuptools \
	python3-wheel \
	wireshark-qt \
	ansible \
	linux-perf \
	cmake \
	build-essential \
	gdb \
	--no-install-recommends

  # Packages linux-perf and cmake are installed to run Linux performance tests
  # Get the FlameGraph software here: https://github.com/brendangregg/FlameGraph

  cleanup

  # Add user to group Wireshark for capturing permissions
  dpkg-reconfigure wireshark-common
  sudo gpasswd -a "$USERNAME" wireshark

  # Install some Python plugins. Neovim adds a Python extension to NeoVIM
  pip3 install --system virtualenv maybe neovim j2cli-3 pygments

  # Install NVM -> Node Version Manager
  cat <<-EOF > /Development/tools/nvm-install.sh
	export NVM_DIR="/Development/tools/nvm" && (
	git clone https://github.com/creationix/nvm.git "$NVM_DIR"
	cd "$NVM_DIR"
	git checkout "$(git describe --abbrev=0 --tags --match "v[0-9]*" origin)"
	) && . "$NVM_DIR/nvm.sh"
	EOF
  chown "$USERNAME:$USERNAME" /Development/tools/nvm-install.sh
  chmod +x /Development/tools/nvm-install.sh
  sudo -u "$USERNAME" nvm-install.sh
}


usage() {
  echo -e "install.sh\n\tThis script installs my basic setup for a debian laptop\n"
  echo "Usage:"
  echo "  sources                            - setup sources & install base pkgs"
  echo "  wifi {broadcom,other}              - install wifi drivers"
  echo "  graphics {intel,geforce,optimus}   - install graphics drivers"
  echo "  wm                                 - install window manager/desktop pkgs"
  echo "  dotfiles                           - get dotfiles (!! as user !!)"
  echo "  scripts                            - install scripts (not needed)"
  echo "  private                            - install private repo and other personal stuff (!! as user !!)"
  echo "  vagrant                            - install vagrant and virtualbox"
  echo "  dev                                - install development environment for Java"
  echo "  golang                             - install golang language"
  echo "  cleanup                            - clean apt etc"
}

main() {
  local cmd=$1

  if [[ -z "$cmd" ]]; then
	usage
	exit 1
  fi

  if [[ $cmd == "sources" ]]; then
	check_is_sudo
	base
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
  elif [[ $cmd == "vagrant" ]]; then
	check_is_sudo

	install_vagrant "$2"
  elif [[ $cmd == "dev" ]]; then
	check_is_sudo

	install_dev
  elif [[ $cmd == "golang" ]]; then
	install_golang "$2"
  elif [[ $cmd == "private" ]]; then
	install_private
  elif [[ $cmd == "cleanup" ]]; then
	cleanup
  else
	usage
  fi
}

main "$@"
