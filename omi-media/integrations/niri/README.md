# Niri integration

The media launcher is surfaced in the Niri session one way; the binding lives
in the **niri/Ominty configuration**, never in the service.

## Shortcut (`Ctrl+Shift+M`)

The ominty action registry owns the binding: `actions/media.toml` →
`media.launcher` with `keys = ["Ctrl+Shift+M"]` → `ominty registry build`
writes it into the generated Niri fragment
(`~/.config/ominty/generated/niri/bindings.kdl`), which `config.kdl` includes.
The action runs DMS IPC → `omintyMedia` plugin `toggle`.

Manual wiring (no registry):

```sh
dms ipc call omintyMedia toggle        # open/close the popup
dms ipc call omintyMedia openCategory video   # open straight into a tab
```

## Deploying the popup plugin

```sh
ln -sfn "$(pwd)/../dms/omintyMedia" ~/.config/DankMaterialShell/plugins/omintyMedia
dms ipc call plugins reload omintyMedia
dms ipc call plugins enable omintyMedia
```

## Blur (panel only)

The popup is split into two layer surfaces on purpose (same as the
dictionary): `ominty:media-dim` (never blurred) and `ominty:media` (the
panel, blurred via the existing layer-rule pattern in `configs/niri/config.kdl`):

```kdl
layer-rule {
    match namespace="^ominty:media$"
    background-effect {
        blur true
    }
}
```