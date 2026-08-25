#!/bin/bash
set -e
set -o pipefail

# install.sh
#	This script installs my basic setup for a debian laptop

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR=$(dirname "$SCRIPT_DIR")

# Resolve the account the installation belongs to. `sudo` supplies SUDO_USER;
# user-only commands use the current account. An explicit TARGET_USER remains
# available for a direct root login or another non-sudo provisioning flow.
USERNAME=${TARGET_USER:-${SUDO_USER:-${USER:-}}}
if [[ -z "$USERNAME" || "$USERNAME" == root ]]; then
	echo "Cannot determine the target user; set TARGET_USER explicitly." >&2
	exit 1
fi
export DEBIAN_FRONTEND=noninteractive

check_is_sudo() {
  if [ "$EUID" -ne 0 ]; then
	echo "Please run as root."
	exit 1
  fi
}

# sets up apt sources
# assumes you are going to use debian testing
setup_sources() {
  # These files deliberately use the rolling "testing" suite rather than a
  # release codename. This installer targets clean systems and therefore does
  # not contain migration or cleanup logic for layouts from older versions.
  install -D -m 0644 "$DOTFILES_DIR/etc/apt/sources.list.d/debian.sources" \
	/etc/apt/sources.list.d/debian.sources
  install -D -m 0644 "$DOTFILES_DIR/etc/apt/apt.conf" /etc/apt/apt.conf
  install -D -m 0644 "$DOTFILES_DIR/etc/apt/preferences" /etc/apt/preferences
  install -D -m 0644 "$DOTFILES_DIR/etc/apt/apt.conf.d/99translations" \
	/etc/apt/apt.conf.d/99translations

  apt update
  apt install -y \
	dirmngr \
	gnupg \
	--no-install-recommends
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
	coreutils \
	curl \
	dmidecode \
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
	icdiff \
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
	openvpn-systemd-resolved \
	openssl \
	opensc \
	pamu2fcfg \
	pcscd \
	pcsc-tools \
	picom \
	pinentry-gnome3 \
	pinentry-curses \
	python3-pip \
	python3-setuptools \
	python3-wheel \
	python3-virtualenv \
	python3-neovim \
	python3-pygments \
	python-is-python3 \
	scdaemon \
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
  # TLP owns persistent power policy. powertop remains useful interactively, but
  # its --auto-tune service overwrites TLP settings depending on service order.
  systemctl disable --now powertop.service || true

  setup_sudo
  mkdir -p /mnt/sdcard

  cleanup

  install_docker

  # update grub with system specific and docker configs and power-saving items
  # acpi_rev_override=5                         -> necessary for bbswitch / bumblebee to disable discrete NVidia GPU
  # acpi_osi=Linux                              -> tell ACPI we're running Linux
  # pci=noaer                                   -> disable Advanced Error Reporting because sometimes flooding the logs
  # nmi_watchdog=0                              -> disable NMI Watchdog, which looks for interrupts to determine if kernel is hanging, to reboot / shutdown without problems
  # cgroup_enable=memory / swapaccount=1 dropped -> cgroup v2 (Debian default) ignores these v1-only flags.
  # apparmor=1 / security=apparmor dropped       -> AppArmor is already on by default on Debian.
  # vsyscall=none dropped                        -> already the kernel default here (CONFIG_LEGACY_VSYSCALL_NONE=y).
  # page_poison dropped                          -> superseded by init_on_free=1 since 5.3 (init_on_alloc=1 is default).
  # slab_nomerge init_on_free=1 dropped          -> KSPP hardening, but init_on_free=1 corrupts the hibernation
  #                                                 image restore: hard hang right after "100% image loaded",
  #                                                 no logs (debugged 2026-07 on the XPS 16, kernels 7.0/7.1).
  # resume= not needed                           -> the installer writes the machine-specific resume device to
  #                                                 /etc/initramfs-tools/conf.d/resume, which is what locates the
  #                                                 hibernation image at boot; just verify it exists.
  #sed -i.bak 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="acpi_rev_override=5 acpi_osi=Linux pci=noaer nmi_watchdog=0 apparmor=1 security=apparmor page_poison=1 slab_nomerge vsyscall=none"/g' /etc/default/grub

  grep -H . /etc/initramfs-tools/conf.d/resume 2>/dev/null || echo "WARNING: no /etc/initramfs-tools/conf.d/resume - resume from hibernation will not work"
  grep -qx '^GRUB_DISABLE_OS_PROBER=.*' /etc/default/grub || echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
  update-grub
  echo
  echo ">>>>>>>>>>"
  echo "To make kernel parameters effective;"
  echo "run update-grub & reboot"
  echo "<<<<<<<<<<"
}

cleanup() {
  apt autoremove -y
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

  local sudoers_file sudoers_tmp
  sudoers_file="/etc/sudoers.d/90-dotfiles-${USERNAME}"
  sudoers_tmp=$(mktemp)

  cat <<-END > "$sudoers_tmp"
Defaults	secure_path="/usr/local/go/bin:/home/${USERNAME}/.go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults	env_keep += "ftp_proxy http_proxy https_proxy no_proxy JAVA_HOME GOPATH EDITOR PIPX_HOME PIPX_BIN_DIR"
# Possibly allow 'sudo' to be used without password.
#${USERNAME} ALL=(ALL) NOPASSWD:ALL
# When using U2F with Yubikey, require authentication generally but exempt these commands.
${USERNAME} ALL=(ALL) ALL
${USERNAME} ALL=NOPASSWD: /sbin/ifconfig, /sbin/ifup, /sbin/ifdown, /sbin/ifquery, /usr/bin/light, /usr/bin/nsenter
END

  chmod 0440 "$sudoers_tmp"
  if visudo -cf "$sudoers_tmp"; then
	install -o root -g root -m 0440 "$sudoers_tmp" "$sudoers_file"
  else
	rm -f "$sudoers_tmp"
	return 1
  fi
  rm -f "$sudoers_tmp"

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

  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor > /usr/share/keyrings/docker-archive-keyring.gpg
  chmod a+r /usr/share/keyrings/docker-archive-keyring.gpg
  gpg --show-keys --with-colons /usr/share/keyrings/docker-archive-keyring.gpg | grep -q -i "9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

  cat <<-EOF > /etc/apt/sources.list.d/docker.sources
	Types: deb
	URIs: https://download.docker.com/linux/debian/
	Suites: trixie
	Components: stable
	Signed-By: /usr/share/keyrings/docker-archive-keyring.gpg
	EOF

  apt update
  # The compose and buildx plugins come from this repo now, so htotheizzo no longer
  # downloads release binaries into ~/.docker/cli-plugins by hand.
  apt install -y \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-compose-plugin \
	docker-buildx-plugin \
	--no-install-recommends

  groupadd -f docker
  gpasswd -a "$USERNAME" docker

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
	"intel")
	  # Intel integrated graphics: in-kernel driver, so no driver package - just
	  # firmware (GPU, Wi-Fi, ISH sensors, SOF audio), microcode, Mesa and VA-API.
	  # Verify package names against the current testing snapshot if apt can't find one.
	  pkgs+=( firmware-misc-nonfree firmware-intel-graphics firmware-intel-misc firmware-iwlwifi firmware-sof-signed intel-media-va-driver-non-free mesa-vulkan-drivers intel-gpu-tools vainfo intel-microcode )
	  ;;
	*)
	  echo "No system specified, assuming graphics drivers present"
	  ;;
  esac

  apt update || true

  apt install -y "${pkgs[@]}" --no-install-recommends

  # refresh initramfs so newly-installed firmware is loaded early at boot
  update-initramfs -u
}

# install syncthing
install_syncthing() {
  sudo apt update
  sudo apt install -y syncthing --no-install-recommends
  # Debian ships both syncthing@.service and a user unit; use its maintained
  # system template instead of carrying a stale local copy.
  sudo systemctl enable --now "syncthing@${USERNAME}.service"
}

# install stuff for i3 window manager
install_wmapps() {
  # Google repo, because Chromium cannot play Netflix but Chrome can. This is a
  # bootstrap source: the package normally writes google-chrome-beta.sources.
  cat <<-EOF > /etc/apt/sources.list.d/google-chrome-bootstrap.sources
	Types: deb
	URIs: https://dl.google.com/linux/chrome/deb/
	Suites: stable
	Components: main
	Signed-By: /usr/share/keyrings/google-linux-archive-keyring.gpg
	EOF

  wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/google-linux-archive-keyring.gpg
  chmod a+r /usr/share/keyrings/google-linux-archive-keyring.gpg
  # Validate the downloaded key contains Google's long-lived primary signing key.
  # (Signing subkeys rotate, so only the primary fingerprint is pinned here.)
  gpg --show-keys --with-colons /usr/share/keyrings/google-linux-archive-keyring.gpg | grep -q -i "EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796"

  apt update
  apt install -y \
	arandr \
	blueman \
	bluez-firmware \
	dunst \
	feh \
	fonts-noto-color-emoji \
	graphviz \
	i3 \
	i3lock \
	i3status \
	libanyevent-i3-perl \
	libnotify-bin \
	libnotify4 \
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

  # Avoid duplicate targets after the Chrome package creates its maintained
  # source. Keep the bootstrap source only if that package behavior changes.
  if [[ -e /etc/apt/sources.list.d/google-chrome-beta.sources ]]; then
	rm -f /etc/apt/sources.list.d/google-chrome-bootstrap.sources
  fi

  # update Pulse audio settings (replaces entire line)
  sed -i.bak '/flat-volumes/c\flat-volumes = no' /etc/pulse/daemon.conf

  # update clickpad settings
  mkdir -p /etc/X11/xorg.conf.d/

  # pretty fonts
  install -D -m 0644 "$DOTFILES_DIR/etc/fonts/local.conf" /etc/fonts/local.conf

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
  local dotfiles_checkout="/home/$USERNAME/dotfiles"

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

  # Reuse an existing checkout without modifying it. Never destroy local or
  # uncommitted work merely to run the installer again.
  if git -C "$dotfiles_checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "Using existing dotfiles checkout: $dotfiles_checkout"
  elif [[ -e "$dotfiles_checkout" ]]; then
	echo "Refusing to replace non-Git path: $dotfiles_checkout" >&2
	exit 1
  else
	git clone --recursive https://github.com/mdonkers/dotfiles.git "$dotfiles_checkout"
  fi

  # installs all the things
  cd "$dotfiles_checkout"
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
  local private_checkout="/home/$USERNAME/dotfiles-private"

  # Install also my 'private' dotfiles repo
  if git -C "$private_checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "Using existing private dotfiles checkout: $private_checkout"
  elif [[ -e "$private_checkout" ]]; then
	echo "Refusing to replace non-Git path: $private_checkout" >&2
	return 1
  else
	git clone git@gitlab.com:mdonkers/dotfiles-private.git "$private_checkout"
  fi

  # installs all the things (in subshell because we cd)
  (
  cd "$private_checkout"
  make
  )

  # The global PAM mapping is opened as root. pam-u2f 1.3.1+ warns about
  # group-writable mappings and may reject them in a future release.
  if [[ ! -f /etc/yubikey/u2f_keys ]]; then
	echo "Missing Yubikey mapping: /etc/yubikey/u2f_keys" >&2
	return 1
  fi
  sudo chown root:root /etc/yubikey /etc/yubikey/u2f_keys
  sudo chmod 0755 /etc/yubikey
  sudo chmod 0644 /etc/yubikey/u2f_keys
  # Setup PAM to use the Yubikey for 2F authentication
  # Note! 'sudo' line goes BEFORE common-auth (sufficient: Yubikey touch, else fall through to password).
  # No 'nouserok' on sudo, so a missing/empty u2f_keys falls back to password instead of granting access.
  # 'login' line goes AFTER common-auth (required: password AND Yubikey = 2FA) and KEEPS 'nouserok' so that
  # root / any user without a registered key can still log in with just a (strong) password -- a recovery path.
  local sudo_u2f_pattern login_u2f_pattern
  sudo_u2f_pattern='^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_u2f\.so[[:space:]]+authfile=/etc/yubikey/u2f_keys[[:space:]]+cue[[:space:]]*$'
  login_u2f_pattern='^[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_u2f\.so[[:space:]]+authfile=/etc/yubikey/u2f_keys[[:space:]]+cue[[:space:]]+nouserok[[:space:]]*$'

  if ! sudo grep -Eq "$sudo_u2f_pattern" /etc/pam.d/sudo; then
	sudo sed -i "\\|common-auth|i \\auth       sufficient   pam_u2f.so  authfile=/etc/yubikey/u2f_keys cue" /etc/pam.d/sudo
  fi
  if ! sudo grep -Eq "$login_u2f_pattern" /etc/pam.d/login; then
	sudo sed -i "\\|common-auth|a \\auth       required     pam_u2f.so  authfile=/etc/yubikey/u2f_keys cue nouserok" /etc/pam.d/login
  fi

  # Fail instead of silently leaving authentication half-configured.
  sudo grep -Eq "$sudo_u2f_pattern" /etc/pam.d/sudo
  sudo grep -Eq "$login_u2f_pattern" /etc/pam.d/login
}

# install VirtualBox from Debian's contrib repo (already enabled in the apt sources).
# Not part of the default install flow; run manually via "install.sh virtualbox" when a VM is needed.
install_virtualbox() {
  apt update
  apt install -y \
	virtualbox \
	virtualbox-qt \
	--no-install-recommends
}

# install/update golang from source
install_golang() {
  export GO_VERSION
  GO_VERSION=$(curl -sSL "https://golang.org/VERSION?m=text" | head -n 1)
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
  curl -sSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | sudo tar -v -C /usr/local -xz
  # go was just unpacked into $GO_SRC/bin, which isn't on PATH in this shell yet
  export PATH="$GO_SRC/bin:$PATH"
  local user="$USER"
  # rebuild stdlib for faster builds
  sudo chown -R "${user}" /usr/local/go/pkg
  CGO_ENABLED=0 go install -a -installsuffix cgo std
  )

  # get commandline tools (go was just unpacked into $GO_SRC/bin, not yet on PATH)
  (
  export PATH="$GO_SRC/bin:$PATH"
  set -x
  set +e
  go install github.com/go-delve/delve/cmd/dlv@latest
  go install github.com/google/pprof@latest
  go install github.com/cbednarski/hostess@latest
  go install github.com/mikefarah/yq/v4@latest
  #go install golang.org/x/tools/cmd/cover@latest
  #go install github.com/google/go-jsonnet/cmd/jsonnet@latest
  #go install sigs.k8s.io/kind@latest
  )
}

install_dev() {
  mkdir -p /Development
  mkdir -p /Development/{misc,projects,tools,workspaces}
  chown -R "$USERNAME:$USERNAME" /Development

  # Add Azul Zulu apt repo
  curl -s https://repos.azul.com/azul-repo.key | gpg --dearmor -o /usr/share/keyrings/azul.gpg
  cat <<-EOF > /etc/apt/sources.list.d/zulu.sources
	Types: deb
	URIs: https://repos.azul.com/zulu/deb/
	Suites: stable
	Components: main
	Signed-By: /usr/share/keyrings/azul.gpg
	EOF

  # Automatically accept license agreement
  #echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections

  apt update
  apt install -y \
	zulu25-jdk-headless \
	wireshark \
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
  # ld.gold ships in binutils-gold (not installed here); register it only when
  # present, else update-alternatives aborts on the empty (non-absolute) path.
  if command -v ld.gold >/dev/null 2>&1; then
	update-alternatives --install "/usr/bin/ld" "ld" "$(command -v ld.gold)" 10
  fi
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

  # CLI tools from their official signed apt repos (gh, kubectl, terraform).
  install_clitools
}


usage() {
  echo -e "install.sh\n\tThis script installs my basic setup for a debian laptop\n"
  echo "Usage:"
  echo "  dist                               - setup sources & dist upgrade"
  echo "  sources                            - setup sources & install base pkgs"
  echo "  graphics {geforce|intel}           - install graphics drivers"
  echo "  wm                                 - install window manager/desktop pkgs"
  echo "  dotfiles                           - get dotfiles (!! as user !!)"
  echo "  private                            - install private repo and other personal stuff (!! as user !!)"
  echo "  virtualbox                         - install VirtualBox (manual, when needed)"
  echo "  dev                                - install dev env for Java + CLI tools (gh, kubectl, terraform)"
  echo "  golang                             - install golang language (!! as user !!)"
  echo "  syncthing                          - install syncthing (!! as user !!)"
  echo "  cleanup                            - remove unused apt packages and clean caches"
}

# install commonly-used CLI tools from their official, GPG-signed apt repos.
# Tools without a signed package (aws-cli, bun) are installed manually -- see
# debian_install.md -- to avoid piping unverified install scripts into a shell.
install_clitools() {
  apt update
  apt install -y curl gnupg --no-install-recommends

  # GitHub CLI
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg > /usr/share/keyrings/githubcli-archive-keyring.gpg
  chmod a+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  cat <<-EOF > /etc/apt/sources.list.d/github-cli.sources
	Types: deb
	URIs: https://cli.github.com/packages/
	Suites: stable
	Components: main
	Signed-By: /usr/share/keyrings/githubcli-archive-keyring.gpg
	EOF

  # Kubernetes (kubectl) -- bump vX.YY to the desired minor version
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor > /usr/share/keyrings/kubernetes-apt-keyring.gpg
  cat <<-EOF > /etc/apt/sources.list.d/kubernetes.sources
	Types: deb
	URIs: https://pkgs.k8s.io/core:/stable:/v1.33/deb/
	Suites: /
	Signed-By: /usr/share/keyrings/kubernetes-apt-keyring.gpg
	EOF

  # HashiCorp (terraform) -- pinned to a stable codename (no 'forky' repo upstream)
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor > /usr/share/keyrings/hashicorp-archive-keyring.gpg
  cat <<-EOF > /etc/apt/sources.list.d/hashicorp.sources
	Types: deb
	URIs: https://apt.releases.hashicorp.com/
	Suites: trixie
	Components: main
	Signed-By: /usr/share/keyrings/hashicorp-archive-keyring.gpg
	EOF

  # Helm has no working signed apt repo anymore (baltocdn was decommissioned and now
  # returns "OK" for every path), so install it manually from its GitHub release
  # tarball -- see debian_install.md.
  apt update
  apt install -y gh kubectl terraform --no-install-recommends
}

main() {
  local cmd=$1

  if [[ -z "$cmd" ]]; then
	usage
	exit 1
  fi

  if [[ $cmd == "sources" ]]; then
	check_is_sudo
	# configure APT and install the base package set
	setup_sources
	base
  elif [[ $cmd == "dist" ]]; then
	check_is_sudo
	# configure APT and perform an explicitly requested distribution upgrade
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
  elif [[ $cmd == "syncthing" ]]; then
	install_syncthing
  elif [[ $cmd == "virtualbox" ]]; then
	check_is_sudo
	install_virtualbox
  elif [[ $cmd == "dev" ]]; then
	check_is_sudo
	install_dev
  elif [[ $cmd == "golang" ]]; then
	install_golang "$2"
  elif [[ $cmd == "private" ]]; then
	install_private
  elif [[ $cmd == "cleanup" ]]; then
	check_is_sudo
	cleanup
  else
	usage
	return 1
  fi
}

main "$@"
