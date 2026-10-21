#!/usr/bin/env bash
#
# Ominty — build DankMaterialShell from source at the pinned commit.
#
# Used by install.sh for the Debian-family path (Debian 13 / LMDE 7) as well as
# the Ubuntu-family path, so both machines run the *same* DMS build. That
# matters because configs/dms/shell-overlay/dms-shell.patch is coupled to a
# specific embedded shell tree:
#
#   AvengeMedia/DankMaterialShell 73759d5  ->  shell build c27a2bbcb6e09e50
#
# The build id is the hash DMS writes into its extracted shell directory and
# the value recorded in ~/.local/share/dms-shell/.ominty-overlay.json. Bumping
# DMS_REF means regenerating dms-shell.patch (apply.sh --check will refuse to
# half-patch a build it does not recognise).
#
# User space only: no sudo, no system packages. Everything lands in
# $OMINTY_PREFIX (default ~/.local).
#
# Usage:
#   scripts/source/dms-build.sh            # build the pinned commit
#   scripts/source/dms-build.sh --print    # print the shell dist path and exit
#
# Environment:
#   OMINTY_DMS_REF     commit/branch/tag to build (default: pinned below)
#   OMINTY_DMS_URL     git remote (default: AvengeMedia/DankMaterialShell)
#   OMINTY_PREFIX      install prefix (default: ~/.local)
#   OMINTY_BUILD_DIR   build cache (default: ~/.cache/ominty/build)
#   OMINTY_GO_VERSION  Go version to fetch if `go` is absent
#   OMINTY_DMS_FORCE   set to 1 to rebuild even when the pin is unchanged
#
set -uo pipefail

REPO_DIR="${OMINTY_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PREFIX="${OMINTY_PREFIX:-$HOME/.local}"
BUILD_DIR="${OMINTY_BUILD_DIR:-$HOME/.cache/ominty/build}"
DMS_URL="${OMINTY_DMS_URL:-https://github.com/AvengeMedia/DankMaterialShell.git}"
DMS_REF="${OMINTY_DMS_REF:-73759d575210e8a4eb99b308283046b650df2ac3}"
GO_VERSION="${OMINTY_GO_VERSION:-1.26.8}"
FORCE="${OMINTY_DMS_FORCE:-0}"
JOBS="$(nproc 2>/dev/null || echo 4)"

DMS_SRC="$BUILD_DIR/DankMaterialShell"
DIST="$DMS_SRC/core/internal/shellembed/dist"
STAMP="$BUILD_DIR/.ominty-dms-ref"

say()  { printf '\033[1;34m[ominty/dms]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

case "${1:-}" in
    --print) printf '%s\n' "$DIST"; exit 0 ;;
    -h|--help) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
    "") : ;;
    *) die "unknown argument: $1 (try --help)" ;;
esac

have git || die "git is required to fetch DMS."
mkdir -p "$BUILD_DIR" "$PREFIX/bin"

# --- 1. Go -----------------------------------------------------------------
if ! have go; then
    if [ -x "$BUILD_DIR/go/bin/go" ]; then
        export PATH="$BUILD_DIR/go/bin:$PATH"
    else
        say "Installing Go $GO_VERSION (user-local, no sudo)…"
        curl -fsSL -o "$BUILD_DIR/go.tar.gz" \
            "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" \
            || die "Go download failed"
        rm -rf "$BUILD_DIR/go"
        tar -C "$BUILD_DIR" -xzf "$BUILD_DIR/go.tar.gz" || die "Go extract failed"
        export PATH="$BUILD_DIR/go/bin:$PATH"
    fi
fi
have go || die "go is not available after install"
say "Go: $(go version)"

# --- 2. Source at the pinned commit ---------------------------------------
if [ -d "$DMS_SRC/.git" ]; then
    git -C "$DMS_SRC" remote set-url origin "$DMS_URL" || die "cannot set DMS remote"
else
    say "Cloning $DMS_URL…"
    rm -rf "$DMS_SRC"
    mkdir -p "$DMS_SRC"
    git -C "$DMS_SRC" init -q || die "cannot init $DMS_SRC"
    git -C "$DMS_SRC" remote add origin "$DMS_URL" || die "cannot add DMS remote"
fi

want="$(git -C "$DMS_SRC" rev-parse --verify --quiet "$DMS_REF^{commit}" || true)"
have_commit="$(git -C "$DMS_SRC" rev-parse HEAD 2>/dev/null || true)"
if [ "$want" != "$have_commit" ] || [ ! -d "$DMS_SRC/quickshell" ]; then
    say "Fetching $DMS_REF…"
    git -C "$DMS_SRC" fetch --depth 1 origin "$DMS_REF" || die "DMS fetch failed"
    git -C "$DMS_SRC" checkout -q --force FETCH_HEAD || die "DMS checkout failed"
    git -C "$DMS_SRC" submodule update --init --recursive --depth 1 \
        || die "DMS submodule update failed"
else
    git -C "$DMS_SRC" submodule update --init --recursive --depth 1 \
        || die "DMS submodule update failed"
fi

commit="$(git -C "$DMS_SRC" rev-parse --short=8 HEAD)"
say "DMS source: $commit ($(git -C "$DMS_SRC" log -1 --format=%s))"

# The overlay patch needs the QML common tree, which comes from the submodule.
[ -e "$DMS_SRC/quickshell/DankCommon/Widgets/DankIcon.qml" ] \
    || say "WARNING: quickshell/DankCommon is missing — the shell overlay will not apply."

# --- 3. Build -------------------------------------------------------------
installed="$PREFIX/bin/dms"
stamp="$(cat "$STAMP" 2>/dev/null || true)"
if [ "$FORCE" -ne 1 ] && [ -x "$installed" ] && [ "$stamp" = "$commit" ]; then
    say "DMS $commit already installed at $installed"
else
    say "Building DMS $commit (this takes a minute)…"
    ( cd "$DMS_SRC" && make -C core build ) || die "DMS build failed"
    install -m 0755 "$DMS_SRC/core/bin/dms" "$installed" || die "DMS install failed"
    printf '%s\n' "$commit" > "$STAMP"
fi

[ -f "$DIST/.dankrev" ] || die "shell dist missing at $DIST"
rev="$(cat "$DIST/.dankrev")"

say "Installed: $("$installed" version 2>/dev/null | tail -1)"
say "Shell build: $rev"
say "Shell dist:  $DIST"
