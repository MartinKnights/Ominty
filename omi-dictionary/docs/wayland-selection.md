# Omi Dictionary Service — Wayland Selection

Selected-text acquisition is its own component (`src/omi_dict/selection.py`)
so future text actions (`text.define`, `text.pronounce`, …) reuse it.

## Primitive (already in place on the reference machine)

`clip-tool` (`~/.local/bin/clip-tool`) abstracts the session:

- Wayland (Niri) → `wl-paste` / `wl-copy`
- X11 (Cinnamon) → `xclip` / `xsel`

`clip-tool primary-paste` reads PRIMARY and **falls back to the regular
clipboard** under Wayland, where PRIMARY is rarely populated.

## Strategy

1. PRIMARY → clipboard fallback (`clip-tool primary-paste` — cheap, typical
   case).
2. When both are empty, a **controlled copy**: preserve → `wtype Ctrl+C` →
   read → restore (spec §12).  Clipboard is restored so a lookup never
   visibly changes it.
3. Test matrix across the §29 application classes (Firefox, Chromium, GTK,
   Qt, terminals, Neovim, Electron, PDF viewers) — recorded here in Phase 5.

## Known limitation

Niri does not widely populate PRIMARY; the clipboard fallback path is what
makes most applications work.  Results are documented per application in
Phase 5.
### Worked example — Artha (`Ctrl+Alt+A`)

Artha is an X11 app that reads PRIMARY itself; under Wayland that's empty,
so its search field opened blank.  `~/bin/artha-word` captures the Wayland
selection (PRIMARY → clipboard fallback), focuses Artha's window via Niri
(`focus-window --id`), pastes the word through the bridged clipboard
(`wl-copy` + `wtype Ctrl+V`), presses Enter for the lookup, then restores
the user's clipboard.  X11 sessions launch Artha directly.  Same selection
primitives as `omi-dict selection`.
