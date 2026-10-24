# Ominty — official names

One name per surface, used everywhere a user can see it: window titles, tray
tooltips, notification summaries, dialogs, docs and the keybinding cheat sheet.

The rule is simple: **`Ominty <Noun>`**, title case, nothing else. No "TTS",
no "Piper", no "playlist selector", no "script hub", no product names borrowed
from the implementation.

## The names

| Official name | What it does | Keys | CLI (internal) | DMS plugin | Popup |
| --- | --- | --- | --- | --- | --- |
| **Ominty Media** | Playlist launcher: one tab per folder, Tab/arrows to navigate, type to filter, Enter to play | `Shift+Alt+M` (alias `Ctrl+Shift+M`) | `omi-media` | `omintyMedia` | — |
| **Ominty Dictionary** | Offline dictionary and thesaurus for the selected word | `Ctrl+Shift+A` | `omi-dict` | `omintyDictionary` | — |
| **Ominty Reader** | Reads a document, the selection, or the clipboard aloud | `Super+Alt+O`, `Ctrl+Alt+S`, `Shift+Alt+S` | `ominty tts`, `tts-pick`, `read-selection` | — | `ominty-tts` |
| **Ominty Dictation** | Speech to text, typed into the focused window | `Super+Alt+T` (panel), `Super+Alt+D` (toggle) | `ominty voice` | — | `ominty-voice` |
| **Ominty Capture** | Screen OCR: select an area, get the text on the clipboard | `Ctrl+Alt+R` | `screen-ocr` | — | — |
| **Ominty Scripts** | Script launcher / control panel | `Super+S` | `script_command_centre.sh` | — | — |

## Rules

1. **User-facing text uses the official name.** `zenity --title`, `notify-send`
   summaries, QML headers and tray tooltips.
2. **Internal identifiers do not change.** `omi-media`, `omi-dict`,
   `omintyMedia`, `ominty-tts` and action ids such as `voice.speak.file` are
   contracts; renaming them breaks the registry, symlinks and saved settings.
3. **"Piper" is an engine, not a product.** It may appear in logs, error text
   and docs about the stack, never as a feature name.
4. **Action ids stay `<domain>.<verb>`** (`media.launcher`,
   `voice.speak.clipboard`, `text.define`). The official name is the label, not
   the id.
5. **New surfaces follow the pattern.** If it cannot be named `Ominty <Noun>`,
   it is probably not a user-facing surface yet.

## Where each name appears

| Name | Strings |
| --- | --- |
| Ominty Media | `OmintyMedia.qml` header; `omi-media` error text |
| Ominty Dictionary | `OmintyDictionary.qml` header; lookup errors |
| Ominty Reader | `tts-pick` dialog titles, `piper-indicator` tooltips and icon title, `ominty-tts` fallback title, `ominty tts` errors |
| Ominty Dictation | `ominty-voice` panel label, transcription status |
| Ominty Capture | every `notify-send` in `screen-ocr` |
| Ominty Scripts | every Zenity title in `script_command_centre.sh` |

Renaming a surface is a UI change only: update this table, the strings above,
and the Applications table in `docs/INSTALL.md`. Nothing else depends on it.
