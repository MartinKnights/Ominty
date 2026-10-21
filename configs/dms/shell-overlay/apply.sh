#!/usr/bin/env bash
# Rebuild the Ominty DMS shell fork and apply the motion + accent-glow overlay.
#
# DMS embeds its QML shell in the `dms` binary and extracts it at runtime. The
# location depends on the DMS generation:
#
#   AvengeMedia DMS 1.6.x  ->  /run/user/$UID/danklinux-shell/<build>/
#   Dux Shell 2.0.x        ->  /run/user/$UID/dms-shell/<build>/
#   packaged install       ->  /usr/share/quickshell/dms
#
# Those directories are read-only and are replaced when the DMS build changes,
# so we copy the pristine tree to a writable fork and point DMS at it with
# DMS_SHELL_DIR (the systemd drop-in in configs/systemd/dms.service.d/ does
# that).
#
# Usage:
#   apply.sh [--check] [--dry-run] [SOURCE_DIR]
#
#   --check     only test whether the patch applies to the current build.
#               Nothing is written.
#   --dry-run   print what would be done.
#   SOURCE_DIR  pristine DMS shell tree. When omitted, the candidates below are
#               tried in order (first match wins).
#
# Exit codes:
#   0  applied, or (with --check) the patch applies to a discovered source
#   1  the patch does not apply to this DMS build (stock shell stays)
#   2  bad usage
#   3  no pristine shell tree found (start DMS once, or pass SOURCE_DIR)
#
# Safe to re-run: the fork is rebuilt from the pristine tree each time, so
# local edits are never merged or lost silently.

set -euo pipefail

CHECK_ONLY=0
DRY_RUN=0
SOURCE=""
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *) SOURCE="$arg" ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/dms-shell.patch"
DEST="${DMS_SHELL_DIR:-$HOME/.local/share/dms-shell}"
UID_NUM="$(id -u)"
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$UID_NUM}"
BUILD_DIR="${OMINTY_BUILD_DIR:-$HOME/.cache/ominty/build}"

if [[ ! -f "$PATCH" ]]; then
    echo "error: patch not found: $PATCH" >&2
    exit 1
fi

# Newest directory under <base>, if any.
newest_dir() {
    local base="$1"
    [[ -d "$base" ]] || return 0
    ls -dt "$base"/*/ 2>/dev/null | head -1 | sed 's:/$::' || true
}

is_shell_tree() {
    [[ -d "$1" && -f "$1/shell.qml" ]]
}

# Candidates in preference order. Explicit configuration wins over discovery,
# and a runtime extraction (same build as the running binary) wins over a
# static package tree.
if [[ -z "$SOURCE" ]]; then
    candidates=()
    [[ -n "${DMS_SHELL_SRC:-}" ]] && candidates+=("$DMS_SHELL_SRC")
    candidates+=(
        "$(newest_dir "$RUNTIME/danklinux-shell")"
        "$(newest_dir "/run/user/$UID_NUM/danklinux-shell")"
        "$(newest_dir "$RUNTIME/dms-shell")"
        "$(newest_dir "/run/user/$UID_NUM/dms-shell")"
        "$BUILD_DIR/DankMaterialShell/core/internal/shellembed/dist"
        "$HOME/.cache/ominty/build/DankMaterialShell/core/internal/shellembed/dist"
        /usr/share/quickshell/dms
        /usr/local/share/quickshell/dms
        /etc/xdg/quickshell/dms
    )
    for candidate in "${candidates[@]}"; do
        if is_shell_tree "$candidate"; then
            SOURCE="$candidate"
            break
        fi
    done
fi

if [[ -n "$SOURCE" && ! -d "$SOURCE" ]]; then
    cat >&2 <<EOF
error: '$SOURCE' is not a directory.

An explicit SOURCE_DIR is used as given: it is never replaced by discovery.
Point it at a pristine DMS shell tree (the directory containing shell.qml).
EOF
    exit 3
fi

if [[ -z "$SOURCE" ]]; then
    cat >&2 <<EOF
error: no pristine DMS shell tree found.

Looked in:
  \$DMS_SHELL_SRC
  $RUNTIME/danklinux-shell/*
  /run/user/$UID_NUM/danklinux-shell/*
  $RUNTIME/dms-shell/*
  /run/user/$UID_NUM/dms-shell/*
  $BUILD_DIR/DankMaterialShell/core/internal/shellembed/dist
  /usr/share/quickshell/dms
  /usr/local/share/quickshell/dms
  /etc/xdg/quickshell/dms

Either:
  * start DMS once (systemctl --user start dms.service), then re-run this script,
  * build DMS from source (scripts/source/dms-build.sh), or
  * pass the path explicitly:  apply.sh /path/to/pristine/dms-shell
EOF
    exit 3
fi

# Prefer the build id DMS writes into the tree; fall back to the directory name
# (a packaged tree is just called "dms").
BASE="$(cat "$SOURCE/.dankrev" 2>/dev/null || basename "$SOURCE")"

# Verify against a throwaway copy: `patch --dry-run` still needs a tree whose
# files match the patch context, and the pristine tree is read-only.
check_patch() {
    local tmp
    tmp="$(mktemp -d)"
    cp -a "$SOURCE"/. "$tmp"/
    chmod -R u+w "$tmp"
    if patch -d "$tmp" -p1 --forward --dry-run < "$PATCH" >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    return 1
}

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo "source: $SOURCE"
    echo "base:   $BASE"
    if check_patch; then
        echo "state:  applicable"
        exit 0
    fi
    echo "state:  not-applicable" >&2
    exit 1
fi

echo "source: $SOURCE"
echo "base:   $BASE"
echo "dest:   $DEST"

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would remove $DEST, copy $SOURCE, and apply $PATCH"
    exit 0
fi

# Refuse to ship a half-patched shell: verify first, then rebuild.
if ! check_patch; then
    echo "error: patch does not apply to DMS build '$BASE'; leaving the fork untouched." >&2
    echo "       Re-apply the intent to the new files and regenerate dms-shell.patch." >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -a "$SOURCE" "$DEST"
chmod -R u+w "$DEST"

patch -d "$DEST" -p1 --forward < "$PATCH"

# Sanity check: the accent glow property must exist in the patched shadow.
grep -q "property bool glowEnabled" "$DEST/DankCommon/Common/ElevationShadow.qml" \
    || { echo "error: overlay did not apply cleanly" >&2; exit 1; }

# Record the base build so `ominty inspect` can report what the fork is
# derived from (and whether a DMS upgrade has made it stale).
printf '{"base":"%s","applied":"%s","source":"%s"}\n' \
    "$BASE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SOURCE" \
    > "$DEST/.ominty-overlay.json"

cat <<EOF

Overlay applied (base: $BASE).  Activate it with the systemd drop-in:
  ~/.config/systemd/user/dms.service.d/ominty-shell.conf
  systemctl --user daemon-reload && systemctl --user restart dms.service

Rollback: remove that drop-in and restart dms.service.
EOF
