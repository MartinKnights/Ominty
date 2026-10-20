# omintyOllama — Ollama Manager (native DMS plugin)

Manages the local **Ollama** installation from Ominty/DMS. Replicates the
functionality of `~/Scripts/Bash/ollama_control_center.sh` (Zenity GUI) as a
native shell plugin — but with live pull progress, a persistent chat pane and
polkit-authenticated service control instead of sudo dialogs.

## What it does

| Tab | Functions |
| --- | --- |
| **Models** | List installed models (server-running via `ollama list`, offline fallback reads `~/.ollama/models/manifests`), pull with live % progress, remove, details (`ollama show`), quick chat (one-shot `ollama run`). Popular-model chips + free-text pull field. |
| **Server** | API-server up/down, systemd service state, auto-start state; Start / Stop / Restart / Enable auto-start / Disable auto-start via `pkexec systemctl` (DMS polkit dialog); GPU check — loads the smallest installed model with a one-word prompt, then reads `ollama ps --json` for VRAM share. |
| **Backup** | Create timestamped `tar.gz` of `~/.ollama/models` into `~/.local/share/ominty-ollama/backups`; list archives; restore (typed confirmation — replaces the models directory). |

## Structure

```
omintyOllama/
├── plugin.json            daemon plugin
├── OmintyOllama.qml       overlay UI (PluginComponent, no logic)
└── helpers/
    └── ominty-ollama.py   stdlib Python contract (JSON on stdout)
```

The QML holds no logic; every operation goes through the Python helper
(same pattern as `omintyDownload/helpers/ominty-dl.py`). Helper commands:

`status | list | show <m> | pull <m> | rm <m> | chat <m> <prompt> | gpu |
svc <start|stop|restart|enable|disable> | backup | backups | restore <archive>`

Progress while pulling/backing up/restoring is streamed as one JSON object per
line (`{"ev":"p",...}`), finished with `{"ev":"done",...}`.

## Open it

- IPC: `dms ipc call omintyOllama toggle` (also `open`, `close`,
  `pull <model>`, `view <models|server|backup>`)
- Palette action: `ai.ollama.open` in the Ominty action registry
  (`ominty registry validate && ominty registry build` after editing).
- Recommended keybind: assign `ai.ollama.open` a key in the Ominty keybinds
  (e.g. the Super+A chord grammar, "O" for Ollama).

## Logs

All helper activity is logged to `~/.ollama/ominty-ollama-plugin.log`
(the script's `~/.ollama/ollama_control_center.log` behaviour, renamed).

## Notes

- `ollama list/show/rm/chat/pull` all fail while the server is down; the
  plugin surfaces "start it in the Server tab first" instead.
- Service actions are the system unit (`ollama.service`) — they need root, so
  they go through `pkexec`; the DMS polkit agent must be active (it ships
  with DMS).
- Esc closes; Esc inside chat/details returns to the model list first.
