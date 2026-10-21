# Installation Guide

This guide covers a **clean install**. If the machine already runs a desktop
(Cinnamon, GNOME, …) and the user wants to keep any of it, follow
[`MIGRATION.md`](MIGRATION.md) instead — that path assesses the incumbent
environment and preserves whatever is not deliberately replaced.

## Requirements

- **Debian 13 (Trixie)** or **LMDE 7** (the reference platform). Other
  Debian-based distros may work but are untested.
- A user account with **sudo** access.
- **curl** and **gpg** — used to import the third-party signing keys.
- ~2 GB free disk space (Niri + DMS + dependencies).
- An internet connection (the installer fetches APT keys from
  `download.opensuse.org`).

## 1. Clone

```sh
git clone --recurse-submodules https://github.com/<you>/Ominty.git
cd Ominty
```

The `--recurse-submodules` flag pulls the `ominty-core` implementation
submodule. If you forgot it:

```sh
git submodule update --init --recursive
```

## 2. Install

```sh
./install.sh
```

The installer is **idempotent** — re-running it is safe. It will:

1. Add the required APT repositories (see *Third-party repositories* below),
   ensure `trixie-backports` is enabled, and pin `quickshell` to Debian's build.
2. Install system packages via `apt`: `quickshell` (trixie-backports), plus
   pipewire, xwayland, portals, `fuzzel`, terminals, browser, and file manager
   from Debian. The optional `tts` layer adds the Ayatana tray typelib, Python
   GI bindings and the GStreamer plugins used by the Piper indicator.
3. Install **DMS**, **matugen**, and **ghostty** from the AvengeMedia Open
   Build Service (they are not in Debian).
4. Install **Niri** and **xwayland-satellite** from the prebuilt `.deb`s in
   `packages/`.
5. Deploy the Niri configuration and DMS fragments to `~/.config/niri/`.
6. Deploy the DMS shell settings and plugin settings to
   `~/.config/DankMaterialShell/`.
7. Deploy the Ominty configuration to `~/.config/ominty/` (existing user
   config is **kept**).
8. Symlink the `ominty` and `ominty-hook` CLIs into `~/.local/bin/`.
9. Generate the Niri bindings fragment from the action registry.
10. Install the DMS plugins (Ominty Actions, Ominty Keybinds, and the
    third-party set: dankHooks, dankKDEConnect, dankLauncherKeys,
    quickCapture, wallpaperCarousel).
11. If DMS has already unpacked its shell, verify and apply the Ominty
    motion + accent-glow overlay, then write the `dms.service` drop-in that
    points DMS at the fork. On a fresh install this step is skipped (DMS has
    not run yet) and can be re-run later — see *DMS shell overlay* below.
12. Validate the registry and the Niri config.

Existing configuration files are backed up with a
`.bak-ominty-<timestamp>` suffix before being replaced.

### DMS shell overlay

DMS embeds its QML shell in the `dms` binary and unpacks it on first start.
The motion + accent-glow overlay therefore needs that unpacked tree:

```sh
configs/dms/shell-overlay/apply.sh --check   # does it match this DMS build?
configs/dms/shell-overlay/apply.sh           # rebuild the fork from pristine
```

`--check` is read-only and exits `1` when the patch does not match. `apply.sh`
verifies against a temporary copy first, so a mismatched build is never left
half-patched. On success it records the base build in
`~/.local/share/dms-shell/.ominty-overlay.json`, which `ominty inspect`
reports as `desktop.shell_overlay.base`.

The fork is activated by the drop-in
`~/.config/systemd/user/dms.service.d/ominty-shell.conf` (installed
automatically). It sets `DMS_SHELL_DIR`, and works on both Debian (packaged
unit) and Ubuntu (source-built unit). Rolling back means deleting that drop-in
and restarting `dms.service`.

Re-run `apply.sh` after every DMS upgrade: the unpacked build id changes and
the old fork no longer matches.

### Third-party repositories

`dms`, `matugen`, and `ghostty` are **not packaged in Debian**. They come from
AvengeMedia's Open Build Service, and `install.sh` wires these up automatically:

| OBS project | Provides |
|---|---|
| `home:AvengeMedia:danklinux` | `matugen`, `ghostty`, `danksearch`, `dgop`, `niri` |
| `home:AvengeMedia:dms` | `dms` (the shell itself) |

This adds `/etc/apt/sources.list.d/{danklinux,dms}.list` plus the matching
keyrings in `/etc/apt/keyrings/`.

> **quickshell pinning.** The `danklinux` repo also ships a `quickshell`
> build, but upstream marks it deprecated for Debian and directs users to
> Debian's own. Its version (`0.3.1.db2`) sorts *higher* than Debian's
> (`0.3.0-1~bpo13+1`), so APT would otherwise pick the deprecated one.
> `install.sh` writes `/etc/apt/preferences.d/ominty-quickshell` to force
> Debian's build.

### Options

| Flag | Effect |
|---|---|
| `--profile surface-book-1` | Apply the Surface Book 1 hardware profile (2× scale output, dGPU script). |
| `--layers "desktop tts terminal editor cli containers browser"` | Choose which layers to install. `tts` is optional; drop it to skip the read-aloud stack. |
| `--no-plugins` | Skip the DMS plugin installation step. |
| `--help` | Show usage. |

## 3. First login

1. Log out of your current session.
2. At the display manager, select the **Niri** session.
3. Log in. The DMS bar appears; `Super+K` opens the interaction explorer.

## 4. Post-install checks

```sh
ominty registry validate        # 44 action(s), 0 error(s), 0 warning(s)
niri validate -c ~/.config/niri/config.kdl   # config is valid
systemctl --user is-active dms   # active
ominty inspect                   # platform, desktop and tts state
```

`ominty inspect` should report the right `family`/`is_lmde` for this host, and
`Desktop:` should show the overlay as `applied` once `apply.sh` has run. A
`TTS:` line reports the indicator and typelib state; both are optional.

Then exercise the surfaces:

- `Super+K` — interaction explorer
- `Super+Space` — universal palette (type `volume`)
- `Super+Shift+S` — cheat sheet (GKS)
- `Super+A` — AI menu
- `Super+X` — power menu (Restart Audio / Restart Network / Reload Niri)
- `Ctrl+Alt+S` — read the current selection aloud (TTS layer)
- `Ctrl+Alt+O` — open the TTS document picker (TTS layer)

## 5. AI setup (optional)

The default AI provider is **Pi** (`configs/ominty/ai.toml`). To use a local
model instead:

1. Install [Ollama](https://ollama.com) and pull a model:
   ```sh
   ollama pull qwen2.5:3b
   ```
2. Create `~/.config/ominty/ai.toml`:
   ```toml
   [ai]
   default_provider = "ollama"

   [ai.providers.ollama]
   enabled = true
   model = "qwen2.5:3b"
   ```
3. `Super+A` → **Ask AI** now uses the local model.

## 6. Wallpapers

The wallpaper carousel (`Super+Ctrl+P`) reads `~/Wallpapers`. Drop images
there. The `dankHooks` plugin regenerates the theme palette automatically
when the wallpaper changes.

## 7. Updating

```sh
git -C Ominty pull
git -C Ominty submodule update --init --recursive
./install.sh        # re-run; configs are backed up and replaced
```

If `dms` was upgraded, re-apply the shell overlay so the fork matches the new
build:

```sh
configs/dms/shell-overlay/apply.sh --check   # expect: state: applicable
configs/dms/shell-overlay/apply.sh
systemctl --user daemon-reload && systemctl --user restart dms.service
```

If `--check` reports `not-applicable`, DMS changed the files the patch touches.
`install.sh` leaves the stock shell running in that case; update
`dms-shell.patch` before re-applying.

## Uninstall

There is no automated uninstaller yet. To remove:

```sh
sudo apt remove --purge niri xwayland-satellite quickshell dms matugen ghostty
rm -rf ~/.config/niri ~/.config/DankMaterialShell ~/.config/ominty
rm -rf ~/.local/share/dms-shell
rm -f ~/.config/systemd/user/dms.service.d/ominty-shell.conf
rm -f ~/.local/bin/ominty ~/.local/bin/ominty-hook
systemctl --user daemon-reload
```

To also drop the APT repositories and keyrings the installer added:

```sh
sudo rm -f /etc/apt/sources.list.d/danklinux.list \
            /etc/apt/sources.list.d/dms.list \
            /etc/apt/keyrings/danklinux.gpg \
            /etc/apt/keyrings/dms.gpg \
            /etc/apt/preferences.d/ominty-quickshell
sudo apt update
```

Restore any `.bak-ominty-*` files you want to keep.