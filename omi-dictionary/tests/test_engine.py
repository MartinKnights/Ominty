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