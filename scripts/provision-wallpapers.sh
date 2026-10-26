#!/usr/bin/env bash
#
# Ominty — provision ~/Wallpapers from the system wallpaper sets.
#
# DMS and matugen need a wallpaper before they can generate a palette and the
# niri theme fragment (border + accent glow + animation shaders). A fresh
# install has an empty ~/Wallpapers, so the desktop would stay animationless
# until the user picked one by hand.
#
# This links every distinct system wallpaper into ~/Wallpapers:
#   * recursive scan of the sources (default /usr/share/backgrounds,
#     /usr/share/wallpapers)
#   * duplicates removed by content hash, so a wallpaper that appears in
#     several sets is linked once
#   * preview thumbnails (contents/screenshot*) are ignored
#   * names are "<set>-<file>" so the carousel is readable
#
# It never deletes or overwrites anything in the destination: an existing file
# or link with the same name is left alone, and a different image keeps its own
# name with a -2/-3 suffix.
#
# Usage:
#   scripts/provision-wallpapers.sh [--dry-run] [SOURCE...]
#
set -uo pipefail

DEST="${OMINTY_WALLPAPER_DIR:-$HOME/Wallpapers}"
DRY_RUN=0
SOURCES=()

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) SOURCES+=("$arg") ;;
    esac
done
[ "${#SOURCES[@]}" -gt 0 ] || SOURCES=(/usr/share/backgrounds /usr/share/wallpapers)

say()  { printf '\033[1;34m[ominty/wallpapers]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }
have sha256sum || die "sha256sum is required (coreutils)"
have find      || die "find is required"

sanitise() {  # sanitise <name>
    printf '%s' "$1" \
        | sed 's/[[:space:]]\+/-/g; s/[^A-Za-z0-9._-]//g' \
        | cut -c1-120
}

existing=0
created=0
planned=0
skipped=0

declare -A seen_hash=()
declare -A used_name=()

[ "$DRY_RUN" -eq 1 ] || mkdir -p "$DEST" || die "cannot create $DEST"

for source in "${SOURCES[@]}"; do
    [ -d "$source" ] || continue
    set_name="$(basename "$source")"

    while IFS= read -r -d '' file; do
        base="$(basename "$file")"

        # Preview thumbnails, not wallpapers.
        case "$file" in
            */contents/screenshot*) continue ;;
        esac
        case "$base" in
            screenshot*|Screenshot*) continue ;;
        esac

        real="$(readlink -f "$file" 2>/dev/null || true)"
        [ -n "$real" ] && [ -f "$real" ] || continue

        hash="$(sha256sum "$real" 2>/dev/null | awk '{print $1}')"
        [ -n "$hash" ] || continue
        if [ -n "${seen_hash[$hash]:-}" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        seen_hash[$hash]=1

        # "<set>-<file>"; if that name is taken by a different image, suffix it.
        name="$(sanitise "${set_name}-${base}")"
        candidate="$name"
        n=2
        while [ -n "${used_name[$candidate]:-}" ]; do
            candidate="${name%.*}-${n}.${name##*.}"
            n=$((n + 1))
        done
        used_name[$candidate]=1

        target="$DEST/$candidate"
        if [ -e "$target" ] || [ -L "$target" ]; then
            existing=$((existing + 1))
            continue
        fi

        if [ "$DRY_RUN" -eq 1 ]; then
            say "would link $candidate -> $real"
            planned=$((planned + 1))
        else
            ln -s "$real" "$target" || { warn "could not link $target"; continue; }
            created=$((created + 1))
        fi
    done < <(find -L "$source" -maxdepth 5 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.bmp' \) \
        -print0 2>/dev/null)
done

if [ "$DRY_RUN" -eq 1 ]; then
    say "dry run: would create $planned link(s); $existing already present, $skipped duplicate(s)"
else
    say "created $created link(s); $existing already present, $skipped duplicate(s)"
    say "wallpapers: $DEST"
fi

if [ "$created" -eq 0 ] && [ "$planned" -eq 0 ] && [ "$existing" -eq 0 ]; then
    warn "no system wallpapers found; add your own images to $DEST"
fi
