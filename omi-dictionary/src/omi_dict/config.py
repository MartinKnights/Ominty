"""XDG paths and optional configuration (spec §4, §6).

    data    ~/.local/share/omi/dictionaries/   (source of truth, user dir)
    config  ~/.config/omi/dictionary.toml      (optional — name/priority/default)
    state   ~/.local/state/omi/dictionary/     (logs)

The user data dir takes precedence over a future system-wide
/usr/share/omi/dictionaries/.
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


def data_dir() -> Path:
    return xdg_home("XDG_DATA_HOME", ".local/share") / "omi" / "dictionaries"


def config_path() -> Path:
    return xdg_home("XDG_CONFIG_HOME", ".config") / "omi" / "dictionary.toml"


def state_dir() -> Path:
    return xdg_home("XDG_STATE_HOME", ".local/state") / "omi" / "dictionary"


def log_path() -> Path:
    return state_dir() / "log"


def load_config(path: Path | None = None) -> dict:
    """Load ~/.config/omi/dictionary.toml; never mandatory.

    Returns ``{"general": {...}, "dictionaries": {...}}`` with a matching
    shape whether or not the file exists.
    """
    path = Path(path) if path else config_path()
    cfg: dict = {"general": {}, "dictionaries": {}}
    if not path.is_file():
        return cfg
    try:
        with open(path, "rb") as f:
            raw = tomllib.load(f)
    except (tomllib.TOMLDecodeError, OSError):
        return cfg
    cfg["general"] = dict(raw.get("general", {}) or {})
    cfg["dictionaries"] = {
        str(k): dict(v) for k, v in (raw.get("dictionaries", {}) or {}).items()
    }
    return cfg


# Avoid importing near the top in case the user dir is not writable.
def ensure_dirs() -> None:
    for d in (data_dir(), state_dir()):
        d.mkdir(parents=True, exist_ok=True)
    (state_dir() / "css").mkdir(parents=True, exist_ok=True)