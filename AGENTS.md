# AGENTS.md — installing or migrating to Ominty

This file is the entry point for **any agent deploying Ominty on a user's
machine** — installing it onto a clean system, or migrating an existing desktop
to it. It replaces guessing with a defined sequence: assess, inspect, ask, plan,
apply, verify.

If you are *developing Ominty* rather than deploying it, read
[`ominty-core/AGENTS.md`](ominty-core/AGENTS.md) instead. That file governs the
implementation contracts. This one governs deployment.

---

## 0. The project has two halves

Ominty is developed and deployed on the same machine. Keep the two apart, and
never let the second leak the first.

| | Objective | Where it lives |
| --- | --- | --- |
| **1. Develop** | Build and validate Ominty on the live PC — registry, CLI, DMS plugins, theming, AI, keyboard grammar. | `ominty-core/` and the live machine's configuration |
| **2. Distribute** | Turn what was validated on the live PC into a reproducible, generic install/migration process for the repo. | this file, `install.sh`, `configs/`, `docs/` |

**Objective 1 feeds objective 2.** Nothing belongs in the installer until it has
worked on the live machine; every change that does work there is a candidate for
the repo. Objective 2 must stay generic — no personal paths, no machine-specific
assumptions (see `ominty-core/AGENTS.md` §33).

### Install or migrate?

A machine that already runs a desktop (Cinnamon, GNOME, …) is **migrated**, not
overwritten. A clean machine is **installed**. The migration path is
**migration-first**:

1. **assess** the incumbent environment — what the user actually runs and wants
   to keep;
2. **infer, then confirm** each mapping with the user;
3. **preserve** everything that is not deliberately replaced, with a backup.

The migration is recorded in [`docs/MIGRATION.md`](docs/MIGRATION.md). A clean
machine skips straight to §3.

---

## 1. What Ominty is

Ominty is an opinionated desktop layer for **Debian-family systems**, validated
on **LMDE 7** (Debian 13, `trixie`). It combines:

- **Niri** — a scrollable-tiling Wayland compositor
- **DankMaterialShell (DMS)** — a Quickshell-based desktop shell
- **`ominty`** — a CLI and action registry that make the desktop
  keyboard-driven, discoverable and scriptable
- **matugen** — wallpaper-driven dynamic theming
- Optional layers for the terminal, editor, CLI tooling, containers and browser

The opinionated defaults deliberately avoid snaps and flatpaks, and prefer
Nala over raw APT.

**Validated target: LMDE 7 / Debian 13.** Ubuntu-family systems (Ubuntu, and
Linux Mint built on Ubuntu) are an **experimental** target — `ominty inspect`
reports them as `support_level: experimental`, and `install.sh` provisions the
desktop from source (see [docs/UBUNTU.md](docs/UBUNTU.md)). Any other
distribution is reported as unsupported; do not attempt an install without
explicit user consent.

---

## 2. The rule that matters most

> **Never guess. Never parse human-readable installer output. Never skip the
> questions.**

Run `ominty inspect --json` and read the JSON. If a decision is not in the
JSON, ask the user. If a decision *is* in the JSON, do not ask it again.

---

## 3. The sequence

```sh
git clone --recurse-submodules https://github.com/MartinKnights/Ominty.git
cd Ominty

ominty-core/cli/ominty inspect --json > /tmp/ominty-inspect.json
ominty-core/cli/ominty inspect            # the same report, for humans
```

Then work through sections 4 to 8 below in order.

**Migrating a machine that already has a desktop?** Assess the incumbent
environment *before* section 6, so the required choices are informed by what the
user already runs. Follow [`docs/MIGRATION.md`](docs/MIGRATION.md): inventory the
incumbent session, map its settings to their Niri equivalents, and confirm each
mapping before replacing anything.

**Upgrading a machine that already runs Ominty?** Stop here and follow
[`docs/AGENT-UPGRADE.md`](docs/AGENT-UPGRADE.md) instead of continuing with the
install path below. It is a gate-by-gate runbook for that exact case (update the
checkout, assess, install, verify with `scripts/verify-upgrade.sh`) and it
requires you to produce a friction report at the end. The install flow below
assumes a machine that is not yet running Ominty.

Do not run `install.sh` until you have completed section 6.

---

## 4. Reading `inspect --json`

Top-level keys:

| Key | Meaning |
| --- | --- |
| `schema_version` | Integer. Compare against what you expect; do not assume. |
| `platform` | Distro, version, codename, `is_lmde`, `supported`. |
| `hardware` | `arch`, `cpu`, `gpu`. |
| `session` | The currently active session. |
| `privilege` | Whether passwordless `sudo` works. |
| `layers` | Per-layer package state. See section 5. |
| `apt` | Configured APT sources, pins, backports and OBS state. |
| `configs` | Whether the deployed configuration and CLI symlinks exist. |
| `choices` | Questions that still need a human. See section 6. |
| `findings` | Every check, with `status` of `pass`, `warn` or `fail`. |
| `summary` | `ready`, `blocking`, `warnings`, `required_choices`, `counts`. |

Full field-by-field documentation: [`docs/INSPECT.md`](docs/INSPECT.md).

### Triage

- **`summary.blocking` is non-empty** → do not install. Report each entry to
  the user and stop. A blocking finding means the machine is not supported, or
  a previous install is broken.
- **`summary.ready` is `true`** → the machine can be installed on. Outstanding
  choices are *not* blockers; they are section 6.
- **`summary.warnings`** → mention them, then continue.

A `fail` finding is only blocking when its `severity` is `blocking`. Do not
treat every `fail` as a stop signal.

---

## 5. The layer model

Packages are grouped into layers. The manifest in `ominty-core` is the single
source of truth; `install.sh` reads it rather than keeping its own list, so the
two cannot drift apart.

| Layer | Contents |
| --- | --- |
| `desktop` | Niri, DMS, Quickshell, matugen, audio, portals, Nemo. |
| `terminal` | alacritty, ghostty, zellij, starship, bash-completion. |
| `editor` | neovim, fzf. |
| `cli` | nala, git, curl, jq, ripgrep, fd, bat, tree, htop, fastfetch… |
| `containers` | podman, distrobox. |
| `browser` | firefox-esr. |

Each layer reports `provisioned`, plus per-package `state` of `installed` or
`missing`. A missing package also states its `reason` and `fix`, because
"not installed" and "not available" are different problems:

- an **OBS** package is missing because the AvengeMedia repositories are not
  configured;
- **quickshell** is missing because `trixie-backports` is not enabled;
- **niri** is missing because it ships as a bundled `.deb`.

Quote that reason to the user. It tells them whether the fix is a repository,
a profile, or just an install.

Inspect the manifest directly with:

```sh
ominty-core/cli/ominty layers              # human summary
ominty-core/cli/ominty layers --format json
```

---

## 6. Ask the required questions

`summary.required_choices` lists decisions that **cannot be defaulted**. Each
has an entry in `choices` with `question`, `options`, `default` and `rationale`.

Ask these. Do not guess, and do not proceed past them.

| Choice | Why it is required |
| --- | --- |
| `llm.provider` | Writes `~/.config/ominty/ai.toml` and may download a model. Options report live availability — if both `ollama` and `pi` are unavailable, say so rather than offering them. `none` is always valid. |
| `session.default` | Changes how the machine boots into a desktop. Easy to break from a remote shell. **Confirm the fallback session stays selectable.** |
| `config.migration` | Replacing user configuration is destructive. |

Optional choices (`layers`, `plugins.dms`) may be inferred from what the user
already has installed, but confirm before acting.

Quote `options[].unavailable_reason` when an option is marked unavailable.

Present choices one at a time. Record the answers; you will pass them on as
`--layers` and installer flags.

---

## 7. Plan, then apply

`install.sh` is idempotent and re-runnable. Always show the plan first:

```sh
./install.sh --dry-run --layers "desktop terminal editor cli containers browser"
```

`--dry-run` executes nothing. It prints every command it would run, prefixed
`[DRY ]`. Confirm it changes nothing, then apply:

```sh
./install.sh --layers "desktop terminal editor cli containers browser"
```

Flags:

| Flag | Effect |
| --- | --- |
| `--layers "<ids>"` | Space-separated layer ids. Invalid ids fail with the valid list. |
| `--dry-run` | Print the plan; change nothing. |
| `--no-plugins` | Skip the third-party DMS plugins. |
| `--profile <name>` | Apply a hardware profile from `profiles/`. |

Order the work so that the desktop layer lands first. Later layers are
conveniences; the desktop is the deliverable.

### Rollback

`install.sh` backs up any configuration it replaces to a sibling suffixed
`.bak-ominty-<timestamp>` before overwriting. This is the rollback path — tell
the user it exists, and do not delete the backups for them.

`~/.config/ominty/ai.toml` and `apps.toml` are only written when absent, so
existing user configuration always wins there.

---

## 8. Verify

Re-run the audit and confirm the machine reached the desired state:

```sh
ominty-core/cli/ominty inspect
ominty-core/cli/ominty registry validate      # must report 0 errors
niri validate -c ~/.config/niri/config.kdl   # must report a valid config
```

`install.sh` runs both validations itself and fails loudly on a registry error.
Re-check after the user logs in for the first time, because the session check
inside `inspect` is only meaningful from inside Niri.

Then tell the user to log out and select the **Niri** session at the display
manager. A reboot is not required.

---

## 9. When to stop and report

Stop, and give the user **problem, evidence, impact, options**, when:

- `summary.blocking` is non-empty;
- the distribution is not Debian-family, or the codename is unsupported;
- the architecture is not `x86_64`;
- `registry validate` reports errors — never install a desktop built from an
  invalid action registry;
- `niri validate` rejects the generated configuration;
- a requested change would destroy user configuration without a backup;
- the DMS plugin install fails repeatedly;
- `sudo` is unavailable and privileged steps are required;
- the `ominty-core` submodule is missing or empty.

Never work around a failing validation. A validation failure is information,
not an obstacle.

---

## 10. Permissions

- `install.sh` must run as a **normal user**; it calls `sudo` internally and
  refuses to run as root.
- `ominty inspect` is **read-only and needs no `sudo`**. Run it first.
- `~/.config/ominty/generated/` is derived. Do not hand-edit it — fix the
  registry or the generator and rebuild.

---

## 11. Repository layout

```text
Ominty/
├── AGENTS.md              ← this file (installation)
├── install.sh             ← the installer
├── configs/               ← deployed configuration templates
│   ├── niri/              ← niri config + dms fragments
│   ├── dms/               ← DMS settings
│   └── ominty/            ← ai.toml, apps.toml
├── docs/                  ← installation and reference documentation
├── packages/              ← bundled .debs (niri, xwayland-satellite)
├── profiles/              ← optional hardware profiles
└── ominty-core/           ← the implementation submodule
    ├── AGENTS.md          ← implementation contracts (read when developing)
    ├── cli/ominty         ← the CLI entry point
    ├── cli/omintylib/     ← registry, generator, inspect, ai
    ├── actions/           ← the action registry
    ├── adapters/          ← platform adapters
    └── shell/dms/         ← DMS plugins
```

---

## 12. Naming

This project was previously called **OmiVoid**, and the core submodule was
`omivoid-lmde`. Old installations may still contain `~/.config/omivoid/`,
`~/.local/bin/omivoid` and `omivoidActions` / `omivoidKeybinds` plugin links.

`choices[].detected.legacy_config_dir` reports whether `~/.config/omivoid`
exists. If it does, offer the user a migration rather than installing
alongside it, and remove the stale symlinks once the new ones are in place.