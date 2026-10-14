#!/usr/bin/env bash
# ominty-dms — apply Aether's theme to the whole Ominty/Niri/DMS desktop.
#
# Aether (standalone) generates files but applies nothing system-wide.  DMS
# is our theme engine; its ONLY live-apply path is a wallpaper change
# (`dms ipc call wallpaper set`), which regenerates the entire theme — shell,
# Niri colours (dms/colors.kdl), GTK/Qt, terminals, Firefox — live.
# So: take the wallpaper Aether just used and hand it to DMS.
set -uo pipefail

LOG="${XDG_STATE_HOME:-$HOME/.local/state}/omi/aether-dms.log"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "----- $(date '+%F %T') Aether apply -----"

# Aether writes ~/.config/aether/theme/ominty-dms-seed.conf (= {wallpaper})
# and symlinks the destination; accept either, else newest background.
paths=("$HOME/.config/aether/theme/ominty-dms-seed.conf" \
       "$HOME/.config/aether/ominty-dms-seed")
wp=""
for f in "${paths[@]}"; do
    [ -f "$f" ] || continue
    wp=$(head -n1 "$f" | tr -d '\r')
    [ -n "$wp" ] && break
done
if [ -z "$wp" ] || [ ! -f "$wp" ]; then
    wp=$(ls -t "$HOME/.config/aether/theme/backgrounds/"* 2>/dev/null | head -1)
fi
if [ -z "$wp" ] || [ ! -f "$wp" ]; then
    echo "no wallpaper from Aether — nothing to apply"
    exit 1
fi
echo "applying wallpaper: $wp"

dms ipc call wallpaper set "$wp"
echo "wallpaper set exit=$?"

if command -v notify-send >/dev/null 2>&1; then
    notify-send -a Aether "Ominty theme applied" "Desktop recoloured from $(basename "$wp")" 2>/dev/null || true
fi
