# omintyOllama — Ollama Manager (native DMS plugin)

Manages the local **Ollama** installation from Ominty/DMS. Replicates the
functionality of `~/Scripts/Bash/ollama_control_center.sh` (Zenity GUI) as a
native shell plugin — but with live pull progress, a persistent chat pane and
in-shell service control instead of sudo dialogs.

Machine-general: the helper **detects** the installation on every invocation —
service scope (user systemd unit preferred, falling back to the system unit via
`pkexec`), server port (`OLLAMA_HOST` env → unit `Environment=` → 11434/11435
probes) and models directory (`OLLAMA_MODELS` env → unit config →
`~/.ollama/models`). No machine-specific assumptions baked in.

## What it does

| Tab | Functions |
| --- | --- |
| **Models** | List installed models (server running → `ollama list`, offline fallback reads the detected models dir's `manifests`), pull with live % progress, remove, details (`ollama show`), quick chat (one-shot `ollama run`). Popular-model chips + free-text pull field. |
| **Server** | API-server up/down (with detected host:port), systemd service state, auto-start state; Start / Stop / Restart / Enable auto-start / Disable auto-start — user units run unprivileged, system units go through `pkexec` (DMS polkit dialog, panel auto-closes so the prompt is clickable, result arrives as a toast); GPU check — loads the smallest installed model with a one-word prompt, then reads `ollama ps --json` for VRAM share. |
| **Backup** | Create timestamped `tar.gz` of the detected models dir into `~/.local/share/ominty-ollama/backups`; list archives; restore (typed confirmation — replaces the models directory). |

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
- Service actions run against the detected scope — a user systemd unit
  (`systemctl --user`, no privileges) is preferred; a system unit falls back to
  `pkexec`, so the DMS polkit agent matters there (it ships with DMS).
- Esc closes; Esc inside chat/details returns to the model list first.
