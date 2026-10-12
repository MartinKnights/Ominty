# Omi Media Launcher — testing

Run from the repository root:

```sh
cd Ominty/omi-media
PYTHONPATH=src python3 -m pytest tests/ -q
```

## What is covered

- `tests/test_discovery.py` — unit tests: supported extensions (m3u/m3u8/pls,
  case-insensitive), hidden-file exclusion, case-insensitive sorting,
  missing-directory handling, category ordering + counts.
- `tests/test_cli.py` — integration tests running `bin/omi-media` with a
  sandboxed XDG environment + temporary `media.toml`: `categories --json`,
  `playlists --json`, `play --dry-run` (command shape + exact-title match),
  plus error paths (unknown category, missing playlist) and `-V`.

## Testing conventions

- CLI tests shell out to the real binary (like `omi-dict`), never to the
  module directly — the binary is the contract.
- `--config PATH` and `OMI_MEDIA_ROOT` keep tests hermetic; no test touches
  the real `~/Playlist` or `~/.config/omi/`.
- No test spawns a player: `play` is exercised with `--dry-run`.

## Manual / live verification

With a Niri + DMS session running:

1. `omi-media categories` → counts match the folders (Audio 250, Courses 335,
   Music 99, Video 227).
2. `Ctrl+Shift+M` → popup opens with four category tabs.
3. Switch tabs; type to filter; `Enter` opens VLC on a course playlist and mpv
   on an audio/music playlist; `Esc` closes.