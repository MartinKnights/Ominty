# Ubuntu-family support (source build)

Ominty is **validated on LMDE 7 / Debian 13**. Ubuntu-family systems (Ubuntu,
and Linux Mint built on Ubuntu) are **supported through a source-build path**;
`noble` (Ubuntu 24.04 / Mint 22.x) is the validated base, and other Ubuntu
codenames are installable but reported as unvalidated. This document is the
support matrix and the runbook.

> The full migration strategy, including the two-machine process, lives in
> `Ominty-Migration-Planning.md` (kept with the owner). This file is the
> repo-side summary.

## Support matrix

| Family | Detection (`ID`/`ID_LIKE`) | Desktop source | Support level |
| --- | --- | --- | --- |
| `debian` | `ID=debian` | apt + OBS (Debian 13) | validated |
| `mint-debian` | `ID=linuxmint`, `ID_LIKE=debian` (LMDE) | apt + OBS (Debian 13) | validated |
| `ubuntu` | `ID=ubuntu` | source build | supported (`noble`); other bases unvalidated |
| `mint-ubuntu` | `ID=linuxmint`, `ID_LIKE="ubuntu debian"` (Mint 22.x) | source build | supported (`noble`); other bases unvalidated |
| `void` | `ID=void` | — | reserved |

`ominty inspect` reports this as `platform.family`, `platform.support_level`,
`platform.ubuntu_codename` and `platform.desktop_source`. `is_lmde` is true
only for `mint-debian`; Ubuntu-based Mint is `mint-ubuntu`.

## Why Ubuntu needs a source build

| Component | Debian 13 / LMDE 7 | Ubuntu-family |
| --- | --- | --- |
| `quickshell` | Debian `trixie-backports` | **built from source** — needs Qt ≥ 6.6 (Ubuntu 24.04 ships 6.4.2) |
| `dms` | **built from source** (pinned commit) | **built from source** (the same pinned commit) |
| `matugen` | AvengeMedia OBS | **built from source** (Rust/cargo) |
| `ghostty` | AvengeMedia OBS | not installed by default (alacritty is) |
| `niri` | bundled `.deb` | bundled `.deb`, **plus undeclared runtime deps** |

DMS is source-built on **both** families, not just Ubuntu. The motion/glow
overlay is coupled to the embedded shell tree, and the OBS `dms` package has
moved to a newer shell generation with a different QML layout. Pinning one
commit (`scripts/source/dms-build.sh`) keeps the desktop identical on every
machine and keeps the overlay applicable.

The AvengeMedia Launchpad PPA (`ppa:avengemedia/danklinux`, `…/dms`) is Ubuntu
25.10 / 26.04+ only — it has no `noble` (24.04) builds — so Mint 22.x cannot use
it. `platform.desktop_source` reflects what is actually installed: `source`
when DMS came from the pinned build (the current path on both families), `ppa`
or `obs` for an older package-based install, and `none` when DMS is absent.

### niri `.deb` gaps on Ubuntu

`packages/niri_*.deb` declares only `alacritty, fuzzel` as dependencies, but on
Ubuntu 24.04 it also needs:

- `libseat1` (apt), and
- `libdisplay-info.so.2` — Debian soname 2, while Ubuntu 24.04 ships only
  soname 1. The installer builds **libdisplay-info 0.2.0** and installs it to
  `/usr/local`.

Without these, `niri` installs but dies at runtime with `libseat.so.1` /
`libdisplay-info.so.2` not found, which also breaks `ominty registry build`.

## Runbook

`install.sh` detects the family and, for `ubuntu`/`mint-ubuntu`, runs:

```sh
scripts/ubuntu/ubuntu-deps.sh    # sudo boundary: build deps, niri .debs, libseat1, libdisplay-info 2
scripts/ubuntu/ubuntu-build.sh   # user space: Qt (aqtinstall) -> Quickshell -> DMS (shared pin) -> matugen
```

then continues with the shared steps (deploy configs, `ominty` CLI symlinks,
`registry build`, DMS plugins, `dms.service`, validation).

Apply with the usual dry run first:

```sh
./install.sh --dry-run --layers "desktop tts terminal editor cli browser"
./install.sh --layers "desktop tts terminal editor cli browser"
```

The scripts are also runnable on their own and are idempotent. Versions and
locations are overridable by environment variable:

| Variable | Default |
| --- | --- |
| `OMINTY_QT_VERSION` | `6.8.3` |
| `OMINTY_GO_VERSION` | `1.26.8` |
| `OMINTY_LIBDISPLAY_VERSION` | `0.2.0` |
| `OMINTY_PREFIX` | `~/.local` |
| `OMINTY_BUILD_DIR` | `~/.cache/ominty/build` |

### Desktop shell overlay and the systemd drop-in

`install.sh` writes a full `dms.service` user unit on **both** families (on
Debian/LMDE it overrides the packaged unit of the same name). The motion +
accent-glow overlay is delivered through
`~/.config/systemd/user/dms.service.d/ominty-shell.conf`, which sets
`DMS_SHELL_DIR`. The drop-in is written only after
`configs/dms/shell-overlay/apply.sh --check` confirms the patch matches the
built shell. A mismatched build leaves the stock shell running and removes any
stale drop-in.

Because `install.sh` builds DMS itself, the pristine tree is already at
`~/.cache/ominty/build/DankMaterialShell/core/internal/shellembed/dist`, so the
overlay is applied during the install — no first-login step is needed. If you
build DMS outside the installer, run:

```sh
configs/dms/shell-overlay/apply.sh
systemctl --user daemon-reload && systemctl --user restart dms.service
```

Source-built DMS embeds a build id; `ominty inspect` reports it under
`desktop.shell_overlay.base`. Re-run `apply.sh` after every DMS rebuild.

## Known limitations

- The layer manifest in `ominty-core` (`cli/omintylib/inspect.py`) marks
  source-built packages (`quickshell`, `dms`, `matugen`) with `binary=` names,
  so `ominty inspect` resolves them from `PATH`/`~/.local/bin` and reports
  `"source": "build"` instead of claiming they are missing. `dpkg` still does
  not know about them, so tools outside Ominty will not see a package version.
- `ominty` still targets the Debian-first layer set; some optional layer
  packages (e.g. `ghostty`, `firefox-esr`) do not exist on Ubuntu-family and are
  skipped.
- The bundled `niri` `.deb` should eventually be built per distro family (or its
  `Depends` completed) so the `libseat1` / `libdisplay-info` workaround is no
  longer needed.

## Lessons learned (Ubuntu-based Mint)

- Build the Qt rpath **into** the installed Quickshell
  (`-DCMAKE_INSTALL_RPATH=<Qt>/lib`), otherwise the installed binary picks up
  the system Qt 6.4.2 and fails with ABI warnings.
- Install libdisplay-info by **staging** (`meson install --destdir`) and copying
  as root; running `meson` itself under `sudo` resolves a different meson and
  fails to read `install.dat`.
- `apt-get update` can return non-zero because of an unrelated broken PPA; the
  dependency script tolerates that.
- The DMS runtime must acquire `org.freedesktop.Notifications`; the installer
  writes a user `dms.service` that sets `PATH` to include `~/.local/bin` and
  `OMINTY_CLI`, and the overlay drop-in (see above) sets `DMS_SHELL_DIR`.
