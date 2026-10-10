"""Exact entry lookup (spec §8–§9, ADR-001).

Exact match on the case-folded key.  A BGL alternate such as
``circumspect|circumspectly`` was split into per-headword rows at import, so
plain exact lookup already finds it.
"""

from __future__ import annotations

import zlib

from . import config as cfg
from .errors import DictionaryNeedsRebuild, NoEntryFound
from .index import Index, casefold_key, strip_html, to_display_html
from .registry import configured_name


def _read_body(row) -> str:
    return zlib.decompress(row[1]).decode("utf-8")


def structure(html: str) -> dict:
    """Best-effort structured fields (spec §9); missing fields stay empty."""
    import re

    pos_match = re.search(r"<[Ii]>(?:<[Ff][Oo][Nn][Tt][^>]*>)?\s*([a-z]+)\s*</[Ff][Oo][Nn][Tt]>?", html)
    pron_match = re.search(r"\(([^)]{2,40})\)", html)
    return {
        "pronunciation": pron_match.group(1).strip() if pron_match else "",
        "parts_of_speech": [pos_match.group(1)] if pos_match else [],
        "definitions": [],
        "etymology": "",
        "examples": [],
    }


def lookup(dict_id: str, word: str) -> dict:
    """Return the entry for an exact headword, or raise NoEntryFound."""
    conn = Index(dict_id).open()
    try:
        row = conn.execute(
            "SELECT term, body FROM entries WHERE key = ?", (casefold_key(word),)
        ).fetchone()
    finally:
        conn.close()
    if row is None:
        raise NoEntryFound(f"No entry found for {word!r} in {dict_id!r}")
    term, packed = row
    html = _read_body((term, packed))
    structured = structure(html)
    return {
        "headword": term,
        "html": html,
        "display": to_display_html(html),
        "text": strip_html(html),
        **structured,
    }


def result_shape(query: str, dict_id: str, name: str, entry: dict) -> dict:
    """The stable JSON shape (spec §9)."""
    return {
        "query": query,
        "dictionary": {"id": dict_id, "name": name},
        "entry": {
            "headword": entry["headword"],
            "pronunciation": entry["pronunciation"],
            "parts_of_speech": entry["parts_of_speech"],
            "definitions": entry["definitions"],
            "etymology": entry["etymology"],
            "examples": entry["examples"],
            "html": entry["html"],
            "text": entry.get("text", ""),
            "display": entry.get("display", ""),
        },
    }


def lookup_all(word: str, dictionaries: list[dict]) -> dict:
    """All-Dictionaries mode (spec §11): best effort per dictionary."""
    results = []
    errors = []
    for d in dictionaries:
        try:
            entry = lookup(d["id"], word)
            results.append(result_shape(word, d["id"], d["name"], entry))
        except NoEntryFound:
            continue
        except Exception as exc:  # noqa: BLE001 — one bad dict must not win
            errors.append({"id": d["id"], "message": str(exc)})
    if not results:
        raise NoEntryFound(f"No entry found for {word!r} in any dictionary")
    return {"query": word, "results": results, "errors": errors}