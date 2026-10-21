# DMS motion + accent glow, niri close glow, TTS restore

**Date:** 2026-10-21
**Status:** Implemented and verified
**Predecessor:** [`2026-10-14-niri-dms-aesthetics.md`](2026-10-14-niri-dms-aesthetics.md)
(open/close shaders, matugen template, popup palette)

## 1. Summary

Follow-up to the 2026-10-14 aesthetics work. Four changes:

1. **DMS motion** — modals, popouts, notifications and OSD now grow from a
   near-point instead of a slight scale-up, on a decelerating curve matched
   to niri's window-open curve.
2. **DMS accent glow** — an accent halo around modals, popouts, notifications
   and OSD, using the current matugen primary colour.
3. **niri close glow** — the close shader now emits an accent halo while the
   window fades and collapses; `window-movement` is a 220 ms curve instead of
   a short spring.
4. **TTS restore** — `piper-indicator` had been crashing because the
   `AyatanaAppIndicator3` typelib was missing. Fixed without root and the
   document picker is now bound to `Mod+Alt+O` as well as `Ctrl+Alt+O`.

DMS dialogs are **layer-shell surfaces** (`WlrLayer.Top`/`Overlay`), not niri
windows, so niri's `custom-shader` animations never see them. That is the
reason changes 1–2 are a DMS-side patch rather than more niri shader work.

## 2. DMS shell fork

DMS embeds its QML shell in the `dms` binary and unpacks it to
`/run/user/$UID/danklinux-shell/<hash>/` on start. That path is read-only and
changes with every DMS build, so it cannot hold local edits.

The fork is a writable copy selected via an environment variable:

```
~/.local/share/dms-shell          # 45 MB, 1348 files
~/.config/systemd/user/dms.service
    Environment=DMS_SHELL_DIR=/home/martin/.local/share/dms-shell
```

Running process verified as `qs -p /home/martin/.local/share/dms-shell`.

| Artifact | Location |
|---|---|
| Patch (12 files, +71/−8) | `configs/dms/shell-overlay/dms-shell.patch` |
| Apply / rebuild script | `configs/dms/shell-overlay/apply.sh` |
| Usage + upstream drift notes | `configs/dms/shell-overlay/README.md` |
| service template | `configs/systemd/dms.service` (`DMS_SHELL_DIR=__HOME__/...`) |

## 3. Motion

| Knob | Upstream | Ominty | File |
|---|---|---|---|
| `popupEnterScale` | `0.92` | `0.12` | `Common/Theme.qml` |
| `_effectScaleCollapsed` | `[0.96, 1.0, 0.88, 0.96]` | `[0.12, 0.12, 0.12, 0.12]` | `Common/AnimVariants.qml` |
| enter curve | `expressiveDefaultSpatial` | `omintyOpen` `[0.2, 0.8, 0.2, 1]` | `Common/Anims.qml`, `Common/Theme.qml`, `Modals/Common/DankModal.qml`, `Common/AnimVariants.qml` |
| `syncComponentAnimationSpeeds` | `true` | `false` | `Common/settings/SettingsSpec.js` |
| `modalAnimationDuration` | 150 ms | 800 ms | `Common/settings/SettingsSpec.js` |
| `popoutAnimationDuration` | 150 ms | 800 ms | `Common/settings/SettingsSpec.js` |
| `notificationAnimationDuration` | 200 ms | 450 ms | `Common/settings/SettingsSpec.js` |

`omintyOpen` is registered in `Theme.expressiveCurves` so both the modal host
and the variant/effect engine resolve the same curve. Notifications stay
shorter (450 ms) because they are glance surfaces.

## 4. Accent glow

Implemented by extending the shared `ElevationShadow` component rather than
adding a halo to each surface:

```qml
// DankCommon/Common/ElevationShadow.qml
property bool  glowEnabled: false
property color glowColor: Style.primary
property real  glowBlurPx: 12
property real  glowSpreadPx: 1
property real  glowOpacity: 0.7
readonly property real _glowPad: glowEnabled ? Math.ceil(...) + 2 : 0
```

A second `ShaderEffect` (`glowLayer`, `z: 1`) reuses
`Shaders/qsb/elevation_rect.frag.qsb` with a **transparent fill** and the
accent as the shadow colour, so only the blurred halo outside the rectangle is
drawn. Its anchors are expanded by `_glowPad` so the halo is not clipped.

Enabled surfaces (`glowColor: Theme.primary`, `glowBlurPx: 14`):

| Surface | Opacity | File |
|---|---|---|
| Modal frame | 0.60 | `Modals/Common/DankModalHost.qml` |
| Launcher (both modal variants) | 0.60 | `Modals/DankLauncherV2/DankLauncherV2ModalHost.qml` |
| Popouts (2 anchors) | 0.55 | `Widgets/DankPopoutHost.qml` |
| OSD | 0.55 | `Widgets/DankOSD.qml` |
| OSD sheet | 0.55 | `Widgets/DankOSDSheet.qml` |
| Notifications | 0.55 | `Modules/Notifications/Popup/NotificationPopup.qml` |

The glow follows matugen: `Theme.primary` is the live accent, so a wallpaper
change recolours the halo along with the rest of the shell.

## 5. niri: close glow + window-movement

### Close shader

`configs/matugen/templates/ominty-niri.kdl` (rendered to
`~/.config/niri/dms/ominty-theme.kdl`):

- `window-close` `duration-ms` 300 → **600**
- `window-open` `duration-ms` 350 → **800**
- close shader gains the accent halo:

```glsl
float glowW = max(8.0, min(halfSize.x, halfSize.y) * 0.12);
float glow  = exp(-abs(d) / glowW);
float fade  = smoothstep(0.0, 0.5, q);
vec4  col   = win * inside * fade;
col += vec4(OMINTY_ACCENT * glow, glow) * (1.0 - fade);
return col;
```

The halo is weighted by `1.0 - fade`, so it disappears as the window
collapses. niri cannot sequence close-before-slide, so the close uses a mild
ease-in (`cubic-bezier 0.4 0 0.2 1`) rather than a mirrored open curve.

### Window movement

`~/.config/niri/config.kdl`:

```kdl
window-movement {
    duration-ms 220
    curve "cubic-bezier" 0.45 0 0.75 0.25
}
```

Replaces the 120 ms spring. Validated with `niri validate`.

## 6. TTS restore

### Root cause

`piper-indicator` selects an SNI tray backend on Wayland, which requires the
`AyatanaAppIndicator3` GObject typelib. It was not installed and sudo was not
available, so the indicator exited at import time and `Ctrl+Alt+S`
(`read-selection`) had no player.

### Fix

1. Extracted `gir1.2-ayatanaappindicator3-0.1` and
   `libayatana-appindicator3-1` into
   `~/.local/opt/ayatana-appindicator/` (no root).
2. Added a self-reexec block at the top of `~/bin/piper-indicator`: if the
   user-local typelib exists and `PIPER_TTS_AYATANA_ENV` is unset, it sets
   `LD_LIBRARY_PATH` / `GI_TYPELIB_PATH` and re-execs itself. The block runs
   before `import gi`, which is required because the loader reads
   `LD_LIBRARY_PATH` at process start.
3. Provisioning script for other machines:
   `scripts/tts/ensure-ayatana-appindicator.sh` (downloads the two `.debs`
   with `apt-get download`, extracts with `dpkg-deb -x`).
4. Added `Mod+Alt+O { spawn "/home/martin/bin/tts-pick"; }` next to the
   existing `Ctrl+Alt+O` in `configs/niri/config.kdl`.

Permanent fix when sudo is available:

```bash
sudo apt install gir1.2-ayatanaappindicator3-0.1 libayatana-appindicator3-1
```

### Verification

- `piper-indicator` process alive; DMS tray shows
  `.../org/ayatana/NotificationItem/piper_indicator`.
- End-to-end: `Ctrl+Alt+S` → `read-selection` → `/tmp/piper_queue.txt` →
  `piper-daemon` → playback. `pactl list sink-inputs` showed
  `application.name = "piper-indicator"` for t+4 s → t+10 s.
- `tts-pick` zenity dialog opens under niri.
- `ominty tts say "..."` reaches `synthesizing → playing` with a sink input.
- `niri validate` clean after adding the bind; config reloaded with
  `niri msg action load-config-file`.

## 7. Reproduce

```bash
# 1. DMS shell overlay
cd configs/dms/shell-overlay
./apply.sh
systemctl --user daemon-reload
systemctl --user restart dms.service

# 2. niri config + matugen template
sed "s|__HOME__|$HOME|g" configs/niri/config.kdl > ~/.config/niri/config.kdl
cp configs/matugen/templates/ominty-niri.kdl ~/.config/matugen/templates/
matugen image <wallpaper>        # or change the wallpaper in DMS
niri validate

# 3. TTS typelib
scripts/tts/ensure-ayatana-appindicator.sh
```

## 8. Rollback

| Change | Rollback |
|---|---|
| DMS fork | delete `Environment=DMS_SHELL_DIR=...` from `dms.service`; `daemon-reload` + restart |
| niri close/open | restore the `duration-ms` values (300/350) and drop the glow block from the template; re-render |
| `window-movement` | restore the previous `spring damping-ratio=...` block |
| TTS | remove the self-reexec block; `sudo apt install ...` makes it unnecessary |

## 9. Maintenance notes

- **DMS upgrades** change the embedded-dist hash. After an upgrade, restart
  DMS once, re-run `apply.sh`, then restart again. If a hunk fails, re-apply
  the intent to the new files and regenerate the patch (`diff -ruN a b`).
- **Do not sync `configs/dms/settings.json` from the live machine.** The live
  file carries plugin state (9,964 B vs 4,637 B in the repo); the motion
  defaults live in the patched `SettingsSpec.js`, not in `settings.json`.
- The niri config in the repo is now a full copy of the live file, with
  `/home/martin` replaced by `__HOME__` and rendered by `install.sh`. This
  brings in the TTS binds and spawn-at-startup entries that were only present
  live before. Earlier divergence was accumulated customisation, not a
  separate branch.
- The TTS helper scripts (`read-selection`, `tts-pick`, `piper-indicator`,
  `piper-daemon`, `artha-word`) are user-local in `~/bin` and are **not**
  tracked by this repo. The niri binds reference them via `__HOME__`, so a
  fresh install needs those scripts copied separately. The typelib
  provisioning script is tracked (`scripts/tts/`).
- The close glow is derived from `OMINTY_ACCENT`, so it tracks the matugen
  palette automatically; no per-theme edits are needed.
