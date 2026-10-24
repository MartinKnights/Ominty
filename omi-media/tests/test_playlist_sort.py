"""Playlist reordering (track order vs lexicographic order)."""

from __future__ import annotations

from pathlib import Path

import pytest

from omi_media.playlist import PlaylistError, natural_key, sort_playlist

M3U = """#EXTM3U
#EXTINF:29,Track 1 - Welcome
/tmp/a/Track 1 - Welcome.mp3
#EXTINF:176,Track 10 - Rule #8
/tmp/a/Track 10 - Rule #8.mp3
#EXTINF:20,Track 2 - Second
/tmp/a/Track 2 - Second.mp3
"""


def _write(tmp_path: Path, text: str = M3U, name: str = "p.m3u") -> Path:
    p = tmp_path / name
    p.write_text(text, encoding="utf-8")
    return p


def test_natural_key_orders_numbers_like_a_human():
    names = ["Track 10.mp3", "Track 2.mp3", "Track 1.mp3"]
    assert sorted(names, key=natural_key) == [
        "Track 1.mp3", "Track 2.mp3", "Track 10.mp3"
    ]


def test_sort_returns_track_order_and_keeps_extinf_attached(tmp_path):
    p = _write(tmp_path)
    result = sort_playlist(p)
    assert result["changed"] is True
    assert result["written"] is False
    lines = result["text"].splitlines()
    assert lines[0] == "#EXTM3U"
    # Each file line is immediately preceded by its own EXTINF.
    assert lines[1].startswith("#EXTINF:29") and lines[2].endswith("Track 1 - Welcome.mp3")
    assert lines[3].startswith("#EXTINF:20") and lines[4].endswith("Track 2 - Second.mp3")
    assert lines[5].startswith("#EXTINF:176") and lines[6].endswith("Track 10 - Rule #8.mp3")


def test_in_place_writes_and_keeps_a_backup(tmp_path):
    p = _write(tmp_path)
    result = sort_playlist(p, in_place=True)
    assert result["written"] is True
    backup = Path(result["backup"])
    assert backup.is_file()
    assert "Track 10" in backup.read_text()
    rewritten = p.read_text()
    assert rewritten.index("Track 2") < rewritten.index("Track 10")


def test_in_place_is_a_noop_when_already_ordered(tmp_path):
    text = """#EXTM3U
/tmp/a/1 - One.mp3
/tmp/a/2 - Two.mp3
"""
    p = _write(tmp_path, text)
    result = sort_playlist(p, in_place=True)
    assert result["changed"] is False
    assert result["written"] is False
    assert sorted(x.name for x in tmp_path.iterdir()) == ["p.m3u"]


def test_dry_run_does_not_write(tmp_path):
    p = _write(tmp_path)
    result = sort_playlist(p, in_place=True, dry_run=True)
    assert result["changed"] is True
    assert result["written"] is False
    assert [x.name for x in tmp_path.iterdir()] == ["p.m3u"]


def test_rejects_pls_and_unknown_formats(tmp_path):
    pls = _write(tmp_path, "[playlist]\nFile1=/a.mp3\n", "p.pls")
    with pytest.raises(PlaylistError):
        sort_playlist(pls)
    txt = _write(tmp_path, "/a.mp3\n", "p.txt")
    with pytest.raises(PlaylistError):
        sort_playlist(txt)
