# Ominty

**A keyboard-first, action-driven Wayland desktop for Debian-based systems.**

Ominty is a complete desktop you can install in one command: Niri as the
compositor, DankMaterialShell as the shell, and a small CLI and action registry
that make everything discoverable, scriptable and keyboard-driven. It is built
and validated on **LMDE 7 / Debian 13**, and supports Ubuntu-family systems
through the same source-build path.

---

## Two ways to install

### Do it yourself

```sh
curl -fsSLO https://raw.githubusercontent.com/MartinKnights/Ominty/main/bootstrap.sh
bash bootstrap.sh          # resumable: re-run it if the download drops
cd ~/Ominty
./install.sh --dry-run     # read the plan first
./install.sh
```

`bootstrap.sh` fetches the checkout in retryable pieces (metadata, source,
submodule, then the bundled `.deb`s) and is safe to run as many times as
needed. On a slow link, pass a copy of `packages/` instead:
`OMINTY_PACKAGES_SRC=/media/usb/Ominty/packages bash bootstrap.sh`.

<details><summary>Prefer a plain git clone?</summary>

```sh
git clone --recurse-submodules https://github.com/MartinKnights/Ominty.git
cd Ominty
```
</details>

Log out, pick the **Niri** session at the display manager, and you are in.
Full guide, including post-install checks: [docs/INSTALL.md](docs/INSTALL.md).

### Let your AI do it

Copy this into your agent (Claude Code, opencode, Codex, Cursor — anything with
shell access):

> You are setting up Ominty on this machine. Read `AGENTS.md`, then follow
> `docs/AGENT-INSTALL.md` end to end. Do the read-only assessment and ask me the
> required questions first, then show me the plan for my approval. Stop if a
> gate fails. After the first login, run the verification scripts and tell me
> what still needs me.

The agent reads the repository as its instructions — assessment, questions,
plan, install, verification, report. More prompts (upgrade, repair) and the
rules it must follow: [docs/PROMPTS.md](docs/PROMPTS.md).

> **Requirements:** Debian 13 (trixie) or LMDE 7 (gigi), x86_64, `git`,
> `curl`, `gpg`, `python3`, `sudo`, about 10 GB free and a network connection. Ubuntu 24.04-family is supported through
> the source build; see [docs/UBUNTU.md](docs/UBUNTU.md).

---

## What you get

| Surface | Key | What it does |
| --- | --- | --- |
| **Ominty Media** | `Shift+Alt+M` | Playlist launcher — one tab per folder, type to filter, Enter to play |
| **Ominty Dictionary** | `Ctrl+Shift+A` | Offline dictionary and thesaurus for the selected word |
| **Ominty Reader** | `Super+Alt+O` | Read a document aloud (Piper), with a transport panel |
| **Ominty Reader** (clipboard) | `Shift+Alt+S` | Read the clipboard aloud |
| **Ominty Dictation** | `Super+Alt+T` | Speech to text, typed into the focused window (whisper.cpp) |
| **Ominty Capture** | `Ctrl+Alt+R` | OCR — select an area, get the text on the clipboard |
| **Ominty Scripts** | `Super+S` | Script launcher / control panel |
| Interaction explorer | `Super+K` | Browse and run every Ominty action |
| Universal palette | `Super+Space` | Apps **and** actions together |
| Cheat sheet | `Super+Shift+S` | Tabbed keybinding reference |
| AI menu | `Super+A` | Ask AI / open Pi |
| Power menu | `Super+X` | Restart audio/network, reload Niri, power controls |
| Wallpaper carousel | `Super+Ctrl+P` | Browse and apply wallpapers |

Everything is driven by the **action registry** — one source of truth that
generates the Niri keybindings, the DMS launcher, and the cheat sheet. The
canonical name of every surface is in [docs/NAMING.md](docs/NAMING.md).

## How it is put together

| Piece | Where it comes from |
| --- | --- |
| Niri | bundled `.deb` in `packages/` |
| Quickshell | **built from a pinned commit** (`v0.3.1`) — the shell is validated against it |
| DMS (DankMaterialShell) | **built from a pinned commit** with a motion + accent-glow overlay |
| matugen, ghostty | AvengeMedia Open Build Service |
| `ominty` CLI, action registry | [`ominty-core`](https://github.com/MartinKnights/ominty-core) submodule |
| DMS plugins | six shipped here, 14 pinned by commit in `configs/dms/plugins.lock.json` |

DMS is source-built on **both** Debian and Ubuntu families so every machine runs
the identical shell. That is what makes the overlay, the motion tuning and the
settings portable — and why the installer runs a shell smoke test and falls back
rather than leaving a crash loop.

---

## Documentation

**Start here**

- [INSTALL.md](docs/INSTALL.md) — human install guide, post-install checks, updates
- [PROMPTS.md](docs/PROMPTS.md) — copy-paste prompts for an AI agent
- [AGENTS.md](AGENTS.md) — the contract every deploying agent follows

**Runbooks**

- [AGENT-INSTALL.md](docs/AGENT-INSTALL.md) — agent-executable fresh install, with gates
- [AGENT-UPGRADE.md](docs/AGENT-UPGRADE.md) — agent-executable upgrade + friction report
- [MIGRATION.md](docs/MIGRATION.md) — assessing an existing Cinnamon/GNOME desktop

**Reference**

- [NAMING.md](docs/NAMING.md) — the official name of every surface
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — symptom → diagnosis → fix
- [INSPECT.md](docs/INSPECT.md) — every field of `ominty inspect --json`
- [HARDWARE.md](docs/HARDWARE.md) — supported hardware and profiles
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit together
- [UBUNTU.md](docs/UBUNTU.md) — Ubuntu-family support and the source build

**For maintainers**

- [MAINTAINING.md](docs/MAINTAINING.md) — pins, lockfiles, patches, release checklist

---

## Repository layout

```text
Ominty/
├── AGENTS.md                  # contract for a deploying agent
├── install.sh                 # one-command installer (idempotent)
├── configs/                   # deployable configuration
│   ├── niri/                  #   compositor config
│   ├── dms/                   #   shell settings, plugin lock, overlay patch
│   ├── bin/ local-bin/ Scripts/  # helper scripts the keybindings call
│   └── systemd/               #   user units and drop-ins
├── omi-media/                 # Ominty Media (CLI + DMS popup)
├── omi-dictionary/            # Ominty Dictionary (CLI + DMS popup)
├── ominty-plugins/            # shipped plugins + patches for third-party ones
├── scripts/                   # build, verification, diagnostics, rollback
├── packages/                  # prebuilt .debs (niri, xwayland-satellite)
├── profiles/                  # optional hardware profiles
├── docs/                      # guides, runbooks, reference
└── ominty-core/               # CLI, action registry, adapters (submodule)
```

## Project lineage

Ominty is the distribution layer of the **Ominty** project. The implementation
(CLI, action registry, adapters, DMS plugins) lives in the
[`ominty-core`](https://github.com/MartinKnights/ominty-core) submodule; design
documentation and progress logs live in the umbrella repository.
