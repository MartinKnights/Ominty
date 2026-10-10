# Niri integration

The dictionary service is surfaced in the Niri session two ways; both live
in the *niri configuration*, never in the service.

## 1. Shortcut (`Ctrl+Shift+A`)

The ominty action registry owns the binding: `actions/text.toml` → `text.define`
with `keys = ["Ctrl+Shift+A"]` → `ominty registry build` writes it into the
generated Niri fragment (`~/.config/ominty/generated/niri/bindings.kdl`),
which `config.kdl` includes.  The action runs `omi-dict selection --popup`
(read selection → open the DMS dictionary popup on it).

## 2. Blur (panel only)

Niri 26.04 blurs layer-shell surfaces via `layer-rule` (niri Wiki: Window
Effects / Layer Rules).  The popup is split into **two** layer surfaces on
purpose:

- `ominty:dictionary-dim` — fullscreen dim backdrop + click-outside (never
  blurred);
- `ominty:dictionary` — the actual panel, centred via four-anchor margins
  (this one is blurred).

```kdl
layer-rule {
    match namespace="^ominty:dictionary$"
    background-effect {
        blur true
    }
}
```

Because the blurred surface is exactly panel-sized, **only the popup's
footprint blurs** — not the whole screen.  It ships in
`configs/niri/config.kdl`; Niri hot-reloads on change.

Optional tuning: the global `blur {}` section sets blur size/quality; xray
mode is enabled automatically.