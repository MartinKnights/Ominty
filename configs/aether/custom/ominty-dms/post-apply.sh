#!/usr/bin/env bash
# ominty-dms — seed the Ominty/DMS theme from Aether's chosen colour.
#
# Aether authors a palette; DMS + matugen render the whole desktop from it
# (shell, Niri colours, GTK/Qt, terminals, Firefox…).  We feed DMS the
# colour Aether wrote into the generated seed file.
set -uo pipefail

LOG="${XDG_STATE_HOME:-$HOME/.local/state}/omi/aether-dms.log"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "----- $(date '+%F %T') Aether apply -----"

# Aether writes ~/.config/aether/theme/<app>-<template> and symlinks the
# destination here; accept either.
for f in "$HOME/.config/aether/theme/ominty-dms-seed.conf" \
         "$HOME/.config/aether/ominty-dms-seed"; do
    [ -f "$f" ] || continue
    hex=$(grep -oE '#[0-9A-Fa-f]{6}' "$f" | head -1) && [ -n "$hex" ] && break
done
if [ -z "${hex:-}" ]; then
    echo "no hex colour found in the seed file — nothing to do"
    exit 1
fi

mode=$(dms ipc call theme getMode 2>/dev/null | tr -d '[:space:]')
[ -n "$mode" ] || mode=dark
echo "seeding DMS with $hex (mode=$mode)"

dms matugen generate --kind hex --value "$hex" --mode "$mode" \
    --state-dir "$HOME/.local/state/DankMaterialShell" \
    --shell-dir /usr/share/quickshell/dms \
    --config-dir "$HOME/.config/DankMaterialShell"
echo "dms matugen exit=$?"

if command -v notify-send >/dev/null 2>&1; then
    notify-send -a Aether "Ominty theme applied" "Desktop colours seeded from $hex" 2>/dev/null || true
fi
