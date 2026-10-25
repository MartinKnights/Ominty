# Agent runbook — fresh Ominty install

**Audience:** an AI agent running *on* the target machine.
**Scope:** install Ominty on a machine that is not already running it.
**Do not use this for an upgrade** — that is `docs/AGENT-UPGRADE.md`.
**Migrating from Cinnamon/GNOME?** Do the assessment in
`docs/MIGRATION.md` first, then follow this file.

There are **two deliverables**:

1. a working desktop, verified (Phase 8);
2. a **setup report** at `~/ominty-setup-report-<date>.md` (Phase 10).

An install that produced no report is an incomplete run.

---

## How to invoke this

The user should point you at the file, not at a chat summary:

> Read `AGENTS.md`, then follow `docs/AGENT-INSTALL.md` end to end.

---

## 0. Ground rules

| Rule | Why |
| --- | --- |
| Never run `install.sh` under `sudo` or as root. | It calls sudo itself, per step. |
| Never edit files in the repository. | Local edits break the next pull and hide friction. |
| Never remove packages or delete `.bak-ominty-*`. | They are the recovery path. |
| Never default the three required choices. | They change boot behaviour and user data. |
| Stop at a failed gate; report rather than improvise. | A failed gate is information. |

Commands are bash. Run them from the repository root unless stated otherwise.

---

## 1. Phase 0 — is this machine a valid target?

```sh
cat /etc/os-release
uname -m
df -h "$HOME" | tail -1
for c in git curl gpg python3 sudo systemctl; do
  command -v "$c" >/dev/null || echo "MISSING: $c"
done
for h in github.com download.opensuse.org huggingface.co dl.google.com; do
  curl -fsSI --max-time 8 "https://$h" >/dev/null 2>&1 || echo "unreachable: $h"
done
```

| Gate | Pass condition |
| --- | --- |
| Distribution | `ID=debian` + `VERSION_CODENAME=trixie`, **or** `ID=linuxmint` + `VERSION_CODENAME=gigi`, **or** Ubuntu-family with `UBUNTU_CODENAME` (Mint exposes it) |
| Architecture | `x86_64` |
| Free space | ≥ 10 GB under `$HOME` |
| Required tools | `git`, `curl`, `gpg`, `python3`, `sudo`, `systemctl` |
| Network — required | `github.com` (source pins, plugins) and `download.opensuse.org` (the OBS signing key; the installer aborts without it) |
| Network — required if `go` is absent | `dl.google.com` (the installer downloads Go) |
| Network — optional | `huggingface.co` (the ~142 MB whisper model; the rest of the install succeeds without it) |

**Stop conditions:** Debian 12 / LMDE 6 (`bookworm`, `faye`) — no
`trixie-backports`, so Quickshell cannot be installed; any other distribution;
non-x86_64; less than 10 GB free.

Record the values; they go in the report.

---

## 2. Phase 1 — get the repository

Use the bootstrap script: it fetches in retryable pieces and continues from
where a dropped download stopped. Run it as many times as needed.

```sh
if [ -f bootstrap.sh ]; then
    bash bootstrap.sh
else
    curl -fsSLO https://raw.githubusercontent.com/MartinKnights/Ominty/main/bootstrap.sh
    bash bootstrap.sh
fi
cd ~/Ominty
git submodule status        # must show a commit, not a leading '-'
```

If the bundled `.deb`s keep failing on a slow link, copy them from another
checkout or a USB and point the script at them:
`OMINTY_PACKAGES_SRC=/path/to/packages bash bootstrap.sh`.

If a checkout already exists, use it:

```sh
git -C <repo> status --short     # must be empty
git -C <repo> pull --ff-only
git -C <repo> submodule sync --recursive
git -C <repo> submodule update --init --recursive
```

**Gate 1:** `ominty-core/cli/ominty --help` runs without a traceback.

---

## 3. Phase 2 — read-only assessment

```sh
./ominty-core/cli/ominty inspect --json > /tmp/ominty-before.json || true
./ominty-core/cli/ominty inspect
set -o pipefail
./install.sh --dry-run | tee /tmp/ominty-dryrun.log   # sanity: the plan exists
```

`inspect` exits `1` when there is a blocking finding; the JSON is still valid.

**Gate 2a:** read `summary.blocking` from the JSON.

```sh
python3 - <<'PY'
import json
r = json.load(open("/tmp/ominty-before.json"))
p = r["platform"]
print("family:        ", p["family"])
print("support_level: ", p["support_level"])
print("desktop_source:", p["desktop_source"])
print("ready:         ", r["summary"]["ready"])
for f in r["findings"]:
    if f["severity"] == "blocking":
        print("BLOCKING:", f["id"], "-", f["message"])
PY
```

Pass: `support_level` is `validated` (or `supported` on Ubuntu-family), and any
blocking finding is layer-related (a package the installer adds). A blocking
finding with id `platform` or `hardware` is a stop.

`ready: false` before installing is normal.

**Gate 2b:** the dry run exits `0` and its plan contains, at minimum:

- `scripts/source/quickshell-build.sh` (Debian) or the Ubuntu build script
- `scripts/source/dms-build.sh`
- `scripts/smoke-dms.sh --restart`
- `Deploying helper scripts`
- `apply-plugin-patches.sh`

---

## 4. Phase 3 — snapshot anything that exists

On a machine with no desktop, skip. On a migration, snapshot first:

```sh
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p "$HOME/.ominty-pre-install-$ts"
cp -a "$HOME/.config/niri"              "$HOME/.ominty-pre-install-$ts/" 2>/dev/null
cp -a "$HOME/.config/DankMaterialShell" "$HOME/.ominty-pre-install-$ts/" 2>/dev/null
cp -a "$HOME/bin" "$HOME/.local/bin"    "$HOME/.ominty-pre-install-$ts/" 2>/dev/null
echo "$HOME/.ominty-pre-install-$ts"
```

Record the path in the report. `install.sh` also makes per-file backups.

---

## 5. Phase 4 — ask the required questions

Ask only what is in `summary.required_choices`, one at a time. If a decision is
already resolved in the JSON, do not ask it again.

| Choice | What to ask | How the answer is applied |
| --- | --- | --- |
| `llm.provider` | Which provider (or `none`), quoting availability | **No installer flag.** The installer writes `~/.config/ominty/ai.toml` from the template if absent. After the install, with consent, set `[ai] default_provider` to the chosen provider. For `none`, set it to `none`: the AI actions then report an unavailable provider and nothing is downloaded. (The `enabled` keys are not read by this build.) |
| `session.default` | Should Niri become the default session? | **No installer flag.** Niri is selectable at login either way. If they want it default, point them at their display manager's session setting (on LMDE: the *Login Window* tool); do not edit system files yourself. |
| `config.migration` | Is replacing existing configuration (with backups) acceptable? | **No keep flag.** `install.sh` always backs up to `.bak-ominty-<ts>` and replaces. If the user wants to keep their configuration, stop and do the [MIGRATION.md](MIGRATION.md) assessment, or merge manually afterwards. |

Optional choices, and the exact switch:

| Choice | How to apply |
| --- | --- |
| `layers` | `--layers "desktop tts …"` |
| `plugins.dms` | `--no-plugins` (there is no plugins layer) |
| `tts.enabled` | include or omit `tts` in `--layers` |
| `desktop.shell_overlay` | no flag — it is applied automatically when the patch matches the built shell |

Never write to the repository to record an answer.

---

## 6. Phase 5 — plan and approval

```sh
./install.sh --dry-run --layers "<chosen>"
```

Summarise for the user: packages, the Quickshell and DMS builds, the unit it
will write, the plugins it will pin, the data it will *not* install. Get an
explicit go-ahead.

---

## 7. Phase 6 — apply

Decide whether sudo is available:

```sh
sudo -n true 2>/dev/null && echo "SUDO: non-interactive" || echo "SUDO: needs a password"
```

**Mode A — non-interactive:**

```sh
set -o pipefail
./install.sh --layers "<chosen>" 2>&1 | tee "$HOME/ominty-install-$(date +%F).log"
echo "installer exit: ${PIPESTATUS[0]}"
```

**Mode B — password required:** hand the user this command and wait:

> Run this in your terminal and leave it running — I'll read the log:
> `cd <repo> && ./install.sh --layers "<chosen>" 2>&1 | tee "$HOME/ominty-install-$(date +%F).log"`

**Gate 6:** exit `0`. Warnings are acceptable (optional layers, skipped
packages, Piper). A non-zero exit means a fatal step failed — the log says
which; it is only the shell smoke test if the last lines say so. Either way,
capture the log and still write the report.

The installer **skips the shell smoke test when Niri is not running** (a fresh
machine, a TTY, or a migration from another desktop). That is expected:
`dms.service` is `Requisite=graphical-session.target`, so it cannot run until the
first Niri login. Verification happens in Phase 8.

Pre-login sanity, which does not need a session:

```sh
./ominty-core/cli/ominty inspect --json > /tmp/ominty-after.json || true
"$HOME/.local/bin/dms" version          # ominty-pinned+<sha>
~/.local/bin/quickshell --version        # Quickshell 0.3.1
./ominty-core/cli/ominty registry validate
niri validate
```

---

## 8. Phase 7 — first login

Ask the user to log out and select **Niri** at the display manager (a reboot is
not required; this is a different session, not a new machine). The startup
entries — Piper, the reader/dictation popups, swayidle — only run in a fresh
session.

**If you are running inside the session being replaced** (a terminal in
Cinnamon, for example), logging out ends your own process. In that case:

- run the agent over SSH or from a TTY so you survive the logout, **or**
- finish the pre-login checks, hand the user the Phase 8 command block, and
  resume afterwards.

Never claim verification you did not run. The report records what was actually
checked.

On a migration, tell them the old session stays selectable.

---

## 9. Phase 8 — verify (after login)

Run **inside the Niri session**:

```sh
./scripts/smoke-dms.sh
./scripts/verify-upgrade.sh | tee /tmp/ominty-verify.log
./scripts/verify-parity.py  | tee /tmp/ominty-parity.log
```

| Check | Expected |
| --- | --- |
| `smoke-dms.sh` | exit 0: stable, `NRestarts` unchanged, IPC answers |
| `verify-upgrade.sh` | 0 failed, or a recorded overlay finding (see below) |
| `verify-parity.py` | 0 failed |
| `dms version` | `dms ominty-pinned+<commit>` — **not** `2.0.0`, not `(git) v-1` |
| `systemctl --user cat dms.service` | `ExecStart=.../.local/bin/dms` |
| `DMS_SHELL_DIR` in the unit environment | `~/.local/share/dms-shell` |
| overlay marker | `"base":"c27a2bbcb6e09e50"` |
| `platform.desktop_source` | `source` |
| `summary.ready` | `true` |
| `layers.desktop.satisfied` | `true` |

If the overlay was skipped (`apply.sh` exit 1 or 3), `verify-upgrade.sh` will
report the missing marker. That is a **finding to record**, not a pass: the
stock shell is running. Apply it once DMS has started:

```sh
configs/dms/shell-overlay/apply.sh --check
configs/dms/shell-overlay/apply.sh
systemctl --user daemon-reload && systemctl --user restart dms.service
```

Then ask the user to confirm what a machine cannot: the accent glow, the spring
animation, and the six Ominty keys (`Shift+Alt+M`, `Ctrl+Shift+A`,
`Super+Alt+O`, `Super+Alt+T`, `Ctrl+Alt+R`, `Super+S`).

---

## 10. Phase 9 — optional data

Offer, do not force:

| Data | Command | Effect if skipped |
| --- | --- | --- |
| Dictionaries | `scripts/omi-dict-import.sh ~/Documents/Dictionaries` | Dictionary popup says it is unavailable |
| Playlists | drop `.m3u` files in `~/Playlist/<folder>/` | Media launcher says no folders have playlists |
| Wallpapers | put images in `~/Wallpapers` | Carousel is empty |
| AI provider | edit `~/.config/ominty/ai.toml` with the user | AI actions are unavailable |

Never invent dictionary or media content. Ask where the files are.

---

## 11. Phase 10 — setup report

Write `~/ominty-setup-report-<YYYY-MM-DD>.md`:

```markdown
# Ominty setup report — <host> — <date>

## Machine
- distro / codename / kernel / arch:
- free space before:
- repo commit / submodule commit:

## Verdict
- Install: success / partial / failed / aborted
- Time: total and per phase
- User decisions: llm.provider=…, session.default=…, config.migration=…, layers=…
- Manual interventions: <count> (list)

## Verification
- smoke-dms: pass/fail/skip (reason)
- verify-upgrade: N passed / N failed
- verify-parity: N passed / N failed
- dms version / quickshell version / overlay base:

## Not done yet
- dictionaries / playlists / wallpapers / AI provider (as applicable)

## Friction
| # | Phase | What happened | Severity | Suggested fix |
|---|-------|---------------|----------|---------------|

## Evidence
- installer log, dry-run, before/after JSON, verify logs, snapshot path
```

Print it to the user and give the path.

---

## 12. Failure playbook

| Symptom | Response |
| --- | --- |
| Gate 0 fails (distro/arch/space/missing tools) | Stop. Report the values. |
| `git clone`/submodule fails | Check network and HTTPS; `git submodule sync --recursive` then retry. |
| `inspect` has a `platform.*` or `hardware.*` blocking finding | Stop. |
| `inspect` reports blocking `layer.*` findings | Expected before an install: the installer adds those packages. Continue. |
| Dry run missing a build step | The checkout is stale — redo Phase 1. |
| apt failure | The installer skips unresolvable names; if the *required* layer is affected, capture the apt output and stop. |
| Quickshell build fails | Re-run `scripts/source/quickshell-build.sh` alone for a clean error; capture it. |
| DMS build fails | Re-run `scripts/source/dms-build.sh`; capture it. |
| Installer exit non-zero | Read `~/ominty-install-<date>.log`. If it ends in the shell smoke test, the installer already fell back; run `scripts/collect-diagnostics.sh`. Otherwise a fatal step failed — report it. |
| Shell crash-loops after login | `scripts/collect-diagnostics.sh`, keep `~/ominty-dms-matrix-*.md` from `scripts/diagnose-dms-shell.sh`, report. |
| Overlay `not-applicable` | Not fatal: the stock shell runs. Record it and continue. |
| Overlay exit 3 | Start DMS once, then `configs/dms/shell-overlay/apply.sh`. |
| Plugin patch does not apply | Upstream moved. Report; do not hand-edit the plugin. |
| `niri validate` fails | Do not tell the user to log in. Report the error. |
| Anything else | Stop and report; do not invent a fix. |

Rollback, only on explicit request:

```sh
scripts/rollback-dms.sh --overlay-off
scripts/rollback-dms.sh --to-backup
```

A full uninstall is documented in `docs/INSTALL.md`; it needs explicit
confirmation.

---

## 13. Definition of done

- [ ] Phases 0–8 completed, or stopped at a documented gate.
- [ ] Verification run **after** the first Niri login, with results recorded.
- [ ] Overlay state recorded as applied or as an explicit finding.
- [ ] User asked to confirm the visual/animation result and the six keys.
- [ ] `~/ominty-setup-report-<date>.md` written and its path given to the user.
- [ ] Repository still clean (`git status --short` empty apart from ignored files).
