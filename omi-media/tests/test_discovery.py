"""Unit tests for playlist discovery (Omi Media Launcher spec §7–§8)."""

from __future__ import annotations

from pathlib import Path

from omi_media.discovery import discover_categories, discover_playlists, is_playlist


def _make_playlists(tmp_path: Path, names: list[str]) -> Path:
    d = tmp_path / "playlists"
    d.mkdir()
    for n in names:
        (d / n).write_text("#EXTM3U\n", encoding="utf-8")
    return d


def test_is_playlist_matches_supported_extensions_case_insensitively(tmp_path):
    d = tmp_path / "p"
    d.mkdir()
    for n in ("a.m3u", "b.M3U8", "c.pls"):
        (d / n).write_text("", encoding="utf-8")
    (d / "notes.txt").write_text("", encoding="utf-8")
    (d / ".hidden.m3u").write_text("", encoding="utf-8")
    files = {p.name for p in d.iterdir() if is_playlist(p)}
    assert files == {"a.m3u", "b.M3U8", "c.pls"}


def test_discover_playlists_sorted_case_insensitive_and_skips_hidden(tmp_path):
    d = _make_playlists(tmp_path, ["beta.m3u", "Alpha.m3u", ".ignored.m3u", "gamma.m3u8"])
    result = discover_playlists(str(d))
    titles = [p["title"] for p in result]
    assert titles == ["Alpha", "beta", "gamma"]
    assert all(p["path"].startswith(str(d)) for p in result)


def test_discover_playlists_missing_directory_returns_empty(tmp_path):
    assert discover_playlists(str(tmp_path / "does-not-exist")) == []


def test_discover_categories_order_and_counts(tmp_path):
    video = _make_playlists(tmp_path, ["A Course.m3u", "B Course.m3u"])
    empty = tmp_path / "empty"
    empty.mkdir()
    cats = {
        "video": {"id": "video", "name": "Video", "directory": str(video), "player": "vlc", "player_args": []},
        "music": {"id": "music", "name": "Music", "directory": str(empty), "player": "mpv", "player_args": []},
    }
    result = discover_categories(cats)
    assert [c["id"] for c in result] == ["video", "music"]
    assert result[0]["playlist_count"] == 2
    assert result[1]["playlist_count"] == 0