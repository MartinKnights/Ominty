"""CLI integration tests (Omi Media Launcher spec §9–§11).

Each test runs `bin/omi-media` in a sandboxed XDG environment with a
temporary root + config, mirroring the omi-dict test conventions.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "omi-media"


def _env(tmp_path: Path) -> dict:
    root = tmp_path / "playlists"
    for cat in ("Audio", "Courses", "Music", "Video"):
        (root / cat).mkdir(parents=True, exist_ok=True)
    (root / "Video" / "Linux Administration.m3u").write_text("#EXTM3U\n", encoding="utf-8")
    (root / "Video" / "PHP Course.m3u").write_text("#EXTM3U\n", encoding="utf-8")
    (root / "Music" / "Gospel.m3u").write_text("#EXTM3U\n", encoding="utf-8")
    (root / "Audio" / "Classical.m3u").write_text("#EXTM3U\n", encoding="utf-8")

    cfg_file = tmp_path / "media.toml"
    cfg_file.write_text(
        f'[general]\nroot = "{root}"\n'
        "[categories.video]\nname = \"Video\"\nplayer = \"vlc\"\n"
        "[categories.music]\nname = \"Music\"\nplayer = \"mpv\"\n",
        encoding="utf-8",
    )
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "cfg")
    env["XDG_STATE_HOME"] = str(tmp_path / "state")
    env["XDG_RUNTIME_DIR"] = str(tmp_path / "run")
    (tmp_path / "run").mkdir(exist_ok=True)
    return env, cfg_file


def _run(env, cfg_file, *args):
    return subprocess.run(
        [str(BIN), "--config", str(cfg_file), *args],
        capture_output=True, text=True, env=env, timeout=30,
    )


def test_categories_json(tmp_path):
    env, cfg = _env(tmp_path)
    out = _run(env, cfg, "categories", "--json")
    assert out.returncode == 0
    data = json.loads(out.stdout)
    by_id = {c["id"]: c for c in data["categories"]}
    assert by_id["video"]["playlist_count"] == 2
    assert by_id["music"]["playlist_count"] == 1
    assert by_id["audio"]["playlist_count"] == 1
    # Empty folders are hidden until they contain a playlist.
    assert "courses" not in by_id
    assert [c["id"] for c in data["categories"]] == ["audio", "music", "video"]
    # media.toml still overrides the player for a folder that exists.
    assert by_id["music"]["player"] == "mpv"
    assert by_id["video"]["player"] == "vlc"


def test_playlists_json(tmp_path):
    env, cfg = _env(tmp_path)
    out = _run(env, cfg, "playlists", "video", "--json")
    assert out.returncode == 0
    data = json.loads(out.stdout)
    assert data["category"] == "video"
    titles = [p["title"] for p in data["playlists"]]
    assert titles == ["Linux Administration", "PHP Course"]


def test_play_dry_run(tmp_path):
    env, cfg = _env(tmp_path)
    out = _run(env, cfg, "play", "video", "PHP Course.m3u", "--dry-run", "--json")
    assert out.returncode == 0
    data = json.loads(out.stdout)
    assert data["status"] == "dry_run"
    assert data["command"][0] == "vlc"
    assert data["command"][-1].endswith("PHP Course.m3u")
    assert "--force-window=yes" not in data["command"]  # vlc always has a window


def test_play_accepts_title_without_extension(tmp_path):
    env, cfg = _env(tmp_path)
    out = _run(env, cfg, "play", "music", "Gospel", "--dry-run", "--json")
    assert out.returncode == 0
    data = json.loads(out.stdout)
    assert data["command"][0] == "mpv"
    assert data["command"][-1].endswith("Gospel.m3u")


def test_audio_default_uses_vlc(tmp_path):
    env, cfg = _env(tmp_path)
    out = _run(env, cfg, "play", "audio", "Classical.m3u", "--dry-run", "--json")
    assert out.returncode == 0
    data = json.loads(out.stdout)
    # audio uses the same MPRIS-capable player as video (real window + pill)
    assert data["command"][0] == "vlc"
    assert data["command"][-1].endswith("Classical.m3u")


def test_stop_idle_when_nothing_playing(tmp_path):
    env, cfg = _env(tmp_path)
    out = _run(env, cfg, "stop", "--json")
    assert out.returncode == 0
    assert json.loads(out.stdout)["status"] == "idle"


def test_unknown_category_errors(tmp_path):
    env, cfg = _env(tmp_path)
    out = _run(env, cfg, "playlists", "nope", "--json")
    assert out.returncode == 1
    assert "unknown category" in out.stderr


def test_missing_playlist_errors(tmp_path):
    env, cfg = _env(tmp_path)
    out = _run(env, cfg, "play", "video", "missing.m3u")
    assert out.returncode == 1
    assert "no playlist" in out.stderr


def test_version():
    out = subprocess.run([str(BIN), "-V"], capture_output=True, text=True)
    assert out.returncode == 0
    assert "omi-media" in out.stdout