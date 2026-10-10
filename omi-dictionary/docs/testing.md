# Omi Dictionary Service — Testing

Reference: spec §28–§30.  This file records what is tested and how
(machine-verified evidence), updated as phases land.

## Environments

Core CLI must pass on:

| Platform | Session | Status |
|---|---|---|
| Ominty-Mint (this Dell) | Niri + DMS + Wayland | active dev |
| OmiVoid | Void + Niri + Wayland | to verify later |
| Ominty-LMDE | LMDE + Niri + Wayland | to verify later |

The `omi-dict` CLI must work with no Niri/DMS present.

## Automated tests (`tests/`)

Run: `python3 -m pytest tests/` from `omi-dictionary/`.

## Selection matrix (Phase 5)

Application → selection method → success/failure → clipboard side effects →
latency → limitations.  Recorded here when executed.