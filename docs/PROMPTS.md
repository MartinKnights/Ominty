# Prompts for your AI

Ominty is designed to be set up **by an AI agent running on the machine**, with
the repository as its instructions. Copy one of these prompts into your agent
(Claude Code, opencode, Codex, Cursor — anything with shell access), and it will
work through the matching runbook.

The agent must be able to run shell commands as **your normal user**. It will
ask for your `sudo` password at the install step; that is expected.

---

## 1. Setting up a machine that is not running Ominty

Use this for a clean install, or for a machine still running Cinnamon/GNOME that
should become Ominty.

> You are installing Ominty on this machine. It is a fresh LMDE 7 (Debian 13)
> install that still has Cinnamon. I want Ominty as the desktop, and there is
> nothing from Cinnamon I need to keep.
>
> 1. The repository should be at `~/Ominty`. If it is not, fetch it with the
>    resumable bootstrap:
>    `curl -fsSLO https://raw.githubusercontent.com/MartinKnights/Ominty/main/bootstrap.sh`
>    then `bash bootstrap.sh`. Re-run it if a download drops; it continues from
>    where it stopped. If the checkout exists, `bash bootstrap.sh` updates it.
> 2. Read `AGENTS.md`, then follow `docs/AGENT-INSTALL.md` end to end.
> 3. Do the read-only assessment and ask me the required questions before
>    changing anything. Do not guess answers.
> 4. Show me the plan for approval (the Phase 5 dry run) and wait for my
>    go-ahead before installing.
> 5. Stop and tell me if a gate fails. Do not improvise around a failure, and do
>    not remove packages or edit the repository.
> 6. If logging out would end your own session, stop before the first-login
>    phase and give me the exact commands to run afterwards.
> 7. When it finishes, run the verification scripts and write the setup report.
>    AI comes last: ask me then whether to set up Ollama, Pi or neither, and use
>    `scripts/setup-ai.sh`. Tell me what passed, what was skipped, and what still
>    needs me (dictionary data, playlists, wallpaper).

---

## 2. Updating a machine that already runs Ominty

> This machine already runs Ominty. Read `docs/AGENT-UPGRADE.md` and execute it
> end to end.
>
> Follow its gates literally — if one fails, stop and tell me. Do not skip
> Phase 7: I want the friction report at `~/ominty-upgrade-report-<date>.md`.
> Ask me before anything destructive, and if you cannot answer a `sudo` prompt,
> tell me the exact command to run instead of working around it.

---

## 3. Something is broken

> Something is wrong with my Ominty desktop. Do not reinstall anything.
>
> 1. Run `scripts/collect-diagnostics.sh` and read `SUMMARY.txt` from the folder
>    it creates.
> 2. Read `docs/TROUBLESHOOTING.md` and fix what the evidence actually shows.
> 3. Ask me before anything destructive, and tell me what you are about to run.
> 4. If the cause is not covered, send me the diagnostics tarball instead of
>    guessing.

---

## What good agent behaviour looks like

| It should | It must not |
| --- | --- |
| Read the runbook file before acting | Reconstruct the process from memory or from a chat summary |
| Run `ominty inspect --json` and quote it | Parse human-readable installer output |
| Show a dry-run plan and wait | Install before the design/questions stage |
| Ask the required questions one at a time | Default `session.default` or `config.migration` |
| Stop at a failed gate and report | Patch upstream code, remove packages, or edit the repo to "make it work" |
| Keep the `collect-diagnostics.sh` output | Delete `.bak-ominty-*` backups |

## If the agent gets stuck

Point it at the file directly rather than re-describing the task:

- install problems → `docs/AGENT-INSTALL.md` §"Failure playbook"
- upgrade problems → `docs/AGENT-UPGRADE.md` §"Failure playbook"
- runtime problems → `docs/TROUBLESHOOTING.md`
- it disagrees with the docs → `scripts/check-docs.sh` should have caught that;
  please report it.
