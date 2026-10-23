# Agent runbook — upgrade an existing Ominty install

**Audience:** an AI agent (or a careful human) running *on* the target machine.
**Scope:** upgrade an existing Ominty/Niri/DMS install from this repository.
**Do not use this for a fresh install** — that is `docs/INSTALL.md`.

## How to invoke this

Point the agent at the file, not at a chat summary, so the whole runbook stays in
its context. A prompt that works:

> You are running on my LMDE 7 laptop. Read
> `docs/AGENT-UPGRADE.md` in this repository and execute it end to end.
> Follow its gates literally: stop and ask me if a gate fails. Do not skip
> Phase 7 — I want the friction report. Ask me before anything destructive.

The agent needs: shell access as the normal user, the repository checkout, and
a way to ask you for the sudo password (see Phase 4, mode B).

There are **two deliverables**, and the second one is not optional:

1. the machine is upgraded and verified (Phase 6);
2. a **friction report** is written to `~/ominty-upgrade-report-<date>.md`
   (Phase 7) describing how smooth the process actually was.

The report is the point of the exercise. A successful upgrade that produced no
report is a failed run.

---

## 0. Ground rules

These are hard constraints. If a situation is not covered here, **stop and ask
the user** rather than improvising.

| Rule | Why |
|---|---|
| Never run `install.sh` under `sudo` or as root. | It invokes sudo itself, per command. |
| Never remove packages, especially `dms`. | The old package is harmless; removal is not reversible without network. |
| Never edit files in the repository. | Local edits make the next `git pull` fail and hide the real friction. |
| Never `git commit` on the laptop. | The clone must stay a clean tracking branch. |
| Never `git reset --hard` or `git clean` without asking. | The user may have local work. |
| Never "fix" a failure by patching upstream code. | Record it in the report instead. |
| Ask before anything destructive. | Backups exist, but the user decides. |

Commands are bash. Run them from the repository root unless stated otherwise.
Keep every command's output; Phase 7 needs it.

---

## 1. Phase 0 — identify the host and the checkout

Record the answers; they go in the report.

```bash
cat /etc/os-release
uname -r
df -h "$HOME" | tail -1
```

**Gate 0a — supported release.** `ID=linuxmint` with
`VERSION_CODENAME=gigi`, or `ID=debian` with `VERSION_CODENAME=trixie`.
Anything else (notably `faye`/`bookworm` = Debian 12) is unsupported: stop and
report, do **not** continue.

Locate the existing clone:

```bash
for d in "$HOME/Ominty" "$HOME/Projects"/*/Ominty "$HOME"/src/Ominty; do
  [ -f "$d/install.sh" ] && echo "FOUND: $d"
done
```

If multiple, ask the user which one. `cd` into it and confirm it is the right
repository:

```bash
git remote -v
git rev-parse --abbrev-ref HEAD     # expect: main
```

**Gate 0b — clean tree.**

```bash
git status --short
```

If the output is non-empty: show it to the user and ask whether to
`git stash push -u -m "pre-upgrade"` or to abort. Do not discard anything.

Record in the report: whether the tree was clean, and whether `dms` is installed
as a package (`dpkg -l dms 2>/dev/null | tail -1`).

---

## 2. Phase 1 — update the checkout

```bash
git fetch origin
git log --oneline HEAD..origin/main        # what is about to land; show the user
git pull --ff-only
git submodule sync --recursive
git submodule update --init --recursive
```

`submodule sync` is required: older clones cache the SSH URL in `.git/config`
and `submodule update` will otherwise fail without a key.

**Gate 1** — `git submodule status` shows a commit (not a leading `-`), and
`ominty-core/cli/ominty --help` runs without a traceback.

---

## 3. Phase 2 — read-only assessment

Nothing here changes the machine. Capture all output.

```bash
./ominty-core/cli/ominty inspect --json > /tmp/ominty-before.json || true
./ominty-core/cli/ominty inspect
./install.sh --dry-run | tee /tmp/ominty-dryrun.log
```

`inspect` exits `1` when there is a **blocking** finding — that is a signal, not
a crash, and `--json` still writes a complete document. Never let `set -e` turn
it into an abort; treat its exit code as data.

**Gate 2a — supported platform.** Read the JSON rather than eyeballing it:

```bash
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

Pass condition: `family` is `mint-debian` (or `debian`), `support_level` is
`validated`, and every blocking finding is **layer-related** (a missing package
the installer will add). A blocking finding with id `platform` or `hardware` is
a stop condition.

`ready: False` before the install is normal and expected.

**Gate 2b** — the dry run exits `0` and its plan contains all of:

- `Building DMS from source`
- `Deploying helper scripts`
- `apply.sh --check   # verify the overlay against this DMS build`
- `Installing the DMS user service`

If a step is missing, the checkout is stale — go back to Phase 1.

Show the user a short summary of what will change (package installs, DMS
rebuild, config files replaced with backups) and get an explicit go-ahead
before Phase 4.

---

## 4. Phase 3 — snapshot

```bash
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p "$HOME/.ominty-pre-upgrade-$ts"
cp -a "$HOME/.config/niri/config.kdl"   "$HOME/.ominty-pre-upgrade-$ts/" 2>/dev/null
cp -a "$HOME/.config/DankMaterialShell" "$HOME/.ominty-pre-upgrade-$ts/" 2>/dev/null
cp -a "$HOME/bin"                       "$HOME/.ominty-pre-upgrade-$ts/" 2>/dev/null
cp -a "$HOME/.local/bin"                "$HOME/.ominty-pre-upgrade-$ts/" 2>/dev/null
systemctl --user cat dms.service > "$HOME/.ominty-pre-upgrade-$ts/dms.service.txt" 2>&1
echo "$HOME/.ominty-pre-upgrade-$ts"
```

Write the snapshot path into the report. `install.sh` also creates
`.bak-ominty-<timestamp>` copies; this snapshot is the belt-and-braces one.

---

## 5. Phase 4 — run the installer

First decide whether you can satisfy sudo:

```bash
sudo -n true 2>/dev/null && echo "SUDO: non-interactive" || echo "SUDO: needs a password"
```

### Mode A — sudo available non-interactively

```bash
set -o pipefail
./install.sh 2>&1 | tee /tmp/ominty-install.log
echo "installer exit: ${PIPESTATUS[0]}"
```

### Mode B — sudo needs a password

A background shell cannot answer an interactive password prompt reliably.
Hand the single command to the user and say exactly this:

> Run this in your terminal and leave it running — I'll read the log:
> `cd <repo> && ./install.sh 2>&1 | tee /tmp/ominty-install.log`

Wait for them to finish, then continue. Do not attempt to work around sudo.

**Gate 4** — the log ends with the validation step and the exit code is `0`.
Warnings are allowed (Piper/TTS is optional). Any `[ERROR]` line, or a non-zero
exit, is a stop condition: go to the failure playbook and then Phase 7.

Record in the report: elapsed time, and the number and text of warnings.

---

## 6. Phase 5 — activate

```bash
systemctl --user daemon-reload
systemctl --user restart dms.service
sleep 3
systemctl --user status dms.service --no-pager | head -20
```

Then ask the user to **log out and back in**: keybindings apply immediately,
but the new `spawn-at-startup` entries (Piper daemon, voice popup, swayidle)
only run in a fresh session. Do not reboot on your own initiative.

---

## 7. Phase 6 — verify

Most of this is mechanical, so run the script first:

```bash
./scripts/verify-upgrade.sh | tee /tmp/ominty-verify.log
echo "verify exit: ${PIPESTATUS[0]}"
```

It checks the DMS binary and version, the unit, `DMS_SHELL_DIR`, the overlay
marker and glow patch, `ominty inspect`, the deployed helpers, the Quickshell
links, `niri validate` and TTS, and exits non-zero if anything failed. Paste its
full output into the report.

A failing `desktop layer satisfied` / `summary ready` usually means one apt
package did not install — the script prints the blocking layer id.

Then run the table below for the record; it is the same list the script covers,
plus the checks a machine cannot make. Expected values are in the Appendix.

| # | Check | Command | Pass condition |
|---|---|---|---|
| 1 | Right binary | `dms version` | reports the pinned build, **not** `2.0.0` |
| 2 | Unit is ours | `systemctl --user cat dms.service \| head -5` | `ExecStart=%h/.local/bin/dms` or the resolved home path |
| 3 | Fork in use | `systemctl --user show dms.service -p Environment` | contains `DMS_SHELL_DIR=.../dms-shell` |
| 3b | Shell is alive | `./scripts/smoke-dms.sh` | stable, `NRestarts` unchanged, IPC responsive |
| 4 | Overlay base | `cat ~/.local/share/dms-shell/.ominty-overlay.json` | `"base":"c27a2bbcb6e09e50"` |
| 5 | Overlay applied | `./ominty-core/cli/ominty inspect --json` | `desktop.shell_overlay.state == "applied"` |
| 6 | Desktop source | same JSON | `platform.desktop_source == "source"` |
| 7 | Nothing blocking | same JSON | `summary.ready == true` and `layers.desktop.satisfied == true` |
| 8 | Helper scripts | `for f in artha-word read-selection tts-pick piper-daemon piper-indicator; do test -x ~/bin/$f \|\| echo "MISSING $f"; done` | no output |
| 9 | Local-bin scripts | `for f in screen-ocr start-swayidle wait-for-tray clip-tool; do test -x ~/.local/bin/$f \|\| echo "MISSING $f"; done` | no output |
| 10 | Quickshell links | `ls -l ~/.config/quickshell/ominty-voice ~/.config/quickshell/ominty-tts` | both symlinks resolve |
| 11 | Niri config | `niri validate` | `config is valid` |
| 12 | TTS runtime | `ominty tts status` | a status line, not a traceback |

Save the post-upgrade JSON:

```bash
./ominty-core/cli/ominty inspect --json > /tmp/ominty-after.json
```

The one thing you cannot check is the *look*: ask the user to confirm that the
launcher/popout/OSD have the accent glow and the slower spring animation, and
that `Super+S`, `Ctrl+Alt+S`, `Ctrl+Alt+A`, `Ctrl+Alt+R` do something.

---

## 8. Phase 7 — friction report

Write `~/ominty-upgrade-report-<YYYY-MM-DD>.md`. Keep it outside the repo so
`git status` stays clean. Use exactly this structure:

```markdown
# Ominty upgrade report — <host> — <date>

## Machine
- distro / codename / kernel:
- niri, quickshell, dms before → after:
- dms installed as a package before: yes/no
- GPU / session (niri or Cinnamon):

## Verdict
- Upgrade: success / partial / failed / aborted
- Time: total, and per phase
- Manual interventions by the user: <count> (list them)
- Could this run unattended next time? yes/no + why

## What went smoothly
- ...

## Friction
| # | Phase | What happened | Severity | Suggested fix |
|---|-------|---------------|----------|---------------|
| 1 |       |               | blocker / annoying / cosmetic | |

Severity: blocker = stopped the run; annoying = needed a decision or a retry;
cosmetic = confusing message or doc gap.

## Deviations from docs/AGENT-UPGRADE.md
- ...

## Update-path observations
- Did `git pull` / submodule sync work first try?
- Did the dry run match what actually happened?
- Were warnings actionable, or noise?
- Did any step require knowledge that was not in the runbook?
- Config files replaced that the user had customised (and did the backup help)?

## Evidence
- installer log: /tmp/ominty-install.log
- dry-run: /tmp/ominty-dryrun.log
- verify output: /tmp/ominty-verify.log
- before/after JSON: /tmp/ominty-before.json, /tmp/ominty-after.json
- pre-upgrade snapshot: <path>
```

Then print the report to the user and tell them the file path.

---

## 9. Failure playbook

Apply the matching entry, then continue to Phase 7 — a failed upgrade still
produces a report, and that report is the most valuable kind.

| Symptom | Response |
|---|---|
| `git pull` refuses (dirty tree / diverged) | Stop. Show the user `git status`; ask for a decision. |
| `submodule update` asks for SSH | `git submodule sync --recursive`, retry. |
| Gate 2a failing / `unsupported` | Stop. The host is not LMDE 7 / Debian 13. |
| Dry run errors before doing anything | Capture the traceback; stop. |
| apt failure | Capture the failing package and the apt output; stop. Do not add repos by hand. |
| DMS build fails | Re-run `scripts/source/dms-build.sh` alone to get a clean error; capture it; latest log line is usually enough. |
| Overlay `not-applicable` (exit 1) | Not fatal: the stock shell keeps running. Record it and continue. |
| Overlay exit 3 | Start DMS once, then `configs/dms/shell-overlay/apply.sh`. Record it. |
| `dms.service` fails to start | `journalctl --user -u dms.service -n 80 --no-pager`; capture; try `systemctl --user restart`. |
| Piper/TTS disabled | Allowed (optional layer). Record the warning verbatim. |
| Anything else | Stop and report; do not invent a fix. |

Rollback, only on explicit user request:

```bash
rm -f ~/.config/systemd/user/dms.service.d/ominty-shell.conf
systemctl --user daemon-reload && systemctl --user restart dms.service
# full: restore ~/.config/niri/config.kdl and ~/.config/DankMaterialShell from
# the snapshot in Phase 3, then re-run install.sh from the previous commit.
```

---

## 10. Definition of done

- [ ] Phases 0–6 completed, or the run stopped at a documented gate.
- [ ] All 12 Phase 6 checks executed and their results recorded.
- [ ] User asked to confirm the visual/animation result.
- [ ] `~/ominty-upgrade-report-<date>.md` written and its path given to the user.
- [ ] Repository still clean (`git status --short` empty apart from ignored files).

---

## Appendix — values you should see on a healthy LMDE 7 run

| Thing | Expected |
|---|---|
| `platform.family` | `mint-debian` |
| `platform.support_level` | `validated` |
| `platform.desktop_source` | `source` |
| `summary.ready` | `true` (only after a successful install) |
| DMS source commit | `73759d575210e8a4eb99b308283046b650df2ac3` |
| Embedded shell build | `c27a2bbcb6e09e50` |
| `desktop.shell_overlay.base` | `c27a2bbcb6e09e50` |
| DMS unit | user unit in `~/.config/systemd/user/dms.service` |
| Overlay drop-in | `~/.config/systemd/user/dms.service.d/ominty-shell.conf` |
| Rollback | delete the drop-in, `daemon-reload`, restart `dms.service` |
