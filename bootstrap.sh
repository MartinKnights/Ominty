#!/usr/bin/env bash
#
# Ominty — bootstrap the checkout, in retryable pieces.
#
# A plain `git clone` is one 29 MB transfer (21 MB of it the bundled .debs), and
# a dropped connection loses the whole thing. This script splits the download
# into small steps that can each be retried, and never re-downloads what has
# already succeeded:
#
#   1. metadata only        (--filter=blob:none --no-checkout)   ~100 KB
#   2. source tree          (sparse checkout, without packages/)  ~8 MB
#   3. submodule            (ominty-core)                         small
#   4. bundled .debs        (only when Niri is not installed)     21 MB
#
# Every step has a timeout and a retry count. Re-running the script continues
# from the first step that has not completed.
#
# It is also the repair path: run it again after any interrupted download.
#
# Usage:
#   ./bootstrap.sh
#   OMINTY_DIR=~/src/Ominty ./bootstrap.sh
#   OMINTY_URL=/path/to/Ominty.bundle ./bootstrap.sh    # offline bundle
#
# Environment:
#   OMINTY_DIR            destination (default ~/Ominty)
#   OMINTY_URL            remote, URL or local bundle (default HTTPS GitHub)
#   OMINTY_BRANCH         branch (default main)
#   OMINTY_RETRIES        attempts per step (default 4)
#   OMINTY_TIMEOUT        seconds per attempt (default 900)
#   OMINTY_WITH_PACKAGES  1 = always fetch the bundled .debs
#   OMINTY_PACKAGES_SRC   local directory to copy packages/ from (offline)
#   OMINTY_PACKAGES_URL   base URL for the .debs (default: GitHub raw)
#
set -uo pipefail

DEST="${OMINTY_DIR:-$HOME/Ominty}"
URL="${OMINTY_URL:-https://github.com/MartinKnights/Ominty.git}"
BRANCH="${OMINTY_BRANCH:-main}"
RETRIES="${OMINTY_RETRIES:-4}"
TIMEOUT="${OMINTY_TIMEOUT:-900}"
WITH_PACKAGES="${OMINTY_WITH_PACKAGES:-auto}"

# HTTP/1.1 avoids the "RPC failed; curl 92 HTTP/2 stream" class of error; the
# slow-speed floor turns a stalled transfer into a retryable failure instead of
# hanging forever.
GIT_OPTS=(
    -c http.version=HTTP/1.1
    -c http.postBuffer=524288000
    -c http.lowSpeedLimit=256
    -c http.lowSpeedTime=120
)

say()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

retry() {  # retry <description> <command...>
    local what="$1"; shift
    local attempt=1 rc
    while true; do
        printf '\033[1;34m[bootstrap]\033[0m %s (attempt %d/%d)\n' "$what" "$attempt" "$RETRIES"
        timeout "$TIMEOUT" "$@"
        rc=$?
        [ "$rc" -eq 0 ] && return 0
        if [ "$rc" -eq 124 ]; then
            warn "$what timed out after ${TIMEOUT}s"
        else
            warn "$what failed (exit $rc)"
        fi
        if [ "$attempt" -ge "$RETRIES" ]; then
            warn "$what gave up after $RETRIES attempts"
            return "$rc"
        fi
        local wait=$((attempt * 5))
        warn "retrying in ${wait}s — re-run this script later to continue from here"
        sleep "$wait"
        attempt=$((attempt + 1))
    done
}

have git || die "git is not installed. Run: sudo apt install -y git"
mkdir -p "$(dirname "$DEST")" || die "cannot create $(dirname "$DEST")"

git_at() { git "${GIT_OPTS[@]}" -C "$DEST" "$@"; }

# --- 0. a directory that is not a checkout ---------------------------------
if [ -e "$DEST" ] && [ ! -d "$DEST/.git" ]; then
    aside="$DEST.incomplete-$(date +%Y%m%d-%H%M%S)"
    warn "$DEST exists but is not a git checkout; moving it to $aside"
    mv "$DEST" "$aside" || die "cannot move $DEST aside"
fi

# --- 1. metadata, or continue an existing checkout -------------------------
if [ ! -d "$DEST/.git" ]; then
    say "step 1/4: repository metadata (no files yet)"
    retry "clone metadata" git "${GIT_OPTS[@]}" clone \
        --depth 1 --single-branch --filter=blob:none --no-checkout \
        --branch "$BRANCH" "$URL" "$DEST" \
        || die "could not clone metadata from $URL (re-run to continue)"
else
    say "step 1/4: checkout exists; refreshing metadata"
    git_at remote set-url origin "$URL" || die "cannot point origin at $URL"
    # Only judge dirtiness when there is an index. A clone interrupted before
    # its first checkout has none, and every file looks "deleted" to status.
    if [ -n "$(git_at ls-files --cached 2>/dev/null | head -1)" ]; then
        if [ -n "$(git_at status --porcelain 2>/dev/null)" ]; then
            warn "local changes in $DEST; not resetting."
            warn "Commit or stash them, then re-run this script."
            exit 1
        fi
    fi
    retry "fetch" git "${GIT_OPTS[@]}" -C "$DEST" fetch --depth 1 origin "$BRANCH" \
        || die "fetch failed (re-run to continue)"
fi

# --- 2. source tree, without packages/ -------------------------------------
# Sparse-checkout keeps the 21 MB of bundled .debs out of the critical path:
# the desktop source arrives first, the .debs later and separately.
say "step 2/4: source tree"
git_at sparse-checkout init --cone >/dev/null 2>&1 || true
retry "sparse checkout" git "${GIT_OPTS[@]}" -C "$DEST" sparse-checkout set \
    configs docs omi-dictionary omi-media ominty-plugins profiles scripts tools \
    || die "could not fetch the source tree (re-run to continue)"
retry "checkout" git "${GIT_OPTS[@]}" -C "$DEST" checkout -q -B "$BRANCH" "origin/$BRANCH" \
    || die "checkout failed"

# --- 3. submodule ----------------------------------------------------------
say "step 3/4: ominty-core submodule"
retry "submodule" git "${GIT_OPTS[@]}" -C "$DEST" submodule update \
    --init --recursive --depth 1 \
    || die "submodule update failed (re-run to continue)"

# --- 4. bundled .debs, only when they are actually needed ------------------
need_packages=0
[ "$WITH_PACKAGES" = "1" ] && need_packages=1
have niri || need_packages=1
ls "$DEST"/packages/niri_*.deb >/dev/null 2>&1 || need_packages=1

if [ "$need_packages" -eq 1 ]; then
    say "step 4/4: bundled packages (~21 MB; Niri is not installed)"
    mkdir -p "$DEST/packages"
    # These are fetched outside git on purpose: a single 19 MB blob through the
    # git promisor is all-or-nothing and dies on a slow link. curl retries each
    # file independently, and a local copy avoids the network entirely.
    for name in niri_26.4.0-1_amd64.deb xwayland-satellite_0.8.2-1_amd64.deb; do
        out="$DEST/packages/$name"
        if [ -f "$out" ] && dpkg-deb --info "$out" >/dev/null 2>&1; then
            say "  $name: already present"
            continue
        fi
        if [ -n "${OMINTY_PACKAGES_SRC:-}" ]; then
            say "  $name: copying from $OMINTY_PACKAGES_SRC"
            retry "copy $name" cp "${OMINTY_PACKAGES_SRC%/}/$name" "$out.part" \
                || die "could not copy $name (re-run to continue)"
        else
            have curl || die "curl is not installed (sudo apt install -y curl), or set OMINTY_PACKAGES_SRC=/path/to/packages"
            url="${OMINTY_PACKAGES_URL:-https://raw.githubusercontent.com/MartinKnights/Ominty/$BRANCH/packages}/$name"
            say "  $name: downloading"
            retry "download $name" curl -fL --retry 3 --retry-delay 5 \
                --connect-timeout 20 --speed-limit 128 --speed-time 120 \
                -o "$out.part" "$url" \
                || { rm -f "$out.part"; die "could not download $name (re-run to continue, or set OMINTY_PACKAGES_SRC=/path/to/packages)"; }
        fi
        dpkg-deb --info "$out.part" >/dev/null 2>&1 \
            || { rm -f "$out.part"; die "$name is incomplete; re-run this script"; }
        mv -f "$out.part" "$out"
        say "  $name: ok"
    done
else
    say "step 4/4: skipped (Niri already installed; set OMINTY_WITH_PACKAGES=1 to fetch anyway)"
fi

# --- verify ---------------------------------------------------------------
[ -f "$DEST/install.sh" ] || die "$DEST/install.sh is missing — re-run this script"
[ -f "$DEST/AGENTS.md" ]  || die "$DEST/AGENTS.md is missing — re-run this script"
if git_at submodule status | grep -q '^-'; then
    die "the ominty-core submodule is not initialised; re-run this script"
fi

say "ready: $DEST"
say "  commit:    $(git_at rev-parse --short HEAD) ($(git_at log -1 --format=%s))"
say "  submodule: $(git_at submodule status | awk '{print substr($1,1,8)}')"
say "  packages:  $([ -f "$DEST/packages/niri_26.4.0-1_amd64.deb" ] && echo present || echo 'not fetched (Niri already installed)')"
say ""
say "Next: point your AI at AGENTS.md, or read docs/INSTALL.md yourself."
say "  cd $DEST && cat AGENTS.md"
