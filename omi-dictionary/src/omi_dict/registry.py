"""Dictionary registry — discovery, naming and ordering (spec §5–§7)."""

from __future__ import annotations

from pathlib import Path

from . import config as cfg
from .index import Index


def discovered() -> list[dict]:
    """Installed indexes → id/name/entries (priority from config)."""
    d = cfg.data_dir()
    found: dict[str, dict] = {}
    if d.is_dir():
        for db in sorted(d.glob("*.db")):
            idx = Index(db.stem)
            entries = idx.meta("entries")
            found[db.stem] = {
                "id": db.stem,
                "name": idx.meta("name") or db.stem,
                "entries": int(entries) if entries else 0,
            }
    # Order: config priority, then alphabetical.
    conf = cfg.load_config()
    prio = conf["dictionaries"]
    ordered = sorted(
        found.values(),
        key=lambda e: (
            prio.get(e["id"], {}).get("priority", 10**9),
            e["id"],
        ),
    )
    return ordered


def default_id() -> str:
    """Configured default dictionary (spec §7); falls back to 'oed'."""
    conf = cfg.load_config()
    return conf["general"].get("default_dictionary") or "oed"


def configured_name(dict_id: str) -> str | None:
    conf = cfg.load_config()
    entry = conf["dictionaries"].get(dict_id)
    if entry and entry.get("name"):
        return entry["name"]
    return None