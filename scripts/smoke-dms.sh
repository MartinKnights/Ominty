#!/usr/bin/env bash
#
# Ominty — is the running DMS shell actually alive?
#
# A single `systemctl is-active` is not enough: a crash-looping unit reports
# "activating" (and briefly "active") between restarts. On LMDE 7 the pinned
# shell segfaulted every ~3 s and a one-shot check still passed — see the
# 2026-10-22 upgrade report.
#
# This observes the unit over a window and probes the shell's IPC server.
# Read-only by default; `--restart` restarts the unit first (used by
# install.sh after writing a new unit).
#
# Usage:
#   scripts/smoke-dms.sh [--restart] [--wait SECONDS]
#
# Exit:
#   0  the shell is running, stable and answering IPC
#   1  it is not
#   3  systemd user session unavailable (cannot judge)
#
set -uo pipefail

UNIT="${OMINTY_DMS_UNIT:-dms.service}"
DMS_BIN="${OMINTY_DMS_BIN:-$HOME/.local/bin/dms}"
WAIT=12
RESTART=0

while [ $# -gt 0 ]; do
    case "$1" in
        --restart) RESTART=1; shift ;;
        --wait)    WAIT="${2:?--wait needs a value}"; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m[ominty/smoke]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

have systemctl || { warn "systemctl not available"; exit 3; }
systemctl --user show "$UNIT" >/dev/null 2>&1 || {
    warn "no systemd user session, or $UNIT does not exist"
    exit 3
}
if [ "$(systemctl --user show "$UNIT" -p LoadState --value 2>/dev/null)" != "loaded" ]; then
    warn "$UNIT is not loaded (no such unit)"
    exit 3
fi

show() { systemctl --user show "$UNIT" -p "$1" --value 2>/dev/null; }

if [ "$RESTART" -eq 1 ]; then
    say "restarting $UNIT"
    systemctl --user restart "$UNIT" 2>/dev/null || true
fi

before="$(show NRestarts)"

# Observe for the whole window so an auto-restart cycle cannot hide.
end=$((SECONDS + WAIT))
while [ "$SECONDS" -lt "$end" ]; do
    state="$(show ActiveState)"
    [ "$state" = "failed" ] && break
    sleep 1
done

after="$(show NRestarts)"
state="$(show ActiveState)"
sub="$(show SubState)"

say "unit: $UNIT  state=$state/$sub  restarts: ${before:-?} -> ${after:-?}"

status=0
if [ "$state" != "active" ]; then
    fail "state is '$state', expected 'active'"
    status=1
fi

if [ -n "${before:-}" ] && [ -n "${after:-}" ] && [ "$before" != "$after" ]; then
    fail "unit restarted $((after - before)) time(s) during ${WAIT}s — crash loop"
    status=1
fi

if [ -x "$DMS_BIN" ]; then
    if timeout 6 "$DMS_BIN" ipc call theme getMode >/dev/null 2>&1; then
        say "ipc: responsive"
    else
        fail "ipc: no response (shell is not serving its IPC socket)"
        status=1
    fi
else
    warn "no dms binary at $DMS_BIN; skipped the IPC probe"
fi

if [ "$status" -ne 0 ]; then
    crash_root="$HOME/.cache/quickshell/crashes"
    if [ -d "$crash_root" ]; then
        newest="$(ls -1t "$crash_root" 2>/dev/null | head -1)"
        if [ -n "$newest" ] && [ -f "$crash_root/$newest/report.txt" ]; then
            fail "newest Quickshell crash: $crash_root/$newest/report.txt"
            sed -n '1,12p' "$crash_root/$newest/report.txt" | sed 's/^/       /' >&2
        fi
    fi
    printf '\nJournal (last 25 lines):\n' >&2
    journalctl --user -u "$UNIT" -n 25 --no-pager 2>/dev/null | sed 's/^/  /' >&2 || true
    exit 1
fi

say "dms is healthy"
exit 0
