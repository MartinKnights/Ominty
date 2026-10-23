#!/usr/bin/env bash
#
# Ominty — Ubuntu/Mint desktop build (user space, no sudo).
#
# Called by install.sh for the `ubuntu` / `mint-ubuntu` family, or run directly:
#
#     scripts/ubuntu/ubuntu-build.sh
#
# Ubuntu-family systems do not package Quickshell / DMS / matugen, and their
# Qt is older than Quickshell's floor (>= 6.6). So this builds, in order:
#
#   1. Qt (official binaries via aqtinstall)      -> $QT_PREFIX
#   2. Quickshell (against that Qt)               -> $PREFIX (default ~/.local)
#   3. DMS core (Go, embeds the shell)            -> $PREFIX/bin/dms
#   4. matugen (Rust)                             -> $PREFIX/bin/matugen
#
# Everything is configurable and idempotent; re-running skips completed steps.
#
set -uo pipefail

REPO_DIR="${OMINTY_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PREFIX="${OMINTY_PREFIX:-$HOME/.local}"
BUILD_DIR="${OMINTY_BUILD_DIR:-$HOME/.cache/ominty/build}"
QT_VERSION="${OMINTY_QT_VERSION:-6.8.3}"
QT_ARCH="linux_gcc_64"
GO_VERSION="${OMINTY_GO_VERSION:-1.26.8}"
JOBS="$(nproc 2>/dev/null || echo 4)"

QT_PREFIX="$BUILD_DIR/Qt/$QT_VERSION/gcc_64"
mkdir -p "$BUILD_DIR" "$PREFIX/bin"

say()  { printf '\033[1;34m[ominty/ubuntu]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- 1. Qt ----------------------------------------------------------------
if [ -x "$QT_PREFIX/bin/qmake" ]; then
  say "Qt $QT_VERSION already present at $QT_PREFIX"
else
  say "Installing Qt $QT_VERSION via aqtinstall (qtbase/qtdeclarative/qtsvg/qtwayland + shadertools)…"
  python3 -m venv "$BUILD_DIR/venv" || die "venv creation failed"
  "$BUILD_DIR/venv/bin/pip" install --quiet --upgrade pip aqtinstall \
    || die "aqtinstall install failed"
  "$BUILD_DIR/venv/bin/aqt" install-qt linux desktop "$QT_VERSION" "$QT_ARCH" \
    -m qtshadertools qtwaylandcompositor --outputdir "$BUILD_DIR/Qt" \
    || die "Qt install failed"
fi
[ -x "$QT_PREFIX/bin/qmake" ] || die "Qt not found at $QT_PREFIX after install"

# --- 2. Quickshell --------------------------------------------------------
# Delegated to the shared pinned build so Ubuntu and Debian run the same
# Quickshell, which is what the pinned DMS shell is validated against.
say "Building Quickshell (pinned; see scripts/source/quickshell-build.sh)…"
OMINTY_PREFIX="$PREFIX" \
OMINTY_BUILD_DIR="$BUILD_DIR" \
OMINTY_QT_PREFIX="$QT_PREFIX" \
  bash "$REPO_DIR/scripts/source/quickshell-build.sh" || die "Quickshell build failed"

# --- 3. DMS core ----------------------------------------------------------
# Delegated to the shared pinned build so Ubuntu and Debian get the identical
# embedded shell. The motion/glow overlay (configs/dms/shell-overlay) is
# coupled to that shell tree, so the pin matters.
say "Building DankMaterialShell (pinned; see scripts/source/dms-build.sh)…"
OMINTY_REPO_DIR="$REPO_DIR" \
OMINTY_PREFIX="$PREFIX" \
OMINTY_BUILD_DIR="$BUILD_DIR" \
OMINTY_GO_VERSION="$GO_VERSION" \
  bash "$REPO_DIR/scripts/source/dms-build.sh" || die "DMS build failed"

# --- 4. matugen -----------------------------------------------------------
if [ -x "$PREFIX/bin/matugen" ]; then
  say "matugen already present at $PREFIX/bin/matugen"
else
  say "Building matugen (Rust)…"
  [ -x "$HOME/.cargo/bin/cargo" ] || {
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$BUILD_DIR/rustup.sh" \
      || die "rustup download failed"
    sh "$BUILD_DIR/rustup.sh" -y --no-modify-path || die "rustup install failed"
  }
  "$HOME/.cargo/bin/cargo" install matugen || die "matugen build failed"
  ln -sf "$HOME/.cargo/bin/matugen" "$PREFIX/bin/matugen"
fi

say "Build complete:"
for b in quickshell dms matugen; do printf '  %-11s %s\n' "$b" "$(command -v "$b" || echo "$PREFIX/bin/$b")"; done
