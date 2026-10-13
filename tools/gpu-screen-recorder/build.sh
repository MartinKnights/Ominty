#!/bin/sh
# Reproducible build of gpu-screen-recorder for the Ominty desktop.
#
# Why this exists: the "Screen Recorder YS" DMS plugin needs the
# gpu-screen-recorder backend, but Linux Mint 22.x / Ubuntu 24.04 have no
# package for it (only newer releases ship gpu-screen-recorder-cli), and we
# don't use Flatpak. This script builds it from source and stages the two
# binaries into ./bin/ so the repo carries a working backend.
#
# Usage:
#   ./build.sh              # build, stage binaries into ./bin
#   ./build.sh --install    # also install system-wide (needs sudo)
#
# Debian/Ubuntu build deps (run once):
#   sudo apt install \
#     libxcomposite-dev libxrandr-dev libxdamage-dev \
#     libavcodec-dev libavformat-dev libavutil-dev libswresample-dev libavfilter-dev \
#     libva-dev libva-drm2 libcap-dev libdbus-1-dev
# Plus: gcc, meson, ninja, pkg-config. AMD runtime: mesa-va-drivers.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
# Upstream keeps its canonical repo on a self-hosted git; this public mirror
# tracks it and is plain-cloneable.
upstream="${GSR_UPSTREAM:-https://github.com/antonlobanovskiy/gpu-screen-recorder}"
# Build the source OUTSIDE the repo so it is never committed.
src="${GSR_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/gpu-screen-recorder-src}"

for t in gcc meson ninja pkg-config; do
    command -v "$t" >/dev/null 2>&1 || { echo "missing build tool: $t"; exit 1; }
done

if [ ! -d "$src" ]; then
    echo ">>> cloning $upstream"
    git clone --depth 1 "$upstream" "$src"
fi

cd "$src"
rm -rf build
echo ">>> meson setup"
meson setup build
echo ">>> configure (prefix=/usr, release, strip)"
meson configure --prefix=/usr --buildtype=release -Dsystemd=true -Dstrip=true build
echo ">>> ninja"
ninja -C build

echo ">>> staging binaries into $here/bin"
mkdir -p "$here/bin"
cp -f build/gpu-screen-recorder build/gsr-kms-server "$here/bin/"
chmod 755 "$here/bin/gpu-screen-recorder" "$here/bin/gsr-kms-server"

if [ "${1:-}" = "--install" ]; then
    echo ">>> installing system-wide (sudo)"
    # sudo -E preserves HOME/PATH so the same meson that built it runs the
    # install (a plain sudo env PATH=... resets HOME and breaks meson).
    if ! sudo -E ninja -C build install; then
        echo ">>> meson install failed; installing binaries manually"
        sudo install -m755 build/gpu-screen-recorder /usr/bin/gpu-screen-recorder
        sudo install -m755 build/gsr-kms-server   /usr/bin/gsr-kms-server
    fi
    # Let gsr-kms-server capture the monitor without a password prompt.
    sudo /usr/sbin/setcap cap_sys_admin+ep /usr/bin/gsr-kms-server || true
fi

echo ">>> done. Binaries in $here/bin"
echo "    Cursor tip (AMD Polaris): prefer H.264; HEVC/AV1 can show black bars."
