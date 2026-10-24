"""XDG paths and optional configuration (Omi Media Launcher spec §4–§6).

    config  ~/.config/omi/media.toml   (optional — root + per-folder overrides)
    state   ~/.local/state/omi/media/  (reserved for Phase 2 progress logs)

Shape:

    [general]
    root = "~/Playlist"

    [categories.Music]          # key matching the folder name
    player = "mpv"
    player_args = ["--no-video"]

    [categories.Films]          # or match by path
    directory = "{root}/Video"
    player = "vlc"

The category list is **not** configured: it is the set of subfolders under the
root that contain a playlist (see ``discovery.discover_categories``). This file
only overrides how a folder is presented and played. Entries for folders that
do not exist are ignored, which makes renaming a folder a complete migration.
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

#: Created by install.sh as a starting point. They are ordinary folders: rename
#: or delete them and the launcher follows.
STARTER_FOLDERS = ("Audio", "Courses", "Music", "Video")


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


def folder_overrides(cfg: dict) -> dict[str, dict]:
    """Per-folder overrides from media.toml, keyed by config key.

    Only ``name``, ``player`` and ``player_args`` are meaningful. ``directory``
    is kept so discovery can match an override to a folder by path; entries for
    folders that do not exist are ignored there, not here.
    """
    root = effective_root(cfg)
    out: dict[str, dict] = {}
    for key, spec in (cfg.get("categories") or {}).items():
        item = dict(spec)
        item.setdefault("name", str(key))
        item.setdefault("player", "vlc")
        item.setdefault("player_args", [])
        for field in ("name", "directory"):
            if field in item:
                item[field] = str(item[field]).replace("{root}", root)
        if not isinstance(item["player_args"], list):
            item["player_args"] = []
        item["player_args"] = [str(a) for a in item["player_args"]]
        out[str(key)] = item
    return out
