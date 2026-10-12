# ADR-001: Directory discovery, not a playlist database

Status: **Accepted** (Phase 1)

## Context

The design doc (Omi Media Launcher.md) proposes a small OS-level launcher
backed by directory discovery — the same philosophy as the dictionary popup.
Playlists already live in four loosely-curated folders under
`/home/martin/Playlist/` and are edited by hand / by other tools.

## Decision

Scan the configured category directories for `.m3u`, `.m3u8` and `.pls`
files at runtime.  No database, no daemon, no index.  The CLI returns the
live listing over `--json`.

## Consequences

- **Pros**: zero maintenance; new playlists appear immediately; simple and
  testable; the folder is the single source of truth.
- **Cons**: listing 911 files across four dirs on every popup open is a few
  ms — fine at this scale; no metadata beyond the file name (title = stem).

## Phase 2 note

Course progress/resume (videos watched, current lesson) is a separate
concern and will live under `~/.local/state/omi/media/`, keyed by playlist
path — discovery stays stateless.