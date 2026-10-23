#!/usr/bin/env bash
#
# collect-ominty-diagnostics.sh — gather everything needed to diagnose the
# Ominty/DMS state on THIS machine. Read-only by default.
#
# Run it as your normal user (NOT with sudo):
#
#     bash collect-ominty-diagnostics.sh
#
# It writes a folder next to this script and a small .tar.gz beside it:
#
#     diagnostics-<host>-<timestamp>/
#     diagnostics-<host>-<timestamp>.tar.gz
#
# Optional experiment (stops dms for ~1 minute, then restarts it):
#
#     bash collect-ominty-diagnostics.sh --with-matrix
#
# That is the only mode that changes anything: it tries every DMS binary
# against every Quickshell it can find, each with a throwaway QML cache, and
# records which combinations survive.
#
set -uo pipefail

WITH_MATRIX=0
[ "${1:-}" = "--with-matrix" ] && WITH_MATRIX=1

if [ "$(id -u)" -eq 0 ]; then
    echo "error: run this as your normal user, not with sudo." >&2
    echo "       (sudo makes HOME=/root and you would not be inspecting your own session)" >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
HOST="$(hostname -s 2>/dev/null || hostname)"

# Write beside the script (e.g. on a USB stick), but never inside a git
# checkout: the output must not dirty the repository.
if git -C "$HERE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    OUT_ROOT="${OMINTY_DIAG_DIR:-$HOME}"
else
    OUT_ROOT="${OMINTY_DIAG_DIR:-$HERE}"
fi
OUT="$OUT_ROOT/diagnostics-$HOST-$STAMP"
mkdir -p "$OUT" || { echo "error: cannot write to $OUT" >&2; exit 1; }

TRANSCRIPT="$OUT/transcript.txt"
: > "$TRANSCRIPT"

# Echo everything to the terminal and the transcript.
exec > >(tee -a "$TRANSCRIPT") 2>&1

# A shell started by an agent or over SSH often has no session environment,
# but the compositor does. Ask niri before concluding a variable is unset.
session_env() {  # session_env <VAR>
    local var="$1" val="${!1-}"
    if [ -n "$val" ]; then printf '%s' "$val"; return; fi

    # The compositor's own environment (niri does not need WAYLAND_DISPLAY
    # itself, but it has the rest).
    local pid
    pid="$(pgrep -x niri 2>/dev/null | head -1)"
    if [ -n "$pid" ]; then
        val="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
               | sed -n "s/^${var}=//p" | head -1)"
        [ -n "$val" ] && { printf '%s' "$val"; return; }
    fi

    # WAYLAND_DISPLAY is named after the socket in the runtime directory.
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

# Qt runtime package: Debian 13 uses libqt6core6, Ubuntu 24.04 libqt6core6t64.
qt_runtime_version() {
    for pkg in libqt6core6 libqt6core6t64; do
        v="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)"
        [ -n "$v" ] && { printf '%s (%s)' "$v" "$pkg"; return; }
    done
    echo unknown
}

say()  { printf '\033[1;34m[dossier]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Append a labelled command to a topic file.
collect() {  # collect <absolute-file> <label> <command...>
    local file="$1" label="$2"; shift 2
    {
        printf '\n### %s\n' "$label"
        printf '$ %s\n' "$*"
        "$@" 2>&1
        printf '[exit %s]\n' "$?"
    } >> "$file"
}

# Append a labelled shell snippet to a topic file.
snippet() {  # snippet <absolute-file> <label> <shell-code>
    local file="$1" label="$2" code="$3"
    {
        printf '\n### %s\n' "$label"
        bash -c "$code" 2>&1
        printf '[exit %s]\n' "$?"
    } >> "$file"
}

finish() {
    say "packing $OUT"
    ( cd "$OUT_ROOT" && tar -czf "diagnostics-$HOST-$STAMP.tar.gz" "diagnostics-$HOST-$STAMP" ) \
        && say "archive: $OUT_ROOT/diagnostics-$HOST-$STAMP.tar.gz"
    say "DONE — send back either the folder or the .tar.gz"
}
trap finish EXIT

say "collecting into $OUT"

# ---------------------------------------------------------------------------
say "1/9 system and session"
# ---------------------------------------------------------------------------
F="$OUT/00-system.txt"
collect "$F" "os-release" cat /etc/os-release
collect "$F" "kernel" uname -a
collect "$F" "hardware" bash -c 'lscpu | sed -n "1,12p"'
collect "$F" "memory" free -h
collect "$F" "gpu" bash -c 'lspci -nn | grep -Ei "vga|3d|display"'
collect "$F" "disk" df -h / /home
for var in XDG_SESSION_TYPE WAYLAND_DISPLAY XDG_RUNTIME_DIR DISPLAY XDG_CURRENT_DESKTOP PATH; do
    printf '%-26s %s\n' "$var" "$(session_env "$var")" >> "$F"
done
printf '%-26s %s\n' "DBUS_SESSION_BUS_ADDRESS" "${DBUS_SESSION_BUS_ADDRESS:-<unset>}" >> "$F"
collect "$F" "systemd user environment" systemctl --user show-environment
collect "$F" "active sessions" loginctl list-sessions --no-legend
collect "$F" "sudo" bash -c 'sudo -n true 2>/dev/null && echo "passwordless sudo: yes" || echo "passwordless sudo: no (password required)"'

# ---------------------------------------------------------------------------
say "2/9 packages and binaries"
# ---------------------------------------------------------------------------
F="$OUT/01-packages.txt"
collect "$F" "dpkg quickshell / dms / qt6 / whisper" bash -c \
  'dpkg -l | grep -Ei "^ii *(quickshell|dms|libqt6core6|qt6-base|whisper|piper|ffmpeg|pipewire-bin)" || true'
collect "$F" "quickshell on PATH" bash -c 'command -v quickshell || echo MISSING'
collect "$F" "quickshell --version (PATH)" bash -c 'quickshell --version 2>&1 | head -3 || echo FAILED'
collect "$F" "quickshell --version (local)" bash -c '"$HOME/.local/bin/quickshell" --version 2>&1 | head -3 || echo "no local build"'
collect "$F" "quickshell package version" bash -c 'dpkg-query -W -f="${Version}\n" quickshell 2>/dev/null || echo "not a dpkg package"'
collect "$F" "Qt6Core runtime version" bash -c 'for p in libqt6core6 libqt6core6t64; do dpkg-query -W -f="${Package} ${Version}\n" "$p" 2>/dev/null && break; done; true'
collect "$F" "Qt6Core pkg-config (build headers)" bash -c 'pkg-config --modversion Qt6Core 2>/dev/null || echo "not installed (qt6-base-dev) — expected unless building"'
collect "$F" "dms on PATH" bash -c 'command -v dms || echo MISSING'
collect "$F" "dms version (PATH)" bash -c 'dms version 2>&1 | tail -2 || echo FAILED'
collect "$F" "dms version (/usr/bin)" bash -c '/usr/bin/dms version 2>&1 | tail -2 || echo "no /usr/bin/dms"'
collect "$F" "dms version (local)" bash -c '"$HOME/.local/bin/dms" version 2>&1 | tail -2 || echo "no local build"'
collect "$F" "binary listing" bash -c \
  'ls -l "$HOME/.local/bin/dms" "$HOME/.local/bin/quickshell" "$HOME/.local/bin/whisper-cli" "$HOME/.local/bin/omi-dict" "$HOME/.local/bin/omi-media" /usr/bin/dms /usr/bin/quickshell 2>&1'
collect "$F" "local quickshell Qt libs" bash -c \
  'ldd "$HOME/.local/bin/quickshell" 2>/dev/null | grep -Ei "Qt6Core|not found" | head -5 || true'

# ---------------------------------------------------------------------------
say "3/9 repository state"
# ---------------------------------------------------------------------------
F="$OUT/02-repo.txt"
REPO=""
for cand in "$HOME/Ominty" "$HOME/Projects"/*/Ominty "$HOME"/src/Ominty "$HOME"/git/Ominty; do
    [ -f "$cand/install.sh" ] && { REPO="$cand"; break; }
done
if [ -z "$REPO" ]; then
    REPO="$(find "$HOME" -maxdepth 4 -name install.sh -path '*Ominty*' 2>/dev/null | head -1 | xargs -r dirname)"
fi
{
    echo
    echo "### repository path"
    echo "${REPO:-NOT FOUND}"
} >> "$F"
if [ -n "$REPO" ]; then
    collect "$F" "git log" git -C "$REPO" log -3 --format='%h %ad %s' --date=short
    collect "$F" "git status" git -C "$REPO" status --short
    collect "$F" "submodule" git -C "$REPO" submodule status
    collect "$F" "commit" git -C "$REPO" rev-parse HEAD
    collect "$F" "expected scripts present" bash -c \
      'cd "$1" && for f in scripts/diagnose-dms-shell.sh scripts/smoke-dms.sh scripts/rollback-dms.sh scripts/verify-parity.py scripts/verify-upgrade.sh; do [ -f "$f" ] && printf "ok   %s\n" "$f" || printf "MISS %s\n" "$f"; done' _ "$REPO"
fi

# ---------------------------------------------------------------------------
say "4/9 systemd units"
# ---------------------------------------------------------------------------
F="$OUT/03-systemd.txt"
collect "$F" "user unit" systemctl --user cat dms.service
collect "$F" "unit status" systemctl --user status dms.service --no-pager -l
collect "$F" "unit properties" bash -c \
  'systemctl --user show dms.service -p LoadState -p ActiveState -p SubState -p NRestarts -p ExecMainStatus -p ExecMainStartTimestamp -p Environment'
collect "$F" "drop-in files" bash -c \
  'ls -la "$HOME/.config/systemd/user/dms.service.d" /etc/systemd/user/dms.service.d /usr/lib/systemd/user/dms.service.d 2>&1'
collect "$F" "packaged unit" bash -c 'cat /usr/lib/systemd/user/dms.service 2>/dev/null || echo "no packaged unit"'
collect "$F" "journal (last 250)" journalctl --user -u dms.service -n 250 --no-pager
collect "$F" "coredump notes" bash -c 'coredumpctl list --no-pager 2>/dev/null | tail -15 || echo "coredumpctl unavailable"'

# ---------------------------------------------------------------------------
say "5/9 DMS runtime trees"
# ---------------------------------------------------------------------------
F="$OUT/04-dms-runtime.txt"
collect "$F" "runtime roots" bash -c \
  'for d in /run/user/"$(id -u)"/danklinux-shell /run/user/"$(id -u)"/dms-shell; do echo "--- $d"; ls -la "$d" 2>&1 | head -10; done'
collect "$F" "shell build ids" bash -c \
  'for f in /run/user/"$(id -u)"/danklinux-shell/*/.dankrev /run/user/"$(id -u)"/dms-shell/*/.dankrev; do [ -f "$f" ] && echo "$f: $(cat "$f")"; done 2>/dev/null || echo none'
collect "$F" "overlay fork" bash -c \
  'ls -la "$HOME/.local/share/dms-shell" 2>&1 | head -8; echo "--- marker"; cat "$HOME/.local/share/dms-shell/.ominty-overlay.json" 2>/dev/null || echo "no marker"'
collect "$F" "glow patch present" bash -c \
  'grep -c "glowEnabled" "$HOME/.local/share/dms-shell/DankCommon/Common/ElevationShadow.qml" 2>/dev/null || echo "file missing"'
collect "$F" "source build cache" bash -c \
  'D="$HOME/.cache/ominty/build"; ls -la "$D" 2>&1 | head -12; echo "--- dms ref"; cat "$D/.ominty-dms-ref" 2>/dev/null; echo "--- shell rev"; cat "$D/.ominty-dms-shellrev" 2>/dev/null; echo "--- dist"; ls "$D/DankMaterialShell/core/internal/shellembed/dist/.dankrev" 2>/dev/null && cat "$D/DankMaterialShell/core/internal/shellembed/dist/.dankrev"'
collect "$F" "niri validate" niri validate

# ---------------------------------------------------------------------------
say "6/9 crashes and QML cache"
# ---------------------------------------------------------------------------
F="$OUT/05-crashes.txt"
collect "$F" "crash directories" bash -c \
  'ls -lt "$HOME/.cache/quickshell/crashes" 2>/dev/null | head -12 || echo "no crash directory"'
collect "$F" "newest crash reports" bash -c '
root="$HOME/.cache/quickshell/crashes"
for d in $(ls -1t "$root" 2>/dev/null | head -4); do
  echo "===== $d ====="
  sed -n "1,25p" "$root/$d/report.txt" 2>/dev/null
  echo "--- log tail"
  tail -20 "$root/$d"/*.log 2>/dev/null
done'
collect "$F" "qml cache" bash -c \
  'du -sh "$HOME/.cache/quickshell" 2>/dev/null; find "$HOME/.cache/quickshell" -maxdepth 2 -name qmlcache -printf "%p %TY-%Tm-%Td %TH:%TM\n" 2>/dev/null'
collect "$F" "per-build caches" bash -c 'ls -la "$HOME/.cache/ominty" 2>/dev/null | head -10'

# ---------------------------------------------------------------------------
say "7/9 configuration and keybindings"
# ---------------------------------------------------------------------------
F="$OUT/06-config.txt"
collect "$F" "niri config binds" bash -c \
  'grep -nE "spawn|^binds|include|environment" "$HOME/.config/niri/config.kdl" 2>/dev/null | head -60'
collect "$F" "generated bindings" bash -c \
  'cat "$HOME/.config/ominty/generated/niri/bindings.kdl" 2>/dev/null || echo "not generated"'
collect "$F" "requested chords present?" bash -c '
for k in "Ctrl+Alt+R" "Shift+Alt+M" "Ctrl+Shift+M" "Super+Alt+O" "Mod+Alt+O" "Shift+Alt+S" "Super+Alt+T" "Mod+Alt+T"; do
  n=0
  grep -qs -- "$k" "$HOME/.config/ominty/generated/niri/bindings.kdl" && n=$((n+1))
  grep -qs -- "$k" "$HOME/.config/niri/config.kdl" && n=$((n+1))
  printf "%-14s in %s file(s)\n" "$k" "$n"
done'
collect "$F" "DMS settings size/keys" bash -c \
  'f="$HOME/.config/DankMaterialShell/settings.json"; [ -f "$f" ] && { echo "bytes: $(wc -c < "$f")"; python3 -c "import json,sys;print(\"keys:\",len(json.load(open(sys.argv[1]))))" "$f" 2>/dev/null || true; } || echo MISSING'
collect "$F" "plugin settings keys" bash -c \
  'f="$HOME/.config/DankMaterialShell/plugin_settings.json"; [ -f "$f" ] && python3 -c "import json,sys;print(\"\\n\".join(sorted(json.load(open(sys.argv[1])))))" "$f" 2>/dev/null || echo MISSING'
collect "$F" "plugin lockfile" bash -c \
  'f="$HOME/.config/DankMaterialShell/plugins.lock.json"; [ -f "$f" ] && cat "$f" || echo "no lockfile installed"'
collect "$F" "quickshell config links" bash -c \
  'ls -l "$HOME/.config/quickshell"/* 2>&1'

# ---------------------------------------------------------------------------
say "8/9 plugins and tool stack"
# ---------------------------------------------------------------------------
F="$OUT/07-plugins-tools.txt"
collect "$F" "installed plugins" bash -c '
for d in "$HOME/.config/DankMaterialShell/plugins"/*/; do
    [ -f "$d/plugin.json" ] || continue
    name="$(basename "$d")"
    id="$(grep -m1 "\"id\"" "$d/plugin.json" | sed "s/.*: *\"\([^\"]*\)\".*/\1/")"
    ver="$(grep -m1 "\"version\"" "$d/plugin.json" | sed "s/.*: *\"\([^\"]*\)\".*/\1/")"
    printf "%-22s id=%-24s v=%s\n" "$name" "$id" "$ver"
done | sort'
collect "$F" "helper scripts" bash -c \
  'for f in "$HOME"/bin/artha-word "$HOME"/bin/read-selection "$HOME"/bin/tts-pick "$HOME"/bin/piper-daemon "$HOME"/bin/piper-indicator "$HOME"/.local/bin/screen-ocr "$HOME"/.local/bin/start-swayidle "$HOME"/.local/bin/wait-for-tray "$HOME"/.local/bin/clip-tool "$HOME"/.local/bin/omi-dict "$HOME"/.local/bin/omi-media "$HOME"/Scripts/script_command_centre.sh; do [ -x "$f" ] && echo "ok   $f" || echo "MISS $f"; done'
collect "$F" "piper" bash -c \
  'ls -l "$HOME/.piper-venv/bin/piper" 2>/dev/null || echo "piper not installed"; ls -1 "$HOME/.local/share/piper/voices" 2>/dev/null | head'
collect "$F" "whisper" bash -c \
  'command -v whisper-cli || echo "whisper-cli not on PATH"; ls -lh "$HOME/.local/share/ominty/models" 2>/dev/null || echo "no models dir"'
collect "$F" "stt runtime tools" bash -c \
  'for c in ffmpeg pw-record wtype zenity; do printf "%-10s %s\n" "$c" "$(command -v "$c" || echo MISSING)"; done'
collect "$F" "dictionary" bash -c 'omi-dict dictionaries 2>&1 | head -12 || echo "omi-dict not runnable"'
collect "$F" "media categories" bash -c 'omi-media categories 2>&1 | head -12 || echo "omi-media not runnable"'

# ---------------------------------------------------------------------------
say "9/9 Ominty reports"
# ---------------------------------------------------------------------------
if [ -n "$REPO" ] && [ -x "$REPO/ominty-core/cli/ominty" ]; then
    "$REPO/ominty-core/cli/ominty" inspect --json > "$OUT/inspect.json" 2>"$OUT/inspect.err"
    echo "inspect exit: $?" >> "$OUT/inspect.err"
    "$REPO/ominty-core/cli/ominty" inspect > "$OUT/inspect.txt" 2>&1 || true
fi
if [ -n "$REPO" ] && [ -x "$REPO/scripts/verify-upgrade.sh" ]; then
    "$REPO/scripts/verify-upgrade.sh" > "$OUT/verify-upgrade.txt" 2>&1
    echo "exit: $?" >> "$OUT/verify-upgrade.txt"
fi
if [ -n "$REPO" ] && [ -x "$REPO/scripts/verify-parity.py" ]; then
    "$REPO/scripts/verify-parity.py" > "$OUT/verify-parity.txt" 2>&1
    echo "exit: $?" >> "$OUT/verify-parity.txt"
fi

# ---------------------------------------------------------------------------
# Optional: the DMS x Quickshell matrix.
#
# The previous version launched dms without the session environment, so every
# case "crashed" with whatever the ambient shell happened to provide. This one
# merges the systemd user environment first and judges liveness by "still
# alive after N seconds", not by a single sample.
# ---------------------------------------------------------------------------
if [ "$WITH_MATRIX" -eq 1 ]; then
    say "matrix: stopping dms for the experiment"
    M="$OUT/08-matrix.txt"
    {
        echo "### matrix"
        echo "note: dms.service is stopped for the duration and restarted at the end"
    } >> "$M"

    # A shell started by an agent or over SSH may not have the session env.
    while IFS='=' read -r k v; do
        [ -n "${k:-}" ] && export "$k=$v"
    done < <(systemctl --user show-environment 2>/dev/null \
             | grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XDG_SESSION_TYPE)=')
    # The user manager does not always know the compositor display; niri does.
    for var in WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_SESSION_TYPE; do
        [ -n "${!var-}" ] && continue
        val="$(session_env "$var")"
        [ -n "$val" ] && export "$var=$val"
    done

    {
        echo
        echo "### environment used for the test"
        for v in WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE; do
            printf '%-26s %s\n' "$v" "${!v-<unset>}"
        done
    } >> "$M"

    if [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${XDG_RUNTIME_DIR:-}" ]; then
        echo "SKIPPED: no Wayland session environment; run from a terminal inside niri" >> "$M"
    else
        systemctl --user stop dms.service 2>/dev/null || true
        sleep 2

        dms_list=()
        [ -x /usr/bin/dms ] && dms_list+=("/usr/bin/dms")
        [ -x "$HOME/.local/bin/dms" ] && dms_list+=("$HOME/.local/bin/dms")
        qs_list=()
        for q in /usr/bin/quickshell "$HOME/.local/bin/quickshell"; do
            [ -x "$q" ] && qs_list+=("$(dirname "$q")")
        done

        for dms in "${dms_list[@]}"; do
            for qd in "${qs_list[@]}"; do
                cache="$(mktemp -d)"
                log="$(mktemp)"
                printf '\n=== %s with quickshell from %s ===\n' \
                    "$dms" "$qd" >> "$M"
                PATH="$qd:$PATH" XDG_CACHE_HOME="$cache" \
                    setsid "$dms" run --session >"$log" 2>&1 &
                pid=$!
                sleep 12
                if kill -0 "$pid" 2>/dev/null; then
                    echo "RESULT: alive after 12s" >> "$M"
                    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
                else
                    wait "$pid" 2>/dev/null
                    echo "RESULT: exited (status $?)" >> "$M"
                fi
                sleep 1
                kill -KILL -- "-$pid" 2>/dev/null || true
                echo "--- log (tail 30)" >> "$M"
                tail -30 "$log" >> "$M"
                crash="$cache/quickshell/crashes"
                if [ -d "$crash" ]; then
                    for c in $(ls -1t "$crash" | head -1); do
                        echo "--- crash report $c" >> "$M"
                        sed -n '1,20p' "$crash/$c/report.txt" >> "$M" 2>/dev/null
                    done
                fi
                rm -rf "$cache" "$log"
            done
        done
    fi

    systemctl --user start dms.service 2>/dev/null || true
    sleep 2
    echo >> "$M"
    echo "dms.service after restart: $(systemctl --user is-active dms.service 2>/dev/null)" >> "$M"
    say "matrix written to $M"
fi

# ---------------------------------------------------------------------------
# Human-readable summary
# ---------------------------------------------------------------------------
S="$OUT/SUMMARY.txt"
{
    echo "Ominty diagnostics — $HOST — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    . /etc/os-release 2>/dev/null && echo "OS:       $PRETTY_NAME ($VERSION_CODENAME)"
    echo "Kernel:   $(uname -r)"
    echo "Session:  $(session_env XDG_SESSION_TYPE) wayland_display=$(session_env WAYLAND_DISPLAY)"
    echo "Repo:     ${REPO:-not found}"
    [ -n "$REPO" ] && echo "Commit:   $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)"
    echo
    echo "quickshell (PATH):  $(command -v quickshell || echo MISSING)"
    echo "quickshell version: $(quickshell --version 2>&1 | head -1)"
    echo "local quickshell:   $([ -x "$HOME/.local/bin/quickshell" ] && "$HOME/.local/bin/quickshell" --version 2>&1 | head -1 || echo "not built")"
    echo "Qt6Core runtime:    $(qt_runtime_version)"
    echo "dms (PATH):         $(command -v dms || echo MISSING)"
    echo "dms version:        $(dms version 2>&1 | tail -1)"
    echo
    echo "dms.service:        $(systemctl --user is-active dms.service 2>/dev/null) / $(systemctl --user show dms.service -p NRestarts --value 2>/dev/null) restarts"
    echo "DMS_SHELL_DIR:      $(systemctl --user show dms.service -p Environment --value 2>/dev/null | tr ' ' '\n' | grep DMS_SHELL_DIR || echo unset)"
    echo "overlay marker:     $(cat "$HOME/.local/share/dms-shell/.ominty-overlay.json" 2>/dev/null || echo missing)"
    echo "crashes:            $(ls -1 "$HOME/.cache/quickshell/crashes" 2>/dev/null | wc -l)"
    echo
    echo "verify-upgrade:     $(tail -3 "$OUT/verify-upgrade.txt" 2>/dev/null | tr '\n' ' ')"
    echo "verify-parity:      $(tail -3 "$OUT/verify-parity.txt" 2>/dev/null | tr '\n' ' ')"
    echo
    echo "files:"
    ls -1 "$OUT"
} > "$S"

cat "$S"
say "summary: $S"
