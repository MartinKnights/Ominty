# DMS shell overlay — motion + accent glow

DMS ships its QML shell **inside the `dms` binary** and extracts it at runtime.
The location depends on the shell generation:

| Build | Extracted to |
|---|---|
| AvengeMedia DMS 1.6.x (Ominty's pinned build) | `/run/user/$UID/danklinux-shell/<hash>/` |
| Dux Shell 2.0.x | `/run/user/$UID/dms-shell/<hash>/` |
| packaged install | `/usr/share/quickshell/dms` |

Those directories are read-only and are replaced whenever the DMS build
changes, so Ominty's animation and glow tweaks cannot live there.

Instead:

1. `apply.sh` copies the pristine tree to a writable fork at
   `~/.local/share/dms-shell` (or `$DMS_SHELL_DIR`).
2. It verifies `dms-shell.patch` against a throwaway copy, then applies it
   (12 files, +71/−8 lines). A build it does not recognise is never
   half-patched — the stock shell keeps running.
3. The `dms.service.d/ominty-shell.conf` drop-in points DMS at the fork with
   `Environment=DMS_SHELL_DIR=...`.

```bash
./apply.sh                 # rebuild from the best pristine tree found
./apply.sh --check         # verify only; nothing is written
./apply.sh --dry-run       # show what would happen
./apply.sh /path/to/dist   # explicit source (never replaced by discovery)
systemctl --user daemon-reload && systemctl --user restart dms.service
```

When no `SOURCE_DIR` is given, discovery tries `$DMS_SHELL_SRC`, both runtime
extraction roots, the Ominty source-build cache, and the packaged locations,
in that order.

Source discovery is necessary because Ominty builds DMS from a **pinned
commit** (`scripts/source/dms-build.sh`), and that build's tree is
deterministic:

```
AvengeMedia/DankMaterialShell  73759d5  →  shell build c27a2bbcb6e09e50
```

That hash is the patch's base. Change the pin and the patch must be
regenerated; `apply.sh --check` will refuse until it is.

| Exit | Meaning |
|---|---|
| `0` | Applied, or (with `--check`) the patch applies. |
| `1` | Patch does not match this build; stock shell left in place. |
| `2` | Bad usage. |
| `3` | No pristine tree found. |

Rollback: delete `~/.config/systemd/user/dms.service.d/ominty-shell.conf`, then
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

A normal `./install.sh` re-run handles this: it rebuilds DMS when the pin
changed and re-applies the overlay from the freshly built tree. To do it by
hand:

```bash
# 1. Rebuild DMS at the pinned commit (skips if unchanged)
scripts/source/dms-build.sh
# 2. Rebuild the fork from the new tree
cd configs/dms/shell-overlay && ./apply.sh
# 3. Restart DMS
systemctl --user daemon-reload && systemctl --user restart dms.service
```

If you bump the pin, regenerate the patch first: the embedded shell hash
changes and `--check` will report `not-applicable` until the patch matches.

If a hunk fails, the patch context changed upstream — re-apply the intent
against the new file and regenerate:

```bash
diff -ruN a b > dms-shell.patch
```
