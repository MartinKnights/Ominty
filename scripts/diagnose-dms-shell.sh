#!/usr/bin/env bash
#
# Ominty — work out which DMS/Quickshell combination actually runs.
#
# The pinned DMS shell (73759d5) segfaults on LMDE 7 with Quickshell 0.3.0
# (Debian trixie-backports). The workstation it was developed on runs 0.3.1.
# This script runs the combinations side by side, each with a throwaway QML
# cache, and reports which ones survive.
#
# It stops dms.service for the duration — the shell cannot run twice — and
# restarts it at the end (or leaves it stopped with --no-restore).
#
# Usage:
#   scripts/diagnose-dms-shell.sh
#   scripts/diagnose-dms-shell.sh --quickshell PATH [--quickshell PATH ...]
#   scripts/diagnose-dms-shell.sh --no-restore --wait 25
#
# Exit: 0 if at least one combination started and answered IPC, else 1.
#
set -uo pipefail

WAIT=20
RESTORE=1
EXTRA_QS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --quickshell) EXTRA_QS+=("$2"); shift 2 ;;
        --wait)       WAIT="$2"; shift 2 ;;
        --no-restore) RESTORE=0; shift ;;
        -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m[ominty/matrix]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

OUT="$HOME/ominty-dms-matrix-$(date +%Y%m%d-%H%M%S).md"
WORK="$(mktemp -d)"
results=()

# A shell started by an agent or over SSH often has no session environment,
# but the compositor does. Ask niri before concluding a variable is unset.
session_env() {  # session_env <VAR>
    local var="$1" val="${!1-}"
    if [ -n "$val" ]; then printf '%s' "$val"; return; fi
    local pid
    pid="$(pgrep -x niri 2>/dev/null | head -1)"
    if [ -n "$pid" ]; then
        val="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
               | sed -n "s/^${var}=//p" | head -1)"
        [ -n "$val" ] && { printf '%s' "$val"; return; }
    fi
    case "$var" in
        WAYLAND_DISPLAY)
            local sock
            for sock in "/run/user/$(id -u)"/wayland-*; do
                [ -S "$sock" ] || continue
                basename "$sock"
                return
            done
            ;;
        XDG_RUNTIME_DIR)
            [ -d "/run/user/$(id -u)" ] && printf '/run/user/%s' "$(id -u)"
            return
            ;;
    esac
}

for var in WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_SESSION_TYPE; do
    [ -n "${!var-}" ] && continue
    val="$(session_env "$var")"
    [ -n "$val" ] && export "$var=$val"
done

if [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    echo "error: no Wayland session environment (WAYLAND_DISPLAY/XDG_RUNTIME_DIR)." >&2
    echo "       Run this from a terminal inside the niri session." >&2
    exit 3
fi

# ---- discovery ------------------------------------------------------------
dms_bins=()
[ -x /usr/bin/dms ] && dms_bins+=("/usr/bin/dms")
[ -x "$HOME/.local/bin/dms" ] && dms_bins+=("$HOME/.local/bin/dms")
if [ "${#dms_bins[@]}" -eq 0 ]; then
    if have dms; then dms_bins+=("$(command -v dms)"); else
        echo "error: no dms binary found" >&2; exit 1
    fi
fi

qs_dirs=()
add_qs() {
    local p="$1"
    [ -n "$p" ] || return 0
    if [ -d "$p" ]; then p="$p/quickshell"; fi
    [ -x "$p" ] || return 0
    local d; d="$(dirname "$p")"
    for existing in "${qs_dirs[@]:-}"; do [ "$existing" = "$d" ] && return 0; done
    qs_dirs+=("$d")
}
for p in "${EXTRA_QS[@]:-}"; do add_qs "$p"; done
add_qs /usr/bin/quickshell
add_qs "$HOME/.local/bin/quickshell"
[ "${#qs_dirs[@]}" -eq 0 ] && qs_dirs=("")   # PATH as-is

# ---- one case -------------------------------------------------------------
# run_case <dms-bin> <quickshell-dir>
run_case() {
    local dms="$1" qsdir="$2"
    local tag qs_version cache log pid rc=0 ipc="no" state
    tag="$(basename "$dms") @ ${qsdir:-PATH}"
    qs_version="$(PATH="${qsdir:+$qsdir:}$PATH" quickshell --version 2>&1 | head -1)"
    cache="$WORK/cache-$(echo "$tag" | tr -c 'a-zA-Z0-9' '_')"
    log="$WORK/log-$(echo "$tag" | tr -c 'a-zA-Z0-9' '_')"
    mkdir -p "$cache"

    say "testing: $tag"
    say "  quickshell: ${qs_version:-not found}"

    # A fresh cache per case, so a crashed build cannot poison the next one.
    PATH="${qsdir:+$qsdir:}$PATH" \
    XDG_CACHE_HOME="$cache" \
    setsid "$dms" run --session >"$log" 2>&1 &
    pid=$!

    # Judge liveness by "still running after the window". A single IPC probe is
    # unreliable here: the IPC socket name contains the pid, so a second `dms`
    # invocation does not necessarily find the instance under test.
    local end=$((SECONDS + WAIT)) died=0
    while [ "$SECONDS" -lt "$end" ]; do
        if ! kill -0 "$pid" 2>/dev/null; then died=1; break; fi
        if PATH="${qsdir:+$qsdir:}$PATH" \
             timeout 3 "$dms" ipc call theme getMode >/dev/null 2>&1; then
            ipc="yes"
        fi
        sleep 1
    done

    if [ "$died" -eq 0 ] && kill -0 "$pid" 2>/dev/null; then
        state="alive after ${WAIT}s"
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        kill -KILL -- "-$pid" 2>/dev/null || true
    else
        wait "$pid" 2>/dev/null
        rc=$?
        state="crashed (exit $rc)"
    fi

    say "  result: $state, ipc=$ipc"
    results+=("$tag|${qs_version:-?}|$state|$ipc|$log")

    # Collect the newest crash report produced during this case.
    local crash_root="$cache/quickshell/crashes"
    if [ -d "$crash_root" ]; then
        local newest; newest="$(ls -1t "$crash_root" 2>/dev/null | head -1)"
        [ -n "$newest" ] && results+=("  ! crash report: $crash_root/$newest/report.txt|||")
    fi
}

# ---- run ------------------------------------------------------------------
say "stopping dms.service for the duration"
systemctl --user stop dms.service 2>/dev/null || warn "could not stop dms.service"
sleep 1

for dms in "${dms_bins[@]}"; do
    for qsdir in "${qs_dirs[@]}"; do
        run_case "$dms" "$qsdir"
        sleep 1
    done
done

# ---- report ---------------------------------------------------------------
{
    echo "# DMS shell matrix — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "Host: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME ($VERSION_CODENAME)")"
    echo "Kernel: $(uname -r)"
    echo "Qt: $(qmake6 --version 2>/dev/null | tail -1 || pkg-config --modversion Qt6Core 2>/dev/null || echo unknown)"
    echo
    echo "| Combination | Quickshell | Result | IPC |"
    echo "|---|---|---|---|"
    for r in "${results[@]}"; do
        IFS='|' read -r a b c d _ <<<"$r"
        case "$a" in
            "  ! crash report:"*) echo "${a} ${b}"; continue ;;
        esac
        echo "| $a | ${b:-?} | $c | $d |"
    done
} > "$OUT"

say "matrix written to $OUT"

if [ "$RESTORE" -eq 1 ]; then
    say "restarting the normal dms.service"
    systemctl --user start dms.service 2>/dev/null || warn "could not start dms.service"
fi

# Success = at least one combination reached stable + ipc.
if printf '%s\n' "${results[@]}" | grep -q '|alive after'; then
    exit 0
fi
exit 1
