#!/usr/bin/env bash
#
# Ominty — post-upgrade verification (read-only).
#
# Runs the checks from docs/AGENT-UPGRADE.md Phase 6 and prints PASS / FAIL /
# SKIP per check. Changes nothing, needs no sudo, and is safe to run at any
# time.
#
# Usage:
#   scripts/verify-upgrade.sh
#
# Exit: 0 when nothing failed, 1 when at least one check failed.
#
# Environment:
#   OMINTY_EXPECTED_BASE   expected embedded shell build
#                          (default: c27a2bbcb6e09e50, the pinned DMS build)
#
set -uo pipefail

REPO_DIR="${OMINTY_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OMINTY="$REPO_DIR/ominty-core/cli/ominty"
EXPECTED_BASE="${OMINTY_EXPECTED_BASE:-c27a2bbcb6e09e50}"
SHELL_DIR="${DMS_SHELL_DIR:-$HOME/.local/share/dms-shell}"

pass=0 fail=0 skip=0
ok()      { printf '  \033[32mPASS\033[0m  %s\n' "$*"; pass=$((pass + 1)); }
bad()     { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail + 1)); }
sk()      { printf '  \033[33mSKIP\033[0m  %s\n' "$*"; skip=$((skip + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# --- 1. the managed binary ---------------------------------------------------
section "DMS binary"
DMS_BIN="$HOME/.local/bin/dms"
version=""
if [ ! -x "$DMS_BIN" ]; then
    bad "$DMS_BIN is missing or not executable (run install.sh)"
else
    version="$("$DMS_BIN" version 2>&1 | tail -1)"
    ok "managed binary: $DMS_BIN"
    case "$version" in
        *2.0.*|v2.*) bad "version '$version' is the OBS/Dux 2.x shell, not the pinned build" ;;
        *)           ok "version: $version" ;;
    esac
fi

# --- 2. the user unit --------------------------------------------------------
section "dms.service"
if ! have systemctl; then
    sk "systemctl not available"
elif ! systemctl --user show dms.service >/dev/null 2>&1; then
    sk "no systemd user session (run from the desktop or a login session)"
else
    unit="$(systemctl --user cat dms.service 2>/dev/null)"
    exec_line="$(printf '%s\n' "$unit" | grep '^ExecStart=' | head -1)"

    case "$exec_line" in
        *".local/bin/dms"*) ok "ExecStart points at ~/.local/bin/dms" ;;
        "")                 bad "no ExecStart found in dms.service" ;;
        *)                  bad "ExecStart is ${exec_line#ExecStart=}" ;;
    esac

    if systemctl --user show dms.service -p Environment 2>/dev/null \
            | grep -q 'DMS_SHELL_DIR='; then
        ok "DMS_SHELL_DIR is set in the unit environment"
    else
        bad "DMS_SHELL_DIR is not set — the overlay fork will not be used"
    fi

    if systemctl --user is-active --quiet dms.service 2>/dev/null; then
        ok "dms.service is running"
    else
        bad "dms.service is not running"
    fi
fi

# --- 3. the overlay fork -----------------------------------------------------
section "Shell overlay"
marker="$SHELL_DIR/.ominty-overlay.json"
if [ ! -f "$marker" ]; then
    bad "no overlay marker at $marker"
else
    base="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("base",""))' "$marker" 2>/dev/null)"
    if [ "$base" = "$EXPECTED_BASE" ]; then
        ok "overlay base: $base"
    else
        bad "overlay base is '$base', expected '$EXPECTED_BASE' (stale fork)"
    fi
fi

if grep -q "property bool glowEnabled" \
        "$SHELL_DIR/DankCommon/Common/ElevationShadow.qml" 2>/dev/null; then
    ok "glow patch present in the fork"
else
    bad "glow patch missing from $SHELL_DIR (fork not patched)"
fi

# --- 4. inspect --------------------------------------------------------------
section "ominty inspect"
if [ ! -x "$OMINTY" ]; then
    bad "CLI not found at $OMINTY (submodule missing?)"
else
    json="$(mktemp)"
    "$OMINTY" inspect --json >"$json" 2>/dev/null

    out="$(python3 - "$json" <<'PY'
import json
import sys

try:
    report = json.load(open(sys.argv[1]))
except Exception as exc:  # noqa: BLE001
    print(f"\033[31mFAIL\033[0m  inspect produced no JSON ({exc})")
    print("COUNTS 0 1")
    raise SystemExit(0)

checks = [
    ("platform support_level is validated or supported",
     report.get("platform", {}).get("support_level") in ("validated", "supported")),
    ("platform desktop_source == source",
     report.get("platform", {}).get("desktop_source") == "source"),
    ("desktop shell_overlay.state == applied",
     report.get("desktop", {}).get("shell_overlay", {}).get("state") == "applied"),
    ("desktop layer satisfied",
     report.get("layers", {}).get("desktop", {}).get("satisfied") is True),
    ("summary ready (no blocking findings)",
     report.get("summary", {}).get("ready") is True),
]

failed = 0
for label, good in checks:
    mark = "\033[32mPASS\033[0m" if good else "\033[31mFAIL\033[0m"
    print(f"  {mark}  {label}")
    failed += 0 if good else 1

blocking = [
    f["id"] for f in report.get("findings", [])
    if f.get("severity") == "blocking"
]
if blocking:
    print("        blocking: " + ", ".join(blocking))
print(f"COUNTS {len(checks) - failed} {failed}")
PY
)"

    printf '%s\n' "$out" | grep -v '^COUNTS ' || true
    counts="$(printf '%s\n' "$out" | grep '^COUNTS ' || true)"
    if [ -n "$counts" ]; then
        pass=$((pass + $(printf '%s' "$counts" | awk '{print $2}')))
        fail=$((fail + $(printf '%s' "$counts" | awk '{print $3}')))
    else
        fail=$((fail + 1))
    fi
    rm -f "$json"
fi

# --- 5. deployed helpers -----------------------------------------------------
section "Helper scripts"
missing=""
for f in artha-word read-selection tts-pick piper-daemon piper-indicator; do
    [ -x "$HOME/bin/$f" ] || missing="$missing ~/bin/$f"
done
for f in screen-ocr start-swayidle wait-for-tray clip-tool; do
    [ -x "$HOME/.local/bin/$f" ] || missing="$missing ~/.local/bin/$f"
done
[ -x "$HOME/Scripts/script_command_centre.sh" ] \
    || missing="$missing ~/Scripts/script_command_centre.sh"

if [ -z "$missing" ]; then
    ok "all keybinding helpers are executable"
else
    bad "missing:$missing"
fi

for q in ominty-voice ominty-tts; do
    if [ -e "$HOME/.config/quickshell/$q/shell.qml" ]; then
        ok "quickshell/$q resolves"
    else
        bad "quickshell/$q does not resolve to a shell.qml"
    fi
done

# --- 6. niri -----------------------------------------------------------------
section "Niri"
if have niri; then
    if out="$(niri validate 2>&1)"; then
        ok "config is valid"
    else
        bad "niri validate failed: $(printf '%s' "$out" | strip_ansi | tail -1)"
    fi
else
    sk "niri not on PATH"
fi

# --- 7. optional TTS ---------------------------------------------------------
section "TTS (optional)"
if [ -x "$HOME/.piper-venv/bin/piper" ]; then
    ok "Piper installed at ~/.piper-venv"
else
    sk "Piper not installed (optional: scripts/tts/setup-piper.sh)"
fi

if [ -x "$OMINTY" ] && out="$("$OMINTY" tts status 2>&1)"; then
    detail="$(printf '%s' "$out" | strip_ansi | tr -s '\n' ' ' \
        | sed 's/^ *//; s/ *$//' | cut -c1-60)"
    ok "ominty tts status responded${detail:+: $detail}"
else
    sk "ominty tts status unavailable (optional layer)"
fi

# --- summary -----------------------------------------------------------------
printf '\n\033[1mSummary:\033[0m %d passed, %d failed, %d skipped\n' \
    "$pass" "$fail" "$skip"
if [ "$fail" -gt 0 ]; then
    printf 'Result: \033[31mNOT READY\033[0m — report the failures above.\n'
    exit 1
fi
printf 'Result: \033[32mOK\033[0m\n'
