# Ominty

**A keyboard-first, action-driven Wayland desktop for Debian-based systems.**

Ominty packages the Ominty Phase 1 reference implementation — built and
validated on LMDE 7 (Debian 13) — into a one-command installer for other
Debian-based machines. It brings together:

- **Niri** — the scrollable-tiling Wayland compositor (prebuilt `.deb`)
- **DankMaterialShell (DMS)** — the Quickshell-based desktop shell
- **Ominty** — the action registry, CLI, and adapters that make the desktop
  discoverable and AI-native
- **matugen** — wallpaper-driven dynamic theming
- A complete, working configuration set (Niri + DMS + Ominty)

## Quick start

```sh
git clone --recurse-submodules https://github.com/MartinKnights/Ominty.git
cd Ominty
./install.sh
```

Log out, select the **Niri** session at the display manager, and you're in.

> Requires **Debian 13 (Trixie)** or **LMDE 7**. Needs `sudo`, plus `curl` and
> `gpg` for the third-party signing keys. See
> [docs/INSTALL.md](docs/INSTALL.md) for the full guide.
>
> **Already running Ominty?** Don't reinstall blind — follow
> [docs/AGENT-UPGRADE.md](docs/AGENT-UPGRADE.md), which is written to be
> executed by an agent and produces a friction report.

## Third-party packages

`matugen` and `ghostty` are not in Debian — they come from AvengeMedia's Open
Build Service, and the installer adds that repository and its signing key
automatically.

`dms` is **built from a pinned source commit** (`scripts/source/dms-build.sh`),
not taken from OBS. The motion/glow overlay in `configs/dms/shell-overlay` is
coupled to the embedded shell tree, and the OBS package has moved to a newer,
incompatible generation. Building one pinned commit keeps every machine on the
same shell, so the overlay applies identically on Debian and Ubuntu families.

`quickshell` comes from Debian's `trixie-backports`; the installer pins it there
because the OBS copy is deprecated and would otherwise be preferred by version.

## What you get

| Surface | Key | What it does |
|---|---|---|
| Interaction explorer | `Super+K` | Browse and run every Ominty action |
| Universal palette | `Super+Space` | Apps **and** actions together |
| Cheat sheet | `Super+Shift+S` | Tabbed keybinding reference (GKS) |
| AI menu | `Super+A` | Ask AI / open Pi |
| Power menu | `Super+X` | Restart audio/network, reload Niri, power controls |
| Wallpaper carousel | `Super+Ctrl+P` | Browse and apply wallpapers |

Everything is driven by the **action registry** — one source of truth that
generates the Niri keybindings, the DMS launcher, and the cheat sheet.

## Repository layout

```
Ominty/
├── install.sh                  # one-command installer (idempotent)
├── configs/                    # deployable configurations
│   ├── niri/                   #   compositor config + DMS fragments
│   ├── dms/                    #   shell settings + plugin settings
│   └── ominty/                #   action registry config (roles, AI)
├── packages/                   # prebuilt .debs (niri, xwayland-satellite)
├── profiles/                   # optional hardware profiles
│   └── surface-book-1/         #   reference hardware extras
├── docs/                       # INSTALL, HARDWARE, TROUBLESHOOTING, ARCHITECTURE
└── ominty-core/               # the implementation (git submodule)
```

## Documentation

- [INSTALL.md](docs/INSTALL.md) — step-by-step install, post-install checks, AI setup
- [AGENT-UPGRADE.md](docs/AGENT-UPGRADE.md) — agent-executable upgrade runbook + friction report
- [NAMING.md](docs/NAMING.md) — the official name of every Ominty surface
- [HARDWARE.md](docs/HARDWARE.md) — supported hardware, profiles, known devices
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — common problems and fixes
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit together

## Project lineage

Ominty is the distribution layer of the **Ominty** project. The
implementation (CLI, action registry, adapters, DMS plugins) lives in the
[`ominty-core`](https://github.com/MartinKnights/ominty-core) submodule; the design
documentation and progress log live in the umbrella `Ominty` repository.
A Void Linux port is planned (see the `Ominty-install` project).