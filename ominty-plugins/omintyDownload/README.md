# Ominty Download Manager (`omintyDownload`)

A **native** DMS plugin: an aria2-based download manager for Ominty. Built
natively on the DankMaterialShell plugin API — not ported.

## What it does
- Add an `http(s)` URL from the overlay (bar pill / `Ctrl+Shift+D` / IPC).
- Parallel queue with per-item **progress, speed, status** (active / waiting /
  paused / complete / error).
- **Pause / Resume / Remove** per row.
- Persistent across sessions: the aria2 daemon keeps a session file and
  resumes downloads (`--continue=true`, `--save-session`).

## Architecture
```
overlay (OmintyDownload.qml, daemon)   ← presentation only
   │  shells out: helpers/ominty-dl.py  add|list|pause|resume|remove|start
   ▼
helpers/ominty-dl.py                     ← aria2 JSON-RPC (stdlib only)
   │  spawns a per-user aria2 RPC daemon on 127.0.0.1:6801 (secret: ominty)
   ▼
aria2c (uses ~/.local/bin/aria2c-wrapper → LD_LIBRARY_PATH=~/.local/lib)
```

- State: session at `~/.local/state/omi-download/session`; files to `~/Downloads`
  (`OMINTY_DL_DIR` overrides).
- `plugin.json` — `type: daemon`, overlay via `PanelWindow` (dim has **no
  click-to-close** — a DMS ghost-click bug previously dropped overlays).

## Install
```sh
ln -sfn "$PWD" ~/.config/DankMaterialShell/plugins/omintyDownload
dms restart                       # discover the new plugin
dms ipc call plugins enable omintyDownload
dms ipc call omintyDownload toggle
```
Keybinding: `Ctrl+Shift+D` (action `app.download.toggle` in ominty-core).

## Note
Requires `aria2c` (this machine ships it as a user-local wrapper that needs
`LD_LIBRARY_PATH=$HOME/.local/lib` — the helper invokes `aria2c-wrapper`).