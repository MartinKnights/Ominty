# Omi Dictionary Service

A lightweight, **local**, keyboard-first dictionary subsystem for
Ominty/OmiVoid.  Select a word, press `Ctrl+Shift+A`, get the Oxford
definition — no internet, no dictionary app, no daemon.

```
Select word → Ctrl+Shift+A → Omi Dictionary popup → Oxford definition
```

The popup is one presentation layer; the whole thing is a reusable service
exposed through `omi-dict` (CLI), the DMS popup, and later the Pi agent.

## Layout

| Path | Purpose |
|---|---|
| `bin/omi-dict` | the CLI (the stable contract) |
| `src/omi_dict/` | registry, lookup, search, index, selection, output |
| `adapters/` | format adapters (bgl conversion, stardict) |
| `integrations/` | DMS popup, Niri binding, Pi tooling |
| `config/dictionary.toml.example` | optional user config |
| `docs/` | architecture, formats, selection, testing, ADRs |

## Dictionaries

Dictionaries live in `~/.local/share/omi/dictionaries/` (drop a file in;
it is discovered automatically).  Source `.bgl` files are imported with
`omi-dict import`.  Optional config: `~/.config/omi/dictionary.toml`.

## Status

**v1 complete** (all phases in `docs/architecture.md`).  Select a word →
`Ctrl+Shift+A` → DMS dictionary popup with the OED entry; or use the CLI
(`omi-dict lookup/search/dictionaries/selection`).  Verified against the OED
2nd Edition (336k headwords), Online Etymology, Roget and Word Families.