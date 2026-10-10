# Omi Dictionary Service — Architecture

> Reference: `Omi Dictionary Service.md` (project root).  Status: Phase 1.

The service follows a strict layering.  No UI component contains lookup
logic; no lookup logic knows about DMS.

```
            Selected Text
                  │
                  ▼
          omi-selection (clip-tool primary → clipboard fallback)
                  │
                  ▼
              omi-dict (CLI = the contract)
                  │
        ┌─────────┴─────────┐
        │   Dictionary Core │   registry → lookup → search
        └─────────┬─────────┘
                  ▼
          indexed dictionaries
       (~/.local/share/omi/dictionaries)
                  │
   ┌──────────────┼──────────────┐
   ▼              ▼              ▼
  CLI           DMS popup       Pi (later)
```

## Data flow (per dictionary)

```
.bgl  ──omi-dict import──▶  converted + SQLite index  ──lookup/search──▶  result
        (PyGlossary at       (stdlib runtime only,      (structured + html,
         import time only)    prefix + case-folded key)   spec §9)
```

## Components

| Component | File(s) | Responsibility |
|---|---|---|
| Registry | `src/omi_dict/registry.py` | discover/scan/name dictionaries (§5-6) |
| Lookup | `src/omi_dict/lookup.py` | exact-entry retrieval (default/--dictionary/--all) |
| Search | `src/omi_dict/search.py` | prefix + case-insensitive candidates (§10) |
| Index | `src/omi_dict/index.py` | import + change detection (§20) |
| Selection | `src/omi_dict/selection.py` | selected-text acquisition (§12) |
| Output | `src/omi_dict/output.py` | text/JSON shapes (§8-9) |

## Decisions (locked or open)

| Topic | Status |
|---|---|
| BGL strategy | Phase 1 probe pending → ADR-001 |
| Internal index format | Phase 1 |
| Lookup/search engine | Phase 1 |
| Wayland selection | reuse `clip-tool`; Phase 5 validates app matrix |
| DMS mechanism | DMS plugin overlay (keybinds-sheet pattern); ADR in Phase 7 |
| Service model | **on-demand process, no daemon** (locked, spec §32) |

## Phases (spec §27)

1. dictionary PoC — ✅ **done** (`omi-dict import` + `lookup`; ADR-001)
2. registry — ✅ **done** (discovery, id/name, default, change detection)
3. search — ⏳ next
4. JSON API — ✅ basic (spec §9 shape, incl. `--all`)
5. selection — ⏳
6. Niri shortcut + action — ⏳
7. DMS popup — ⏳
8. multi-dict UI — ⏳
9. interactive search — ⏳
10. hardening — ⏳