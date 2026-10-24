# Ominty Media — dynamic folders and keyboard navigation

**Date:** 2026-10-24
**Status:** approved
**Surface:** Ominty Media (`omi-media`, `omintyMedia`)

## Problem

Ominty Media has four hard-coded categories (`Audio`, `Courses`, `Music`,
`Video`) mapped to four hard-coded directories. A user who renames a folder or
adds one gets nothing: the tab keeps its old label, or the folder is invisible.

Navigation is also mouse-first. The filter field handles `↑`/`↓`/`Enter` and
`Ctrl+[`/`Ctrl+]` cycles categories, but `Tab` does nothing useful and the
category tabs cannot be reached without a pointer. On a keyboard-driven desktop
that is the wrong default.

## Decision

**Folder discovery with config overrides** (option B of three considered), and
**empty folders are hidden** until they contain at least one playlist.

Explicitly rejected: scanning only (throws away per-folder player settings) and
config-only (renaming a folder would do nothing without editing a file).

## Behaviour

### Categories

- The category list is the set of immediate subdirectories of the root
  (`~/Playlist` by default), excluding dot-directories.
- A folder appears only if `discover_playlists()` finds at least one
  `*.m3u`, `*.m3u8` or `*.pls` file in it. The count in the tab is live.
- Order is case-insensitive alphabetical by folder name, so numeric prefixes
  (`01-Audio`) give an explicit order.
- The tab label is the folder name verbatim; the id is its slug, so
  `omi-media play <id> <playlist>` keeps working.
- `~/.config/omi/media.toml` is optional and only *overrides*: `player`,
  `player_args` and `name` for a folder that exists. Entries for folders that do
  not exist are ignored; a folder with no entry gets `vlc` and no arguments.
- If the root is missing, or no subfolder contains a playlist, the popup shows
  the root path and a one-line hint instead of an empty tab row.
- `install.sh` still creates `Audio`, `Courses`, `Music`, `Video` as a starting
  point. They are ordinary folders: renaming or deleting them is supported.

### Keyboard

Three focus zones — tabs, filter, list — cycled with `Tab` / `Shift+Tab`, with a
visible focus ring on the active zone.

| Zone | Keys |
| --- | --- |
| Tabs | `←`/`→` and `↑`/`↓` change folder; `Enter` moves focus to the list |
| Filter | typing filters; `↓`/`↑` move the list selection; `Enter` plays; `Tab` moves to the list |
| List | `↑`/`↓` move; `Enter` plays; `←`/`→` change folder; a printable key moves to the filter and starts typing |
| Anywhere | `Esc` closes; `Ctrl+[` / `Ctrl+]` cycle folders |

Focus starts in the filter, so "open, type, Enter" behaves as it does today.
Playing closes the popup.

## Compatibility

`omi-media categories --json` keeps its exact shape:

```json
{"categories": [{"id", "name", "directory", "player", "playlist_count"}]}
```

The popup, the CLI and any script that reads that output keep working. Config
files that already name categories keep working when the folder exists; when it
does not, the entry is ignored rather than creating a phantom tab.

## Testing

- Unit tests for discovery: ordering, hidden folders excluded, empty folders
  excluded, missing root, nested files ignored, config override applied, config
  entry for a missing folder ignored, `OMI_MEDIA_ROOT` override.
- Manual: the key map above on the live popup, including a folder with one
  playlist and a folder with none.

## Out of scope

- Per-folder icons or colours.
- Recursive scanning below the first level.
- A "recently played" list or any persisted state.
