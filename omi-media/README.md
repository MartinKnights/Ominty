# Omi Media Launcher (`omi-media`)

A small, keyboard-first, **local** media launcher for Ominty, built with the
same design philosophy as the dictionary popup: a lightweight OS-level tool
backed by **directory discovery** — no playlist database to maintain.

```
Shift+Alt+M
      ↓
Media popup (DMS `omintyMedia`)
      ↓
Tab between tabs → filter → list
      ↓
type → filter → ↑/↓ → Enter
      ↓
configured player opens the .m3u (VLC / mpv)
```

## Layout

| Path | Purpose |
|---|---|
| `bin/omi-media` | the CLI (the stable contract) |
| `src/omi_media/` | config, discovery, players, cli |
| `config/media.toml.example` | optional per-folder overrides |
| `integrations/` | DMS popup, Niri binding |
| `docs/` | architecture, testing, ADRs |

## Folders

Every subfolder of the root (`~/Playlist` by default) is a category.  Add a
folder, rename one, or prefix it (`01-Audio`) and the tabs follow on the next
open — there is nothing else to configure.  A folder with no playlist is
hidden until it contains one; dot-folders are ignored.

Each folder is scanned for `.m3u`, `.m3u8` and `.pls` files when the popup
opens, so dropping a playlist in is the whole import step.

`~/.config/omi/media.toml` is optional and only overrides how a folder is
presented or played:

```toml
[general]
root = "~/Playlist"

[categories.Music]          # key = folder name
player = "mpv"
player_args = ["--no-video"]

[categories.Films]          # or match by path
directory = "{root}/Video"
player = "vlc"
```

## Keyboard

Three zones, cycled with `Tab` / `Shift+Tab`; the focused zone is outlined.

| Zone | Keys |
| --- | --- |
| Tabs | `←`/`→` and `↑`/`↓` change folder, `Enter` moves to the list |
| Filter | type to filter, `Backspace` edits, `↑`/`↓` move the selection, `Enter` plays |
| List | `↑`/`↓` move, `Enter` plays, `←`/`→` change folder, any printable key jumps to the filter |

`Esc` closes. `Ctrl+[` / `Ctrl+]` cycle folders from anywhere.

## Status

**Phase 1 (v1) complete**: discovery + selectable popup + hand-off to the
player.  Phase 2 capabilities (course progress/resume, per-lesson drill-down,
favourites, recently played) are deliberately deferred — see `docs/architecture.md`.