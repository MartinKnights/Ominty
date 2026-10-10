# ADR-001 — BGL strategy, index format and look-up engine

**Date:** 2026-10-10
**Status:** Accepted (Phase 1 probe concluded)
**Spec refs:** §3 (format), §32 (required decision), §19–20 (performance/indexing)

## Context

The user's dictionaries are Babylon `.bgl` files. The Phase 1 probe
converted every representative file with **PyGlossary 5.4.2** (its
`BabylonBgl` plugin) and found:

| Source | Size | Convert | Tabfile |
|---|---|---|---|
| Word Families.bgl | 31 KB | 0.1 s | 643 lines |
| Roget thesaurus.bgl | 2 MB | 2 s | 17,948 lines |
| Online Etymology.bgl | 2 MB | 1 s | 19,020 lines |
| **OED 2nd Edition.bgl** | 214 MB | **52 s** | **258,813 lines, 890 MB** |

Entries convert to `term[|alt…]\t<body>` rows preserving rich markup
(`<B>`, `<i>`, `<font color>`, `bword://` cross-links). Every OED entry
carries a repeated boilerplate `<DIV id=init_OED2…>` block (embedded JS/CSS,
`file://d:/…` font refs) that should be stripped at import.

## Decision

1. **BGL strategy: convert, don't read directly.** BGL is read with
   **PyGlossary at import time only** and converted to our own format. No
   other tool reads BGL at runtime. PyGlossary is therefore a build/import
   dependency, never a runtime one (spec §124).
2. **Internal format: one SQLite database per dictionary**, schema:

   ```sql
   meta(key, value)      -- name, source file, entry count, converted-at
   entries(id, term, key, body)
     -- term: single headword; one row per | alternate in the BGL
     -- key:  case-folded (NFC) term, indexed for exact + prefix lookup
     -- body: zlib-compressed, boilerplate-stripped HTML
   ```

   Storage and lookups live in the Python standard library (`sqlite3`,
   `zlib`); a text preview is derived from `body` at query time.
3. **Lookup semantics:** exact match on `key`; if the BGL stored the word as
   an alternate (`circumspect|circumspectly`) it matched because alternates
   are split into their own rows at import. Prefix search (Phase 3) uses the
   `key` index with a bounded range scan.
4. **Reimport policy (§20):** `import` is idempotent; a content/metadata hash
   plus mtime avoids rebuilding unchanged dictionaries.
5. **Service model: on-demand process, no daemon** (spec §32). SQLite reads
   are ~ms and process startup is instant; a resident service buys nothing
   for v1.

## Consequences

- PyGlossary (Python 3.12+) is the only non-stdlib dependency, and only on
  the import path. Documented for Void/LMDE/Mint packaging (spec §33).
- `.bgl` source files can stay outside the data dir; the data dir holds the
  prepared indexes (+ future `meta` files) and is the discovery source of
  truth (§4–5).