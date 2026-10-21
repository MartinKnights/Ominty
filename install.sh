#!/usr/bin/env bash
#
# Ominty — one-command installer for Debian 13 / LMDE 7
#
# Installs the layers declared in the ominty-core manifest (see
# `ominty layers`): the Niri + DankMaterialShell desktop, terminal and shell,
# editor, CLI tooling, containers and browser. Also installs Niri from a
# bundled .deb, Quickshell from Debian trixie-backports (or source on Ubuntu),
# DMS from a pinned source build, matugen/ghostty from the AvengeMedia Open
# Build Service, and deploys the Ominty configuration.
#
# DMS is built from source on *both* families: the motion/glow overlay in
# configs/dms/shell-overlay is coupled to a specific embedded shell tree, and
# the OBS package now ships a newer, incompatible shell.
#
# The manifest is the single source of truth, so this script and
# `ominty inspect` cannot disagree about what a layer contains.
#
# Usage:
#   ./install.sh                              # all layers
#   ./install.sh --layers desktop             # desktop only
#   ./install.sh --layers "desktop terminal"  # pick layers
#   ./install.sh --profile surface-book-1     # + hardware profile
#   ./install.sh --dry-run                     # print the plan, change nothing
#   ./install.sh --no-plugins                 # skip DMS plugin install
#   ./install.sh --help
#
# Idempotent: safe to re-run. Existing configuration is backed up
# (suffix .bak-ominty-<timestamp>) before being replaced.
#
set -euo pipefail

# --- configuration ---------------------------------------------------------

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE=""
INSTALL_PLUGINS=1
DRY_RUN=0
OMINTY_CLI="$REPO_DIR/ominty-core/cli/ominty"

# Which layers to install. The manifest in ominty-core is the single source of
# truth for what each layer contains, so the installer and `ominty inspect`
# cannot drift apart. Override with --layers.
LAYERS="desktop tts terminal editor cli containers browser"

# Package lists are derived from that manifest rather than duplicated here.
# `layer_packages <source> [exclude...]` prints required package names.
layer_packages() {
  local source="$1"; shift
  local args=() layer
  for layer in $LAYERS; do args+=(--layer "$layer"); done
  "$OMINTY_CLI" layers --format shell "${args[@]}" \
    | awk -F'\t' -v src="$source" '$1 == src { print $2 }' \
    | grep -vxF "$@" \
    || true
}

# Resolve the layer manifest. This must run *after* argument parsing, since
# --layers changes $LAYERS.
resolve_layers() {
  for layer in $LAYERS; do
    if ! "$OMINTY_CLI" layers --format shell --layer "$layer" >/dev/null 2>&1; then
      die "Unknown layer: $layer (available: $("$OMINTY_CLI" layers --format ids | tr '\n' ' '))"
    fi
  done
  APT_PACKAGES=$(layer_packages apt quickshell)
  # dms is built from source (see DMS_BUILD below), not taken from OBS: the
  # OBS package is a newer, incompatible shell generation.
  OBS_PACKAGES=$(layer_packages obs dms)
}

# quickshell needs its own apt-get call with an explicit target release, so it
# is excluded from the general Debian list (see resolve_layers).
# ghostty is in the terminal layer and therefore absent from the desktop layer.
#
# libseat1 is listed in the desktop layer because packages/niri_*.deb declares
# only `alacritty, fuzzel` as dependencies. Without libseat1, niri installs but
# dies at runtime with "error while loading shared libraries: libseat.so.1",
# which also breaks `ominty registry build` (it shells out to `niri validate`).
APT_PACKAGES=""
OBS_PACKAGES=""

# Open Build Service projects providing those packages. `danklinux` carries the
# DMS runtime companions (matugen, ghostty, danksearch, dgop, niri);
# `dms` carries the DMS shell itself.
OBS_REPOS=(
  "danklinux|home:AvengeMedia:danklinux"
)
OBS_SUITE="Debian_13"

# Third-party DMS plugins from the DMS plugin registry
DMS_PLUGINS=(dankHooks dankKDEConnect dankLauncherKeys quickCapture wallpaperCarousel)

# --- helpers ---------------------------------------------------------------

say()  { printf '\033[1;34m[Ominty]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
plan() { printf '\033[1;35m[DRY ]\033[0m %s\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Run a command, or describe it instead when --dry-run is active. Every
# mutating step goes through this so a dry run touches nothing.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "$*"
  else
    "$@"
  fi
}

backup_existing() {  # backup_existing <path>
  local p="$1"
  [ -e "$p" ] || return 0
  local bak="${p}.bak-ominty-$(date +%Y%m%d-%H%M%S)"
  run cp -a "$p" "$bak"
  say "Backed up existing $p -> $bak"
}

backup_if_changed() {  # backup_if_changed <new-source> <dest>
  # Helper scripts are user-editable too, so preserve a locally modified copy
  # before replacing it. Identical files are replaced silently, which keeps
  # re-running the installer from littering ~/bin with identical .bak files.
  local src="$1" dest="$2"
  [ -e "$dest" ] || return 0
  cmp -s "$src" "$dest" && return 0
  local bak="${dest}.bak-ominty-$(date +%Y%m%d-%H%M%S)"
  run cp -a "$dest" "$bak"
  say "Backed up modified $dest -> $bak"
}

have_repo_line() {  # have_repo_line <suite>
  grep -rqs -- "$1" /etc/apt/sources.list /etc/apt/sources.list.d/
}

ensure_backports() {
  have_repo_line "trixie-backports" && return 0
  say "Enabling trixie-backports (required for quickshell)..."
  echo "deb http://deb.debian.org/debian trixie-backports main" \
    | run sudo tee /etc/apt/sources.list.d/trixie-backports.list >/dev/null
}

pin_quickshell() {
  # The danklinux OBS repo also ships a quickshell build, but upstream marks it
  # deprecated for Debian and directs users to Debian's own build (trixie-backports
  # on Debian 13). The OBS version string (0.3.1.db2) sorts higher than Debian's
  # (0.3.0-1~bpo13+1), so without this pin APT would prefer the deprecated build.
  local pin=/etc/apt/preferences.d/ominty-quickshell
  if [ ! -f "$pin" ]; then
    say "Pinning quickshell to the Debian build..."
    printf 'Package: quickshell\nPin: release n=trixie-backports\nPin-Priority: 1001\n' \
      | run sudo tee "$pin" >/dev/null
  fi
}

add_obs_repositories() {
  local entry name project base keyring list
  run install -d -m 0755 /etc/apt/keyrings
  for entry in "${OBS_REPOS[@]}"; do
    name="${entry%%|*}"
    project="${entry#*|}"
    keyring="/etc/apt/keyrings/${name}.gpg"
    list="/etc/apt/sources.list.d/${name}.list"
    base="https://download.opensuse.org/repositories/${project}/${OBS_SUITE}"
    if [ ! -s "$keyring" ]; then
      say "Importing signing key for ${project}..."
      run curl -fsSL "$base/Release.key" --output "$base/Release.key.tmp"
    run sudo gpg --dearmor --yes -o "$keyring" "$base/Release.key.tmp"
    run rm -f "$base/Release.key.tmp"
    fi
    if [ ! -f "$list" ]; then
      say "Adding APT source ${project}/${OBS_SUITE}..."
      echo "deb [signed-by=${keyring}] ${base}/ /" | run sudo tee "$list" >/dev/null
    fi
  done
}

# --- argument parsing ------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --layers) LAYERS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-plugins) INSTALL_PLUGINS=0; shift ;;
    -h|--help)
      awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
      exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
done

# --- preflight -------------------------------------------------------------

[ "$(id -u)" -eq 0 ] && die "Do not run as root; run as a normal user (sudo is used internally)."
have sudo || die "sudo is required."
have apt-get || die "This installer targets Debian-based systems (apt-get not found)."
have git || die "git is required (DMS is built from source)."
have curl || die "curl is required (used to import the OBS signing keys)."
have gpg || die "gpg is required (used to dearmor the OBS signing keys)."
[ -x "$OMINTY_CLI" ] || die "ominty-core submodule missing or incomplete. Run: git submodule update --init --recursive"
have python3 || die "python3 is required (the ominty CLI reads the layer manifest)."

resolve_layers

# The layer lists are only useful if they actually resolved.
[ -n "$APT_PACKAGES" ] || die "No Debian packages resolved from the layer manifest (layers: $LAYERS)."
case " $LAYERS " in
  *desktop*) : ;;
  *) warn "The 'desktop' layer is not selected; this installs tooling without the desktop itself." ;;
esac

# --- OS family --------------------------------------------------------------
# detect_platform() in ominty-core collapses the Debian family to "debian"
# because they share apt/systemd. The installer needs the finer distinction to
# choose a provisioning path (mirrors ominty-core cli/omintylib/platform.py).
. /etc/os-release 2>/dev/null || true
detect_family() {
  local id id_like
  id="$(printf '%s' "${ID:-}" | tr '[:upper:]' '[:lower:]')"
  id_like="$(printf '%s' "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"
  case "$id" in
    void) echo void ;;
    linuxmint) case "$id_like" in *ubuntu*) echo mint-ubuntu ;; *) echo mint-debian ;; esac ;;
    ubuntu) echo ubuntu ;;
    debian) echo debian ;;
    *) case "$id_like" in *ubuntu*) echo ubuntu ;; *debian*) echo debian ;; *) echo unknown ;; esac ;;
  esac
}
FAMILY="$(detect_family)"
say "Detected family: $FAMILY (${PRETTY_NAME:-unknown})"

case "$FAMILY" in
  debian|mint-debian)
    case "${VERSION_CODENAME:-}" in
      trixie|gigi) : ;;
      faye|bookworm)
        die "${PRETTY_NAME:-Debian 12} is not supported: it has no trixie-backports, so Quickshell cannot be installed. Upgrade to Debian 13 / LMDE 7 first."
        ;;
      *) warn "Untested Debian-family codename '${VERSION_CODENAME:-?}'. Debian 13 / LMDE 7 is the validated target." ;;
    esac
    ;;
  ubuntu|mint-ubuntu)
    warn "Ubuntu-family target ($FAMILY) — supported via the source-build path."
    ;;
  *)
    die "Unsupported distribution (${PRETTY_NAME:-unknown}). Ominty targets Debian-family systems."
    ;;
esac

if [ "$FAMILY" = "ubuntu" ] || [ "$FAMILY" = "mint-ubuntu" ]; then
  # --- 1-2 (Ubuntu): build the desktop from source --------------------------
  # Ubuntu-family systems do not package Quickshell/DMS/matugen and ship a Qt
  # older than Quickshell's floor, so the desktop is built from source. The
  # scripts own the sudo boundary (deps) and the user-space build respectively.
  say "Provisioning the Ubuntu-family desktop (source build; see docs/UBUNTU.md)."
  run bash "$REPO_DIR/scripts/ubuntu/ubuntu-deps.sh"
  run bash "$REPO_DIR/scripts/ubuntu/ubuntu-build.sh"

  # Best effort: the apt-sourced layer packages that also exist on Ubuntu.
  # quickshell/dms/matugen/ghostty are built here or unavailable, so excluded.
  APT_BEST_EFFORT="$(layer_packages apt quickshell)"
  if [ -n "$APT_BEST_EFFORT" ]; then
    say "Installing remaining layer packages (best effort)…"
    # shellcheck disable=SC2086
    run sudo apt-get install -y $APT_BEST_EFFORT || warn "Some layer packages are unavailable on this family; continuing."
  fi
else
  # --- 1. apt repositories (Debian/LMDE) ------------------------------------
  ensure_backports
  pin_quickshell
  add_obs_repositories

  # --- 2. system packages (Debian/LMDE) -------------------------------------
  say "Installing layers: $LAYERS"
  say "Installing system packages (this needs sudo)..."
  run sudo apt-get update -y

  # quickshell first, pinned to Debian's trixie-backports build rather than the
  # deprecated OBS one (see pin_quickshell).
  run sudo apt-get install -y -t trixie-backports quickshell
  # shellcheck disable=SC2086
  run sudo apt-get install -y $APT_PACKAGES
  # shellcheck disable=SC2086
  [ -z "$OBS_PACKAGES" ] || run sudo apt-get install -y $OBS_PACKAGES
fi

# --- 2b. DMS from source ----------------------------------------------------
# Both families build DMS from the same pinned commit, so the motion/glow
# overlay in §5a matches the embedded shell on every machine. On Debian this
# replaces the OBS `dms` package (excluded above); on Ubuntu ubuntu-build.sh
# delegates here too.
DMS_BUILD="$REPO_DIR/scripts/source/dms-build.sh"
DMS_DIST="${OMINTY_BUILD_DIR:-$HOME/.cache/ominty/build}/DankMaterialShell/core/internal/shellembed/dist"
if [ -x "$DMS_BUILD" ]; then
  say "Building DMS from source (pinned; this takes a minute)..."
  run bash "$DMS_BUILD"
else
  warn "scripts/source/dms-build.sh is missing; leaving the existing DMS in place."
fi

# Use the build we just made for every later `dms` call. On an upgraded machine
# ~/.local/bin may not be on PATH yet, and a leftover /usr/bin/dms would be a
# different shell generation with a different plugin API.
DMS_BIN="$HOME/.local/bin/dms"
[ -x "$DMS_BIN" ] || DMS_BIN="$(command -v dms 2>/dev/null || true)"

# --- 2c. Optional TTS runtime ----------------------------------------------
# Piper is not packaged for Debian 13, so the optional tts layer uses a
# user-space virtualenv. A failure here never blocks the install.
case " $LAYERS " in
  *" tts "*)
    if [ -x "$REPO_DIR/scripts/tts/setup-piper.sh" ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        plan "bash scripts/tts/setup-piper.sh   # venv + voice model (optional)"
      else
        bash "$REPO_DIR/scripts/tts/setup-piper.sh" \
          || warn "Piper setup failed; TTS stays disabled."
      fi
    fi
    ;;
esac

# --- 3. Niri + xwayland-satellite -------------------------------------------

if ! have niri; then
  say "Installing Niri + xwayland-satellite from prebuilt .debs..."
  run sudo apt-get install -y "$REPO_DIR"/packages/niri_*.deb "$REPO_DIR"/packages/xwayland-satellite_*.deb
else
  say "Niri already installed ($(niri --version 2>/dev/null || echo '?'))."
fi

# --- 4. deploy configurations -----------------------------------------------

say "Deploying configurations..."
run mkdir -p ~/.config/niri ~/.config/DankMaterialShell ~/.config/ominty ~/.local/bin

# niri
backup_existing ~/.config/niri/config.kdl
if [ "$DRY_RUN" -eq 1 ]; then
  plan "render $REPO_DIR/configs/niri/config.kdl -> ~/.config/niri/config.kdl (with __HOME__ replaced)"
else
  sed "s|__HOME__|$HOME|g" "$REPO_DIR/configs/niri/config.kdl" \
    > ~/.config/niri/config.kdl
fi
run mkdir -p ~/.config/niri/dms
for f in "$REPO_DIR"/configs/niri/dms/*.kdl; do
  run cp "$f" ~/.config/niri/dms/
done

# hardware profile
if [ -n "$PROFILE" ]; then
  if [ -d "$REPO_DIR/profiles/$PROFILE" ]; then
    say "Applying hardware profile: $PROFILE"
    if [ -f "$REPO_DIR/profiles/$PROFILE/niri-outputs.kdl" ]; then
      run cp "$REPO_DIR/profiles/$PROFILE/niri-outputs.kdl" ~/.config/niri/dms/outputs.kdl
    fi
  else
    die "Unknown profile: $PROFILE (available: $(ls "$REPO_DIR/profiles"))"
  fi
fi

# DMS
backup_existing ~/.config/DankMaterialShell/settings.json
run cp "$REPO_DIR/configs/dms/settings.json" ~/.config/DankMaterialShell/settings.json
backup_existing ~/.config/DankMaterialShell/plugin_settings.json
if [ "$DRY_RUN" -eq 1 ]; then
  plan "render $REPO_DIR/configs/dms/plugin_settings.json.template -> ~/.config/DankMaterialShell/plugin_settings.json (with __HOME__ replaced)"
else
  sed "s|__HOME__|$HOME|g" "$REPO_DIR/configs/dms/plugin_settings.json.template" \
    > ~/.config/DankMaterialShell/plugin_settings.json
fi

# matugen user templates (Ominty aesthetics: popup palette + niri border/glow).
# matugen does not expand ~ or $HOME in config paths, so config.toml is rendered
# from a template with __HOME__ replaced.
run mkdir -p ~/.config/matugen/templates
run cp "$REPO_DIR"/configs/matugen/templates/* ~/.config/matugen/templates/
backup_existing ~/.config/matugen/config.toml
if [ "$DRY_RUN" -eq 1 ]; then
  plan "render $REPO_DIR/configs/matugen/config.toml.template -> ~/.config/matugen/config.toml (with __HOME__ replaced)"
else
  sed "s|__HOME__|$HOME|g" "$REPO_DIR/configs/matugen/config.toml.template" \
    > ~/.config/matugen/config.toml
fi

# ominty (user configuration wins)
for f in ai.toml apps.toml; do
  if [ ! -f ~/.config/ominty/$f ]; then
    run cp "$REPO_DIR/configs/ominty/$f" ~/.config/ominty/$f
  else
    say "~/.config/ominty/$f exists — keeping user configuration."
  fi
done

# --- 4b. Helper scripts + session units ------------------------------------
# configs/niri/config.kdl binds and spawns these, so they have to exist on a
# fresh machine. The TTS entries exit quietly when Piper is absent.
say "Deploying helper scripts..."
run mkdir -p ~/bin ~/.local/bin ~/Scripts ~/.config/quickshell ~/.config/swaylock
for f in "$REPO_DIR"/configs/bin/*; do
  backup_if_changed "$f" ~/bin/"$(basename "$f")"
  run install -m 0755 "$f" ~/bin/
done
for f in "$REPO_DIR"/configs/local-bin/*; do
  backup_if_changed "$f" ~/.local/bin/"$(basename "$f")"
  run install -m 0755 "$f" ~/.local/bin/
done
backup_if_changed "$REPO_DIR/configs/Scripts/script_command_centre.sh" \
  ~/Scripts/script_command_centre.sh
run install -m 0755 "$REPO_DIR/configs/Scripts/script_command_centre.sh" \
  ~/Scripts/script_command_centre.sh

# Quickshell popups spawned by config.kdl (voice indicator, TTS player).
# -n so re-running never nests a link inside the previous target.
run ln -sfn "$REPO_DIR/ominty-core/shell/quickshell/ominty-voice" \
  ~/.config/quickshell/ominty-voice
run ln -sfn "$REPO_DIR/ominty-core/shell/quickshell/ominty-tts" \
  ~/.config/quickshell/ominty-tts

# swayidle unit + swaylock theme (started by ~/.local/bin/start-swayidle).
backup_if_changed "$REPO_DIR/configs/systemd/swayidle.service" \
  ~/.config/systemd/user/swayidle.service
run cp "$REPO_DIR/configs/systemd/swayidle.service" \
  ~/.config/systemd/user/swayidle.service
backup_if_changed "$REPO_DIR/configs/swaylock/config" ~/.config/swaylock/config
run cp "$REPO_DIR/configs/swaylock/config" ~/.config/swaylock/config

# --- 5. ominty CLI ---------------------------------------------------------

say "Setting up the ominty CLI..."
if [ ! -d "$REPO_DIR/ominty-core" ]; then
  die "ominty-core submodule missing. Clone with: git clone --recurse-submodules <url>"
fi
run ln -sf "$REPO_DIR/ominty-core/cli/ominty" ~/.local/bin/ominty
run ln -sf "$REPO_DIR/ominty-core/cli/ominty-hook" ~/.local/bin/ominty-hook

say "Generating the Niri bindings fragment..."
# registry build writes ~/.config/ominty/generated/... so it must be skipped in
# a dry run, not merely printed.
if [ "$DRY_RUN" -eq 1 ]; then
  plan "$REPO_DIR/ominty-core/cli/ominty registry build  # writes ~/.config/ominty/generated/niri/bindings.kdl"
else
  "$REPO_DIR/ominty-core/cli/ominty" registry build
fi

# --- 5a. DMS shell overlay (motion + accent glow) ---------------------------
# DMS embeds its QML shell in the binary and extracts it on first start. The
# overlay needs that extracted dist, so on a fresh install it is skipped and
# can be applied after DMS has run once. --check verifies the patch against
# the current build before touching anything.
OVERLAY="$REPO_DIR/configs/dms/shell-overlay/apply.sh"
OVERLAY_DROPIN="$REPO_DIR/configs/systemd/dms.service.d/ominty-shell.conf"
OVERLAY_OK=0
if [ -x "$OVERLAY" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "$OVERLAY --check   # verify the overlay against this DMS build"
    OVERLAY_OK=1
  else
    # Prefer the tree we just built; apply.sh falls back to runtime/package
    # discovery when it is absent.
    check_rc=0
    if [ -d "$DMS_DIST" ]; then
      "$OVERLAY" --check "$DMS_DIST" || check_rc=$?
    else
      "$OVERLAY" --check || check_rc=$?
    fi
    case "$check_rc" in
      0)
        OVERLAY_OK=1
        say "Applying DMS shell overlay (motion + accent glow)..."
        if [ -d "$DMS_DIST" ]; then
          run "$OVERLAY" "$DMS_DIST"
        else
          run "$OVERLAY"
        fi
        ;;
      1)
        warn "DMS shell overlay does not match this DMS build; keeping the stock shell."
        ;;
      3)
        warn "DMS shell overlay skipped: no pristine shell tree found. Start DMS once, then run configs/dms/shell-overlay/apply.sh"
        ;;
      *)
        warn "DMS shell overlay check failed (exit $check_rc); keeping the stock shell."
        ;;
    esac
  fi
fi
if [ "$OVERLAY_OK" -eq 1 ] && [ -f "$OVERLAY_DROPIN" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "render configs/systemd/dms.service.d/ominty-shell.conf -> ~/.config/systemd/user/dms.service.d/"
  else
    mkdir -p ~/.config/systemd/user/dms.service.d
    sed "s|__HOME__|$HOME|g" "$OVERLAY_DROPIN" \
      > ~/.config/systemd/user/dms.service.d/ominty-shell.conf
  fi
else
  # A stale drop-in would point DMS at a fork that no longer matches the build.
  if [ "$DRY_RUN" -eq 0 ]; then
    rm -f ~/.config/systemd/user/dms.service.d/ominty-shell.conf
  fi
fi

# --- 5b. DMS user service ---------------------------------------------------
# DMS is source-built on both families, so the installer owns the user unit.
# On Debian/LMDE this overrides the packaged /usr/lib/systemd/user/dms.service
# (same unit name, higher priority); the packaged file is left untouched.
say "Installing the DMS user service..."
if [ "$DRY_RUN" -eq 1 ]; then
  plan "render configs/systemd/dms.service -> ~/.config/systemd/user/dms.service (with __HOME__ replaced)"
  plan "systemctl --user daemon-reload; systemctl --user enable dms.service"
else
  mkdir -p ~/.config/systemd/user
  backup_existing ~/.config/systemd/user/dms.service
  sed "s|__HOME__|$HOME|g" "$REPO_DIR/configs/systemd/dms.service" \
    > ~/.config/systemd/user/dms.service
  systemctl --user daemon-reload
  systemctl --user enable dms.service || warn "Could not enable dms.service"
fi

# --- 6. DMS plugins ---------------------------------------------------------

if [ "$INSTALL_PLUGINS" -eq 1 ]; then
  say "Installing DMS plugins..."
  run mkdir -p ~/.config/DankMaterialShell/plugins
  run ln -sfn "$REPO_DIR/ominty-core/shell/dms/ominty-actions" \
    ~/.config/DankMaterialShell/plugins/omintyActions
  run ln -sfn "$REPO_DIR/ominty-core/shell/dms/ominty-keybinds" \
    ~/.config/DankMaterialShell/plugins/omintyKeybinds
  for p in "${DMS_PLUGINS[@]}"; do
    if [ ! -e ~/.config/DankMaterialShell/plugins/$p ]; then
      if [ -n "$DMS_BIN" ]; then
        run "$DMS_BIN" plugins install "$p" || warn "Could not install plugin: $p"
      else
        warn "DMS binary not found; skipping plugin install: $p"
      fi
    fi
  done
fi

# --- 7. validation ----------------------------------------------------------

say "Validating..."
"$REPO_DIR/ominty-core/cli/ominty" registry validate
if have niri; then
  niri validate -c ~/.config/niri/config.kdl \
    || warn "niri validate reported issues (re-check after first login)."
fi

say "Done. Log out and select the 'Niri' session at the display manager."
say "Next steps: docs/INSTALL.md (post-install checks, AI setup, troubleshooting)."