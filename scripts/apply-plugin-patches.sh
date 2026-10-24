#!/usr/bin/env bash
#
# Ominty — apply patches to third-party DMS plugins.
#
# `dms plugins restore` (and `dms plugins update`) reset managed plugins to
# their upstream commit, which silently discards local fixes. This script
# re-applies the patches in ominty-plugins/patches/ after a restore, and is
# safe to run repeatedly.
#
# Why patches and not a fork: the fixes are small and upstream-tracking, and a
# fork would pin us to a snapshot of someone else's plugin. Each patch is
# attributed by directory and file name.
#
# Patch naming: <pluginId>-<purpose>.patch
#   dankChat-qt68-contextmenu.patch  ->  ~/.config/DankMaterialShell/plugins/dankChat
#
# Usage:
#   scripts/apply-plugin-patches.sh            # apply what is missing
#   scripts/apply-plugin-patches.sh --check    # report only; exit 1 if stale
#
set -uo pipefail

REPO_DIR="${OMINTY_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PATCH_DIR="${OMINTY_PATCH_DIR:-$REPO_DIR/ominty-plugins/patches}"
PLUGIN_DIR="${DMS_PLUGIN_DIR:-$HOME/.config/DankMaterialShell/plugins}"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say()  { printf '\033[1;34m[ominty/patches]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }
have patch || { warn "the 'patch' program is missing (install diffutils)"; exit 2; }

[ -d "$PATCH_DIR" ] || { say "no patches directory at $PATCH_DIR"; exit 0; }

applied=0
missing=0
failed=0

for file in "$PATCH_DIR"/*.patch; do
    [ -e "$file" ] || continue
    name="$(basename "$file")"
    plugin="${name%%-*}"
    target="$PLUGIN_DIR/$plugin"

    if [ ! -d "$target" ]; then
        warn "$name: plugin '$plugin' is not installed; skipped"
        continue
    fi

    # Already applied? A reverse dry-run succeeds only if every hunk is present.
    if patch -d "$target" -p1 --dry-run --reverse --forward \
            < "$file" >/dev/null 2>&1; then
        say "$name: already applied"
        applied=$((applied + 1))
        continue
    fi

    if [ "$CHECK_ONLY" -eq 1 ]; then
        warn "$name: NOT applied to $target"
        missing=$((missing + 1))
        continue
    fi

    if patch -d "$target" -p1 --dry-run --forward < "$file" >/dev/null 2>&1; then
        patch -d "$target" -p1 --forward < "$file" >/dev/null \
            && { say "$name: applied"; applied=$((applied + 1)); }
    else
        warn "$name: does not apply to $target (plugin version changed?)"
        warn "         plugin: $(git -C "$target" log -1 --format=%h 2>/dev/null || echo 'no git')"
        failed=$((failed + 1))
    fi
done

if [ "$CHECK_ONLY" -eq 1 ] && [ "$missing" -gt 0 ]; then
    exit 1
fi
[ "$failed" -gt 0 ] && exit 1
exit 0
