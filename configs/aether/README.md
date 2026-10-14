# Aether integration (Ominty)

Aether authors a theme from a wallpaper; these files make **Apply Theme**
change the whole Ominty/Niri/DMS desktop (wallpaper **and** colours).

## How it works

```
Aether (pick / edit theme)  →  Apply Theme
        │ writes ~/.config/aether/theme/ominty-dms-seed.conf  ({wallpaper})
        ▼
custom/ominty-dms/post-apply.sh
        │
        ▼
dms ipc call wallpaper set "<aether wallpaper>"
        │
        ▼
DMS regenerates + applies the ENTIRE theme LIVE:
DMS shell · Niri colours (dms/colors.kdl) · GTK/Qt · alacritty/ghostty ·
Firefox · zed · …
```

DMS is the theme engine (unchanged) and its **only live-apply path is a
wallpaper change** — external `dms matugen generate/queue` writes files but
the running shell does not repaint (verified).  So the hook hands Aether's
wallpaper to DMS, which recolours everything live.  Integration over
duplication: one theme engine, Aether as the authoring front-end.

## Install

```sh
mkdir -p ~/.config/aether/custom
cp -r configs/aether/custom/ominty-dms ~/.config/aether/custom/
chmod +x ~/.config/aether/custom/ominty-dms/post-apply.sh
```

Then in Aether: choose a wallpaper → **Apply Theme**.

## Notes

- Applying Aether sets the **wallpaper too** (that is what triggers DMS's
  live recolour).
- The desktop palette is DMS's Material derivation of the chosen wallpaper
  (the same source Aether extracts from).  Aether's per-colour slider edits
  are **not** pushed to the live desktop — only the wallpaper is.  (Writing
  an exact hex palette is possible via `dms matugen generate --kind hex
  --value <hex>`, but the running shell only reflects it after a DMS
  restart, so it isn't used here.)
- Logs: `~/.local/state/omi/aether-dms.log`
