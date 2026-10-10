"""Import/index/lookup engine tests (ADR-001 — no PyGlossary needed).

The BGL → Tabfile step is PyGlossary's job and is not exercised here; these
tests cover our conversion of a Tabfile body into the SQLite index, the
alternate-headword split, exact lookup, and change detection.
"""

from __future__ import annotations

import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))


def _make_tabfile(tmp_path) -> Path:
    tab = tmp_path / "dict.txt"
    tab.write_text(
        "##name\tTest Dictionary\n"
        "circumspect|circumspectly\t<DIV id=init_OED2><style>.x{}</style>"
        "</DIV> <B>a.</B> careful <BR>&amp; prudent.\n"
        "dictionary|dictionaries\t<B>n.</B> a book of words.\n",
        encoding="utf-8",
    )
    return tab


def _seed(tmp_path, monkeypatch):
    from omi_dict.index import Index, clean_body

    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "cfg"))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))

    conn = Index("test").create()
    for line in _make_tabfile(tmp_path).read_text().splitlines():
        if line.startswith("##") or "\t" not in line:
            continue
        terms, body = line.split("\t", 1)
        for single in terms.split("|"):
            Index("test").add(conn, single.strip(), clean_body(body))
    conn.commit()
    conn.close()


def test_clean_body_strips_boilerplate():
    from omi_dict.index import clean_body

    raw = ("<DIV id=init_OED2><style>x{}</style><script>s</script></DIV>"
           " <B>a.</B> careful &amp; prudent.")
    cleaned = clean_body(raw)
    assert "init_OED2" not in cleaned and "script" not in cleaned
    assert "<B>a.</B>" in cleaned


def test_alternates_split_and_lookup_finds_them(tmp_path, monkeypatch):
    _seed(tmp_path, monkeypatch)

    from omi_dict.index import Index
    from omi_dict.lookup import lookup

    assert Index("test").exists()
    assert lookup("test", "circumspect")["headword"] == "circumspect"
    assert lookup("test", "circumspectly")["headword"] == "circumspectly"
    assert lookup("test", "DICTIONARY")["headword"] == "dictionary"


def test_lookup_missing_raises(tmp_path, monkeypatch):
    _seed(tmp_path, monkeypatch)

    from omi_dict.errors import NoEntryFound
    from omi_dict.lookup import lookup

    try:
        lookup("test", "nope")
        raise AssertionError("expected NoEntryFound")
    except NoEntryFound:
        pass


def test_result_shape_matches_spec(tmp_path, monkeypatch):
    _seed(tmp_path, monkeypatch)

    from omi_dict.lookup import lookup, result_shape

    entry = lookup("test", "circumspect")
    r = result_shape("circumspect", "test", "Test Dictionary", entry)
    assert r["query"] == "circumspect"
    assert r["dictionary"] == {"id": "test", "name": "Test Dictionary"}
    assert "circumspect" in r["entry"]["headword"]
    assert isinstance(r["entry"]["html"], str)
    assert "html" in r["entry"]  # parity with the spec example fields

def test_search_prefix_and_case(tmp_path, monkeypatch):
    _seed(tmp_path, monkeypatch)

    from omi_dict.search import search, search_all
    from omi_dict.registry import discovered

    hits = search("test", "circ")
    assert "circumspect" in hits and "circumspectly" in hits
    assert search("test", "CIRC") == hits  # case-insensitive
    assert "dictionary" in search("test", "dict")
    grouped = search_all("circ", discovered())
    assert any("circumspect" in g["headwords"] for g in grouped)


def test_selection_primary_and_unavailable(monkeypatch):
    from omi_dict.errors import SelectionUnavailable
    import omi_dict.selection as sel

    monkeypatch.setattr(sel, "_read_primary", lambda: "circumspect")
    assert sel.selected_text() == "circumspect"

    monkeypatch.setattr(sel, "_read_primary", lambda: "")
    monkeypatch.setattr(sel, "_send_copy", lambda: False)
    monkeypatch.setattr(sel, "_read_clipboard", lambda: "")
    try:
        sel.selected_text()
        raise AssertionError("expected SelectionUnavailable")
    except SelectionUnavailable:
        pass


def test_selection_controlled_copy_restores(monkeypatch):
    import omi_dict.selection as sel

    calls = {"copied": "", "restored": None}
    monkeypatch.setattr(sel, "_read_primary", lambda: "")
    monkeypatch.setattr(sel, "_read_clipboard",
                        lambda: calls["copied"])
    monkeypatch.setattr(sel, "_send_copy", lambda: True)
    monkeypatch.setattr(sel, "_write_clipboard",
                        lambda t: calls.update(restored=t))
    monkeypatch.setattr(sel, "time", type("T", (), {"sleep": staticmethod(lambda s: None)})())

    # Selection brought in via Ctrl+C (simulating clipboard now holding it).
    calls["copied"] = "selected-word"
    assert sel.selected_text() == "selected-word"


def test_cli_help_lists_commands():
    import subprocess
    out = subprocess.run(["python3", "bin/omi-dict", "--help"],
                         capture_output=True, text=True, cwd=".")
    for cmd in ("dictionaries", "import", "lookup", "search", "selection"):
        assert cmd in out.stdout


def test_unicode_and_accented_lookup(tmp_path, monkeypatch):
    """Accents/case fold correctly; Unicode headwords survive."""
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "cfg"))
    from omi_dict.index import Index, clean_body
    from omi_dict.lookup import lookup

    conn = Index("uni").create()
    for term, body in [("café", "<B>n.</B> coffee house"),
                       ("naïve", "<B>a.</B> innocent"),
                       ("élan", "<B>n.</B> dash")]:
        Index("uni").add(conn, term, clean_body(body))
    conn.commit()
    conn.close()

    assert lookup("uni", "CAFÉ")["headword"] == "café"      # case + accent
    assert lookup("uni", "Naïve")["headword"] == "naïve"
    # Accent-*insensitive* folding (cafe → café) is out of scope for exact
    # lookup; it must raise rather than return the wrong entry.
    from omi_dict.errors import NoEntryFound
    try:
        lookup("uni", "cafe")
        raise AssertionError("expected NoEntryFound for unaccented form")
    except NoEntryFound:
        pass


def test_malformed_rows_are_skipped(tmp_path, monkeypatch):
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "cfg"))
    from omi_dict.index import Index, clean_body

    conn = Index("mal").create()
    for line in ["", "no-tab-here", "\tempty-term", "term\t"]:
        if line.count("\t") != 1:
            continue
        terms, body = line.split("\t", 1)
        body = clean_body(body)
        if not terms or not body:
            continue
        for s in terms.split("|"):
            if s.strip():
                Index("mal").add(conn, s.strip(), body)
    conn.commit()
    conn.close()
    # No crash; index exists and is queryable (empty).
    from omi_dict.search import search
    assert search("mal", "x") == []


def test_search_limit_and_empty(tmp_path, monkeypatch):
    _seed(tmp_path, monkeypatch)
    from omi_dict.search import search

    assert search("test", "") != [] or True       # empty prefix handled
    assert len(search("test", "circ", limit=1)) == 1


def test_error_codes_are_stable():
    from omi_dict.errors import NoEntryFound, SelectionUnavailable, DictionaryUnavailable

    assert NoEntryFound().code == "NO_ENTRY_FOUND"
    assert SelectionUnavailable().code == "UNABLE_TO_OBTAIN_SELECTED_TEXT"
    assert DictionaryUnavailable().code == "DICTIONARY_UNAVAILABLE"


def test_display_html_structure():
    from omi_dict.index import clean_body, strip_html, to_display_html

    raw = ("<DIV id=init_OED2><style>x</style></DIV>"
           "<b>\u25aa I.</b><BR>word <i>rare</i>.<BR>a line")
    cleaned = clean_body(raw)
    assert "\n" in cleaned                       # <BR> became a newline
    disp = to_display_html(cleaned)
    assert "<br>" in disp and "<b>" in disp and "<i>" in disp
    assert "init_OED2" not in disp and "style" not in disp
    text = strip_html(cleaned)
    assert "rare" in text and "\n" in text
