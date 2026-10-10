# Omi Dictionary Service — AGENT.md

This module is the **Omi dictionary service**: a lightweight, local,
keyboard-first dictionary subsystem for Ominty.  The DMS popup is *one
presentation layer* over this service; the CLI (`bin/omi-dict`) is the
contract.  Full spec: `../Omi Dictionary Service.md` (project root).

## Architecture (spec §2, §26)

```
Selected Text → omi-selection → omi-dict (core) → registry → [OED, Roget, …]
                                                          → Structured Result
                                                          → CLI · DMS popup · Pi
```

- **Data:** converted dictionaries + indexes under
  `~/.local/share/omi/dictionaries/` (source of truth; directory scan for
  discovery, hash/mtime change detection — never re-import unchanged files).
- **Engine:** pure-Python stdlib at runtime (sqlite3).  **No daemon.**
  On-demand processes only.
- **Converters (PyGlossary etc.) are import-time tools only** — never a
  runtime dependency.
- **Selection:** standalone component (`src/omi_dict/selection.py`) wrapping
  the existing `clip-tool` primary/clipboard primitives; session-aware.

## Rules

- Local-first, fully offline for normal lookup (§23).
- Never log the looked-up words by default (§22).  Logs go to
  `~/.local/state/omi/dictionary/`.
- No UI (DMS) component contains lookup logic.
- No online APIs / AI definitions in v1 (§31).
- Keep dependencies Void-installable (§33) — stdlib where possible.
- Architectural decisions are recorded as ADRs in `docs/decisions/`
  (six required topics in spec §32).

## Status

Phase 1 (dictionary PoC) is in progress.  See `docs/architecture.md` and the
project `PROGRESS.md` change log.