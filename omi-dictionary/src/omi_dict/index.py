"""Dictionary indexing / import (spec §3, §20, ADR-001).

`omi-dict import <file.bgl>`:
    file.bgl ──PyGlossary──▶ tabfile (temp) ──parse──▶ SQLite index

The SQLite index is the runtime format.  PyGlossary is import-time only.
"""

from __future__ import annotations

import re
import shutil
import sqlite3
import tempfile
import unicodedata
import zlib
from pathlib import Path

from . import config as cfg

BOILERPLATE_RE = re.compile(
    r"<DIV id=init_OED2.*?</DIV>|<style.*?</style>|<script.*?</script>"
    r"|<IMG\b[^>]*\bonload[^>]*>|<IMG[^>]*>|<link\b[^>]*>",
    re.IGNORECASE | re.DOTALL,
)
SPACES_RE = re.compile(r"\s{2,}")
META_RE = re.compile(r"^##(\w+)\t(.*)$")


def casefold_key(term: str) -> str:
    """Normalised lookup key (NFC + casefold)."""
    return unicodedata.normalize("NFC", term).casefold()


def clean_body(raw: str) -> str:
    """Strip the per-entry boilerplate and normalise line structure.

    ``<BR>`` tags and BGL ``\\t`` segment markers become real newlines so the
    entry keeps its paragraph/sense structure; only runs of spaces are
    collapsed (newlines are preserved for rich rendering).
    """
    body = BOILERPLATE_RE.sub(" ", raw)
    body = body.replace("file://d:/b/lmpn.ttf", "")
    body = re.sub(r"(?i)<br\s*/?>", "\n", body)
    body = body.replace("\\t", "\n").replace("\t", "\n")
    body = re.sub(r"[ \f\v]{2,}", " ", body)
    body = re.sub(r"\n{3,}", "\n\n", body)
    return body.strip()


def strip_html(body: str) -> str:
    """Minimal HTML → readable plain text (paragraphs and sense lines kept)."""
    text = re.sub(r'<a [^>]*bword://([^">]+)[^>]*>', r"\1", body)
    text = re.sub(r"<[^>]+>", "", text)
    text = (text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
            .replace("&nbsp;", " ").replace("&quot;", '"').replace("&#39;", "'"))
    lines: list[str] = []
    for line in text.split("\n"):
        line = re.sub(r"[ \t]{2,}", " ", line).strip()
        if line:
            lines.append("  " + line)
        elif lines and lines[-1] != "":
            lines.append("")
    return "\n".join(lines).strip()


# Tags the DMS popup can render (Qt rich text subset).  Everything else is
# unwrapped/dropped and colours removed so the entry follows the active theme.
_DISPLAY_KEEP = re.compile(r"</?(?:b|i|u|em|strong|br)\b[^>]*>", re.IGNORECASE)
_DISPLAY_TAG = re.compile(r"<[^>]+>")


def to_display_html(body: str) -> str:
    """Sanitised, theme-friendly rich text for the popup (structure only)."""
    h = re.sub(r"</?(?:span|font|a|div|nobr|p)\b[^>]*>", "", body, flags=re.IGNORECASE)
    h = _DISPLAY_TAG.sub(lambda m: m.group(0) if _DISPLAY_KEEP.fullmatch(m.group(0)) else "", h)
    h = (h.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
         .replace("&nbsp;", " ").replace("&quot;", '"').replace("&#39;", "'"))
    h = re.sub(r"[ \t]{2,}", " ", h)
    return "<br>".join(part.strip() for part in h.split("\n") if part.strip())


def find_pyglossary() -> str | None:
    """Locate the pyglossary CLI (uv tool install puts it in ~/.local/bin)."""
    found = shutil.which("pyglossary")
    if found:
        return found
    for candidate in (
        Path.home() / ".local" / "bin" / "pyglossary",
        Path.home() / ".local" / "share" / "uv" / "tools"
        / "pyglossary" / "bin" / "pyglossary",
    ):
        if candidate.is_file():
            return str(candidate)
    return None


def convert_bgl_to_tabfile(bgl_path: Path, out_path: Path) -> None:
    """Run PyGlossary (BGL → Tabfile) into out_path.

    Raises RuntimeError when PyGlossary is missing or conversion fails.
    """
    cli = find_pyglossary()
    if cli is None:
        raise RuntimeError(
            "PyGlossary is required for importing. Install it with: "
            "uv tool install --python 3.12 pyglossary"
        )
    import subprocess

    proc = subprocess.run(
        [cli, str(bgl_path), str(out_path), "--write-format=Tabfile",
         "--no-progress-bar"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0 or not out_path.is_file():
        raise RuntimeError(
            f"PyGlossary failed (rc={proc.returncode}): "
            f"{proc.stderr.strip() or proc.stdout.strip()}"
        )


def _slugify(name: str) -> str:
    s = name.lower().strip()
    s = re.sub(r"\(.*?\)", "", s)  # drop bracketed (2nd Edition) etc.
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "dictionary"


def default_id(source: Path) -> str:
    """Derive a dictionary id from the source file name (spec §6)."""
    stem = source.name
    for ext in (".bgl", ".BGL"):
        if stem.endswith(ext):
            stem = stem[: -len(ext)]
            break
    return _slugify(stem)


class Index:
    """One SQLite dictionary index under the data dir."""

    def __init__(self, dict_id: str) -> None:
        self.dict_id = dict_id
        self.path: Path = cfg.data_dir() / f"{dict_id}.db"

    def exists(self) -> bool:
        return self.path.is_file()

    def open(self) -> sqlite3.Connection:
        if not self.exists():
            raise FileNotFoundError(f"no index for {self.dict_id!r} (run omi-dict import)")
        return sqlite3.connect(self.path)

    def create(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if self.path.exists():
            self.path.unlink()
        conn = sqlite3.connect(self.path)
        conn.execute("PRAGMA journal_mode=OFF")
        conn.execute("PRAGMA synchronous=OFF")
        conn.executescript(
            """
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
            CREATE TABLE entries (
                id INTEGER PRIMARY KEY,
                term TEXT NOT NULL,
                key TEXT NOT NULL,
                body BLOB NOT NULL
            );
            CREATE INDEX idx_entries_key ON entries(key);
            """
        )
        return conn

    def meta(self, key: str) -> str | None:
        with self.open() as conn:
            row = conn.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
            return row[0] if row else None

    def set_meta(self, conn: sqlite3.Connection, key: str, value: str) -> None:
        conn.execute(
            "INSERT INTO meta(key, value) VALUES(?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )

    def add(self, conn: sqlite3.Connection, term: str, body: str) -> None:
        packed = zlib.compress(body.encode("utf-8"), level=6)
        conn.execute(
            "INSERT INTO entries(term, key, body) VALUES(?, ?, ?)",
            (term, casefold_key(term), packed),
        )


def import_bgl(bgl_path: Path, dict_id: str | None = None,
               name: str | None = None, force: bool = False) -> dict:
    """Convert + index a .bgl into the data dir. Idempotent per source hash."""
    bgl_path = Path(bgl_path)
    if not bgl_path.is_file():
        raise FileNotFoundError(f"no such file: {bgl_path}")
    dict_id = dict_id or default_id(bgl_path)
    index = Index(dict_id)
    cfg.ensure_dirs()

    # Change detection (§20): skip a rebuild when nothing changed.
    import hashlib

    h = hashlib.sha256(bgl_path.read_bytes()).hexdigest()
    if not force and index.exists() and index.meta("source_hash") == h:
        return {"id": dict_id, "reused": True, "entries": int(index.meta("entries") or 0)}

    with tempfile.TemporaryDirectory(prefix="omi-dict-") as tmp:
        tabfile = Path(tmp) / "dict.txt"
        convert_bgl_to_tabfile(bgl_path, tabfile)
        conn = index.create()
        try:
            entries = converted = 0
            display_name = name or bgl_path.stem
            for line in tabfile.read_text(encoding="utf-8", errors="replace").splitlines():
                m = META_RE.match(line)
                if m:
                    if m.group(1) == "name":
                        display_name = m.group(2).strip()
                    continue
                if "\t" not in line:
                    continue
                terms, body = line.split("\t", 1)
                body = clean_body(body)
                if not terms or not body:
                    continue
                for single in terms.split("|"):
                    if single.strip():
                        index.add(conn, single.strip(), body)
                        converted += 1
                entries += 1
            index.set_meta(conn, "name", display_name)
            index.set_meta(conn, "source", str(bgl_path))
            index.set_meta(conn, "source_hash", h)
            index.set_meta(conn, "entries", str(converted))
            index.set_meta(conn, "rows", str(entries))
            conn.commit()
        finally:
            conn.close()
    return {"id": dict_id, "reused": False,
            "name": display_name, "entries": converted, "rows": entries}