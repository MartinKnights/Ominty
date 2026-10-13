# gpu-screen-recorder (bundled build)

Backend for the **Screen Recorder YS** DankMaterialShell plugin on the Ominty
desktop. This folder carries a prebuilt, working copy plus a script to rebuild
it, because **Linux Mint 22.x / Ubuntu 24.04 have no package** for it and we
don't use Flatpak.

- **Upstream:** [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder/about/) by dec05eba
- **Mirror used to build:** <https://github.com/antonlobanovskiy/gpu-screen-recorder>
- **Version built:** `5.15.1-anton1`
- **License:** GPL-3.0-only (see `LICENSE`)

## Why

The DMS plugin `screenRecorderYS` shells out to `gpu-screen-recorder` on
`PATH`. That binary isn't in Mint/Ubuntu-24.04 repos (only newer releases ship
`gpu-screen-recorder-cli`), and we build from source rather than Flatpak. The
built binaries live in `bin/` so anyone setting up Ominty can install them
without a full toolchain.

## What the plugin needs

- `gpu-screen-recorder` on `PATH`
- `gsr-kms-server` (invoked by it) with the `cap_sys_admin+ep` capability so
  monitor capture doesn't prompt for a password (`-w portal` isn't used — there
  is no ScreenCast portal here)

## Install (quick — use the bundled binaries)

```bash
sudo install -m755 bin/gpu-screen-recorder /usr/bin/gpu-screen-recorder
sudo install -m755 bin/gsr-kms-server   /usr/bin/gsr-kms-server
sudo /usr/sbin/setcap cap_sys_admin+ep /usr/bin/gsr-kms-server
gpu-screen-recorder --version          # expect 5.15.1-anton1
```

## Rebuild from source

```bash
sudo apt install \
  libxcomposite-dev libxrandr-dev libxdamage-dev \
  libavcodec-dev libavformat-dev libavutil-dev libswresample-dev libavfilter-dev \
  libva-dev libva-drm2 libcap-dev libdbus-1-dev
# plus gcc, meson, ninja, pkg-config; AMD runtime: mesa-va-drivers

./build.sh              # builds and stages bin/
./build.sh --install    # builds and installs system-wide (sudo)
```

`build.sh` clones upstream into `$XDG_CACHE_HOME/gpu-screen-recorder-src`
(outside this repo), runs the meson release build, copies the two binaries
into `./bin/`, and — with `--install` — installs them and sets the capability.

> Note on install: prefer `sudo -E ninja -C build install`. A plain
> `sudo env PATH=...` resets `HOME`, so root can't see a user-installed
> `meson`/`mesonbuild` and the install fails with a meson `install.dat`
> version error. The script falls back to copying the binaries if that happens.

## Verifying

```bash
gpu-screen-recorder --info            # vendor, codecs, monitors
# quick capture test (5s, stop with Ctrl-C):
gpu-screen-recorder -w HDMI-A-2 -f 30 -k h264 -o /tmp/test.mp4
ffprobe /tmp/test.mp4
```

## Notes

- **AMD Polaris (RX 470/480/570/580):** hardware encode is **H.264** and
  **HEVC** (VAAPI). HEVC/AV1 can produce **black bars** — prefer H.264.
- The `--info` probe logs a harmless DBus `ScreenCast` warning when no
  desktop portal is present; direct KMS capture is used instead.
- Capturing a monitor needs either the `cap_sys_admin` capability above, or the
  active session already owning the DRM device (worked without the cap on the
  build machine, but set it to be safe).
