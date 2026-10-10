# DMS integration — `omintyDictionary` plugin

The popup is a DMS plugin (`PluginComponent`, an overlay `PanelWindow`)
that shells out to `omi-dict` and renders the JSON.  It contains no lookup
logic.

## Deploy (user scope)

```sh
ln -sfn "$(pwd)" ~/.config/DankMaterialShell/plugins/omintyDictionary
dms ipc call plugins reload omintyDictionary
dms ipc call plugins enable omintyDictionary
```

## Control

| Action | Command |
|---|---|
| Open empty (type a word) | `dms ipc call omintyDictionary open` |
| Open on a word | `dms ipc call omintyDictionary openWith circumspect` |
| Toggle | `dms ipc call omintyDictionary toggle` |
| Close | `dms ipc call omintyDictionary close` |

The Niri action (`text.define`, `Ctrl+Shift+A`) runs
`omi-dict selection --popup`, which reads the selection and calls
`openWith <word>`; with no selection it opens the popup empty.

## Keyboard

`Ctrl+L` search field · `↑`/`↓` candidates · `Enter` lookup ·
`Ctrl+[` / `Ctrl+]` cycle dictionaries · `Esc` close.

## v1 notes

- Dictionary selector cycles through discovered dictionaries plus the
  virtual **All Dictionaries** entry (All mode renders one section per
  result, first shown first).
- Interactive search suggestions come from the default dictionary.
- In-popup dictionary dropdown-visualisation is a cycle button; a full
  dropdown list and collapsible All sections are follow-ups.
