#!/usr/bin/env bash
#
# Ominty — import StarDict/Babylon dictionaries into the omi-dict service.
#
# The dictionary popup (Ctrl+Shift+A) reads from ~/.local/share/omi/dictionaries
# and ships with no data: the source dictionaries are hundreds of megabytes and
# do not belong in a git repository. This script imports whatever .bgl files it
# finds, so the popup has something to answer with.
#
# Usage:
#   scripts/omi-dict-import.sh [DIRECTORY]
#
# DIRECTORY defaults to ~/Documents/Dictionaries. Each .bgl becomes one
# dictionary id; the four common ones are mapped to the ids the shipped
# configuration expects (oed, etymology, roget, wordfamilies).
#
# Run it again after adding files — omi-dict skips unchanged sources.
#
set -uo pipefail

REPO_DIR="${OMINTY_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC_DIR="${1:-$HOME/Documents/Dictionaries}"

say()  { printf '\033[1;34m[ominty/dict]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

if command -v omi-dict >/dev/null 2>&1; then
    DICT="omi-dict"
elif [ -x "$REPO_DIR/omi-dictionary/bin/omi-dict" ]; then
    DICT="$REPO_DIR/omi-dictionary/bin/omi-dict"
else
    die "omi-dict not found (run install.sh first)"
fi

[ -d "$SRC_DIR" ] || die "no such directory: $SRC_DIR"

# Map the common filenames onto the ids the shipped config refers to, so
# `default_dictionary = "oed"` resolves without editing anything.
dict_id() {
    local base; base="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$base" in
        *"oxford english dictionary"*) echo "oed" ;;
        *etymology*)                   echo "etymology" ;;
        *roget*)                       echo "roget" ;;
        *"word families"*)             echo "wordfamilies" ;;
        *)
            printf '%s' "$base" \
                | sed 's/\.bgl$//; s/[^a-z0-9]\+/-/g; s/^-//; s/-$//' \
                | cut -c1-40
            ;;
    esac
}

found=0
imported=0
for file in "$SRC_DIR"/*.bgl; do
    [ -e "$file" ] || continue
    found=$((found + 1))
    id="$(dict_id "$(basename "$file")")"
    [ -n "$id" ] || { warn "cannot derive an id for $(basename "$file"); skipped"; continue; }
    say "importing $(basename "$file") as '$id'"
    if "$DICT" import --dictionary "$id" "$file" >/dev/null; then
        imported=$((imported + 1))
    else
        warn "import failed: $(basename "$file")"
    fi
done

if [ "$found" -eq 0 ]; then
    warn "no .bgl files in $SRC_DIR"
    warn "copy the dictionary sources there, or pass the directory as an argument."
    exit 1
fi

say "$imported of $found dictionaries imported"
say "installed:"
"$DICT" dictionaries 2>/dev/null | sed 's/^/  /' || true
