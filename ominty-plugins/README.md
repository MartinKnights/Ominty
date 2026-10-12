# Ominty Plugins

Migrated **Omarchy bar widgets → Ominty/DMS plugins**. The process is a skill:
`porting-omarchy-plugins` (see `~/.config/opencode/skills/porting-omarchy-plugins/`).

Each plugin lives in its own folder here and is symlinked into the DMS plugin
dir to run:

```sh
ln -sfn "$PWD/<plugin>" ~/.config/DankMaterialShell/plugins/<id>
dms ipc call plugins reload <id>
dms ipc call plugins enable <id>
```

| Plugin | Source (Omarchy) | Status |
|---|---|---|
| `omintyReader` | github.com/ClumZeez/omarchy-reader | pilot — overlay/daemon done, bar widget follow-up |
| `omintyDownload` | github.com/wicky14/omarchy-download-manager | tracked |
| ai-usage / BF-Agent-Ledger / opencode-go | agent-usage widgets | tracked — needs an Ominty agents data layer |

See the skill for the full process and pitfalls (manifest conversion,
`qs.Commons`→`qs.Common`, overlay-vs-composite, PanelWindow output placement,
state-path rebasing, verification).