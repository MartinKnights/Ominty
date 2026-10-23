#!/usr/bin/env bash
#
# Ominty — build whisper.cpp and fetch an English model (user space only).
#
# Speech-to-text is local: `voice.dictate` records with pw-record, normalises
# with ffmpeg, transcribes with whisper.cpp and types the result with wtype.
# Debian 13 packages none of whisper.cpp, so Ominty builds it.
#
# Usage:
#   scripts/source/whisper-build.sh              # build + model
#   scripts/source/whisper-build.sh --model-only # just fetch the model
#   scripts/source/whisper-build.sh --print      # print the binary path
#   scripts/source/whisper-build.sh --check      # report readiness, change nothing
#
# Environment:
#   OMINTY_WHISPER_REF    tag or commit (default: v1.9.5)
#   OMINTY_WHISPER_MODEL  model file name (default: ggml-base.en.bin)
#   OMINTY_PREFIX         install prefix (default: ~/.local)
#   OMINTY_BUILD_DIR      build cache (default: ~/.cache/ominty/build)
#   OMINTY_MODEL_DIR      model directory (default: ~/.local/share/ominty/models)
#
set -uo pipefail

PREFIX="${OMINTY_PREFIX:-$HOME/.local}"
BUILD_DIR="${OMINTY_BUILD_DIR:-$HOME/.cache/ominty/build}"
MODEL_DIR="${OMINTY_MODEL_DIR:-$HOME/.local/share/ominty/models}"
WS_URL="${OMINTY_WHISPER_URL:-https://github.com/ggml-org/whisper.cpp.git}"
WS_REF="${OMINTY_WHISPER_REF:-v1.9.5}"
MODEL_NAME="${OMINTY_WHISPER_MODEL:-ggml-base.en.bin}"
MODEL_BASE="${OMINTY_WHISPER_MODEL_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main}"
JOBS="$(nproc 2>/dev/null || echo 4)"

WS_SRC="$BUILD_DIR/whisper.cpp"
WS_BIN="$PREFIX/bin/whisper-cli"
MODEL="$MODEL_DIR/$MODEL_NAME"

say()  { printf '\033[1;34m[ominty/stt]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

case "${1:-}" in
    --print) printf '%s\n' "$WS_BIN"; exit 0 ;;
    --check)
        printf 'whisper-cli: %s\n' "$([ -x "$WS_BIN" ] && echo "$WS_BIN" || echo MISSING)"
        printf 'model:       %s\n' "$([ -s "$MODEL" ] && echo "$MODEL" || echo MISSING)"
        for c in ffmpeg pw-record wtype; do
            printf '%-12s %s\n' "$c:" "$(command -v "$c" || echo MISSING)"
        done
        exit 0
        ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --model-only) MODEL_ONLY=1 ;;
    "") MODEL_ONLY=0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
esac

mkdir -p "$BUILD_DIR" "$PREFIX/bin" "$MODEL_DIR"

# --- model ---------------------------------------------------------------
if [ -s "$MODEL" ]; then
    say "model already present: $MODEL"
else
    say "downloading $MODEL_NAME (~142 MB)"
    if curl -fL --retry 2 -o "$MODEL.part" "$MODEL_BASE/$MODEL_NAME"; then
        mv -f "$MODEL.part" "$MODEL"
        say "model: $MODEL"
    else
        rm -f "$MODEL.part"
        warn "could not download the model; dictation will report a missing model"
    fi
fi

[ "$MODEL_ONLY" -eq 1 ] && exit 0

# --- build ---------------------------------------------------------------
have git || die "git is required."
for c in cmake ninja pkg-config; do
    have "$c" || die "$c is required (install the Quickshell build deps)"
done

if [ -d "$WS_SRC/.git" ]; then
    git -C "$WS_SRC" remote set-url origin "$WS_URL" || die "cannot set remote"
else
    say "cloning $WS_URL"
    rm -rf "$WS_SRC"
    mkdir -p "$WS_SRC"
    git -C "$WS_SRC" init -q || die "cannot init $WS_SRC"
    git -C "$WS_SRC" remote add origin "$WS_URL" || die "cannot add remote"
fi

want="$(git -C "$WS_SRC" rev-parse --verify --quiet "$WS_REF^{commit}" || true)"
head="$(git -C "$WS_SRC" rev-parse HEAD 2>/dev/null || true)"
if [ "$want" != "$head" ] || [ ! -d "$WS_SRC/src" ]; then
    say "fetching $WS_REF"
    git -C "$WS_SRC" fetch --depth 1 origin "$WS_REF" || die "fetch failed"
    git -C "$WS_SRC" checkout -q --force FETCH_HEAD || die "checkout failed"
fi

commit="$(git -C "$WS_SRC" rev-parse --short=8 HEAD)"
stamp="$(cat "$BUILD_DIR/.ominty-whisper-ref" 2>/dev/null || true)"

if [ -x "$WS_BIN" ] && [ "$stamp" = "$commit" ]; then
    say "whisper-cli $commit already installed at $WS_BIN"
else
    say "building whisper.cpp $commit"
    cmake -GNinja -B "$WS_SRC/build" -S "$WS_SRC" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_INSTALL_RPATH="$PREFIX/lib" \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DWHISPER_BUILD_TESTS=OFF \
        -DWHISPER_BUILD_EXAMPLES=ON \
        -DWHISPER_BUILD_SERVER=OFF || die "cmake configure failed"
    cmake --build "$WS_SRC/build" -j "$JOBS" || die "whisper.cpp build failed"
    # install only the CLI + libraries, not the sample programs
    cmake --install "$WS_SRC/build" --component Unspecified 2>/dev/null \
        || cmake --install "$WS_SRC/build"
    printf '%s\n' "$commit" > "$BUILD_DIR/.ominty-whisper-ref"
fi

[ -x "$WS_BIN" ] || die "build produced no whisper-cli at $WS_BIN"

say "installed: $WS_BIN"
say "model:     $MODEL"
if ! have ffmpeg || ! have pw-record || ! have wtype; then
    warn "missing runtime tools: ffmpeg / pw-record (pipewire-bin) / wtype"
fi
