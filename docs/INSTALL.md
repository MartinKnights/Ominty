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
11. Build DMS from the pinned source commit and install the helper scripts
    (`configs/bin`, `configs/local-bin`, `configs/Scripts`), the Quickshell
    voice/TTS config links, and the `swayidle` unit.
12. If a pristine DMS shell tree is available, verify and apply the Ominty
    motion + accent-glow overlay, then write the `dms.service` drop-in that
    points DMS at the fork. The tree is found automatically (build cache,
    runtime extraction or package) — see *DMS shell overlay* below.
13. Validate the registry and the Niri config.

Existing configuration files are backed up with a
`.bak-ominty-<timestamp>` suffix before being replaced.

### DMS from source

DMS is built from **one pinned commit** on both families:

```
AvengeMedia/DankMaterialShell  73759d575210e8a4eb99b308283046b650df2ac3
  └─ dank-qml-common           fc42c683c7fd16e7583536acabae54a5fd678fc3
      → embedded shell build   c27a2bbcb6e09e50
```

That build id is what the overlay patch is written against, so the pin and the
patch move together. `scripts/source/dms-build.sh` does the work in user space
(no sudo), caches the checkout in `~/.cache/ominty/build`, records the built
commit in `.ominty-dms-ref`, and skips the build when the pin has not changed.
Override with `OMINTY_DMS_REF` / `OMINTY_DMS_FORCE=1`.

> The AvengeMedia OBS `dms` package is a newer shell generation with a
> different QML layout. `install.sh` therefore installs `matugen`, `ghostty`
> and friends from OBS but **not** `dms`.

### DMS shell overlay

DMS embeds its QML shell in the `dms` binary and extracts it at runtime —
`/run/user/$UID/danklinux-shell/<build>/` for the pinned 1.6.x build,
`/run/user/$UID/dms-shell/<build>/` for newer shells — and packaged installs
keep it at `/usr/share/quickshell/dms`. The motion + accent-glow overlay
copies that pristine tree to a writable fork:

```sh
configs/dms/shell-overlay/apply.sh --check   # does it match this DMS build?
configs/dms/shell-overlay/apply.sh           # rebuild the fork from pristine
```

`--check` is read-only and exits:

| Exit | Meaning |
| --- | --- |
| `0` | The patch applies to the discovered (or given) tree. |
| `1` | The patch does **not** apply to this DMS build. |
| `2` | Bad usage. |
| `3` | No pristine shell tree found (pass a path, or build/start DMS). |

An explicit `SOURCE_DIR` argument is always honoured and never replaced by
discovery. Without one, `apply.sh` tries `$DMS_SHELL_SRC`, the runtime
extraction for both shell generations, the source-build cache, and the package
locations, in that order.

`apply.sh` verifies against a temporary copy first, so a mismatched build is
never left half-patched. On success it records the base build in
`~/.local/share/dms-shell/.ominty-overlay.json`, which `ominty inspect`
reports as `desktop.shell_overlay.base`.

The fork is activated by the drop-in
`~/.config/systemd/user/dms.service.d/ominty-shell.conf` (installed
automatically). It sets `DMS_SHELL_DIR`. `install.sh` writes the `dms.service`
user unit on both families, so the drop-in always applies (on Debian it
overrides the packaged unit of the same name). Rolling back means deleting
that drop-in and restarting `dms.service`.

Re-run `apply.sh` after every DMS change: the unpacked build id changes and the
old fork no longer matches.

### Third-party repositories

`matugen` and `ghostty` are **not packaged in Debian**. They come from
AvengeMedia's Open Build Service, and `install.sh` wires this up automatically:

| OBS project | Provides |
|---|---|
| `home:AvengeMedia:danklinux` | `matugen`, `ghostty`, `danksearch`, `dgop` |

This adds `/etc/apt/sources.list.d/danklinux.list` plus the matching keyring in
`/etc/apt/keyrings/`.

> **`dms` is not installed from OBS.** The project there now ships a newer shell
> generation whose QML layout the overlay patch does not match, so
> `install.sh` builds the pinned commit instead (see *DMS from source*). It also
> no longer configures `home:AvengeMedia:dms`, so an `apt upgrade` cannot pull
> the incompatible package over a working install.

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
# .gitmodules now uses HTTPS; sync an older clone that still points the
# submodule at git@github.com (otherwise update tries SSH and needs a key).
git -C Ominty submodule sync --recursive
git -C Ominty submodule update --init --recursive
./install.sh        # re-run; configs are backed up and replaced
```

`install.sh` is idempotent. On a re-run it also:

- rebuilds DMS when the pinned commit in `scripts/source/dms-build.sh` changed
  (and skips the build when it did not),
- re-applies the shell overlay against the freshly built tree,
- redeploys the helper scripts and refreshes the Quickshell voice/TTS links.

If you want to check the overlay on its own:

```sh
configs/dms/shell-overlay/apply.sh --check   # expect: state: applicable
```

Exit `1` (`not-applicable`) means DMS changed the files the patch touches.
`install.sh` then leaves the stock shell running — update `dms-shell.patch`
before re-applying. Exit `3` just means no pristine tree was found; start DMS
once, or pass the path:

```sh
configs/dms/shell-overlay/apply.sh ~/.cache/ominty/build/DankMaterialShell/core/internal/shellembed/dist
systemctl --user daemon-reload && systemctl --user restart dms.service
```

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