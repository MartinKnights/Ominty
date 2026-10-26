#!/usr/bin/env bash
#
# Ominty — do the docs still describe the code?
#
# Run before every push. It checks the claims that have already gone stale once:
# surface names, the DMS delivery model, the category model, support levels,
# referenced scripts and links. It also checks that the runbooks agree on the
# verification commands and the shell build id.
#
# Usage: scripts/check-docs.sh
# Exit:  0 clean, 1 drift found.
#
set -uo pipefail

REPO_DIR="${OMINTY_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO_DIR" || exit 2

pass=0 fail=0
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Docs an agent or a user reads as instructions. Historical/reference docs
# (NAMING, MIGRATION, MAINTAINING) are allowed to name the old terms on purpose.
AGENT_DOCS=(README.md AGENTS.md docs/INSTALL.md docs/AGENT-INSTALL.md
            docs/AGENT-UPGRADE.md docs/TROUBLESHOOTING.md)

banned_in() {  # banned_in <phrase> <file>...
    local phrase="$1"; shift
    local hits
    hits="$(grep -nF -- "$phrase" "$@" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
        bad "stale phrase: \"$phrase\""
        printf '%s\n' "$hits" | sed 's/^/        /'
    else
        ok "no \"$phrase\""
    fi
}

section "Stale claims"
banned_in "support_level: experimental" "${AGENT_DOCS[@]}"
banned_in "is an **experimental** target" "${AGENT_DOCS[@]}"
banned_in "four categories" "${AGENT_DOCS[@]}"
# INSTALL.md is allowed to say this while explaining what the installer does not do.
banned_in "home:AvengeMedia:dms" README.md AGENTS.md docs/AGENT-INSTALL.md \
    docs/AGENT-UPGRADE.md docs/TROUBLESHOOTING.md
# Old surface names belong only to NAMING.md (which lists them) and history.
banned_in "Playlist Selector" "${AGENT_DOCS[@]}"
banned_in "Script Hub" "${AGENT_DOCS[@]}"
banned_in "Screen OCR" "${AGENT_DOCS[@]}"
banned_in "Piper TTS" "${AGENT_DOCS[@]}"
banned_in "/tmp/ominty-install.log" "${AGENT_DOCS[@]}"

section "Flow invariants"
grep -qE "Niri is not running|Niri session" docs/AGENT-INSTALL.md \
    && ok "AGENT-INSTALL knows the smoke test needs a Niri session" \
    || bad "AGENT-INSTALL does not mention the Niri-session requirement"
grep -qF "after login" docs/AGENT-INSTALL.md \
    && ok "AGENT-INSTALL verifies after login" \
    || bad "AGENT-INSTALL does not place verification after login"
grep -qF "layer.*" AGENTS.md \
    && ok "AGENTS triage distinguishes layer.* blocking" \
    || bad "AGENTS triage does not distinguish layer.* blocking"
grep -qF -- "--session-default" docs/AGENT-INSTALL.md \
    && grep -qF -- "--session-default" AGENTS.md \
    && ok "session default is documented with its flag" \
    || bad "session default / --session-default is not documented in both files"
grep -qF "setup-ai.sh" docs/AGENT-INSTALL.md \
    && grep -qF "setup-ai.sh" AGENTS.md \
    && ok "AI setup is documented as the final phase" \
    || bad "AI setup (scripts/setup-ai.sh) is not documented in both files"

section "Referenced scripts exist"
missing_scripts=0
while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if [ ! -e "$REPO_DIR/$ref" ]; then
        bad "doc references missing file: $ref"
        missing_scripts=$((missing_scripts + 1))
    fi
done < <(grep -rhoE 'scripts/[A-Za-z0-9_./-]+\.(sh|py)' \
            README.md AGENTS.md docs/*.md 2>/dev/null | sort -u)
[ "$missing_scripts" -eq 0 ] && ok "every referenced script exists"

section "Links resolve"
missing_links=0
while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    while IFS= read -r link; do
        [ -n "$link" ] || continue
        case "$link" in
            http*|mailto:*|'#'*) continue ;;
        esac
        target="${link%%#*}"
        [ -n "$target" ] || continue
        if [ ! -e "$(dirname "$doc")/$target" ]; then
            bad "$doc -> $link"
            missing_links=$((missing_links + 1))
        fi
    done < <(grep -oE '\]\([^)]+' "$doc" 2>/dev/null | sed 's/^](//')
done < <(printf '%s\n' README.md AGENTS.md docs/*.md)
[ "$missing_links" -eq 0 ] && ok "all local links resolve"

section "Runbooks agree on verification"
for f in AGENTS.md docs/AGENT-INSTALL.md docs/AGENT-UPGRADE.md; do
    for cmd in scripts/smoke-dms.sh scripts/verify-upgrade.sh scripts/verify-parity.py; do
        grep -qF -- "$cmd" "$f" \
            && ok "$f mentions ${cmd##*/}" \
            || bad "$f does not mention ${cmd##*/}"
    done
done

section "Shell build id is consistent"
base="$(grep -oE 'OMINTY_EXPECTED_BASE:-[0-9a-f]{16}' scripts/verify-upgrade.sh \
        | head -1 | sed 's/.*:-//')"
if [ -z "$base" ]; then
    bad "cannot read OMINTY_EXPECTED_BASE from scripts/verify-upgrade.sh"
else
    ok "canonical shell build: $base"
    for f in docs/INSTALL.md docs/AGENT-INSTALL.md docs/AGENT-UPGRADE.md \
             docs/MAINTAINING.md configs/dms/shell-overlay/README.md; do
        grep -qF -- "$base" "$f" \
            && ok "$f quotes it" \
            || bad "$f does not quote $base"
    done
fi

section "Bootstrap"
for f in README.md docs/INSTALL.md docs/AGENT-INSTALL.md docs/PROMPTS.md; do
    grep -qF "bootstrap.sh" "$f" \
        && ok "$f documents bootstrap.sh" \
        || bad "$f does not mention bootstrap.sh"
done
while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ -f "packages/$name" ] \
        && ok "bootstrap lists $name and it exists" \
        || bad "bootstrap.sh lists $name but packages/$name is missing"
done < <(grep -oE '[A-Za-z0-9._+:-]+\.deb' bootstrap.sh | sort -u)

section "Every reference doc is indexed"
for f in docs/*.md; do
    case "$f" in
        docs/plans/*) continue ;;
        docs/TROUBLESHOOTING.md|docs/INSTALL.md|docs/PROMPTS.md|docs/NAMING.md|\
        docs/INSPECT.md|docs/HARDWARE.md|docs/ARCHITECTURE.md|docs/UBUNTU.md|\
        docs/MIGRATION.md|docs/AGENT-INSTALL.md|docs/AGENT-UPGRADE.md|\
        docs/MAINTAINING.md) ;;
        *) bad "unclassified doc: $f" ;;
    esac
    grep -qF -- "$(basename "$f")" README.md \
        && ok "README indexes $(basename "$f")" \
        || bad "README does not link $(basename "$f")"
done

printf '\n\033[1mSummary:\033[0m %d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
    printf 'Result: \033[31mDOCS OUT OF DATE\033[0m\n'
    exit 1
fi
printf 'Result: \033[32mOK\033[0m\n'
