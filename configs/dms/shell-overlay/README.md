# DMS shell overlay — motion + accent glow

DMS ships its QML shell **inside the `dms` binary** and unpacks it to
`/run/user/$UID/danklinux-shell/<hash>/` at startup. That directory is
read-only and is replaced whenever the DMS build changes, so Ominty's
animation and glow tweaks cannot live there.

Instead:

1. `apply.sh` copies the unpacked dist to a writable fork at
   `~/.local/share/dms-shell` (or `$DMS_SHELL_DIR`).
2. It applies `dms-shell.patch` (12 files, +71/−8 lines).
3. `~/.config/systemd/user/dms.service` points DMS at the fork with
   `Environment=DMS_SHELL_DIR=...`.

```bash
./apply.sh                 # rebuild from the newest extracted dist
./apply.sh --dry-run       # show what would happen
./apply.sh /path/to/dist   # explicit source
systemctl --user daemon-reload && systemctl --user restart dms.service
```

Rollback: delete the `DMS_SHELL_DIR` line from `dms.service`, then
`systemctl --user daemon-reload && systemctl --user restart dms.service`.

## What the patch changes

### Motion

| Knob | Upstream | Ominty | File |
|---|---|---|---|
| `popupEnterScale` | `0.92` | `0.12` | `Common/Theme.qml` |
| `_effectScaleCollapsed` | `[0.96, 1.0, 0.88, 0.96]` | `[0.12, 0.12, 0.12, 0.12]` | `Common/AnimVariants.qml` |
| enter curve | `expressiveDefaultSpatial` | `omintyOpen` = `[0.2, 0.8, 0.2, 1]` | `Common/Anims.qml`, `Common/Theme.qml`, `Modals/Common/DankModal.qml`, `Common/AnimVariants.qml` |
| `modalAnimationDuration` | 150 ms | 800 ms | `Common/settings/SettingsSpec.js` |
| `popoutAnimationDuration` | 150 ms | 800 ms | `Common/settings/SettingsSpec.js` |
| `notificationAnimationDuration` | 200 ms | 450 ms | `Common/settings/SettingsSpec.js` |
| `syncComponentAnimationSpeeds` | `true` | `false` | `Common/settings/SettingsSpec.js` |

Popups/modals now grow from a near-point (12 % scale) on a decelerating
curve that matches the niri window-open curve. Notification timing is kept
shorter because it is a glance surface.

### Accent glow

`DankCommon/Common/ElevationShadow.qml` gains an optional outer halo that
reuses the existing elevation shader with a **transparent fill**: only the
blurred accent "shadow" outside the rectangle is drawn. New properties:

- `glowEnabled` (default `false`)
- `glowColor` (default `Style.primary`)
- `glowBlurPx` (default `12`)
- `glowSpreadPx` (default `1`)
- `glowOpacity` (default `0.7`)

Enabled surfaces (all use `Theme.primary`, `glowBlurPx: 14`):

| Surface | Opacity | File |
|---|---|---|
| Modal frame | 0.60 | `Modals/Common/DankModalHost.qml` |
| Launcher (both modal variants) | 0.60 | `Modals/DankLauncherV2/DankLauncherV2ModalHost.qml` |
| Popouts | 0.55 | `Widgets/DankPopoutHost.qml` |
| OSD + OSD sheet | 0.55 | `Widgets/DankOSD.qml`, `Widgets/DankOSDSheet.qml` |
| Notifications | 0.55 | `Modules/Notifications/Popup/NotificationPopup.qml` |

Because DMS dialogs are **layer-shell surfaces**, niri's `custom-shader`
animations do not apply to them — this is why the tuning has to happen in
DMS's own QML animation engine and why the glow is a QML effect.

## Updating after a DMS upgrade

```bash
# 1. Restart DMS once so it extracts the new build
systemctl --user restart dms.service
# 2. Rebuild the fork from the new dist
cd configs/dms/shell-overlay && ./apply.sh
# 3. Restart again
systemctl --user restart dms.service
```

If a hunk fails, the patch context changed upstream — re-apply the intent
against the new file and regenerate:

```bash
diff -ruN a b > dms-shell.patch
```
