# Troubleshooting

Symptom → check → fix. Every entry assumes you can open a terminal in the Niri
session; if the desktop will not start at all, use a TTY (`Ctrl+Alt+F3`) and
log in there.

## Start here

Collect evidence before changing anything:

```sh
scripts/collect-diagnostics.sh          # read-only; writes diagnostics-<host>-<date>/
scripts/smoke-dms.sh                    # is the shell alive and answering?
scripts/verify-upgrade.sh               # plumbing: unit, overlay, helpers
scripts/verify-parity.py                # function: actions, plugins, stacks
```

The diagnostics folder contains `SUMMARY.txt` plus system, packages, repo,
systemd, runtime, crash, config, plugin and tool reports. It is safe to send as
is; it contains no passwords.

Where the logs are:

| What | Where |
| --- | --- |
| Shell unit | `journalctl --user -u dms.service -n 200` |
| Quickshell crashes | `~/.cache/quickshell/crashes/<id>/report.txt` |
| Reader player | `$XDG_RUNTIME_DIR/ominty-tts/player.log` |
| Piper daemon | `/tmp/piper_daemon.log` |
| Installer | `~/ominty-install-<date>.log` |
| Diagnostics | `diagnostics-<host>-<date>/SUMMARY.txt` |

---

## The shell (DMS)

### No bar at all

**Check**

```sh
systemctl --user status dms.service --no-pager
systemctl --user cat dms.service | grep ExecStart
```

**Fix**

- `ExecStart=.../.local/bin/dms` → the pinned build is in use. Read the journal.
- `ExecStart=/usr/bin/dms` → the installer fell back to the packaged shell.
  Re-run `./install.sh`; if it fails again, run
  `scripts/diagnose-dms-shell.sh` and keep `~/ominty-dms-matrix-*.md`.
- Unit not found → `./install.sh` again (it writes the user unit).
- Journal says `Could not find the Qt platform plugin "wayland"` or
  `QT_QPA_PLATFORM=xcb` → the Qt Wayland plugin is missing:
  `sudo apt-get install -y qt6-wayland`, then restart `dms.service`. Without it
  Quickshell falls back to XWayland, where layer-shell surfaces do not exist,
  so the bar never maps.

### The bar appears, then disappears (crash loop)

**Check**

```sh
scripts/smoke-dms.sh
```

It reports `NRestarts`, the state, the newest Quickshell crash report and the
journal tail.

**Fix**

```sh
scripts/rollback-dms.sh --overlay-off     # same build, stock shell
```

If it still loops, the build itself is incompatible with this Quickshell:

```sh
scripts/rollback-dms.sh --to-packaged     # packaged /usr/bin/dms
scripts/diagnose-dms-shell.sh             # which combination works
```

Do not hand-edit `~/.local/share/dms-shell`; it is regenerated.

### The bar renders but nothing responds

Usually a stale QML cache. Since the per-build cache change this only affects
the packaged fallback.

**Fix** (safe: stop, move, start)

```sh
systemctl --user stop dms.service
mv ~/.cache/quickshell/qmlcache "$HOME/.cache/quickshell/qmlcache.bak-$(date +%s)" 2>/dev/null
systemctl --user start dms.service
```

For the pinned build the cache is `~/.cache/ominty/dms-<rev>/quickshell`.

### The theme or glow is missing

```sh
cat ~/.local/share/dms-shell/.ominty-overlay.json
systemctl --user show dms.service -p Environment | tr ' ' '\n' | grep DMS_SHELL_DIR
```

The marker's `base` must be `c27a2bbcb6e09e50`. If `DMS_SHELL_DIR` is unset, the
drop-in is missing: re-run `./install.sh`, or apply the overlay by hand:

```sh
configs/dms/shell-overlay/apply.sh --check   # 0 = applicable
configs/dms/shell-overlay/apply.sh
systemctl --user daemon-reload && systemctl --user restart dms.service
```

Exit `1` means the patch no longer matches the build — the stock shell keeps
running. Report it; do not force it.

**Animations off / no border or glow.** The base config has `animations { off }`;
the theme fragment turns them on and adds the border, shadow and shaders. That
fragment is rendered by matugen from a wallpaper:

```sh
ls ~/Wallpapers | head
ls ~/.config/niri/dms/ominty-theme.kdl
```

If `~/Wallpapers` is empty, `scripts/provision-wallpapers.sh` fills it. Then
render once:

```sh
matugen image "$(find ~/Wallpapers -maxdepth 1 -type l | head -1)" \
  -c ~/.config/matugen/config.toml -m dark
systemctl --user restart niri   # or: niri msg action reload-config
```

---

## DMS plugins

### A plugin opens blank

Blank almost always means a QML load failure, not missing data.

**Check**

```sh
dms ipc call <pluginId> viewStatus     # e.g. dankChat, omintyMedia
dms ipc call plugins reload <pluginId>
journalctl --user -b --no-pager | grep -iE "is not a type|Non-existent attached"
```

**Fix**

```sh
scripts/apply-plugin-patches.sh --check   # exit 1 = a patch is missing
scripts/apply-plugin-patches.sh
dms ipc call plugins reload <pluginId>
```

Two known cases:

- DankChat 0.6.0 uses a Qt attached object removed in 6.8; the patch fixes it.
- DankChat's `MediaPlayerView.qml` also imports `QtMultimedia`. Without
  `qml6-module-qtmultimedia` the component fails and the window is blank.
  Install it, then reload the plugin.

### A plugin disappeared after an update

`dms plugins update` and `dms plugins restore` reset managed plugins to
upstream, discarding local patches — and `restore` only installs what the
lockfile lists.

**Fix**

```sh
cat ~/.config/DankMaterialShell/plugins.lock.json
dms plugins restore ~/.config/DankMaterialShell/plugins.lock.json
scripts/apply-plugin-patches.sh
dms ipc call plugins reload <pluginId>
```

The Ominty plugins (`omintyMedia`, `omintyDictionary`, `omintyDownload`,
`omintyOllama`, `omintyActions`, `omintyKeybinds`) are symlinks into this
repository; `./install.sh` re-creates them.

### Plugin settings are empty

`~/.config/DankMaterialShell/plugin_settings.json` is deployed by the
installer. Re-run `./install.sh`; the previous file is kept as
`.bak-ominty-<timestamp>`.

---

## Ominty Media

### "No folders with playlists — add .m3u files under ~/Playlist"

A folder is a tab only when it contains a playlist; empty folders are hidden.

```sh
ls ~/Playlist
omi-media categories
```

Put a `.m3u`, `.m3u8` or `.pls` in any folder under `~/Playlist` and reopen the
launcher (`Shift+Alt+M`). Add folders at will; they become tabs automatically.

### A playlist will not play

```sh
omi-media play <category> "<playlist>" --dry-run
```

That prints the exact player command. If the player is missing, install it or
point the folder at another one in `~/.config/omi/media.toml`:

```toml
[categories.Music]
player = "mpv"
player_args = ["--no-video"]
```

### Tracks play in the wrong order

The `.m3u` order *is* the playback order; the format has no track field. A
generated playlist is usually lexicographic (`Track 10` before `Track 2`):

```sh
omi-media sort --in-place "<playlist>"      # keeps a backup
omi-media sort --in-place --dry-run "<playlist>"
```

VLC has no persistent "sort by title" setting, so this is the only fix.

---

## Ominty Reader (text to speech)

### Picking a document does nothing

It now shows a dialog with the reason. The same reason is in
`$XDG_RUNTIME_DIR/ominty-tts/player.log`.

```sh
ominty tts say /path/to/file --json
ominty tts status
```

**Fix**

- `pandoc not found` / `pdftotext not found` / `catdoc not found` → the `tts`
  layer did not install: `./install.sh --layers "desktop tts"`.
- `TTS player exited immediately` → read `player.log`; usually a missing
  GStreamer plugin (`gstreamer1.0-plugins-good`).
- `piper not found in venv` → `scripts/tts/setup-piper.sh`.

### The panel does not appear

The panel is a Quickshell surface (`ominty-tts`), started at login.

```sh
ls -l ~/.config/quickshell/ominty-tts
pgrep -af "quickshell -c ominty-tts"
```

Re-create the link with `./install.sh`; log out and back in for the startup
entry.

### No sound

```sh
~/.piper-venv/bin/piper --help >/dev/null && echo piper-ok
ls ~/.local/share/piper/voices/*.onnx
wpctl status | head -20
```

Install a voice with `scripts/tts/setup-piper.sh` and check the default sink.

### Clipboard reading does nothing

`Shift+Alt+S` speaks the clipboard. It needs `wl-clipboard` and the Piper
daemon; check `/tmp/piper_daemon.log` and copy something first.

---

## Ominty Dictionary

### "Dictionary unavailable"

No dictionaries are imported (they are ~800 MB and not in git).

```sh
omi-dict dictionaries
```

**Fix**

```sh
scripts/omi-dict-import.sh ~/Documents/Dictionaries
```

The script maps the common filenames to the ids the config expects (`oed`,
`etymology`, `roget`, `wordfamilies`).

### Wrong dictionary or no results

```sh
cat ~/.config/omi/dictionary.toml    # default_dictionary = "oed"
omi-dict dictionaries
```

Set `default_dictionary` to an id that exists, or import the missing one.

---

## Ominty Dictation (speech to text)

### The panel opens but nothing is typed

```sh
ominty voice status
ominty action run voice.dictate --json
```

**Fix**

| Missing | Fix |
| --- | --- |
| `whisper-cli` | `scripts/source/whisper-build.sh` |
| model file | same script; it downloads `ggml-base.en.bin` |
| `pw-record` | install `pipewire-bin` |
| `wtype` | install `wtype` (desktop layer) |

`Super+Alt+D` toggles dictation; `Super+Alt+T` shows the panel. There is no
key-release event under Niri, so it is a toggle by design.

### Dictation never stops

`ominty voice dictate` again, or `ominty voice panel` and use the stop button.
`ominty voice status` shows whether a recording is active.

---

## Ominty Capture (screen OCR)

### OCR returns nothing

```sh
tesseract --version
grim -g "$(slurp)" - | tesseract stdin stdout
```

If the manual pipeline works, the keybinding is fine and the selection was
empty. If `tesseract` is missing, install the desktop layer
(`./install.sh --layers desktop`). The result is shown as a notification and
copied to the clipboard with `wl-copy`.

---

## Downloading the repository

### The clone stops partway / `unexpected disconnect`

A plain `git clone` is one ~30 MB transfer (21 MB of it the bundled `.debs`) and
cannot resume. Use the bootstrap instead:

```sh
curl -fsSLO https://raw.githubusercontent.com/MartinKnights/Ominty/main/bootstrap.sh
bash bootstrap.sh          # run it again if it stops; it continues
```

It downloads in four independent steps, keeps a partial checkout, and skips
whatever already succeeded on the next run.

### The `.deb` downloads keep failing

They are fetched outside git, one file at a time. Copy them from another
checkout or a USB:

```sh
OMINTY_PACKAGES_SRC=/media/usb/Ominty/packages bash bootstrap.sh
```

Each file is verified with `dpkg-deb --info` before it is moved into place.

### `destination path 'Ominty' already exists`

That is the leftover of a failed clone. `bootstrap.sh` handles it: a directory
without `.git` is moved to `Ominty.incomplete-<timestamp>` and re-cloned; a
partial `.git` is reused and the download continues.

## Installer and build

### apt skips a package

The installer resolves each name first and skips what the configured sources do
not provide, then prints a summary at the end.

```sh
apt-cache show <package>
```

If the package genuinely does not exist for this release, the layer reports it as
missing in `ominty inspect`. That is acceptable for optional layers; a missing
*desktop* package is a stop.

### The Quickshell build fails

```sh
scripts/source/quickshell-build.sh --check-deps
```

It names missing pieces. The three that a fresh Debian/LMDE install lacks are:

| Symptom in the log | Package |
| --- | --- |
| `egl` pkg-config module not found | `libegl-dev` |
| `QtWaylandClient/…` include path missing | `qt6-wayland-private-dev` |
| `staging/ext-background-effect/ext-background-effect-v1.xml` missing | `wayland-protocols` from `trixie-backports` (1.47; trixie has 1.44) |

The installer now installs all three and **fails hard** if the build still
fails, because the pinned DMS shell cannot run on Debian's 0.3.0. Re-run the
build alone for a clean error:

```sh
scripts/source/quickshell-build.sh
```

### The DMS build fails

```sh
scripts/source/dms-build.sh
```

Usually a missing `git`/`make`, a Go download problem, or a shallow clone that
cannot fetch the pin. `OMINTY_DMS_FORCE=1 scripts/source/dms-build.sh` rebuilds
even when the stamp matches.

### `install.sh` exits non-zero

A fatal step failed. Read `~/ominty-install-<date>.log` for the last `[ERROR]`
or the failing command. If the tail is the shell smoke test, the installer
already fell back to the stock shell or the packaged unit; then:

```sh
scripts/smoke-dms.sh
scripts/diagnose-dms-shell.sh
scripts/collect-diagnostics.sh
```

On a fresh machine the smoke test is **skipped** (no graphical session yet), so
a non-zero exit there is a build or package failure, not the shell.

### `sudo` is not available to the agent

Run the installer in your own terminal:

```sh
cd <repo> && ./install.sh 2>&1 | tee ~/ominty-install-$(date +%F).log
```

---

## Session

### Niri is not offered at the display manager

```sh
ls /usr/share/wayland-sessions/
```

The bundled `.deb` installs `niri.desktop`. If it is missing,
`sudo apt-get install --reinstall ./packages/niri_*.deb`.

### Black screen after login

Switch to a TTY and check:

```sh
niri validate
journalctl --user -b -u dms.service -n 100
```

A rejected `niri validate` is the usual cause. Restore the backup made by
`install.sh` (`~/.config/niri/config.kdl.bak-ominty-*`) and report the error.

### The machine boots into the wrong session

This is the `session.default` choice. Re-run `./install.sh --session-default
niri` to write `~/.dmrc` (a backup is kept; other sessions stay selectable), or
set it in the display manager's *Login Window* tool. Without the flag the
installer leaves the default alone.

---

## Reporting

Send:

1. `diagnostics-<host>-<date>.tar.gz` from `scripts/collect-diagnostics.sh`;
2. `~/ominty-install-<date>.log` if the problem followed an install;
3. the exact command that failed and its output.

Do not send `.bak-ominty-*` backups or the dictionary data — they are large and
not needed.
