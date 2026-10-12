# Omi Media Launcher (`omi-media`)

A small, keyboard-first, **local** media launcher for Ominty, built with the
same design philosophy as the dictionary popup: a lightweight OS-level tool
backed by **directory discovery** — no playlist database to maintain.

```
Ctrl+Shift+M
      ↓
Media popup (DMS `omintyMedia`)
      ↓
Category tab: Audio · Courses · Music · Video
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
| `config/media.toml.example` | optional user config |
| `integrations/` | DMS popup, Niri binding |
| `docs/` | architecture, testing, ADRs |

## Playlists

Playlists live under a root folder (`/home/martin/Playlist` by default) in
four category directories: `Audio`, `Courses`, `Music`, `Video`.  Each is
scanned for `.m3u`, `.m3u8` and `.pls` files when the popup opens — drop a
playlist file in and it appears automatically.

## Status

**Phase 1 (v1) complete**: discovery + selectable popup + hand-off to the
player.  Phase 2 capabilities (course progress/resume, per-lesson drill-down,
favourites, recently played) are deliberately deferred — see `docs/architecture.md`.