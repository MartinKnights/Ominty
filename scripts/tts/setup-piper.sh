#!/usr/bin/env bash
#
# Ominty — install Piper TTS into a user-space virtualenv and fetch a voice.
#
# Piper is not packaged for Debian 13, so the optional `tts` layer uses PyPI
# instead. Nothing here needs sudo and nothing here is required for the desktop
# to work: if it fails, TTS stays disabled and everything else is unaffected.
#
# Usage:
#   scripts/tts/setup-piper.sh
#
# Environment:
#   OMINTY_PIPER_VENV    virtualenv location   (default ~/.piper-venv)
#   OMINTY_PIPER_VOICE   voice name            (default en_GB-northern_english_male-medium)
#   OMINTY_PIPER_VOICES  voice directory       (default ~/.local/share/piper/voices)
#
set -uo pipefail

VENV="${OMINTY_PIPER_VENV:-$HOME/.piper-venv}"
VOICE_NAME="${OMINTY_PIPER_VOICE:-en_GB-northern_english_male-medium}"
VOICE_DIR="${OMINTY_PIPER_VOICES:-$HOME/.local/share/piper/voices}"

# Voice catalogue path on HuggingFace (rhasspy/piper-voices).
VOICE_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/northern_english_male/medium"

say()  { printf '\033[1;34m[ominty/tts]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

have python3 || die "python3 is required."

if [ -x "$VENV/bin/piper" ]; then
    say "Piper already installed at $VENV/bin/piper"
else
    say "Creating virtualenv at $VENV…"
    python3 -m venv "$VENV" || die "venv creation failed (is python3-venv installed?)"
    "$VENV/bin/pip" install --quiet --upgrade pip || warn "pip upgrade failed; continuing."
    say "Installing piper-tts from PyPI…"
    "$VENV/bin/pip" install --quiet piper-tts || die "pip install piper-tts failed"
fi

[ -x "$VENV/bin/piper" ] || die "piper is missing after install"

say "Fetching voice '$VOICE_NAME'…"
mkdir -p "$VOICE_DIR"
for ext in onnx onnx.json; do
    target="$VOICE_DIR/$VOICE_NAME.$ext"
    if [ -s "$target" ]; then
        say "  $(basename "$target") already present"
        continue
    fi
    if ! curl -fsSL --retry 2 -o "$target.part" "$VOICE_BASE/$VOICE_NAME.$ext"; then
        rm -f "$target.part"
        warn "could not download $VOICE_NAME.$ext; TTS will stay silent until a voice is present."
        continue
    fi
    mv -f "$target.part" "$target"
    say "  $(basename "$target") downloaded"
done

say "Piper ready: $("$VENV/bin/piper" --help >/dev/null 2>&1 && echo yes || echo 'installed (help failed)')"
say "Voice dir: $VOICE_DIR"
