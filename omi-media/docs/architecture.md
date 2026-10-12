# Omi Media Launcher — architecture (v1)

## Goal

A tiny, keyboard-first, **local** playlist launcher: discover `.m3u` /
`.m3u8` / `.pls` files by scanning a few configured directories, show them
in a searchable DMS popup, and hand the selected playlist file to a
per-category player.  No playlist database, no daemon, no internet.

## Design principles (from Ominty core)

1. **Directory discovery is the source of truth.**  Drop a playlist file in
   a category folder and it appears immediately.  There is no index to keep
   in sync.
2. **The CLI is the contract.**  `bin/omi-media` is the only component that
   knows how playlists are discovered and launched.  The DMS popup holds no
   logic — it shells out to `omi-media … --json` and renders (the same split
   as `omi-dict` ↔ `omintyDictionary`).
3. **Surface via the Omi Quick Action pattern.**  `type → filter → arrows →
   Enter → Esc`; category tabs switch the folder.
4. **Configurable, never hard-coded.**  Categories, directories and players
   all come from `~/.config/omi/media.toml`.

## Components

```
Ctrl+Shift+M  (Niri, via action registry -> DMS IPC)
      │
      ▼
omintyMedia (DMS plugin, QML)      ← presentation only
      │  shells out: omi-media categories/playlists/play --json
      ▼
omi-media (Python CLI, bin/omi-media)
      │
      ├── config.py     XDG paths + media.toml (defaults merged in)
      ├── discovery.py  scan a directory for *.m3u/*.m3u8/*.pls
      ├── players.py    build + spawn the category player
      └── cli.py        categories | playlists | play   (+ --json)
```

## Data & configuration

| Path | Purpose |
|---|---|
| `/home/martin/Playlist/{Audio,Courses,Music,Video}` | default category folders (root configurable) |
| `~/.config/omi/media.toml` | optional category + player config |
| `~/.local/state/omi/media/` | reserved (Phase 2 progress/resume logs) |

Defaults when no config file exists: root = `~/Playlist`, four categories
(Audio, Courses, Music, Video), players **vlc** (Video, Courses) and **mpv**
(Audio, Music).

## CLI contract (v1)

| Command | Output |
|---|---|
| `omi-media categories --json` | `[{id,name,directory,player,playlist_count}]` |
| `omi-media playlists <cat> --json` | `[{name,title,path}]` for the folder |
| `omi-media play <cat> <playlist> [--dry-run] [--json]` | launches the player; dry-run prints the command |

## Phases

### Phase 1 (v1) — this build
Directory discovery + category selector popup + hand-off to the player.

### Phase 2 — deliberately deferred (design doc, "Omi Media Launcher.md")
- **Course-aware view / resume**: show `18 videos · Current 07 — Systemd ·
  Progress 6/18` and resume at the last-played item.  Would add playback-state
  tracking (a small state file or DB) — nothing in v1 assumes its absence.
- **Per-lesson drill-down**: expand a playlist into its entries (parse the
  m3u) and launch a specific lesson.
- **Favourites / recently played** for the video/audio selector.

The JSON contracts, per-category config, and the `play` command are shaped so
these can be added without rewriting: e.g. `playlist` gains an optional
`entries` list; `play` gains an optional `--entry`, and resume state lives
under `~/.local/state/omi/media/`.

## Relevant decisions
- `ADR-001-directory-discovery.md` — why discovery, not a database.