#!/usr/bin/env bash
# Rebuild the Ominty DMS shell fork and apply the motion + accent-glow overlay.
#
# DMS embeds its QML shell inside the `dms` binary and unpacks it to
# /run/user/$UID/danklinux-shell/<hash> on every start.  We cannot edit that
# directory (read-only, recreated on restart), so we copy it to a writable fork
# and point DMS at it with DMS_SHELL_DIR (see configs/systemd/dms.service).
#
# Usage:
#   apply.sh [--dry-run] [SOURCE_DIR]
#
#   SOURCE_DIR  pristine DMS dist to start from.  Defaults to the newest
#               /run/user/$UID/danklinux-shell/* directory.
#
# Safe to re-run: the fork is rebuilt from the pristine dist each time, so
# local edits are never merged or lost silently.

set -euo pipefail

DRY_RUN=0
SOURCE=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

echo "source: $SOURCE"
echo "dest:   $DEST"

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would remove $DEST, copy $SOURCE, and apply $PATCH"
    exit 0
fi

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -a "$SOURCE" "$DEST"
chmod -R u+w "$DEST"

patch -d "$DEST" -p1 --forward < "$PATCH"

# Sanity check: the accent glow property must exist in the patched shadow.
grep -q "property bool glowEnabled" "$DEST/DankCommon/Common/ElevationShadow.qml" \
    || { echo "error: overlay did not apply cleanly" >&2; exit 1; }

cat <<EOF

Overlay applied.  Activate it with:
  Environment=DMS_SHELL_DIR=$DEST   # in ~/.config/systemd/user/dms.service
  systemctl --user daemon-reload && systemctl --user restart dms.service

Rollback: remove the DMS_SHELL_DIR line and restart dms.service.
EOF
