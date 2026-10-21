#!/usr/bin/env bash
# Rebuild the Ominty DMS shell fork and apply the motion + accent-glow overlay.
#
# DMS embeds its QML shell inside the `dms` binary and unpacks it to
# /run/user/$UID/danklinux-shell/<build>/ on every start.  That directory is
# read-only and is replaced when the DMS build changes, so we copy it to a
# writable fork and point DMS at it with DMS_SHELL_DIR (the systemd drop-in in
# configs/systemd/dms.service.d/ does that).
#
# Usage:
#   apply.sh [--check] [--dry-run] [SOURCE_DIR]
#
#   --check     only test whether the patch applies to the current build;
#               exit 0 when it does, 1 when it does not. Nothing is written.
#   --dry-run   print what would be done (without --check it does not verify
#               the patch, because verification needs a temporary copy).
#   SOURCE_DIR  pristine DMS dist to start from.  Defaults to the newest
#               /run/user/$UID/danklinux-shell/* directory.
#
# Safe to re-run: the fork is rebuilt from the pristine dist each time, so
# local edits are never merged or lost silently.

set -euo pipefail

CHECK_ONLY=0
DRY_RUN=0
SOURCE=""
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *) SOURCE="$arg" ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/dms-shell.patch"
DEST="${DMS_SHELL_DIR:-$HOME/.local/share/dms-shell}"

if [[ ! -f "$PATCH" ]]; then
    echo "error: patch not found: $PATCH" >&2
    exit 1
fi

if [[ -z "$SOURCE" ]]; then
    SOURCE="$(ls -dt /run/user/"$(id -u)"/danklinux-shell/*/ 2>/dev/null | head -1 || true)"
    SOURCE="${SOURCE%/}"
fi

if [[ -z "$SOURCE" || ! -d "$SOURCE" ]]; then
    cat >&2 <<'EOF'
error: no pristine DMS shell dist found.

DMS unpacks its shell the first time it runs.  Either:
  * start DMS once (systemctl --user start dms.service), then re-run this script, or
  * pass the path explicitly:  apply.sh /path/to/pristine/dms-shell
EOF
    exit 1
fi

BASE="$(basename "$SOURCE")"

# Verify against a throwaway copy: `patch --dry-run` still needs a tree whose
# files match the patch context, and the pristine dist is read-only.
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
    echo "base:  $BASE"
    if check_patch; then
        echo "state: applicable"
        exit 0
    fi
    echo "state: not-applicable" >&2
    exit 1
fi

echo "source: $SOURCE"
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
