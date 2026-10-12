"""Playlist discovery (Omi Media Launcher spec §7–§8).

Directory discovery — no database.  A category is a configured directory;
its playlists are the ``*.m3u``, ``*.m3u8`` and ``*.pls`` files inside it,
sorted by title (case-insensitive).  Hidden files are ignored.
"""

from __future__ import annotations

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


def discover_categories(categories: dict) -> list[dict]:
    """The configured categories (in config order) with live playlist counts."""
    out = []
    for cid, spec in categories.items():
        playlists = discover_playlists(spec["directory"])
        out.append({
            "id": cid,
            "name": spec["name"],
            "directory": spec["directory"],
            "player": spec["player"],
            "playlist_count": len(playlists),
        })
    return out