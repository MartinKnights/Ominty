# Aether integration (Ominty)

Aether authors a colour palette from a wallpaper; these files make it drive
the **whole Ominty/Niri/DMS desktop**.

## How it works

```
Aether (pick / edit palette)  →  Apply Theme
        │ writes ~/.config/aether/theme/ominty-dms-seed.conf  ({accent})
        ▼
custom/ominty-dms/post-apply.sh
        │
        ▼
dms matugen generate --kind hex --value <accent> --mode <dark|light>
        │
        ▼
entire desktop palette: DMS shell · Niri colours (dms/colors.kdl) ·
GTK/Qt · alacritty/ghostty · Firefox · zed · …
```

DMS is the renderer (unchanged); Aether becomes the palette author.  This is
integration-over-duplication: no second theme engine.

## Install

```sh
mkdir -p ~/.config/aether/custom
cp -r configs/aether/custom/ominty-dms ~/.config/aether/custom/
chmod +x ~/.config/aether/custom/ominty-dms/post-apply.sh
```

Then in Aether: pick a wallpaper → **Apply Theme**.

## Tuning

- **Seed colour** — `custom/ominty-dms/seed.conf` defaults to `{accent}`.
  Choose any Aether variable, e.g. `{blue}`, `{background}`, `{color4}`.
- **Scheme / spec / contrast** — add `--matugen-type`, `--spec`, `--contrast`
  flags in `post-apply.sh` (see `dms matugen generate --help`).
- Applying Aether is a deliberate theme set; a later DMS wallpaper change
  re-derives the palette from that wallpaper.

## Logs

`~/.local/state/omi/aether-dms.log`
