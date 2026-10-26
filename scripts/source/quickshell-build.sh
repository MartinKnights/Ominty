#!/usr/bin/env bash
#
# Ominty — build Quickshell at the pinned commit, user space only.
#
# Why this exists: the DMS shell is built against a specific Quickshell/Qt
# baseline. Debian 13 ships Quickshell 0.3.0 in trixie-backports, and the
# pinned DMS shell (73759d5) segfaults on it in QQmlTypeLoader. The workstation
# that the configuration was developed on runs 0.3.1. This script closes that
# gap on Debian-family machines without touching the system packages.
#
# Debian 13 already carries Qt 6.8.2, so unlike the Ubuntu path there is no
# private Qt build here — this is a plain CMake build against system Qt.
#
# Usage:
#   scripts/source/quickshell-build.sh            # build/install the pin
#   scripts/source/quickshell-build.sh --print    # print the binary path
#   scripts/source/quickshell-build.sh --check-deps
#
# Environment:
#   OMINTY_QUICKSHELL_REF   tag or commit (default: v0.3.1)
#   OMINTY_QUICKSHELL_URL   git remote
#   OMINTY_PREFIX           install prefix (default: ~/.local)
#   OMINTY_BUILD_DIR        build cache (default: ~/.cache/ominty/build)
#   OMINTY_QT_PREFIX        Qt prefix override (default: system Qt)
#   OMINTY_QUICKSHELL_FORCE set to 1 to rebuild an unchanged pin
#
set -uo pipefail

PREFIX="${OMINTY_PREFIX:-$HOME/.local}"
BUILD_DIR="${OMINTY_BUILD_DIR:-$HOME/.cache/ominty/build}"
QS_URL="${OMINTY_QUICKSHELL_URL:-https://github.com/quickshell-mirror/quickshell.git}"
QS_REF="${OMINTY_QUICKSHELL_REF:-v0.3.1}"
QT_PREFIX="${OMINTY_QT_PREFIX:-}"
FORCE="${OMINTY_QUICKSHELL_FORCE:-0}"
JOBS="$(nproc 2>/dev/null || echo 4)"

QS_SRC="$BUILD_DIR/quickshell"
QS_BIN="$PREFIX/bin/quickshell"
STAMP="$BUILD_DIR/.ominty-quickshell-ref"

# Debian/Ubuntu package names needed to build. Kept here so install.sh and a
# human can both ask for the same list.
BUILD_DEPS="cmake ninja-build pkg-config qt6-base-dev qt6-base-private-dev
qt6-declarative-dev qt6-declarative-private-dev qt6-wayland-dev
qt6-wayland-private-dev qt6-shadertools-dev libcli11-dev libdrm-dev libgbm-dev
libjemalloc-dev libunwind-dev libpam0g-dev libegl-dev libpipewire-0.3-dev
libpolkit-agent-1-dev libwayland-dev wayland-protocols libxkbcommon-dev
spirv-tools libglib2.0-dev libxcb1-dev"

say()  { printf '\033[1;34m[ominty/qs]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

check_deps() {
    local missing=""
    for c in cmake ninja pkg-config git; do
        have "$c" || missing="$missing $c"
    done
    # Qt6 dev headers and EGL are what actually break the configure step.
    if have pkg-config; then
        for m in Qt6Core Qt6Qml Qt6Quick Qt6WaylandClient egl; do
            pkg-config --exists "$m" 2>/dev/null || missing="$missing $m-dev"
        done
    fi
    # wayland-protocols >= 1.47 (trixie-backports) carries the protocol the
    # build needs; trixie's 1.44 fails late with a missing XML file.
    if [ ! -f /usr/share/wayland-protocols/staging/ext-background-effect/ext-background-effect-v1.xml ]; then
        missing="$missing wayland-protocols>=1.47(trixie-backports)"
    fi
    if [ -n "$missing" ]; then
        warn "missing build dependencies:$missing"
        warn "on Debian 13: sudo apt-get install -y $(echo $BUILD_DEPS | tr '\n' ' ')"
        warn "and: sudo apt-get install -y -t trixie-backports wayland-protocols"
        return 1
    fi
    return 0
}

case "${1:-}" in
    --print) printf '%s\n' "$QS_BIN"; exit 0 ;;
    --check-deps) check_deps; exit $? ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") : ;;
    *) die "unknown argument: $1 (try --help)" ;;
esac

have git || die "git is required."
check_deps || die "install the build dependencies first"

mkdir -p "$BUILD_DIR" "$PREFIX/bin"

# --- source ---------------------------------------------------------------
if [ -d "$QS_SRC/.git" ]; then
    git -C "$QS_SRC" remote set-url origin "$QS_URL" || die "cannot set remote"
else
    say "cloning $QS_URL"
    rm -rf "$QS_SRC"
    mkdir -p "$QS_SRC"
    git -C "$QS_SRC" init -q || die "cannot init $QS_SRC"
    git -C "$QS_SRC" remote add origin "$QS_URL" || die "cannot add remote"
fi

want="$(git -C "$QS_SRC" rev-parse --verify --quiet "$QS_REF^{commit}" || true)"
head="$(git -C "$QS_SRC" rev-parse HEAD 2>/dev/null || true)"
if [ "$want" != "$head" ] || [ ! -d "$QS_SRC/src" ]; then
    say "fetching $QS_REF"
    git -C "$QS_SRC" fetch --depth 1 origin "$QS_REF" || die "fetch failed"
    git -C "$QS_SRC" checkout -q --force FETCH_HEAD || die "checkout failed"
    git -C "$QS_SRC" submodule update --init --recursive --depth 1 \
        || warn "submodule update failed; the build may still work"
fi

commit="$(git -C "$QS_SRC" rev-parse --short=8 HEAD)"
stamp="$(cat "$STAMP" 2>/dev/null || true)"

if [ "$FORCE" -ne 1 ] && [ -x "$QS_BIN" ] && [ "$stamp" = "$commit" ]; then
    say "Quickshell $commit already installed at $QS_BIN"
else
    say "building Quickshell $commit (this takes a few minutes)"
    cmake_args=(
        -GNinja
        -B "$QS_SRC/build"
        -S "$QS_SRC"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$PREFIX"
        -DVENDOR_CPPTRACE=ON
        "-DDISTRIBUTOR=Ominty (pinned $QS_REF)"
    )
    [ -n "$QT_PREFIX" ] && cmake_args+=(-DCMAKE_PREFIX_PATH="$QT_PREFIX")

    cmake "${cmake_args[@]}" || die "cmake configure failed"
    cmake --build "$QS_SRC/build" -j "$JOBS" || die "quickshell build failed"
    cmake --install "$QS_SRC/build" || die "quickshell install failed"

    install -d "$PREFIX/bin"
    [ -x "$QS_BIN" ] || die "build produced no binary at $QS_BIN"
    printf '%s\n' "$commit" > "$STAMP"
fi

say "installed: $("$QS_BIN" --version 2>&1 | head -1)"
say "binary:    $QS_BIN"
