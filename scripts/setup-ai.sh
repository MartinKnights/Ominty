#!/usr/bin/env bash
#
# Ominty — set up the AI layer (the LAST step of an install).
#
# AI is deliberately not part of the desktop install: it needs network, a
# model download, and in Pi's case credentials. The desktop is verified first,
# then this script offers a provider.
#
# It can install and configure:
#   ollama  the local model server, plus one model
#   pi      the pi coding agent (npm), credentials still configured by the user
#   none    explicitly leave AI unconfigured
#
# Usage:
#   scripts/setup-ai.sh                                  # show status, change nothing
#   scripts/setup-ai.sh --install ollama --provider ollama --model qwen2.5:3b
#   scripts/setup-ai.sh --install pi --provider pi
#   scripts/setup-ai.sh --install both --provider ollama
#   scripts/setup-ai.sh --provider none
#
# Options:
#   --install none|ollama|pi|both   install the runtime(s), if missing
#   --provider none|ollama|pi       write ~/.config/ominty/ai.toml
#   --model NAME                    Ollama model to pull (default qwen2.5:3b)
#   --dry-run                       print what would happen
#
# Exit: 0 on success, 1 if a requested step failed.
#
set -uo pipefail

INSTALL="none"
PROVIDER=""
MODEL="${OMINTY_OLLAMA_MODEL:-qwen2.5:3b}"
DRY_RUN=0
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ominty/ai.toml"

while [ $# -gt 0 ]; do
    case "$1" in
        --install)  INSTALL="${2:?--install needs a value}"; shift 2 ;;
        --provider) PROVIDER="${2:?--provider needs a value}"; shift 2 ;;
        --model)    MODEL="${2:?--model needs a value}"; shift 2 ;;
        --dry-run)  DRY_RUN=1; shift ;;
        -h|--help)  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m[ominty/ai]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[DRY ] %s\n' "$*"
    else
        "$@"
    fi
}

case "$INSTALL" in none|ollama|pi|both) ;; *) die "--install must be none, ollama, pi or both" ;; esac
case "${PROVIDER:-none}" in none|ollama|pi) ;; *) die "--provider must be none, ollama or pi" ;; esac

# --- status -----------------------------------------------------------------
say "current state"
have ollama && say "  ollama: $(ollama --version 2>/dev/null | head -1)" || say "  ollama: not installed"
have pi     && say "  pi:     $(pi --version 2>/dev/null | head -1)"     || say "  pi:     not installed"
if have ominty; then
    ominty ai provider list 2>/dev/null | sed 's/^/  /' || true
fi

if [ "$INSTALL" = "none" ] && [ -z "$PROVIDER" ]; then
    [ "$DRY_RUN" -eq 1 ] || {
        echo
        say "nothing requested. Pass --install and/or --provider (see --help)."
    }
    exit 0
fi

# --- Ollama -----------------------------------------------------------------
if [ "$INSTALL" = "ollama" ] || [ "$INSTALL" = "both" ]; then
    if have ollama; then
        say "ollama already installed"
    else
        have curl || die "curl is required to install Ollama"
        say "installing Ollama from the official installer (needs sudo)"
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '[DRY ] curl -fsSL https://ollama.com/install.sh | sh\n'
        else
            curl -fsSL https://ollama.com/install.sh | sh \
                || die "Ollama install failed; install it manually from https://ollama.com"
        fi
    fi

    if [ "$DRY_RUN" -eq 0 ]; then
        have ollama || die "ollama is still not on PATH after install"
        # The official installer starts a systemd service; make sure it is up.
        if have systemctl; then
            systemctl is-active --quiet ollama 2>/dev/null \
                || { sudo systemctl enable --now ollama 2>/dev/null || warn "could not start ollama.service"; }
        fi
        say "pulling model: $MODEL (this can take a while)"
        ollama pull "$MODEL" || die "ollama pull $MODEL failed"
    else
        printf '[DRY ] ollama pull %s\n' "$MODEL"
    fi
fi

# --- Pi ---------------------------------------------------------------------
if [ "$INSTALL" = "pi" ] || [ "$INSTALL" = "both" ]; then
    if have pi; then
        say "pi already installed: $(command -v pi)"
    else
        have npm || die "npm is required for Pi: sudo apt-get install -y npm"
        say "installing pi into ~/.local (user space)"
        run npm install -g --prefix "$HOME/.local" @earendil-works/pi-coding-agent \
            || die "npm install failed"
        if [ "$DRY_RUN" -eq 0 ]; then
            export PATH="$HOME/.local/bin:$PATH"
            have pi || warn "pi installed but not on PATH; add ~/.local/bin to PATH"
        fi
    fi
    warn "pi needs provider credentials (e.g. OPENAI_API_KEY) — configure them before using Super+A."
fi

# --- configuration ----------------------------------------------------------
if [ -n "$PROVIDER" ]; then
    say "writing $CONFIG (provider: $PROVIDER)"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[DRY ] would write %s\n' "$CONFIG"
    else
        mkdir -p "$(dirname "$CONFIG")"
        [ -f "$CONFIG" ] && cp -a "$CONFIG" "$CONFIG.bak-ominty-$(date +%Y%m%d-%H%M%S)"
        {
            echo "# Ominty AI configuration — written by scripts/setup-ai.sh"
            echo
            echo "[ai]"
            echo "default_provider = \"$PROVIDER\""
            echo
            echo "[ai.providers.pi]"
            echo "enabled = true"
            echo
            echo "[ai.providers.ollama]"
            echo "enabled = true"
            echo "model = \"$MODEL\""
        } > "$CONFIG"
    fi

    case "$PROVIDER" in
        ollama) have ollama || warn "provider is ollama but the binary is not installed" ;;
        pi)     have pi     || warn "provider is pi but the binary is not installed" ;;
        none)   say "AI left unconfigured; the AI actions report no provider." ;;
    esac
fi

if [ "$DRY_RUN" -eq 0 ] && have ominty; then
    say "provider status"
    ominty ai provider list 2>/dev/null | sed 's/^/  /' || true
fi
