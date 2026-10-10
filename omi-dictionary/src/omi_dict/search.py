"""Headword search — prefix + case-insensitive (spec §10, Phase 3).

Exact lookup and search are separate operations.  Search returns candidate
headwords for a prefix using the case-folded ``key`` indexed column (bounded
range scan → uses the index; exact lookup never slows down).
"""

from __future__ import annotations

from .index import Index, casefold_key


def search(dict_id: str, prefix: str, limit: int = 40) -> list[str]:
    """Candidate headwords for a prefix in one dictionary."""
    key = casefold_key(prefix)
    hi = key + "\U0010FFFF"  # exclusive upper bound (all Unicode)
    conn = Index(dict_id).open()
    try:
        rows = conn.execute(
            "SELECT term FROM entries WHERE key >= ? AND key < ? "
            "ORDER BY key LIMIT ?",
            (key, hi, limit),
        ).fetchall()
    finally:
        conn.close()
    return [r[0] for r in rows]


def search_all(prefix: str, dictionaries: list[dict], limit: int = 40) -> list[dict]:
    """Candidates across dictionaries, labelled by dict id (for All mode)."""
    out: list[dict] = []
    for d in dictionaries:
        try:
            hits = search(d["id"], prefix, limit)
        except Exception:  # noqa: BLE001 — one bad dict must not win
            continue
        out.append({"dictionary": {"id": d["id"], "name": d["name"]},
                    "headwords": hits})
    return out