# Omi Dictionary Service — Dictionary Formats

Records what the on-machine dictionaries actually are and how they are
processed.  Living document — updated as the Phase 1 probe concludes.

## The source files

10 Babylon `.bgl` dictionaries at `/home/martin/Documents/Dictionaries/`:

| File | Size |
|---|---|
| Oxford English Dictionary (2nd Edition) .bgl | 214 MB |
| Babylon (OED) Oxford English Dictionary (20-Volume) 2012.bgl | 21 MB |
| britannica_concise_encyclopedi.bgl | 16 MB |
| Oxford Learner's Thesaurus.bgl | 3.6 MB |
| Online Etymology Dictionary1.1.bgl | 2.0 MB |
| Babylon Roget the new thesaurus.bgl | 2.0 MB |
| Business Dictionary.bgl | 0.6 MB |
| DictionaryOfFinancialAndBusinessTerms0.4.bgl | 0.2 MB |
| word and phrase origins1.0.bgl | 0.26 MB |
| Word Families.bgl | 31 KB |

All begin with the BGL package magic `12 34 00 02 …` (big-endian `0x1234`,
format version 2).

## Processing pipeline (proposed)

```
.bgl → PyGlossary (import-time) → StarDict/tabfile → own SQLite index
```

PyGlossary is a **build/import-time** tool only.  The runtime reader is the
project's own (stdlib).  The index keeps the rich entry body and derives a
case-folded headword key for fast exact + prefix lookup.

## Probe results (2026-10-10)

PyGlossary **5.4.2** (`BabylonBgl` plugin) reads every local `.bgl` without
issue (magic `12 34 00 02` = format v2).  Converted to Tabfile
(`term[|alt…]\t<body>`, `##` metadata lines):

| Source | Size | Convert | Tabfile |
|---|---|---|---|
| Word Families.bgl | 31 KB | 0.1 s | 643 lines |
| Babylon Roget the new thesaurus.bgl | 2 MB | 2 s | 17,948 lines |
| Online Etymology Dictionary1.1.bgl | 2 MB | 1 s | 19,020 lines |
| **OED 2nd Edition.bgl** | 214 MB | **52 s** | **258,813 lines, 890 MB** |

Imported into `~/.local/share/omi/dictionaries/` (SQLite, ADR-001):

| id | headwords | db size |
|---|---|---|
| `oed` | 336,273 | 824 MB |
| `etymology` | 20,681 | 4.8 MB |
| `roget` | 17,928 | 5.7 MB |
| `wordfamilies` | 3,392 | 0.6 MB |

Format notes:

- Multi-headword BGL terms arrive as `a|b` alternates; the importer splits
  them into one row per headword so exact lookup matches both.
- OED entries each carry a per-entry bootstrap block (`<DIV id=init_OED2>`,
  embedded CSS/JS, `<IMG onload=…>`, `file://d:/…` font refs, `bword://`
  cross-links).  The bootstrap is stripped at import; `bword://` terms are
  kept as plain text.
- OED definitions are dense prose with historical citations — the body
  does not compress heavily, hence the 824 MB index for the full 2nd ed.
- Exact lookup latency (CLI): ~75 ms cold (process start + SQLite + zlib).