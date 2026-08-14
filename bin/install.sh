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
	firewalld \
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
  apt autoremove
  apt autoclean
  apt clean
}

# Enable the managed firewalld configuration. Network trust is deliberately
# explicit: pass the names of NetworkManager profiles that should permit SSH.
# This command is also called without profiles by `make etc` to install the
# restrictive default policy before any network is marked as trusted.
configure_firewall() {
  local connection device

  if ! command -v firewall-offline-cmd >/dev/null || ! command -v firewall-cmd >/dev/null; then
	echo "firewalld is not installed; run the base install first." >&2
	return 1
  fi

  for connection in "$@"; do
	if ! nmcli -g connection.id connection show "$connection" >/dev/null 2>&1; then
	  echo "Unknown NetworkManager connection: $connection" >&2
	  return 1
	fi
  done

  # Validate before reloading, so a malformed ruleset cannot replace the
  # currently working firewall. firewall-offline-cmd must not be used while
  # the daemon is running.
  if systemctl is-active --quiet firewalld.service; then
	firewall-cmd --check-config
  else
	firewall-offline-cmd --check-config
  fi

  # The standalone nftables unit must stay off: its /etc/nftables.conf loader
  # would otherwise compete with firewalld for ownership of the ruleset.
  systemctl disable --now nftables.service
  systemctl enable --now firewalld.service
  firewall-cmd --set-default-zone=public
  firewall-cmd --reload

  for connection in "$@"; do
	nmcli connection modify "$connection" connection.zone home-ssh
	while IFS= read -r device; do
	  if [[ -n "$device" && "$device" != "--" ]]; then
		firewall-cmd --zone=home-ssh --change-interface="$device"
	  fi
	done < <(nmcli -g GENERAL.DEVICES connection show "$connection")
  done
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
  apt install -y \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-ce-rootless-extras \
	docker-compose-plugin \
	docker-buildx-plugin \
	uidmap \
	--no-install-recommends

  # Rootless Docker: do NOT run the root daemon -- the root socket is the
  # Shai-Hulud escalation path. dockerd runs as the user (user namespaces) instead.
  systemctl daemon-reload
  systemctl disable --now docker.service docker.socket || true

  # Ensure subuid/subgid ranges exist for rootless user namespaces.
  grep -q "^${USERNAME}:" /etc/subuid || usermod --add-subuids 100000-165535 "$USERNAME"
  grep -q "^${USERNAME}:" /etc/subgid || usermod --add-subgids 100000-165535 "$USERNAME"

  # dockerd-rootless-setuptool.sh's iptables preflight needs the nf_tables module.
  # Load it now and on every boot so the per-user daemon's networking survives reboots.
  modprobe nf_tables || true
  echo nf_tables > /etc/modules-load.d/docker-rootless.conf

  # Let the user's systemd run without an active login so rootless dockerd persists.
  # The per-user daemon setup runs later as the user via install_docker_rootless
  # (invoked by 'install.sh dotfiles').
  loginctl enable-linger "$USERNAME"
}

# Set up rootless Docker for the current (non-root) user. Run as the user; the
# rootless packages are installed by 'sources' (install_docker). Safe to re-run.
install_docker_rootless() {
  if ! command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
	echo "dockerd-rootless-setuptool.sh missing -- run 'sudo bin/install.sh sources' first."
	return 1
  fi
  dockerd-rootless-setuptool.sh install
  systemctl --user enable --now docker
  echo "Rootless Docker set up (DOCKER_HOST is in .exports; open a new shell)."
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
	  # Intel Arc / Xe (Panther Lake, XPS 16): in-kernel "xe" driver, so no driver package -
	  # just firmware (GPU, Wi-Fi, ISH sensors, SOF audio), microcode, Mesa and VA-API.
	  # firmware-cirrus carries the Cirrus SDCA SoundWire blobs (sdca/1fa/1028/dba/* +
	  # cs35l57 amp tuning) the mic/speakers need — Debian split these out of
	  # firmware-misc-nonfree into a per-vendor package, so it must be listed explicitly.
	  # Verify package names against the current testing snapshot if apt can't find one.
	  pkgs+=( firmware-misc-nonfree firmware-intel-graphics firmware-intel-misc firmware-iwlwifi firmware-sof-signed firmware-cirrus intel-media-va-driver-non-free mesa-vulkan-drivers intel-gpu-tools vainfo intel-microcode )
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

  curl -sSL https://raw.githubusercontent.com/mdonkers/dotfiles/main/etc/systemd/system/syncthing@.service > /etc/systemd/system/syncthing@.service

  systemctl daemon-reload
  systemctl enable "syncthing@${USERNAME}"
}

# install stuff for i3 window manager
install_wmapps() {
  # Get Firefox from unstable to use the latest version
  cat <<-EOF > /etc/apt/sources.list.d/firefox.sources
	Types: deb
	URIs: https://deb.debian.org/debian/
	Suites: unstable
	Components: main
	Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
	EOF

  # Google repo, because Chromium cannot play Netflix but Chrome can
  # own file name (google-chrome.sources): the google-chrome-beta pkg auto-writes
  # its own google-chrome-beta.sources, so don't collide with that.
  cat <<-EOF > /etc/apt/sources.list.d/google-chrome.sources
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
	pipewire \
	pipewire-pulse \
	pipewire-alsa \
	wireplumber \
	libspa-0.2-bluetooth \
	libspa-0.2-libcamera \
	gstreamer1.0-libcamera \
	gstreamer1.0-plugins-base \
	gstreamer1.0-plugins-good \
	gstreamer1.0-tools \
	libcamera-ipa \
	libcamera-tools \
	v4l-utils \
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

  # Audio runs on PipeWire now (pipewire-pulse replaces the PulseAudio daemon;
  # libspa-0.2-bluetooth restores BT audio). pulseaudio-utils is kept only for `pactl`
  # (i3 volume keys). PipeWire has no flat-volumes setting — its default already behaves
  # like the old PulseAudio flat-volumes=no — so the /etc/pulse/daemon.conf tweak is gone.

  # IPU7 / OV08X40 webcam. On top of the apt bits above, two out-of-repo pieces are
  # needed; the matching /etc config
  # (modprobe load-order, no-autosuspend udev rule, v4l2-relayd default/instance/
  # modules-load, dma-buf sandbox drop-in) is symlinked in by `make etc`.
  # 1. intel_cvs: drives the Synaptics SVP7500 CVS bridge so the OV08X40 sensor enumerates.
  #    Temporary compatibility source: copy only the pinned DKMS tree from the
  #    svp7500 fix-pack; do not execute any of that repository's installer scripts.
  #    Re-check Debian support and intel/vision-drivers PRs #40 and #41 before the
  #    next fresh installation, then prefer the distribution/upstream driver when
  #    it includes the required SVP7500 and IRQ fixes. See camera/README.md.
  #    AUTOINSTALL rebuilds the module on kernel upgrades.
  apt install -y git dkms build-essential "linux-headers-$(uname -r)" --no-install-recommends
  local svp7500_fix_pack_commit=5d40327c217f4279b235073f1cd9f8e40a9b4a20
  local camera_source_dir
  camera_source_dir=$(mktemp -d)
  git clone https://github.com/jibsta210/svp7500-camera-fix-pack \
	"$camera_source_dir/svp7500-camera-fix-pack"
  git -C "$camera_source_dir/svp7500-camera-fix-pack" checkout --detach \
	"$svp7500_fix_pack_commit"
  test "$(git -C "$camera_source_dir/svp7500-camera-fix-pack" rev-parse HEAD)" = \
	"$svp7500_fix_pack_commit"
  rm -rf /usr/src/intel-cvs-1.0
  cp -r "$camera_source_dir/svp7500-camera-fix-pack/dkms/intel-cvs-1.0" /usr/src/
  dkms add intel-cvs/1.0 2>/dev/null || true
  dkms install intel-cvs/1.0
  rm -rf "$camera_source_dir"

  # 2. Locally patched, package-managed v4l2loopback + v4l2-relayd. The exact source
  #    descriptors, archive hashes, patches, rationale and rollback procedure live in
  #    camera/. Build dependencies may be removed after installation (see its README).
  apt install -y --no-install-recommends \
	debhelper \
	help2man \
	dh-sequence-dkms \
	autoconf-archive \
	libgstreamer1.0-dev \
	libgstreamer-plugins-base1.0-dev \
	pkgconf \
	systemd-dev
  local camera_package_dir
  local camera_architecture
  camera_package_dir=$(mktemp -d)
  camera_architecture=$(dpkg --print-architecture)
  "$DOTFILES_DIR/bin/build-camera-packages" "$camera_package_dir"
  apt install -y \
	"$camera_package_dir/v4l2loopback-dkms_0.15.4-1+queuefix1_all.deb" \
	"$camera_package_dir/v4l2-relayd_0.2.0-0ubuntu1+keepalive3_${camera_architecture}.deb"
  rm -rf "$camera_package_dir"
  # The pipewire/wireplumber user services come pre-enabled via Debian presets on a fresh
  # install, so no manual `systemctl --user enable` is needed here.

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

  # Rootless Docker per-user setup (runs as the user, like the rest of this step).
  install_docker_rootless
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
  echo "  docker-rootless                    - set up rootless Docker (!! as user !!)"
  echo "  private                            - install private repo and other personal stuff (!! as user !!)"
  echo "  virtualbox                         - install VirtualBox (manual, when needed)"
  echo "  dev                                - install dev env for Java + CLI tools (gh, kubectl, terraform)"
  echo "  golang                             - install golang language (!! as user !!)"
  echo "  syncthing                          - install syncthing (!! as user !!)"
  echo "  firewall [connection ...]         - enable firewalld; allow SSH on named NetworkManager profiles"
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
  elif [[ $cmd == "docker-rootless" ]]; then
	install_docker_rootless
  elif [[ $cmd == "syncthing" ]]; then
	install_syncthing
  elif [[ $cmd == "firewall" ]]; then
	check_is_sudo
	shift
	configure_firewall "$@"
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
