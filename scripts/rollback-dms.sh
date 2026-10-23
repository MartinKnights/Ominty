#!/usr/bin/env bash
#
# Ominty — put DMS back into a known-working state.
#
# The 2026-10-22 LMDE run needed four different rollbacks, each done by hand.
# This script makes them one command, and keeps the scope narrow: it never
# touches the niri config, the helper scripts or the theme. (Restoring the
# whole config.kdl is what silently deleted the new keybindings last time.)
#
# Usage:
#   scripts/rollback-dms.sh --overlay-off    # keep the build, use the stock shell
#   scripts/rollback-dms.sh --to-backup      # restore the previous dms.service
#   scripts/rollback-dms.sh --to-packaged    # drop our unit, use /usr/bin/dms
#   scripts/rollback-dms.sh --list           # show what is available
#
set -uo pipefail

UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/dms.service"
DROPIN_DIR="$UNIT_DIR/dms.service.d"
DROPIN="$DROPIN_DIR/ominty-shell.conf"
DMS_BIN="${OMINTY_DMS_BIN:-$HOME/.local/bin/dms}"
SMOKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/smoke-dms.sh"

say()  { printf '\033[1;34m[ominty/rollback]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

newest_backup() {
    ls -1t "$UNIT".bak-ominty-* 2>/dev/null | head -1
}

inline_overlay() {
    [ -f "$UNIT" ] && grep -q '^Environment=DMS_SHELL_DIR=' "$UNIT"
}

list_state() {
    echo "user unit:      $([ -f "$UNIT" ] && echo present || echo absent)"
    echo "overlay drop-in:$([ -f "$DROPIN" ] && echo present || echo absent)"
    echo "inline overlay: $(inline_overlay && echo present || echo absent)"
    echo "packaged unit:  $([ -f /usr/lib/systemd/user/dms.service ] && echo present || echo absent)"
    local b; b="$(newest_backup)"
    echo "newest backup:  ${b:-none}"
}

restart_and_check() {
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user restart dms.service 2>/dev/null || true
    if [ -x "$SMOKE" ]; then
        "$SMOKE"
    else
        warn "smoke-dms.sh not found; cannot verify"
    fi
}

case "${1:-}" in
    --list)
        list_state
        exit 0
        ;;
    --overlay-off)
        say "disabling the shell overlay (stock shell stays on the pinned build)"
        systemctl --user stop dms.service 2>/dev/null || true
        rm -f "$DROPIN"
        # Older installs carried the environment line in the unit itself;
        # a drop-in-only rollback would leave the fork active.
        if inline_overlay; then
            cp -a "$UNIT" "$UNIT.bak-ominty-$(date +%Y%m%d-%H%M%S)"
            sed -i 's|^Environment=DMS_SHELL_DIR=.*|# disabled by rollback-dms.sh|' "$UNIT"
        fi
        restart_and_check
        ;;
    --to-backup)
        backup="$(newest_backup)"
        [ -n "$backup" ] || die "no $UNIT.bak-ominty-* backup found"
        say "restoring $backup"
        systemctl --user stop dms.service 2>/dev/null || true
        cp -a "$backup" "$UNIT"
        restart_and_check
        ;;
    --to-packaged)
        [ -f /usr/lib/systemd/user/dms.service ] \
            || die "no packaged dms unit at /usr/lib/systemd/user/dms.service"
        say "removing the Ominty unit and using the packaged /usr/bin/dms"
        systemctl --user stop dms.service 2>/dev/null || true
        # Keep a copy so --to-backup can return to the source build later.
        [ -f "$UNIT" ] && cp -a "$UNIT" "$UNIT.bak-ominty-$(date +%Y%m%d-%H%M%S)"
        rm -f "$UNIT" "$DROPIN"
        restart_and_check
        ;;
    -h|--help|"")
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        die "unknown argument: $1 (try --help)"
        ;;
esac

# A rollback that leaves a crash loop is not a rollback.
rc=$?
if [ "$rc" -ne 0 ]; then
    warn "the restored DMS did not pass its smoke test — see the output above"
    exit "$rc"
fi
say "rollback complete"
