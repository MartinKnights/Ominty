# Niri integration

The dictionary service is surfaced in the Niri session two ways; both live
in the *niri configuration*, never in the service.

## 1. Shortcut (`Ctrl+Shift+A`)

The ominty action registry owns the binding: `actions/text.toml` → `text.define`
with `keys = ["Ctrl+Shift+A"]` → `ominty registry build` writes it into the
generated Niri fragment (`~/.config/ominty/generated/niri/bindings.kdl`),
which `config.kdl` includes.  The action runs `omi-dict selection --popup`
(read selection → open the DMS dictionary popup on it).

## 2. Blur behind the popup

Niri 26.04 blurs layer-shell surfaces via `layer-rule` (see the niri
Wiki: Window Effects / Layer Rules):

```kdl
layer-rule {
    match namespace="^ominty:"
    background-effect {
        blur true
    }
}
```

This matches every Ominty overlay (`ominty:dictionary`, `ominty:keybinds`,
`ominty:voice`, `ominty:tts`) so translucent popup backgrounds are blurred
whatever they float over.  It ships in `configs/niri/config.kdl`; Niri
hot-reloads `config.kdl` on change (no restart needed).

Optional tuning: the global `blur {}` config section (niri docs) sets blur
size/quality; xray mode is enabled automatically for these surfaces.