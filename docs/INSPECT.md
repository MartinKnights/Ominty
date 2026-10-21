# `ominty inspect --json` schema

The machine-readable installation audit. This is the contract an installing
agent depends on; treat changes to it as a compatibility event and check
`schema_version`.

```sh
ominty inspect --json
ominty inspect --json --layer desktop   # narrow to specific layers
ominty inspect                          # human-readable
```

Read-only, and never requires `sudo`. Exit code is `0` when
`summary.ready` is true, `1` otherwise — that reflects *blocking* findings
only, so it is safe to use in scripts.

---

## Top level

| Key | Type | Notes |
| --- | --- | --- |
| `schema_version` | int | Currently `1`; new fields are additive within a version. |
| `tool` | string | Always `"ominty"`. |
| `platform` | object | See below. |
| `hardware` | object | `arch`, `cpu`, `gpu`. |
| `desktop` | object | DMS/niri/matugen versions and shell-overlay state. |
| `session` | object | `type`, `desktop`, `wayland_display`. |
| `privilege` | object | `sudo` (passwordless?), `required`. |
| `layers` | object | Keyed by layer id. |
| `apt` | object | `sources`, `pins`, `backports_enabled`, `obs_danklinux_enabled`, `obs_dms_enabled`. |
| `configs` | object | Keyed by config name. |
| `tts` | object | Indicator, typelib and voice state. |
| `choices` | array | See "Choice points". |
| `findings` | array | Every check. |
| `summary` | object | `ready`, `blocking`, `warnings`, `required_choices`, `counts`. |

---

## `platform`

```json
{
  "id": "debian",
  "distro_id": "linuxmint",
  "pretty_name": "Linux Mint 22.3",
  "version_id": "22.3",
  "codename": "zena",
  "ubuntu_codename": "noble",
  "is_lmde": false,
  "family": "mint-ubuntu",
  "desktop_source": "source",
  "support_level": "supported",
  "supported": true
}
```

`id` is the platform family Ominty's adapters key on: `debian`, `void`, or
`unknown`. `family` keeps the provisioning distinction that `id` collapses:

| `family` | Meaning |
| --- | --- |
| `debian` | Debian proper. |
| `mint-debian` | LMDE. |
| `ubuntu` | Ubuntu proper. |
| `mint-ubuntu` | Ubuntu-based Mint. |
| `void` / `unknown` | Not (yet) supported. |

`is_lmde` is true only for `mint-debian`. Ubuntu-based Mint has `ubuntu` in
`ID_LIKE` *and* `debian`, so testing for `debian` alone would misclassify it.

`desktop_source` says how DMS got onto the machine: `obs` (Debian/LMDE
package), `ppa` (Ubuntu Launchpad PPA), `source` (built into `~/.local`), or
`none`. The installer uses it to decide whether it may replace `dms.service`
or must leave the packaged unit alone and use a drop-in.

`support_level` is one of `supported`, `validated`, `unvalidated` or
`unsupported`; `supported` is the boolean shortcut.

- Debian-family hosts are validated when `codename` is `trixie`, `faye` or
  `gigi` (`gigi` is Debian 13's codename, which some LMDE 7 images report
  instead of LMDE's own `faye`).
- Ubuntu-family hosts are supported through the **source-build** path when
  their Ubuntu base (`ubuntu_codename`, falling back to `codename` for Ubuntu
  itself) is `noble`. Other Ubuntu bases warn as unvalidated.
- A non-Debian-family distribution is a **blocking** finding. An untested
  codename is only a warning, because it is a judgement call for the user.

---

## `layers`

```json
"layers": {
  "desktop": {
    "id": "desktop",
    "label": "Niri + DMS desktop",
    "description": "Compositor, shell, theming, audio and portals.",
    "provisioned": true,
    "packages": [
      {
        "name": "dms",
        "state": "installed",
        "version": "1.6.2db1",
        "source": "obs",
        "required": true
      },
      {
        "name": "niri",
        "state": "missing",
        "version": null,
        "source": "local",
        "required": true,
        "reason": "Not installed; ships as a local .deb in packages/.",
        "fix": "Run install.sh to install the bundled .deb."
      }
    ],
    "satisfied": false,
    "missing": ["niri"]
  }
}
```

`source` is one of:

| Value | Meaning |
| --- | --- |
| `apt` | In the Debian/Ubuntu archive. |
| `obs` | From the AvengeMedia Open Build Service. Needs `install.sh` to add the sources. |
| `local` | A `.deb` bundled in `packages/`. |

`provisioned` says whether `install.sh` installs the layer today. A layer with
`provisioned: false` reports a **warning**, never a blocking finding — do not
tell the user a layer is broken when it simply is not offered yet.

`optional: true` marks a feature layer (currently `tts`). Missing packages in
an optional layer also report a **warning**: the user may simply not want the
feature, so it must never block a desktop install. `install.sh` still installs
the layer's packages when the layer is selected; `--layers` can leave it out.

`reason` and `fix` appear only on `missing` packages. Always pass `reason` on
to the user: it distinguishes an uninstalled package from an unavailable one.

---

## `desktop`

Version and overlay state for the Niri + DMS desktop.

```json
{
  "dms_version": "ominty-managed-v1+d0c1b3f",
  "niri_version": "26.04",
  "matugen_version": "4.2.0",
  "custom_shader": true,
  "shell_dir": "/home/user/.local/share/dms-shell",
  "shell_overlay": {"state": "applied", "base": "c27a2bbcb6e09e50"},
  "theme_fragment": {
    "path": "/home/user/.config/niri/dms/ominty-theme.kdl",
    "present": true
  }
}
```

`custom_shader` is true when niri is 26.04 or newer, the first version whose
config understands `custom-shader`. `shell_overlay.state` is `applied` only
when the fork at `shell_dir` actually contains the accent-glow property;
`base` is the DMS build the fork was created from, as recorded by
`configs/dms/shell-overlay/apply.sh`. A DMS upgrade changes the pristine build
id, so comparing `base` against the running build tells you the fork is stale.

The desktop checks are informational: a stock shell or a missing theme fragment
is a warning, never a blocker.

---

## `tts`

Read-aloud state. TTS is optional; every missing piece is a warning.

```json
{
  "indicator": "/home/user/bin/piper-indicator",
  "daemon": "/home/user/bin/piper-daemon",
  "running": true,
  "typelib": "user",
  "voice": "en_GB-cori-high",
  "voices": ["en_GB-cori-high", "en_US-kusal-medium"]
}
```

`typelib` is `system` (installed by apt), `user` (extracted into the rootless
prefix under `~/.local/opt`), or `missing`. When it is `missing`, tell the user
to install `gir1.2-ayatanaappindicator3-0.1` (the `tts` layer) or run the
rootless fallback; do not treat it as a blocked install.

`voice` honours `OMINTY_TTS_VOICE`, then the first voice found under
`~/.local/share/piper/voices`.

---

## `findings`

```json
{
  "id": "layer.desktop",
  "status": "warn",
  "severity": "info",
  "message": "Layer 'Niri + DMS desktop' is missing 1 required package(s): niri.",
  "fix": "Run install.sh, or install the missing packages individually."
}
```

| `status` | Meaning |
| --- | --- |
| `pass` | Check succeeded. |
| `warn` | Usable, but the user should know. |
| `fail` | Something is wrong. |

`severity` decides whether a `fail` blocks:

- `blocking` → do not install. Report and stop.
- `info` → informational only.

Only failures with `severity: "blocking"` appear in `summary.blocking`.

Finding ids are stable and namespaced: `platform`, `hardware.*`, `desktop.*`,
`layer.*`, `config.*`, `plugin.*`, `session`, `session.dms`, `tts.*`,
`choice.*`.

---

## `summary`

```json
{
  "ready": false,
  "blocking": ["config.ominty_cli", "config.ominty_hook"],
  "warnings": ["layer.cli", "choice.llm.provider"],
  "required_choices": ["llm.provider", "session.default", "config.migration"],
  "counts": {"pass": 6, "warn": 12, "fail": 2}
}
```

`ready` is `not summary.blocking`.

**Outstanding choices do not affect `ready`.** A question waiting for an answer
is not a failure. Read `required_choices` separately and ask.

---

## Choice points

```json
{
  "id": "llm.provider",
  "question": "Which LLM should power the AI actions (Super+A), or should AI be left unconfigured?",
  "required": true,
  "multiple": false,
  "rationale": "AI actions need a provider before the configuration can be written...",
  "default": "ollama",
  "detected": {
    "configured_provider": "pi",
    "config_file": "/home/user/.config/ominty/ai.toml",
    "provider_status": {
      "ollama": {"state": "unavailable", "detail": "ollama binary not found in PATH"},
      "pi": {"state": "available", "detail": ""}
    }
  },
  "options": [
    {
      "value": "ollama",
      "label": "Ollama (local models)",
      "detail": "Runs models on this machine...",
      "available": false,
      "unavailable_reason": "ollama binary not found in PATH"
    }
  ]
}
```

`multiple` distinguishes a multi-select (`layers`, where `default` is a list)
from a single-select.

`available` is probed live. When the AI layer cannot be probed at all, options
stay `available: true` rather than being wrongly reported unusable — an
unavailable-looking option that actually works is worse than a missing detail.

### Current choices

| id | Required | Question |
| --- | --- | --- |
| `llm.provider` | yes | Which LLM powers the AI actions, or none? |
| `layers` | no | Which optional groups to install (multi-select). |
| `session.default` | yes | Make Niri the default login session, or leave it? |
| `config.migration` | yes | Replace existing configuration, or keep it? |
| `plugins.dms` | no | Install the third-party DMS plugins? |
| `desktop.shell_overlay` | no | Apply Ominty's motion + accent-glow overlay, or keep stock DMS? |
| `tts.enabled` | no | Install the Piper read-aloud stack? |

---

## `--layer`

Restricts the report to the named layers. Findings not scoped to a layer
(`platform`, `hardware`, `session`, `config.*`, `plugin.*`, `choice.*`) are
global and are always kept, because they affect any install. Choice points are
also always kept.

An unknown layer id is an error, and the message lists the valid ids.

---

## Stability

The schema changes only with a `schema_version` bump. Fields may be **added**
within a version; agents should ignore keys they do not recognise rather than
failing.