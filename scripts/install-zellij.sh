#!/usr/bin/env bash
#
# Ominty — install zellij from its upstream release.
#
# Debian 13 packages no zellij, and `https://zellij.dev/launch` is a *launcher*:
# it downloads the release to /tmp and runs it in the foreground (it is the
# "try it now" command, not an installer). This script fetches the same
# upstream release tarball and installs the binary into ~/.local/bin, so the
# terminal layer can actually satisfy it.
#
# No sudo: the binary goes to $OMINTY_PREFIX/bin (default ~/.local/bin).
#
# Usage:
#   scripts/install-zellij.sh
#
# Environment:
#   OMINTY_PREFIX   install prefix (default ~/.local)
#
set -uo pipefail

PREFIX="${OMINTY_PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin/zellij"
VERSION="${OMINTY_ZELLIJ_VERSION:-latest}"

say()  { printf '\033[1;34m[ominty/zellij]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

if have zellij; then
    say "zellij already installed: $(command -v zellij) ($(zellij --version 2>/dev/null | head -1))"
    exit 0
fi
if [ -x "$BIN" ]; then
    say "zellij already installed at $BIN ($("$BIN" --version 2>/dev/null | head -1))"
    exit 0
fi

have curl || die "curl is required"
have tar  || die "tar is required"

case "$(uname -m)" in
    x86_64)          arch="x86_64" ;;
    aarch64|arm64)   arch="aarch64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac

if [ "$VERSION" = "latest" ]; then
    url="https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz"
else
    url="https://github.com/zellij-org/zellij/releases/download/v${VERSION}/zellij-${arch}-unknown-linux-musl.tar.gz"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "downloading $url"
curl -fL --retry 4 --retry-delay 5 --connect-timeout 20 \
     --speed-limit 128 --speed-time 120 \
     -o "$tmp/zellij.tar.gz" "$url" \
    || die "download failed; re-run to try again"

tar -xzf "$tmp/zellij.tar.gz" -C "$tmp" || die "could not extract the release"
[ -f "$tmp/zellij" ] || die "the release did not contain a zellij binary"

mkdir -p "$PREFIX/bin" || die "cannot create $PREFIX/bin"
install -m 0755 "$tmp/zellij" "$BIN" || die "could not install to $BIN"

"$BIN" --version >/dev/null 2>&1 || die "the installed binary does not run"
say "installed: $BIN ($("$BIN" --version | head -1))"
