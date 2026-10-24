# AGENTS.md — deploying Ominty

This is the entry point for **any agent putting Ominty on a machine**. Read this
file first; it tells you which runbook to follow. Do not reconstruct the process
from memory or from a chat summary — the repository is the source of truth.

If you are *developing* Ominty rather than deploying it, read
[`ominty-core/AGENTS.md`](ominty-core/AGENTS.md) instead. That file governs the
implementation contracts; this one governs deployment.

---

## 1. Pick the flow

| The machine… | Read |
| --- | --- |
| has no desktop, or you are replacing it entirely | [`docs/AGENT-INSTALL.md`](docs/AGENT-INSTALL.md) |
| already runs **Ominty** (any version) | [`docs/AGENT-UPGRADE.md`](docs/AGENT-UPGRADE.md) |
| runs Cinnamon/GNOME and should keep most of it | [`docs/MIGRATION.md`](docs/MIGRATION.md) **first**, then `docs/AGENT-INSTALL.md` |
| has a broken Ominty desktop | [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — do not reinstall |
| is a different distribution | stop and report; only Debian 13 and its derivatives are supported |

The upgrade runbook produces a **friction report**; the install runbook produces
a **setup report**. Both are required deliverables, not optional extras.

---

## 2. What Ominty is

An opinionated Wayland desktop for Debian-family systems:

- **Niri** — scrollable-tiling compositor (bundled `.deb`)
- **DankMaterialShell (DMS)** — the shell, **built from a pinned commit** with a
  motion + accent-glow overlay
- **Quickshell** — the QML runtime, **built from a pinned commit** (`v0.3.1`)
- **`ominty`** — CLI, action registry, and the glue that generates keybindings
- **matugen** — wallpaper-driven theming (OBS)
- Six Ominty applications (Media, Dictionary, Reader, Dictation, Capture,
  Scripts) plus pinned third-party DMS plugins

DMS is source-built on **both** Debian and Ubuntu families so every machine runs
the identical shell. The installer builds Quickshell first, builds DMS, installs
its user unit, and **smoke-tests the shell**: if it crash-loops it disables the
overlay, then falls back to the packaged unit, and exits non-zero.

### Supported platforms

| Platform | Status |
| --- | --- |
| Debian 13 (`trixie`) | validated |
| LMDE 7 (`gigi`) | validated |
| Ubuntu 24.04-family (`noble`, incl. Mint 22.x) | **supported** via the source build |
| Debian 12 (`bookworm`) / LMDE 6 (`faye`) | **blocked** — no `trixie-backports`, so Quickshell cannot be installed |
| Anything else | unsupported; stop and report |

`ominty inspect` reports this as `platform.support_level` and
`platform.supported`. Trust it over this table.

---

## 3. The rules

> **Never guess. Never parse human-readable installer output. Never skip the
> questions. Never fix a failure by editing the repository.**

| Rule | Why |
| --- | --- |
| Read the runbook file before acting | The process has gates and ordering that matter |
| Run `ominty inspect --json` and read the JSON | Human output is for the user |
| Ask the required questions one at a time | Three decisions cannot be defaulted |
| Show the dry-run plan and wait | The user must see what will change |
| Never run `install.sh` as root or under `sudo` | It calls `sudo` itself, per step |
| Never remove packages, especially `dms` | A leftover package is harmless; removal is not |
| Never edit files in the repository | Local edits break the next pull and hide friction |
| Never delete `.bak-ominty-*` backups | They are the rollback path |
| Stop at a failed gate | A validation failure is information, not an obstacle |

---

## 4. The assessment

```sh
ominty-core/cli/ominty inspect --json > /tmp/ominty-inspect.json
ominty-core/cli/ominty inspect                 # the same report for a human
```

| Key | Meaning |
| --- | --- |
| `platform` | distro, codename, `family`, `desktop_source`, `support_level` |
| `layers` | per-package state, `provisioned`, `satisfied` |
| `desktop` | DMS/Quickshell versions, overlay state, theme fragment |
| `tts` | Piper, indicator, running state, voices |
| `configs` | whether the deployed config and CLI symlinks exist |
| `choices` | decisions that still need a human |
| `findings` | every check with `status` (`pass`/`warn`/`fail`) and `severity` |
| `summary` | `ready`, `blocking`, `warnings`, `required_choices` |

Full field reference: [`docs/INSPECT.md`](docs/INSPECT.md).

**Triage:**

- `summary.blocking` non-empty → **stop** and report each entry.
- `summary.ready: true` → the machine can be installed on; outstanding choices
  are not blockers.
- A `fail` finding is only a stop signal when its `severity` is `blocking`.

Note: `inspect` exits `1` when there is a blocking finding. That is data, not a
crash — `--json` still writes a complete document.

---

## 5. The questions

`summary.required_choices` lists decisions that cannot be defaulted. Ask them
**one at a time**, quote the options and any `unavailable_reason`, and record the
answer.

| Choice | Why it cannot be defaulted |
| --- | --- |
| `llm.provider` | Writes `~/.config/ominty/ai.toml`; may download a model. `none` is always valid. |
| `session.default` | Changes what the machine boots into; easy to lock the user out. Confirm a fallback session stays selectable. |
| `config.migration` | Replacing an existing configuration is destructive. |

Optional choices (`layers`, `plugins.dms`, `desktop.shell_overlay`,
`tts.enabled`) may be inferred from the machine, but confirm before acting.

Pass the answers through as installer flags (for example `--layers "desktop
tts"`), never by editing the repository.

---

## 6. Plan, then apply

```sh
./install.sh --dry-run --layers "desktop tts terminal editor cli containers browser"
```

`--dry-run` executes nothing; it prints every command prefixed `[DRY ]`. Show it
to the user and wait for a go-ahead, then:

```sh
./install.sh 2>&1 | tee ~/ominty-install-$(date +%F).log
```

| Flag | Effect |
| --- | --- |
| `--layers "<ids>"` | Space-separated layer ids; invalid ids list the valid ones |
| `--dry-run` | Print the plan; change nothing |
| `--no-plugins` | Skip DMS plugins entirely |
| `--profile <name>` | Apply a hardware profile from `profiles/` |

**Time and space:** 20–40 minutes and ~10 GB free on a first install (the
Quickshell and DMS builds, plus a ~142 MB whisper model). On a machine that has
already built them, a re-run takes 2–5 minutes because the pins are cached.

**`sudo`:** if the agent cannot answer a password prompt, hand the single
command to the user and wait — do not try to work around it. `install.sh` may be
split only by the user running it themselves.

What the installer actually does is documented in
[`docs/INSTALL.md`](docs/INSTALL.md) §2; do not paraphrase it to the user from
memory.

---

## 7. Verify

The canonical suite. Every deployment ends with these:

| Check | Command | Pass |
| --- | --- | --- |
| Shell is alive | `scripts/smoke-dms.sh` | exit 0 (stable, IPC answers) |
| Plumbing | `scripts/verify-upgrade.sh` | 0 failed |
| Function | `scripts/verify-parity.py` | 0 failed |
| Registry | `ominty-core/cli/ominty registry validate` | 0 errors |
| Compositor config | `niri validate` | `config is valid` |

`verify-upgrade.sh` checks the things that are easy to get wrong (which binary
the unit runs, `DMS_SHELL_DIR`, the overlay marker, deployed helpers, niri
config). `verify-parity.py` checks that every registered action has its program,
every configured plugin exists, every generated binding resolves, and the
TTS/STT/media/dictionary stacks are complete. **Passing one does not imply the
other.**

The one check no machine can make is visual. Ask the user to confirm the accent
glow, the spring animation, and the six Ominty keys after logging in.

---

## 8. When to stop and report

Stop and give the user **problem, evidence, impact, options** when:

- `summary.blocking` is non-empty, or the distro/codename is unsupported;
- the architecture is not `x86_64`;
- `sudo` is unavailable and a privileged step is required;
- `registry validate` or `niri validate` reports errors;
- the installer exits non-zero (it does so deliberately when the shell cannot run);
- a plugin patch no longer applies after an upstream update;
- a change would destroy user configuration without a backup.

Never work around a failing gate by editing the repository, removing packages,
or forcing a unit. Report it; that is the useful outcome.

Recovery tools, in order of preference:

```sh
scripts/rollback-dms.sh --overlay-off    # keep the build, stock shell
scripts/rollback-dms.sh --to-backup      # previous dms.service
scripts/rollback-dms.sh --to-packaged    # packaged /usr/bin/dms
scripts/collect-diagnostics.sh           # full evidence dossier
```

Rollback is **DMS-scoped**. Do not restore `~/.config/niri/config.kdl` unless the
user explicitly asks for a full revert: the upgrade legitimately changed it, and
restoring it silently deletes the keybindings.

---

## 9. Data that is not in git

Four things are too large or too personal to ship. Tell the user, then offer the
command:

| Data | Where it goes | How |
| --- | --- | --- |
| Dictionaries (~800 MB of `.bgl`) | `~/.local/share/omi/dictionaries` | `scripts/omi-dict-import.sh [DIR]` |
| Piper voice (~60 MB) | `~/.local/share/piper/voices` | `scripts/tts/setup-piper.sh` (the installer runs it) |
| whisper model (~142 MB) | `~/.local/share/ominty/models` | `scripts/source/whisper-build.sh` (the installer runs it) |
| Playlists | `~/Playlist/<folder>/*.m3u` | the user's own files; one tab per folder |

Without the dictionaries, Ominty Dictionary reports that the dictionary is
unavailable. Without a playlist, Ominty Media says so. Neither is an install
failure.

---

## 10. Naming and layout

User-facing names are fixed by [`docs/NAMING.md`](docs/NAMING.md): **Ominty
Media**, **Ominty Dictionary**, **Ominty Reader**, **Ominty Dictation**,
**Ominty Capture**, **Ominty Scripts**. Internal ids (`omi-media`,
`omintyMedia`, `voice.speak.file`) are contracts and must not be renamed.

The repository layout is in the [README](README.md#repository-layout). If you are
looking for something specific:

| You need | Look in |
| --- | --- |
| installer behaviour | `install.sh`, `docs/INSTALL.md` |
| the shell overlay and pins | `configs/dms/shell-overlay/`, `scripts/source/` |
| plugin pins and patches | `configs/dms/plugins.lock.json`, `ominty-plugins/patches/` |
| verification | `scripts/verify-*.{sh,py}`, `scripts/smoke-dms.sh` |
| diagnostics | `scripts/collect-diagnostics.sh`, `docs/TROUBLESHOOTING.md` |
| changing the process | `docs/MAINTAINING.md` |
