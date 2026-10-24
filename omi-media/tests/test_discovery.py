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


def _mk(root: Path, name: str, playlists: list[str]) -> Path:
    d = root / name
    d.mkdir(parents=True, exist_ok=True)
    for n in playlists:
        (d / n).write_text("#EXTM3U\n", encoding="utf-8")
    return d


def test_discover_categories_scans_folders_and_hides_empty(tmp_path):
    _mk(tmp_path, "Video", ["B.m3u", "A.m3u"])
    _mk(tmp_path, "Music", ["Gospel.m3u"])
    _mk(tmp_path, "Courses", [])            # empty -> hidden
    (tmp_path / ".hidden").mkdir()
    (tmp_path / ".hidden" / "x.m3u").write_text("", encoding="utf-8")
    (tmp_path / "loose.m3u").write_text("", encoding="utf-8")  # file, not a folder

    cats = discover_categories(str(tmp_path))
    assert [c["name"] for c in cats] == ["Music", "Video"]   # alphabetical
    assert [c["playlist_count"] for c in cats] == [1, 2]
    assert all(c["player"] == "vlc" for c in cats)


def test_discover_categories_missing_root_is_empty(tmp_path):
    assert discover_categories(str(tmp_path / "nope")) == []


def test_discover_categories_applies_overrides_by_name_and_directory(tmp_path):
    _mk(tmp_path, "Music", ["Gospel.m3u"])
    _mk(tmp_path, "Video", ["Film.m3u"])
    overrides = {
        "music": {"name": "Music", "player": "mpv", "player_args": ["--no-video"]},
        "films": {"directory": str(tmp_path / "Video"), "player": "vlc"},
    }
    cats = {c["id"]: c for c in discover_categories(str(tmp_path), overrides)}
    assert cats["music"]["player"] == "mpv"
    assert cats["music"]["player_args"] == ["--no-video"]
    assert cats["video"]["player"] == "vlc"
