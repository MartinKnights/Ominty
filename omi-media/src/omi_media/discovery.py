"""Playlist discovery (Omi Media Launcher spec §7–§8).

Directory discovery — no database.  A category is a configured directory;
its playlists are the ``*.m3u``, ``*.m3u8`` and ``*.pls`` files inside it,
sorted by title (case-insensitive).  Hidden files are ignored.
"""

from __future__ import annotations

import re
from pathlib import Path

PLAYLIST_EXTENSIONS = (".m3u", ".m3u8", ".pls")


def is_playlist(path: Path) -> bool:
    return path.is_file() and path.suffix.lower() in PLAYLIST_EXTENSIONS and not path.name.startswith(".")


def discover_playlists(directory: str) -> list[dict]:
    """List the playlists in a directory, sorted by title."""
    root = Path(directory)
    if not root.is_dir():
        return []
    items = [
        {"name": p.name, "title": p.stem, "path": str(p)}
        for p in root.iterdir()
        if is_playlist(p)
    ]
    items.sort(key=lambda item: item["title"].lower())
    return items


def slugify(name: str) -> str:
    """A stable, CLI-safe id from a folder name ("02-Music" -> "02-music")."""
    out = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")
    return out or "category"


def _override_for(folder: Path, overrides: dict) -> dict:
    """Find the media.toml entry that applies to this folder.

    Match is lenient so both styles work: a key equal to the folder name
    (case-insensitive), an explicit ``name`` that matches, or a ``directory``
    that resolves to the folder.
    """
    for key, spec in overrides.items():
        spec = dict(spec)
        if key.lower() == folder.name.lower():
            return spec
        if str(spec.get("name", "")).lower() == folder.name.lower():
            return spec
        directory = spec.get("directory")
        if directory and Path(str(directory)) == folder:
            return spec
    return {}


def discover_categories(root: str, overrides: dict | None = None) -> list[dict]:
    """The root's subfolders that contain a playlist, alphabetically.

    The folder tree is the category list, so adding or renaming a folder is the
    configuration. A folder with no playlist is hidden: an empty tab is noise.
    ``overrides`` (media.toml) may change a folder's name, player or player
    arguments; entries for folders that do not exist are ignored.
    """
    overrides = overrides or {}
    base = Path(root)
    if not base.is_dir():
        return []

    folders = sorted(
        (p for p in base.iterdir() if p.is_dir() and not p.name.startswith(".")),
        key=lambda p: p.name.lower(),
    )

    out: list[dict] = []
    used: set[str] = set()
    for folder in folders:
        playlists = discover_playlists(str(folder))
        if not playlists:
            continue
        spec = _override_for(folder, overrides)
        cid = slugify(folder.name)
        while cid in used:                 # "Music" and "music" on one root
            cid = f"{cid}-2"
        used.add(cid)
        out.append({
            "id": cid,
            "name": str(spec.get("name") or folder.name),
            "directory": str(folder),
            "player": str(spec.get("player") or "vlc"),
            "player_args": [str(a) for a in (spec.get("player_args") or [])],
            "playlist_count": len(playlists),
        })
    return out
