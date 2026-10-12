"""XDG paths and optional configuration (Omi Media Launcher spec §4–§6).

    config  ~/.config/omi/media.toml   (optional — categories + players)
    state   ~/.local/state/omi/media/  (reserved for Phase 2 progress logs)

Shape:

    [general]
    root = "/home/martin/Playlist"

    [categories.video]
    name = "Video"
    directory = "/home/martin/Playlist/Video"
    player = "vlc"
    player_args = []

Priorities: a user config file overlays the built-in defaults, so the
tool works out of the box with the standard four folders.  `OMI_MEDIA_ROOT`
overrides the default root (handy for tests and new installs).
"""

from __future__ import annotations

import os
import tomllib
from pathlib import Path


def xdg_home(env_var: str, fallback_dir: str) -> Path:
    env = os.environ.get(env_var)
    if env:
        return Path(env)
    return Path.home() / fallback_dir


def config_path() -> Path:
    return xdg_home("XDG_CONFIG_HOME", ".config") / "omi" / "media.toml"


def state_dir() -> Path:
    return xdg_home("XDG_STATE_HOME", ".local/state") / "omi" / "media"


DEFAULT_ROOT = os.environ.get("OMI_MEDIA_ROOT") or str(Path.home() / "Playlist")

DEFAULT_CATEGORIES = {
    # mpv's force-window=auto shows no window for audio files without cover
    # art, so audio/music always request the controller window explicitly.
    "audio": {"name": "Audio", "directory": "{root}/Audio", "player": "mpv", "player_args": ["--force-window=yes"]},
    "courses": {"name": "Courses", "directory": "{root}/Courses", "player": "vlc", "player_args": []},
    "music": {"name": "Music", "directory": "{root}/Music", "player": "mpv", "player_args": ["--force-window=yes"]},
    "video": {"name": "Video", "directory": "{root}/Video", "player": "vlc", "player_args": []},
}


def load_config(path: Path | None = None) -> dict:
    """Load ~/.config/omi/media.toml; never mandatory.

    Returns ``{"general": ..., "categories": ...}`` with a matching shape
    whether or not the file exists.
    """
    path = Path(path) if path else config_path()
    cfg: dict = {"general": {}, "categories": {}}
    if not path.is_file():
        return cfg
    try:
        with open(path, "rb") as f:
            raw = tomllib.load(f)
    except (tomllib.TOMLDecodeError, OSError):
        return cfg
    cfg["general"] = dict(raw.get("general", {}) or {})
    cfg["categories"] = {
        str(k): dict(v) for k, v in (raw.get("categories", {}) or {}).items()
    }
    return cfg


def effective_root(cfg: dict) -> str:
    return str(cfg.get("general", {}).get("root") or DEFAULT_ROOT)


def categories(cfg: dict) -> dict[str, dict]:
    """Resolved categories: built-in defaults merged with the user config.

    Merging is **per key**: a user override that sets only e.g. ``player``
    keeps the default ``player_args`` (so mpv's forcing flags survive a
    partial override).  Any ``directory`` value containing ``{root}`` has the
    effective root interpolated.
    """
    root = effective_root(cfg)
    merged = {**DEFAULT_CATEGORIES, **cfg.get("categories", {})}
    result: dict[str, dict] = {}
    for cid, spec in merged.items():
        item = dict(DEFAULT_CATEGORIES.get(cid, {}))
        item.update(spec)
        item.setdefault("name", cid.capitalize())
        item.setdefault("player", "vlc")
        item.setdefault("player_args", [])
        item["name"] = str(item["name"])
        # Directory falls back to {root}/<Name> so an override that omits
        # `directory` still lands on the same folder the defaults use.
        item.setdefault("directory", f"{root}/{item['name']}")
        item["directory"] = str(item["directory"]).replace("{root}", root)
        item["player"] = str(item["player"])
        if not isinstance(item["player_args"], list):
            item["player_args"] = []
        item["player_args"] = [str(a) for a in item["player_args"]]
        item["id"] = cid
        result[cid] = item
    return result