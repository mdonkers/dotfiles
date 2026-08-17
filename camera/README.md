# Dell XPS IPU7 camera compatibility packages

This directory makes the working camera stack reproducible while its fixes are
not yet available in the distribution packages used by this machine.

The Dell XPS camera is an OV08X40 sensor behind a Synaptics SVP7500 bridge on
Intel Panther Lake/IPU7. `intel-cvs` exposes the sensor to libcamera. The stock
libcamera `simple` pipeline performs the ISP work, and `v4l2-relayd` publishes a
720p YUYV virtual camera for X11 applications such as Chrome and Slack.

## Local fixes

- `v4l2loopback 0.15.4-1+queuefix1` backports all four commits from upstream
  pull request #656. They fix OUTPUT queue semantics, blocking `DQBUF`,
  `STREAMOFF` wakeups, and buffer-position preservation.
- `v4l2-relayd 0.2.0-0ubuntu1+keepalive3` adds a configurable idle grace period,
  repeatable V4L2 controls that run after the physical input reaches `PLAYING`,
  and bounds its appsink-to-appsrc bridge to two frames. Without the latter,
  stale frames accumulate and a smooth stream degrades to roughly one frame per
  second.
- `intel-cvs` is temporarily pinned to fix-pack commit
  `5d40327c217f4279b235073f1cd9f8e40a9b4a20`. Only its
  `dkms/intel-cvs-1.0` source tree is copied; none of the fix-pack's installer
  or system-configuration scripts are executed. The copied tree was verified
  byte-for-byte against the installed, working source.

## `intel-cvs` upstream status

This was reviewed on 2026-08-17. The canonical driver source is
[`intel/vision-drivers`](https://github.com/intel/vision-drivers), but the
working fix-pack tree still contains changes that are not in Intel's `main`
branch:

- Intel pull request [#40](https://github.com/intel/vision-drivers/pull/40)
  contains additional security and stability fixes, but was still open.
- Intel pull request [#41](https://github.com/intel/vision-drivers/pull/41)
  contains the important `IRQF_ONESHOT` fix that prevents the CVS bridge from
  becoming unreliable after idle periods, but was still open.
- Intel issue [#37](https://github.com/intel/vision-drivers/issues/37) tracks
  the SVP7500/HM1092 investigation. Its original MIPI-configuration hypothesis
  was later retracted by the fix-pack author, and the fix-pack source includes
  experimental IR-camera diagnostics that have not been upstreamed.
- Debian Forky did not provide an `intel-vision-dkms` package on this machine.

For now the complete known-working tree is retained instead of attempting to
separate required RGB fixes from experimental code. Before the next fresh
installation, check the Debian kernel/packages and the Intel pull requests
above. Prefer a distribution or upstream Intel driver once it contains the
required SVP7500 and IRQ fixes; at that point remove the fix-pack dependency
and this compatibility note.

## Direct PipeWire camera status

This was last tested on 2026-08-14 with PipeWire 1.6.8, WirePlumber 0.5.15,
libcamera 0.7.2, Chrome Beta 152.0.7977.30 and Slack 4.51.180. Both Chromium
builds contain the experimental `WebRtcPipeWireCamera` feature, but direct
capture is not currently reliable enough to replace the relay.

The direct test used the physical PipeWire/libcamera camera while the relay was
stopped:

```sh
sudo systemctl stop v4l2-relayd@camera.service
systemctl --user restart wireplumber.service

google-chrome-beta \
  --user-data-dir=/tmp/chrome-pipewire-camera-test \
  --no-first-run \
  --enable-features=WebRtcPipeWireCamera \
  https://webrtc.github.io/samples/src/content/getusermedia/gum/
```

Restarting WirePlumber is significant after reloading or replacing camera
kernel/userspace components. Its libcamera SPA node keeps the generated stream
configuration for the lifetime of the process. Before the restart, the stale
camera output port advertised no formats; after it, the port correctly
advertised RGBA, RGBx, BGRA and BGRx at all supported resolutions.

Chrome then requested permission, opened the physical camera and configured a
640x360 ABGR8888 stream. WirePlumber immediately aborted in libcamera's
software ISP with this bounds assertion:

```text
std::array<unsigned int, 64>::operator[]: Assertion '__n < this->size()' failed
```

This is the same failure documented by libcamera patchwork
[#25007](https://patchwork.libcamera.org/patch/25007/): corrupt sparse 10/12-bit
input frames can contain set high bits, producing out-of-range software-ISP
histogram and lookup-table indexes. The proposed patch masks those bits in the
CPU debayer input buffers. It remained unmerged and had state
`Changes Requested` when rechecked on 2026-08-17. A maintainer asked for a
revised patch in
[June 2026](https://lists.libcamera.org/pipermail/libcamera-devel/2026-June/059100.html).
The RFC also does not protect the CPU statistics path when the GPU/EGL debayer
is active, which is the path used on this machine. Carrying it unchanged would
therefore not fix this setup.

For now, do not locally replace the core libcamera packages. Even after fixing
the crash, direct Chromium capture would still need the experimental feature
flag and a solution for the sensor timing used for low-light capture. The relay
applies `vertical_blanking=2824` after libcamera starts; direct PipeWire capture
does not currently apply that camera-specific control.

Recheck this after substantial libcamera, PipeWire, Chromium or Intel camera
driver updates, and before the next fresh installation:

1. Check patchwork #25007 and the libcamera mailing list for a merged or revised
   CPU/GPU-safe fix.
2. Check the distribution libcamera source/changelog for equivalent sparse
   10/12-bit input masking and statistics bounds protection.
3. Stop the relay, restart WirePlumber, and confirm that the physical camera
   output port advertises formats before testing a browser.
4. Retest Chrome with `WebRtcPipeWireCamera`, then Slack only after Chrome can
   stream without restarting or crashing WirePlumber.
5. Compare sustained frame rate, CPU use and low-light image quality against
   the relay before considering removal of the virtual camera.
6. Restart the relay after the experiment if direct capture is still unsuitable:

   ```sh
   sudo systemctl start v4l2-relayd@camera.service
   ```

Source archive hashes are pinned in `bin/build-camera-packages`; signed Debian
and Ubuntu source descriptors and all local patches are stored here. Generated
binary packages are intentionally not committed.

## Build

Install the build dependencies:

```sh
sudo apt-get install --no-install-recommends \
  build-essential debhelper help2man dh-sequence-dkms \
  autoconf-archive libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev pkgconf systemd-dev
```

Build into a disposable output directory:

```sh
mkdir -p /tmp/camera-packages
bin/build-camera-packages /tmp/camera-packages
```

The builder downloads only the pinned upstream source archives, verifies their
SHA-256 hashes, applies the stored packaging patches, and builds:

```text
v4l2loopback-dkms_0.15.4-1+queuefix1_all.deb
v4l2-relayd_0.2.0-0ubuntu1+keepalive3_<architecture>.deb
```

## Install and activate

```sh
sudo apt-get install \
  /tmp/camera-packages/v4l2loopback-dkms_0.15.4-1+queuefix1_all.deb \
  /tmp/camera-packages/v4l2-relayd_0.2.0-0ubuntu1+keepalive3_amd64.deb
```

After installing a new v4l2loopback build, reboot, or stop the relay and reload
the module before restarting it:

```sh
sudo systemctl stop v4l2-relayd@camera.service
sudo modprobe -r v4l2loopback
sudo modprobe v4l2loopback
sudo systemctl start v4l2-relayd@camera.service
```

The active pipeline is configured in `etc/default/v4l2-relayd`, with
camera-specific controls in `etc/v4l2-relayd.d/camera.conf`. It captures the
only stable full-sensor mode, changes the physical sensor from its default
~28.57fps timing to ~14.29fps after libcamera starts, and publishes 720p at
15fps with bilinear scaling. The lower sensor rate reduced low-light analogue
gain from roughly 11.8x to 5.9x in testing. The relay keeps the input warm for
three seconds across transient browser disconnects, then releases the camera.
`etc/udev/rules.d/99-ipu7-camera-sensor.rules` supplies the stable sensor device
path used by the control configuration.

## Verify

```sh
dpkg-query -W v4l2loopback-dkms v4l2-relayd
cat /sys/module/v4l2loopback/srcversion
journalctl -u v4l2-relayd@camera.service --since '2 minutes ago'
```

While a consumer remains open, the journal should contain only one libcamera
initialization. The camera LED should switch off around three seconds after the
last consumer closes.

## Remove temporary build dependencies

The development packages are unnecessary at runtime. Always simulate first,
then remove only if the proposed list contains nothing you use for other work:

```sh
apt-get --simulate remove --autoremove \
  debhelper help2man dh-sequence-dkms dh-dkms autoconf-archive \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev pkgconf systemd-dev

sudo apt-get remove --autoremove \
  debhelper help2man dh-sequence-dkms dh-dkms autoconf-archive \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev pkgconf systemd-dev
```

## Eventual cleanup

When Debian's v4l2loopback contains upstream PR #656, remove the local loopback
patches and package build, then install the distribution version. When upstream
v4l2-relayd has equivalent idle-timeout, bounded-live-queue and post-input-start
control behavior, do the same for the relay patches. Direct PipeWire capture is
only a replacement once the libcamera crash and camera-specific low-light
timing are both resolved. Do not remove the local packages first unless a
working replacement is already installed.
