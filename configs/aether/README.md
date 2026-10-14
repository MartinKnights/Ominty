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
  are **not** pushed to the live desktop — only the wallpaper is.
- **Why not push an exact hex palette?**  DMS runs in *dynamic* theme mode
  (`currentThemeName = 'dynamic'`): it derives the palette from the current
  wallpaper on every start.  `dms matugen generate --kind hex …` writes the
  palette files, but (a) the running shell does not repaint, and (b) a
  `dms restart` just re-derives from the wallpaper and discards it
  (verified).  So the **wallpaper is the channel** — set it and DMS
  recolours, live and durably.  Aether's *wallpaper* edits (blur/exposure/…)
  therefore do flow through, since they change the image DMS derives from.
- Exact static palettes would need a DMS *custom theme* (its Plugins &
  Themes surface), which isn't file-drivable from here — out of scope.
- Logs: `~/.local/state/omi/aether-dms.log`
