# Niri + DMS Aesthetics — Implementation Plan

**Date:** 2026-10-14
**Design:** `docs/plans/2026-10-14-niri-dms-aesthetics-design.md`
**Status:** ✅ Implemented & validated 2026-10-14 — all nine tasks complete.
See `PROGRESS.md` (2026-10-14 entry) for the outcome and the two shader fixes
(`half` is a reserved GLSL word; int/float needs an explicit `float()`). The
checkboxes below are the original step-by-step instructions, kept for reference.

---

## 0. Correction to the design doc (read first)

The design doc assumed `custom-shader "/path/to.frag"`. **That is wrong for niri 26.04.**

Verified against the `v26.04` tag:

- `niri-config/src/animations.rs` parses `custom-shader` as a plain **string** node.
- `src/niri.rs:1568-1573` passes that string **directly** as GLSL **source**:
  `shaders::set_custom_open_program(renderer, config.animations.window_open.custom_shader.as_deref())`.
- The `path="…"` property form exists only on newer `main`.

**Consequence:** the shader must be **inline** in the KDL. matugen therefore generates the
whole `animations` block (shader text + baked colour) instead of a separate `.frag` file.

Two further corrections to the design doc:

- The popup sources are **hardlinks** (same inode) between
  `~/.config/quickshell/<p>/shell.qml` and
  `Ominty/ominty-core/shell/quickshell/<p>/shell.qml`. Edit the repo copy; the config copy
  follows automatically.
- The popups read a **palette file we generate** (`~/.config/ominty/theme/palette.json`),
  not `dms-colors.json`. This sidesteps the unresolved "which DMS state dir is live"
  ambiguity (`~/.cache` per `Theme.qml:24` vs `~/.local/state` per the current
  `colors.kdl`).

---

## 1. Goal

Four enhancements to the niri + DankMaterialShell desktop:

1. **Open animation** — a dot at the window centre grows, expands horizontally into a
   line, then grows vertically into the full window rectangle, drawn in the themed border
   colour with a glow; the window content fades in as the shape completes.
2. **Close animation** — the window converges from its corners to a centre dot and fades
   to nothing; the glow is cut instantly; total ≤ 1 s.
3. **Persistent glow** — every window carries a themed glow, stronger outside than inside.
4. **TTS/STT theming** — the `ominty-voice` and `ominty-tts` Quickshell popups follow the
   DMS theme automatically.

---

## 2. Architecture

```
wallpaper / seed colour
        │
        ▼
  dms matugen generate
        │   DMS merges ~/.config/matugen/config.toml ([config] + [templates])
        │   into a temp config, then runs:
        │     matugen <args> -c <tmp>/templates.toml --continue-on-error
        │
        ├── DMS templates ──► ~/.config/niri/dms/colors.kdl      (existing, untouched)
        │
        └── user templates
              ├── ominty-niri.kdl    ──► ~/.config/niri/dms/ominty-theme.kdl
              │                          animations { on; window-open/close custom-shader }
              │                          + layout { border, shadow }
              └── ominty-palette.json ─► ~/.config/ominty/theme/palette.json
                                         (popup palette)
```

`~/.config/niri/config.kdl` gains one include **after** `dms/windowrules.kdl` (line 349),
so our `layout`/`animations` win over the DMS-generated ones:

```kdl
include "dms/ominty-theme.kdl" optional=true
```

---

## 3. Verified facts (with evidence)

| Fact | Evidence |
|---|---|
| `custom-shader` = inline GLSL string | `niri-config/src/animations.rs`; `src/niri.rs:1568-1573` (v26.04) |
| shader API (`open_color`/`close_color`, uniforms) | `docs/wiki/examples/open_custom_shader.frag` |
| `animations { on }` resets `off` | `niri-config/src/animations.rs` |
| later `window-open`/`window-close` replaces earlier | `merge_clone!` in `animations.rs` |
| `border { on }` resets `off`; `shadow { on }` enables | `niri-config/src/appearance.rs` |
| DMS merges user `[config]` + `[templates]` | `core/internal/matugen/matugen.go:658-770` |
| user config must contain a **literal `[templates]` line** | `extractTOMLSection` (matugen.go:981) |
| matugen invoked `matugen <args> -c <tmp>/templates.toml --continue-on-error` | matugen.go:604-609, 1086 |
| `.red/.green/.blue` are 0-255 ints | `quickshell/matugen/templates/kcolorscheme.colors` |
| popups are hardlinks into ominty-core | inodes 13374228 / 13375209 |

---

## 4. Tasks

### Task 1 — Preflight spike: prove the user-template pipeline

**Files:** create `~/.config/matugen/config.toml`, `~/.config/matugen/templates/ominty-spike.txt`

- [ ] Create `~/.config/matugen/templates/ominty-spike.txt`:

```
primary_hex={{colors.primary.default.hex}}
primary_rgb={{colors.primary.default.red}},{{colors.primary.default.green}},{{colors.primary.default.blue}}
```

- [ ] Create `~/.config/matugen/config.toml` — note the **literal `[templates]` line**,
      which DMS's `extractTOMLSection` requires:

```toml
[config]

[templates]

[templates.ominty_spike]
input_path = '/home/martin/.config/matugen/templates/ominty-spike.txt'
output_path = '/tmp/opencode/ominty-spike.out'
```

- [ ] Run:

```bash
dms matugen generate --kind image \
  --value /home/martin/Wallpapers/linuxmint-victoria-jgallegos_greece.jpg
cat /tmp/opencode/ominty-spike.out
```

- [ ] **Verify:** the file exists; `primary_hex` equals the active colour in
      `~/.config/niri/dms/colors.kdl`; `primary_rgb` is three 0-255 integers.
- [ ] **Verify:** the merged TOML is accepted (a bare `[templates]` after `[templates.*]`
      is legal TOML — super-table defined after sub-tables). If matugen errors, move the
      `[templates]` line to the top of the file and re-test.
- [ ] If the output file is missing → the pipeline is broken. **Stop and report**;
      fallback is a systemd `path` unit watching the palette and regenerating the files.

### Task 2 — Popup palette template

**Files:** create `~/.config/matugen/templates/ominty-palette.json`; add
`[templates.ominty_palette]` to the user config.

- [ ] Create `~/.config/matugen/templates/ominty-palette.json`:

```json
{
  "dark": {
    "background": "{{colors.surface_container.dark.hex}}",
    "on_background": "{{colors.on_surface.dark.hex}}",
    "primary": "{{colors.primary.dark.hex}}",
    "on_primary": "{{colors.on_primary.dark.hex}}",
    "error": "{{colors.error.dark.hex}}",
    "outline": "{{colors.outline_variant.dark.hex}}",
    "surface_variant": "{{colors.surface_variant.dark.hex}}"
  },
  "light": {
    "background": "{{colors.surface_container.light.hex}}",
    "on_background": "{{colors.on_surface.light.hex}}",
    "primary": "{{colors.primary.light.hex}}",
    "on_primary": "{{colors.on_primary.light.hex}}",
    "error": "{{colors.error.light.hex}}",
    "outline": "{{colors.outline_variant.light.hex}}",
    "surface_variant": "{{colors.surface_variant.light.hex}}"
  }
}
```

- [ ] Append to `~/.config/matugen/config.toml`:

```toml
[templates.ominty_palette]
input_path = '/home/martin/.config/matugen/templates/ominty-palette.json'
output_path = '/home/martin/.config/ominty/theme/palette.json'
```

- [ ] `mkdir -p ~/.config/ominty/theme` then run `dms matugen generate …` (as Task 1).
- [ ] **Verify:** `~/.config/ominty/theme/palette.json` exists and is valid JSON with
      `dark`/`light` keys.

### Task 3 — Niri theme template: glow only (low risk)

**Files:** create `~/.config/matugen/templates/ominty-niri.kdl`; add
`[templates.ominty_niri]`; edit `~/.config/niri/config.kdl`.

- [ ] Create `~/.config/matugen/templates/ominty-niri.kdl` (glow only for now):

```kdl
// ! Auto-generated by matugen (ominty-niri.kdl). Do not edit directly.
layout {
    border {
        on
        width 2
        active-color   "{{colors.primary.default.hex}}"
        inactive-color "{{colors.outline.default.hex}}"
    }
    shadow {
        on
        softness 40
        spread 8
        offset x=0 y=0
        color "{{colors.primary.default.hex}}40"
    }
}
```

- [ ] Append to `~/.config/matugen/config.toml`:

```toml
[templates.ominty_niri]
input_path = '/home/martin/.config/matugen/templates/ominty-niri.kdl'
output_path = '/home/martin/.config/niri/dms/ominty-theme.kdl'
```

- [ ] Add the include to `~/.config/niri/config.kdl` after line 349:

```kdl
include "dms/ominty-theme.kdl" optional=true
```

- [ ] Run `dms matugen generate …`, then `niri validate -c ~/.config/niri/config.kdl`.
- [ ] **Verify:** `~/.config/niri/dms/ominty-theme.kdl` exists; niri reloads without error;
      windows show a themed border + soft glow.

### Task 4 — Enable animations (built-in, no shader yet)

- [ ] Append to `~/.config/matugen/templates/ominty-niri.kdl`:

```kdl
animations {
    on
    window-open  { duration-ms 350; curve "cubic-bezier" 0.2 0.8 0.2 1 }
    window-close { duration-ms 300; curve "cubic-bezier" 0.4 0 0.2 1 }
}
```

- [ ] Regenerate + `niri validate`.
- [ ] **Verify:** opening/closing a window animates (the `animations { off }` at
      `config.kdl:158` is overridden by our later `animations { on }`).

### Task 5 — Open shader

- [ ] Replace the `window-open` block in the template with:

```kdl
    window-open {
        duration-ms 350
        curve "cubic-bezier" 0.2 0.8 0.2 1
        custom-shader r"
const vec3 OMINTY_ACCENT = vec3({{colors.primary.default.red}}/255.0, {{colors.primary.default.green}}/255.0, {{colors.primary.default.blue}}/255.0);

float ominty_sd_box(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    vec2 half = max(size_geo.xy * 0.5, vec2(1.0));
    vec2 pos  = (coords_geo.xy - vec2(0.5)) * size_geo.xy;

    float dotR = max(2.0, min(half.x, half.y) * 0.05);
    float grow = smoothstep(0.00, 0.30, p);
    float wide = smoothstep(0.30, 0.60, p);
    float tall = smoothstep(0.60, 0.90, p);

    vec2 b;
    b.x = mix(dotR, half.x, wide);
    b.y = mix(dotR, half.y, tall);
    b   = mix(vec2(dotR), b, grow);
    float r = mix(dotR, 12.0, tall);

    float d = ominty_sd_box(pos, b, r);

    float inside = 1.0 - smoothstep(-1.0, 1.0, d);
    float glowW  = max(8.0, min(half.x, half.y) * 0.12);
    float glow   = exp(-abs(d) / glowW);

    vec3 tex = niri_geo_to_tex * coords_geo;
    vec4 win = texture2D(niri_tex, tex.st);

    float content = smoothstep(0.88, 1.0, p);
    float frameA  = 1.0 - smoothstep(0.88, 1.0, p);

    vec4 col = win * inside * content;
    col += vec4(OMINTY_ACCENT * glow, glow) * frameA;

    float full = smoothstep(0.96, 1.0, p);
    return mix(col, win, full);
}
        "
    }
```

- [ ] Regenerate + `niri validate`; watch `journalctl -ef /usr/bin/niri` for shader
      compile warnings.
- [ ] **Verify:** the dot → line → rectangle → content sequence plays; the colour matches
      the border; the glow is visible.
- [ ] Tune `dotR`, the stage boundaries, `glowW` and `frameA` until it looks right.

### Task 6 — Close shader

- [ ] Replace the `window-close` block with:

```kdl
    window-close {
        duration-ms 300
        curve "cubic-bezier" 0.4 0 0.2 1
        custom-shader r"
float ominty_sd_box(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float q = 1.0 - niri_clamped_progress;
    vec2 half = max(size_geo.xy * 0.5, vec2(1.0));
    vec2 pos  = (coords_geo.xy - vec2(0.5)) * size_geo.xy;

    float dotR = max(2.0, min(half.x, half.y) * 0.05);
    float grow = smoothstep(0.00, 0.30, q);
    float wide = smoothstep(0.30, 0.60, q);
    float tall = smoothstep(0.60, 0.90, q);

    vec2 b;
    b.x = mix(dotR, half.x, wide);
    b.y = mix(dotR, half.y, tall);
    b   = mix(vec2(dotR), b, grow);
    float r = mix(dotR, 12.0, tall);

    float d = ominty_sd_box(pos, b, r);
    float inside = 1.0 - smoothstep(-1.0, 1.0, d);

    vec3 tex = niri_geo_to_tex * coords_geo;
    vec4 win = texture2D(niri_tex, tex.st);

    float fade = smoothstep(0.0, 0.35, q);
    return win * inside * fade;
}
        "
    }
```

- [ ] Regenerate + `niri validate`.
- [ ] **Verify:** the window converges to a centre dot and fades; the glow is gone from
      the first frame (no synthetic glow, and the shadow outside the geometry is masked
      out); total ≤ 1 s.

### Task 7 — Theme the `ominty-voice` popup

**File:** `Ominty/ominty-core/shell/quickshell/ominty-voice/shell.qml` (hardlinked to
`~/.config/quickshell/ominty-voice/shell.qml`).

- [ ] Add a palette `FileView` + property near the other `readonly property`s:

```qml
    readonly property string palettePath: (Quickshell.env("HOME") || "") + "/.config/ominty/theme/palette.json"
    property var pal: ({
        background: "#181825", on_background: "#cdd6f4", primary: "#89b4fa",
        on_primary: "#11111b", error: "#f38ba8", outline: "#313244",
        surface_variant: "#313244"
    })

    FileView {
        id: paletteFile
        path: root.palettePath
        __preload: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(paletteFile.text());
                if (d && d.dark) root.pal = d.dark;
            } catch (e) {}
        }
    }
```

- [ ] Replace the hardcoded colours (lines 112-204):

| old | new |
|---|---|
| `#181825` | `root.pal.background` |
| `#cdd6f4` | `root.pal.on_background` |
| `#f38ba8` | `root.pal.error` |
| `#89b4fa` | `root.pal.primary` |
| `#313244` | `root.pal.outline` |
| `#11111b` | `root.pal.on_primary` |
| `#6c7086` | `root.pal.outline` |

- [ ] Restart the popup: `pkill -f "quickshell -c ominty-voice"` (it is relaunched on
      demand by `ominty voice`).
- [ ] **Verify:** the popup uses the DMS palette; changing the DMS theme re-themes it live.

### Task 8 — Theme the `ominty-tts` popup

**File:** `Ominty/ominty-core/shell/quickshell/ominty-tts/shell.qml`.

- [ ] Add the same palette `FileView` + `pal` property as Task 7.
- [ ] Replace the hardcoded colours (lines 120-214):

| old | new |
|---|---|
| `#181825` | `root.pal.background` |
| `#cdd6f4` | `root.pal.on_background` |
| `#f38ba8` / `#f38ba855` | `root.pal.error` / `root.pal.error + "55"` |
| `#89b4fa` | `root.pal.primary` |
| `#313244` | `root.pal.outline` |
| `#45475a` | `root.pal.surface_variant` |
| `#11111b` | `root.pal.on_primary` |
| `#7f849c` | `root.pal.outline` |

- [ ] Restart the popup: `pkill -f "quickshell -c ominty-tts"`.
- [ ] **Verify:** the popup uses the DMS palette and re-themes live.

### Task 9 — End-to-end verification

- [ ] `niri validate -c ~/.config/niri/config.kdl` → clean.
- [ ] Change the DMS wallpaper/theme; confirm the shader colour, glow and both popups all
      update without a restart.
- [ ] Open/close several windows; confirm the animations and that the colour matches the
      border.
- [ ] `journalctl -ef /usr/bin/niri` → no shader compile warnings.
- [ ] Confirm `~/.config/niri/dms/colors.kdl`, `layout.kdl`, `windowrules.kdl` are
      untouched by our templates.

---

## 5. Error handling

- **matugen user templates fail** → DMS passes `--continue-on-error`, so other templates
  still render; our files keep their previous contents. Fallback: a systemd `path` unit
  watching the palette and regenerating the files with a small script.
- **Shader compile error** → niri logs a warning and falls back to the default animation.
  Mitigation: `niri validate` + `journalctl -ef /usr/bin/niri`.
- **`palette.json` missing/malformed** → popups keep their hardcoded fallback colours.
- **niri update breaks the shader API** → shaders are isolated in one generated file;
  disable by removing the single include.

## 6. Risks & limitations

- **Inner glow** — niri has no native inner glow; the border is a linear bbox gradient, not
  a ring falloff. Approximated with a bright border + soft shadow.
- **Open animation cannot wait for app readiness** — inherent to niri.
- **Shader API instability** — no backwards-compatibility guarantee.
- **Close glow pop** — masking the shadow from the first close frame causes a small pop;
  tunable.
- **matugen template braces** — the GLSL contains `{`/`}`; minijinja only treats `{{`,
  `{%`, `{#` specially, so plain braces are safe. Avoid `{{` in the shader.

## 7. Files

**Create**

- `~/.config/matugen/config.toml`
- `~/.config/matugen/templates/ominty-niri.kdl`
- `~/.config/matugen/templates/ominty-palette.json`
- `~/.config/niri/dms/ominty-theme.kdl` (generated)
- `~/.config/ominty/theme/palette.json` (generated)

**Modify**

- `~/.config/niri/config.kdl` (add one include)
- `Ominty/ominty-core/shell/quickshell/ominty-voice/shell.qml`
- `Ominty/ominty-core/shell/quickshell/ominty-tts/shell.qml`

**Untouched**

- `~/.config/niri/dms/colors.kdl`, `layout.kdl`, `windowrules.kdl` (DMS-owned)
