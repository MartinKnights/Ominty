# Cross-distro migration report — DMS overlay, niri glow, TTS

**Date:** 2026-10-21
**Status:** Proposal (no code changed for this report)
**Source commits:** `Ominty` `914e8ea` · `ominty-core` `23a8d76`
**Targets:** Debian 13 / LMDE 7 (validated) and Ubuntu-family: Ubuntu 24.04
`noble`, Mint 22.x, Ubuntu 25.10/26.04 (source-build or PPA path)

---

## 1. Purpose

The work committed locally on the workstation (Mint 22.3, Ubuntu family) has to
land in two repos that must serve **both** Debian-family and Ubuntu-family
users. This report:

1. classifies each change by how portable it actually is;
2. lists the concrete edits required in `Ominty` and `ominty-core`;
3. defines the **assessment workflow** an installing agent follows to learn
   what the user already has and what they prefer, before anything is changed.

The guiding rule stays the same as `docs/MIGRATION.md`:
**infer, then confirm; never overwrite user configuration without a backup.**

---

## 2. What is being migrated

| # | Workstream | Artifact | Portability class |
|---|---|---|---|
| 1 | DMS motion + accent glow | `configs/dms/shell-overlay/*` | **build-coupled** — tied to the DMS embedded-shell build |
| 2 | niri close glow + timing | `configs/matugen/templates/ominty-niri.kdl` | **version-coupled** — needs `custom-shader` + `{{mode}}` |
| 3 | niri generic config | `configs/niri/config.kdl` | **portable** (templated `__HOME__`) |
| 4 | TTS restore | `scripts/tts/ensure-ayatana-appindicator.sh`, `~/bin/piper-*` | **dependency-coupled** — package name/path differs per family |
| 5 | Palette mode | `configs/matugen/templates/ominty-palette.json` + popups | **portable** (needs matugen `{{mode}}`) |
| 6 | Docs | `docs/plans/2026-10-21-dms-motion-glow-tts.md` | portable |

Only #4 is genuinely family-specific. #1 and #2 are the risky ones because they
depend on *versions* that differ between the OBS build and the source build.

---

## 3. Target matrix (as observed, not assumed)

| | Debian 13 / LMDE 7 | Ubuntu 24.04 noble / Mint 22.x | Ubuntu 25.10 / 26.04 |
|---|---|---|---|
| `ominty inspect` family | `debian` / `mint-debian` | `ubuntu` / `mint-ubuntu` | same |
| quickshell | Debian `trixie-backports` (pinned) | built from source (Qt 6.8.3) | PPA possible |
| DMS | OBS `home:AvengeMedia:dms` (`1.6.x`) | built from source (`ominty-managed-v1+<sha>`) | PPA |
| matugen | OBS | `cargo install matugen` (4.x) | PPA |
| niri | bundled `.deb` 26.4.0-1 | bundled `.deb` + `libseat1` + libdisplay-info 0.2 | bundled `.deb` |
| `dms.service` | shipped by the `dms` package | written by `install.sh` | written by `install.sh` (or PPA unit) |
| Ayatana typelib | `0.5.94-1` present in the apt archive | `0.5.93-1build3` in the apt archive | present |
| validation status | validated | code says `supported`, docs say `experimental` | untested |

**Evidence from the two real machines**

- Workstation: `Linux Mint 22.3`, `ID_LIKE="ubuntu debian"`,
  `VERSION_CODENAME=zena`, niri 26.04, matugen 4.2.0,
  Quickshell 0.3.1 (local build), `dms ominty-managed-v1+d0c1b3f`.
- LMDE inventory (`10-Ominty-LMDE/package-inventory-lmde.txt`):
  `gir1.2-ayatanaappindicator3-0.1 0.5.94-1` and
  `libayatana-appindicator3-1 0.5.94-1` are already installed — so the
  no-root typelib workaround is **not** needed on the Debian reference machine.

### Discrepancies to fix first

| # | Issue | Evidence | Direction |
|---|---|---|---|
| D1 | `platform.is_lmde` is true on Ubuntu-based Mint | `ominty inspect --json` → `"is_lmde": true`, `"family": "mint-ubuntu"` | test `ID=linuxmint` **and** `debian` in `ID_LIKE` |
| D2 | Docs say Ubuntu-family is experimental; code reports `supported` | `docs/UBUNTU.md` vs `_check_platform()` | pick one; recommend “supported (source build)” and document it |
| D3 | `SUPPORTED_CODENAMES` only lists Debian codenames | `inspect.py` | add a family-aware validated set (`trixie`, `faye`, `gigi`; `noble`, `zena`) |
| D4 | TTS dependencies are absent from the layer manifest | no TTS layer in `inspect.py` | add a `tts` layer (see §6.2) |

---

## 4. Workstream analysis

### 4.1 DMS motion + accent glow — the build-coupled one

The overlay patches the QML that DMS embeds in its binary. The extracted
directory is named by a **build hash** (`c27a2bbcb6e09e50` on this machine);
a different DMS build means different context lines.

What must change:

1. **Version guard in `apply.sh`.** Add `--check`:
   - find the pristine dist;
   - run `patch --dry-run` and report “applicable / not applicable”;
   - exit non-zero (without copying) when it is not.
   `install.sh` uses `--check` first and skips the overlay with a warning
   instead of shipping a half-patched shell.
2. **Never break DMS on mismatch.** If the patch does not apply, DMS must keep
   running the stock shell. Today a failed `patch` aborts the script (good),
   but `install.sh` must treat that as a warning, not a fatal install error.
3. **systemd delivery differs by family.**
   - Debian: the `dms` package ships its own unit. Do **not** overwrite it;
     write a drop-in instead:
     `~/.config/systemd/user/dms.service.d/ominty-shell.conf` containing
     `[Service]` + `Environment=DMS_SHELL_DIR=%h/.local/share/dms-shell`.
   - Ubuntu source build: keep the full unit written by `install.sh`, adding
     the same environment line.
   This removes the current asymmetry where Debian never gets the overlay
   environment at all.
4. **Refresh after upgrade.** `dms update` (or an apt upgrade) changes the
   embedded dist; the fork becomes stale. Add a `ominty` maintenance command
   (see §6.3) and document the three-step refresh in `docs/UBUNTU.md` and
   `docs/INSTALL.md`.
5. **Make the overlay optional.** A choice point (`desktop.shell_overlay`)
   defaulting to `ominty` but allowing `stock` for users who want upstream
   animations. This also gives a clean rollback path.

### 4.2 niri close glow + timing — the version-coupled one

`custom-shader` is available in the niri build we ship (26.04/26.4.0-1), and
both families install the same bundled `.deb`. Risks:

- A future bundled `.deb` bump that changes shader semantics.
- A user who already runs a distro niri (not the bundled one) that predates
  `custom-shader`.

What must change:

1. In `install.sh`, probe `niri --version`; if the version is below the
   shader-capable baseline, render the template **without** the
   `custom-shader` blocks and say so. A config that validates is better than a
   pretty one that does not.
2. Keep the shader in the matugen template (already the case) so the accent
   follows the palette on both families.
3. Document that `window-movement` is a 220 ms curve and that closing is
   deliberately ease-in (niri cannot sequence close-before-slide).

### 4.3 TTS — the family-specific one

| Concern | Debian 13 / LMDE 7 | Ubuntu-family |
|---|---|---|
| typelib package | `gir1.2-ayatanaappindicator3-0.1` (present) | same package name, present in `noble` |
| library package | `libayatana-appindicator3-1` | same |
| multiarch path | `x86_64-linux-gnu` | `x86_64-linux-gnu` (use `dpkg-architecture -qDEB_HOST_MULTIARCH`) |
| rootless fallback | rarely needed | rarely needed; keep as `--no-root` fallback |
| scripts location | `~/bin` on the reference machine | same, but not tracked |

What must change:

1. Add both packages to the **desktop layer** in `ominty-core` (or a new `tts`
   layer). Then `install.sh` installs them on both families through the
   existing layer-driven apt path.
2. Ship the helper scripts in the repo. They are currently untracked, which
   means a fresh install produces keybindings that point at nothing:
   `read-selection`, `tts-pick`, `piper-indicator`, `piper-daemon`.
   Proposed layout: `configs/tts/bin/` → installed to `~/.local/bin/`
   (portable), with the niri binds changed from `__HOME__/bin` to
   `__HOME__/.local/bin`. Keep `~/bin` as a legacy lookup for existing users.
3. Make the indicator’s self-reexec **conditional** (it already is): if the
   system typelib exists, it does nothing. Keep
   `scripts/tts/ensure-ayatana-appindicator.sh` only as the fallback.
4. Voice model path is user state, not repo state. Resolve it from
   `~/.config/ominty/tts.toml` with `OMINTY_TTS_VOICE` / `PIPER_VOICE`
   overrides; do not hard-code `~/.local/share/piper/...` in the service.
5. Mention the tray protocol constraint: TTS appears in the DMS tray because
   it uses libayatana/SNI. Do not “fix” it to Qt-style SNI (`MIGRATION.md` §2).

### 4.4 Palette mode — portable, needs a version floor

`{{mode}}` is emitted by matugen into `palette.json`; the popups read it. This
works on matugen 4.2.0. Add a `matugen --version` check and fall back to
`"dark"` when the key is absent (the popup code already tolerates a missing
`mode`, so this is only a documentation/reporting issue).

---

## 5. Repo change plan

### 5.1 `Ominty` (installer, configs, docs)

| File | Change | Family |
|---|---|---|
| `configs/dms/shell-overlay/apply.sh` | add `--check`, version/report output, `--force` | both |
| `configs/systemd/dms.service` | keep as the full unit for source builds | Ubuntu |
| `configs/systemd/dms.service.d/ominty-shell.conf` | **new** drop-in with `DMS_SHELL_DIR` | Debian |
| `install.sh` | `--check` before apply; warning not fatal; write drop-in on Debian; TTS apt step via layer | both |
| `configs/tts/bin/{read-selection,tts-pick,piper-indicator,piper-daemon}` | **new**, installed to `~/.local/bin` | both |
| `configs/niri/config.kdl` | TTS binds → `__HOME__/.local/bin` | both |
| `scripts/tts/ensure-ayatana-appindicator.sh` | keep as fallback; mention apt first | both |
| `docs/INSTALL.md` | TTS deps + overlay step + post-install checks | both |
| `docs/UBUNTU.md` | drop-in vs full unit; refresh-after-upgrade | Ubuntu |
| `docs/MIGRATION.md` | TTS tray/typelib note, overlay note | both |
| `docs/HARDWARE.md` / `profiles/` | no change | — |

### 5.2 `ominty-core` (CLI, inspect, docs)

| File | Change | Why |
|---|---|---|
| `cli/omintylib/inspect.py` | fix `is_lmde` (D1); family-aware codenames (D3); add `tts` layer; add `build` source (G1); new config checks; new choices | assessment accuracy |
| `cli/omintylib/platform.py` | expose `desktop_source` (`obs` / `source` / `ppa`) | report provisioning path |
| `cli/omintylib/tts.py` | typelib probe + `ensure` subcommand wiring | one implementation, no duplicated bash |
| `docs/ai/11-voice-integration.md` | document the rootless typelib fallback + tray protocol | user-facing |
| `docs/decisions/ADR-007-voice-tts-stt.md` | append an implementation note | record |
| `docs/05-platform-abstraction.md` | add “DMS shell overlay” as a platform-specific concern | architecture |

---

## 6. Assessment workflow — current installation and preferences

This is the part the installing agent runs **before** changing anything. It
extends the existing `inspect → choices → dry-run → apply → verify` loop from
`Ominty-Migration-Planning.md` §6.

### 6.1 Step 0 — facts (read-only, no sudo)

```sh
ominty inspect --json > /tmp/ominty-inspect.json
```

Read, in this order:

| JSON path | Use |
|---|---|
| `platform.family`, `support_level`, `codename` | choose provisioning path |
| `platform.desktop_source` *(new)* | OBS vs source build vs PPA |
| `layers.*.missing` | what is absent |
| `configs.*` | what is already deployed |
| `findings[].severity == "blocking"` | stop if non-empty |
| `choices[].resolved == false` | questions still to ask |

Never parse human-readable output; never re-ask a `resolved` choice.

### 6.2 Step 1 — inventory the incumbent desktop

Detect what the user runs today and which parts would be lost. The
`MIGRATION.md` sections are the checklist:

| Area | Probe | Decide |
|---|---|---|
| Session / display manager | `$XDG_CURRENT_DESKTOP`, `loginctl`, `/etc/X11/default-display-manager` | offer Niri as default (`session.default`) |
| Autostart entries | `ls ~/.config/autostart/*.desktop` | map each to `spawn-at-startup` or drop |
| Tray apps | running SNI/XEmbed items | warn about Qt-style SNI (`MIGRATION.md` §2) |
| Keybindings | Cinnamon `~/.cinnamon`, `dconf dump /org/cinnamon/` | map to Ominty grammar, keep user extras |
| Terminal / shell | `$TERMINAL`, `$SHELL`, `update-alternatives` | keep or install layer |
| Browser | `xdg-settings get default-web-browser` | keep or install layer |
| Editor | `$EDITOR`, `$VISUAL` | keep or install layer |
| Theme / wallpaper | DMS `settings.json`, `~/.config/matugen`, wallpapers | preserve; matugen regenerates |
| AI | `~/.config/ominty/ai.toml`, `ollama list`, `pi` | `llm.provider` choice |
| TTS/STT | `~/bin/piper-*`, `~/.local/share/piper`, `piper` on PATH | `tts.enabled` choice |
| Containers / dev | `podman`, `distrobox`, `docker` | optional layers |

The rule is **infer, then confirm**: if the probe answers a question, record it
as `resolved` with `detected` evidence; never ask.

### 6.3 Step 2 — preference model (what “software preferences” means here)

A preference is a *durable user choice*, not a package name. Capture it in one
place so both repos agree:

```json
{
  "schema_version": 1,
  "host": {"family": "mint-ubuntu", "codename": "zena"},
  "desktop": {
    "session_default": "niri",
    "shell_overlay": "ominty",        // ominty | stock
    "theme_mode": "dark",
    "wallpaper": "/home/user/Pictures/..."
  },
  "apps": {
    "terminal": "alacritty",
    "browser": "firefox",
    "editor": "neovim",
    "file_manager": "nemo"
  },
  "voice": {
    "tts": true,
    "tts_voice": "en_GB-northern_english_male-medium",
    "stt": false
  },
  "ai": {"provider": "ollama", "model": "..."},
  "migration": {"keep_user_configs": true, "backup": true}
}
```

Proposed command: `ominty plan --json` (read-only) returns this record plus the
resolved layer list; `install.sh --plan <file>` applies exactly it. Until that
exists, the same information is reconstructed from `inspect --json` +
`summary.required_choices`.

### 6.4 Step 3 — reconcile and ask

1. Diff detected preferences against Ominty defaults.
2. Ask only the delta, one question at a time (`summary.required_choices`).
3. For each answer, record `detected` so a later run does not ask again.
4. Refuse to proceed on `summary.blocking`; treat `warn` as consent-required.

New choice points required by this work:

| id | Required | Default | Detects |
|---|---|---|---|
| `desktop.shell_overlay` | no | `ominty` | DMS version + patch applicability |
| `tts.enabled` | no | detected from `~/bin/piper-*` | Piper + typelib |
| `tts.voice` | no | detected model file | available voices |
| `desktop.source` | no | `auto` | `obs` / `source` / `ppa` |

### 6.5 Step 4 — dry run, apply, verify

```sh
./install.sh --dry-run --layers "<ids>"
./install.sh --layers "<ids>"

ominty inspect                 # no blocking findings
ominty registry validate       # 0 errors
niri validate -c ~/.config/niri/config.kdl
systemctl --user is-active dms.service
```

Family-specific verification:

| Check | Debian | Ubuntu |
|---|---|---|
| DMS unit | `systemctl --user cat dms.service` shows the package unit + drop-in | full unit written by installer |
| overlay | `systemctl --user show -p Environment dms.service` contains `DMS_SHELL_DIR` | same |
| niri libs | `ldd "$(command -v niri)" \| grep 'not found'` empty | same + libdisplay-info |
| TTS | `gir1.2-ayatanaappindicator3-0.1` installed | same, or user prefix exists |
| tray | indicator visible in DMS tray | same |

### 6.6 Step 5 — record the outcome

Write the resolved plan (or a summary) to `~/.local/state/ominty/install.json`:
date, family, source commit, layers, choices, overlay applied (yes/no + DMS
build), verification results. This makes the next assessment cheap and makes
support reproducible.

---

## 7. Proposed `inspect` schema additions (v2 draft)

```json
{
  "schema_version": 2,
  "platform": {
    "family": "mint-ubuntu",
    "is_lmde": false,
    "desktop_source": "source",
    "support_level": "supported"
  },
  "desktop": {
    "dms_version": "ominty-managed-v1+d0c1b3f",
    "shell_dir": "/home/user/.local/share/dms-shell",
    "shell_overlay": {"state": "applied", "base": "c27a2bbcb6e09e50"},
    "niri_version": "26.04",
    "custom_shader": true,
    "matugen_version": "4.2.0"
  },
  "tts": {
    "indicator": "running",
    "typelib": "system",
    "voice": "en_GB-northern_english_male-medium",
    "tray_item": "org/ayatana/NotificationItem/piper_indicator"
  }
}
```

Rules stay the same: additive fields within a version, `schema_version` bump on
breaking changes, agent ignores unknown keys.

---

## 8. Test matrix

| Scenario | Family | Expected |
|---|---|---|
| Clean LMDE 7 | `mint-debian` | OBS install, drop-in written, stock DMS unit preserved, TTS via apt |
| Clean Debian 13 | `debian` | same as LMDE |
| Clean Ubuntu 24.04 | `ubuntu` | source build, full unit, overlay applied |
| Clean Mint 22.x | `mint-ubuntu` | source build; `is_lmde` must be **false** |
| Existing Cinnamon desktop | both | inventory + choices, no data loss, backups present |
| DMS upgraded (new hash) | both | `--check` fails, overlay skipped with warning, desktop still starts |
| niri older than shader baseline | both | template rendered without shader, config validates |
| typelib missing, no sudo | both | user prefix + self-reexec works |
| typelib present | both | self-reexec no-ops |
| Ubuntu 25.10/26.04 | `ubuntu` | PPA path (if implemented) or source build |

---

## 9. Sequencing

1. **`ominty-core` first** — assessment correctness is a prerequisite:
   D1/D3 fixes, `build` source, TTS layer, new choices, schema v2.
2. **`Ominty` second** — submodule bump + `apply.sh --check` + drop-in +
   TTS scripts + docs.
3. Tag both (`v0.x`) so the two machines can pin the same release.
4. Roll out to the Debian reference first (validated path), then the
   workstation (source-build path), then document the diff.

Do not push the current local commits before step 1 lands, otherwise the
installer will reference `inspect` fields that do not exist yet.

---

## 10. Risks and rollbacks

| Risk | Impact | Mitigation / rollback |
|---|---|---|
| DMS build mismatch | patch fails or half-applies | `--check` + skip; remove drop-in / env line |
| DMS upgrade breaks fork | stale UI | `apply.sh` refresh; worst case remove `DMS_SHELL_DIR` |
| Debian unit overwritten | DMS loses package defaults | never overwrite; drop-in only |
| niri without `custom-shader` | config invalid | version probe; render without shader |
| typelib absent | no tray icon | apt, then user-prefix fallback |
| Ubuntu docs/code disagree | agent makes wrong call | fix D2 before push |
| Scripts untracked | dead keybindings on fresh install | ship under `configs/tts/bin` |

Rollback is always: remove the drop-in (or `DMS_SHELL_DIR`), restore the
`.bak-ominty-<timestamp>` config, restart `dms.service`.

---

## 11. Open decisions

1. Should the shell overlay be **default on** for both families, or opt-in on
   Ubuntu until the source build is pinned?
2. Ship the TTS helper scripts in `Ominty` (`configs/tts/bin`) or rewrite them
   as `ominty-core` adapters (`voice.tts` action)? The latter matches ADR-007
   but is more work.
3. Should `install.sh` keep a full `dms.service` for source builds, or always
   use a drop-in over whatever unit exists?
4. Promote Ubuntu-family from “experimental” in `docs/UBUNTU.md` now that the
   code reports `supported`, or keep the docs conservative until CI exists?
5. Do we need a per-distro `packages/` layout (niri `.deb` built for noble),
   or is the current bundled Debian build + libdisplay-info workaround
   acceptable for the next release?
