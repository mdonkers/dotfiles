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
	--no-install-recommends

  # Set "testing" distribution as default
  cat <<-EOF > /etc/apt/apt.conf
	APT::Default-Release "testing";
	EOF

  # Pin packages to "testing" distribution
  cat <<-EOF > /etc/apt/preferences
	Package: *
	Pin: release o=Debian,a=testing
	Pin-Priority: 900

	Package: *
	Pin: release o=Debian,a=unstable
	Pin-Priority: 300

	Package: *
	Pin: release o=Debian
	Pin-Priority: -1
	EOF

  cat <<-EOF > /etc/apt/sources.list
	deb http://httpredir.debian.org/debian testing main contrib non-free non-free-firmware
	deb-src http://httpredir.debian.org/debian/ testing main contrib non-free non-free-firmware

	deb http://httpredir.debian.org/debian/ testing-updates main contrib non-free non-free-firmware
	deb-src http://httpredir.debian.org/debian/ testing-updates main contrib non-free non-free-firmware

	deb http://security.debian.org/ testing-security main contrib non-free non-free-firmware
	deb-src http://security.debian.org/ testing-security main contrib non-free non-free-firmware

	deb http://httpredir.debian.org/debian experimental main contrib non-free non-free-firmware
	deb-src http://httpredir.debian.org/debian experimental main contrib non-free non-free-firmware
	EOF

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
	acpi \
	adduser \
	apparmor \
	automake \
	bash-completion \
	bc \
	bind9-dnsutils \
	bridge-utils \
	bzip2 \
	ca-certificates \
	cgroupfs-mount \
	coreutils \
	curl \
	file \
	findutils \
	fwupd \
	fwupd-signed \
	gcc \
	git \
	git-lfs \
	gnupg \
	gpg-agent \
	grep \
	gzip \
	hostname \
	inotify-tools \
	iproute2 \
	jq \
	less \
	libpam-u2f \
	libpam-systemd \
	libwww-perl \
	light \
	linux-headers-amd64 \
	lm-sensors \
	lsb-release \
	lsof \
	make \
	mc \
	mount \
	neovim \
	net-tools \
	network-manager \
	nftables \
	openvpn \
	openssl \
	opensc \
	pamu2fcfg \
	pcscd \
	pcsc-tools \
	picom \
	python3-pip \
	python3-setuptools \
	python3-wheel \
	python3-virtualenv \
	python3-neovim \
	python3-pygments \
	python-is-python3 \
	scdaemon \
	smbios-utils \
	silversearcher-ag \
	ssh \
	strace \
	sudo \
	systemd-resolved \
	tar \
	thermald \
	tree \
	tzdata \
	udisks2 \
	unzip \
	whois \
	wireless-tools \
	xz-utils \
	zip \
	--no-install-recommends

  # install tlp with recommends
  apt install -y tlp tlp-rdw
  systemctl enable powertop.service

  setup_sudo
  mkdir -p /mnt/sdcard

  cleanup

  install_docker
  install_scripts

  # update grub with system specific and docker configs and power-saving items
  # acpi_rev_override=5                         -> necessary for bbswitch / bumblebee to disable discrete NVidia GPU
  # acpi_osi=Linux                              -> tell ACPI we're running Linux
  # pci=noaer                                   -> disable Advanced Error Reporting because sometimes flooding the logs
  # nmi_watchdog=0                              -> disable NMI Watchdog, which looks for interrupts to determine if kernel is hanging, to reboot / shutdown without problems
  # cgroup_enable=memory swapaccount=1          -> enable cgroup memory accounting
  # page_poison=1 slab_nomerge vsyscall=none    -> Kernel hardening around leaking sensitive data via memory
  #sed -i.bak 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="acpi_rev_override=5 acpi_osi=Linux pci=noaer nmi_watchdog=0 apparmor=1 security=apparmor page_poison=1 slab_nomerge vsyscall=none"/g' /etc/default/grub

  sed -i.bak 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1 apparmor=1 security=apparmor page_poison=1 slab_nomerge vsyscall=none"/g' /etc/default/grub
  grep -qx '^GRUB_DISABLE_OS_PROBER=.*' /etc/default/grub || echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
  update-grub
  echo
  echo ">>>>>>>>>>"
  echo "To make kernel parameters effective;"
  echo "run update-grub & reboot"
  echo "<<<<<<<<<<"
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

  local -r SUDOERS_CONFIG=$(cat <<-END
	Defaults	secure_path="/usr/local/go/bin:/home/${USERNAME}/.go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	Defaults	env_keep += "ftp_proxy http_proxy https_proxy no_proxy JAVA_HOME GOPATH EDITOR PIPX_HOME PIPX_BIN_DIR"
	# Possibly allow 'sudo' to be used without password.
	#${USERNAME} ALL=(ALL) NOPASSWD:ALL
	# When using U2F with Yubikey, need to use passwords (configured to only request Yubikey in PAM) but exclude some commands from needing password.
	${USERNAME} ALL=(ALL) ALL
	${USERNAME} ALL=NOPASSWD: /sbin/ifconfig, /sbin/ifup, /sbin/ifdown, /sbin/ifquery, /usr/bin/light, /usr/bin/nsenter
END
) || true

  # set secure path
  if ! grep -q -z "${SUDOERS_CONFIG}" /etc/sudoers; then
	echo "Appending to the /etc/sudoers file"
	printf "%s\n" "${SUDOERS_CONFIG}" >> /etc/sudoers
	echo -e "\\n# binfmt for executing e.g. JAR files directly\\nnone\\t/proc/sys/fs/binfmt_misc\\tbinfmt_misc\\tdefaults\\t0\\t0" >> /etc/fstab
  else
	echo "Not appending, /etc/sudoers already in correct state"
  fi

}

# installs docker master
# and adds necessary items to boot params
install_docker() {

  # Remove potential old Docker installs
  apt-get purge -y \
	docker \
	docker.io \
	containerd \
	runc

  # create docker group
  sudo groupadd docker || true
  sudo gpasswd -a "$USERNAME" docker

  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor > /usr/share/keyrings/docker-archive-keyring.gpg
  chmod a+r /usr/share/keyrings/docker-archive-keyring.gpg
  gpg --show-keys --with-colons /usr/share/keyrings/docker-archive-keyring.gpg | grep -q -i "9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

  cat <<-EOF > /etc/apt/sources.list.d/docker.list
	deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) test
	EOF

  apt update
  apt install -y \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	--no-install-recommends

  systemctl daemon-reload
  systemctl enable docker
  sleep 5
  systemctl start docker

  docker -v
}

# install graphics drivers
install_graphics() {
  local system=$1

  local pkgs=( xorg xserver-xorg xserver-xorg-input-libinput )

  case $system in
	"geforce")
	  pkgs+=( nvidia-driver nvidia-settings )
	  ;;
	*)
	  echo "No system specified, assuming graphics drivers present"
	  ;;
  esac

  apt update || true
  apt -y upgrade

  apt install -y "${pkgs[@]}" --no-install-recommends
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

# install syncthing
install_syncthing() {
  sudo apt update
  sudo apt install -y syncthing --no-install-recommends

  curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/main/etc/systemd/system/syncthing@.service > /etc/systemd/system/syncthing@.service

  systemctl daemon-reload
  systemctl enable "syncthing@${USERNAME}"
}

# install stuff for i3 window manager
install_wmapps() {
  # Get Firefox from unstable to use the latest version
  cat <<-EOF > /etc/apt/sources.list.d/firefox.list
	deb http://http.debian.net/debian unstable main
	EOF

  # Google repo, because Chromium cannot play Netflix but Chrome can
  cat <<-EOF > /etc/apt/sources.list.d/google-chrome-beta.list
	deb [signed-by=/usr/share/keyrings/google-linux-archive-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main
	EOF

  wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/google-linux-archive-keyring.gpg
  chmod a+r /usr/share/keyrings/google-linux-archive-keyring.gpg
  # Validate the key if it matches the expected fingerprints
  gpg --show-keys --with-colons /usr/share/keyrings/google-linux-archive-keyring.gpg | grep -q -i "4CCA1EAF950CEE4AB83976DCA040830F7FAC5991"
  gpg --show-keys --with-colons /usr/share/keyrings/google-linux-archive-keyring.gpg | grep -q -i "EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796"

  apt update
  apt install -y \
	arandr \
	blueman \
	bluez-firmware \
	feh \
	fonts-noto-color-emoji \
	i3 \
	i3lock \
	i3status \
	libanyevent-i3-perl \
	network-manager-gnome \
	pavucontrol \
	pulseaudio \
	pulseaudio-module-bluetooth \
	pulseaudio-utils \
	pulsemixer \
	rxvt-unicode \
	scrot \
	suckless-tools \
	xinput \
	xclip \
	google-chrome-beta \
	--no-install-recommends

  apt install -y -t unstable firefox --no-install-recommends

  # update Pulse audio settings (replaces entire line)
  sed -i.bak '/flat-volumes/c\flat-volumes = no' /etc/pulse/daemon.conf

  # update clickpad settings
  mkdir -p /etc/X11/xorg.conf.d/

  # pretty fonts
  curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/main/etc/fonts/local.conf > /etc/fonts/local.conf

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
  mkdir -p "/home/$USERNAME/.gnupg"
  chmod go-rx "/home/$USERNAME/.gnupg"

  mkdir -p "/home/$USERNAME/.config"
  chmod go-rx "/home/$USERNAME/.config"

  mkdir -p "/home/$USERNAME/Downloads"
  # Optionally setup downloads folder as tmpfs
  # echo -e "\n# tmpfs for downloads\ntmpfs\t/home/${USERNAME}/Downloads\ttmpfs\tnodev,nosuid,size=2G\t0\t0" >> /etc/fstab

  # install dotfiles from repo
  rm -rf "/home/$USERNAME/dotfiles"
  git clone --recursive https://github.com/mdonkers/dotfiles.git "/home/$USERNAME/dotfiles"

  # installs all the things
  cd "/home/$USERNAME/dotfiles"
  make

  sudo systemctl enable "i3lock@${USERNAME}"
  #systemctl --user enable slack-status.timer

  curl -sSL "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz" | sudo tar -v -C /usr/local/bin -xz --no-same-owner

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

  # Make sure user rights for yubikey file is correct
  sudo chown -R root:root /etc/yubikey/
  # Setup PAM to use the Yubikey for 2F authentication
  # Note! For 'sudo' the line is added before 'common-auth' as its sufficient for authentication. For 'login' after the include
  sudo sed -i "\\|common-auth|i \\auth       sufficient   pam_u2f.so  authfile=/etc/yubikey/u2f_keys cue nouserok" /etc/pam.d/sudo
  sudo sed -i "\\|common-auth|a \\auth       required     pam_u2f.so  authfile=/etc/yubikey/u2f_keys cue nouserok" /etc/pam.d/login
}

install_virtualbox() {
  cat <<-EOF > /etc/apt/sources.list.d/virtualbox.list
  #deb http://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib
  deb http://download.virtualbox.org/virtualbox/debian bullseye contrib
EOF
  curl -sSL https://www.virtualbox.org/download/oracle_vbox_2016.asc | apt-key add -

  apt update
  apt install -y \
	virtualbox-6.1 \
	--no-install-recommends
}

install_vagrant() {
  VAGRANT_VERSION=2.3.0

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
  go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
  go install golang.org/x/tools/cmd/cover@latest
  go install golang.org/x/review/git-codereview@latest
  go install golang.org/x/tools/cmd/goimports@latest
  go install golang.org/x/tools/cmd/gorename@latest
  go install golang.org/x/tools/cmd/guru@latest

  go install github.com/cbednarski/hostess@latest
  go install github.com/google/go-jsonnet/cmd/jsonnet@latest
  go install github.com/mikefarah/yq/v4@latest
  go install sigs.k8s.io/kind@latest
  )
}

install_dev() {
  mkdir -p /Development
  mkdir -p /Development/{misc,projects,tools,workspaces}
  chown -R "$USERNAME:$USERNAME" /Development

  # add Ansible apt repo
  cat <<-EOF > /etc/apt/sources.list.d/ansible.list
	deb http://ppa.launchpad.net/ansible/ansible/ubuntu impish main
	EOF

  # add the Ansible gpg key
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367

  # Automatically accept license agreement
  #echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections

  apt update
  apt install -y \
	openjdk-17-jdk-headless \
	openjdk-17-dbg \
	wireshark-qt \
	ansible \
	linux-perf \
	cmake \
	build-essential \
	gdb \
	lld \
	ccache \
	clang \
	ninja-build \
	pipx \
	--no-install-recommends

  # Make LD (linker) configurable via 'update-alternatives' and set default to lld
  update-alternatives --install "/usr/bin/ld" "ld" "$(command -v ld.lld)" 20
  update-alternatives --install "/usr/bin/ld" "ld" "$(command -v ld.gold)" 10
  update-alternatives --config ld

  # Packages linux-perf and cmake are installed to run Linux performance tests
  # Get the FlameGraph software here: https://github.com/brendangregg/FlameGraph

  cleanup

  # Add user to group Wireshark for capturing permissions
  DEBIAN_FRONTEND=dialog dpkg-reconfigure wireshark-common
  sudo gpasswd -a "$USERNAME" wireshark

  # Install some Python plugins. Other plugins are installed as Debian packages
  PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install tcconfig

  # Install NVM -> Node Version Manager
  cat <<-'EOF' > /Development/tools/nvm-install.sh
	export NVM_DIR="/Development/tools/nvm" && (
	git clone https://github.com/creationix/nvm.git "$NVM_DIR"
	cd "$NVM_DIR"
	git checkout "$(git describe --abbrev=0 --tags --match "v[0-9]*" origin)"
	) && . "$NVM_DIR/nvm.sh"
	EOF
  chown "$USERNAME:$USERNAME" /Development/tools/nvm-install.sh
  chmod +x /Development/tools/nvm-install.sh
  sudo -u "$USERNAME" /Development/tools/nvm-install.sh
}


usage() {
  echo -e "install.sh\n\tThis script installs my basic setup for a debian laptop\n"
  echo "Usage:"
  echo "  dist                               - setup sources & dist upgrade"
  echo "  sources                            - setup sources & install base pkgs"
  echo "  graphics {geforce}                 - install graphics drivers"
  echo "  wm                                 - install window manager/desktop pkgs"
  echo "  dotfiles                           - get dotfiles (!! as user !!)"
  echo "  private                            - install private repo and other personal stuff (!! as user !!)"
  echo "  vagrant                            - install vagrant and virtualbox"
  echo "  dev                                - install development environment for Java"
  echo "  golang                             - install golang language (!! as user !!)"
  echo "  syncthing                          - install syncthing (!! as user !!)"
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
	# setup /etc/apt/sources.list
	setup_sources
	base
  elif [[ $cmd == "dist" ]]; then
	check_is_sudo
	# setup /etc/apt/sources.list
	setup_sources
	dist_upgrade
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
  elif [[ $cmd == "private" ]]; then
	install_private
  elif [[ $cmd == "cleanup" ]]; then
	cleanup
  else
	usage
  fi
}

main "$@"
