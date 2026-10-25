# Maintaining Ominty

How the process is wired, and how to change it without breaking the machines it
already runs on. Read this before touching a pin.

## The principle

The live machine is where changes are validated; the repository is what other
machines can reproduce. Anything in the installer must have worked on a real
machine first, and must stay generic — no personal paths, no
machine-specific assumptions.

## The moving parts

| Pin | File | Current | Coupled to |
| --- | --- | --- | --- |
| DMS commit | `scripts/source/dms-build.sh` | `73759d5…` | the embedded shell build (`c27a2bbcb6e09e50`), `dms-shell.patch`, the settings schema |
| `dank-qml-common` | DMS submodule | `fc42c68…` | the shell build id |
| Quickshell | `scripts/source/quickshell-build.sh` | `v0.3.1` | whether the pinned DMS shell loads at all |
| whisper.cpp | `scripts/source/whisper-build.sh` | `v1.9.5` | the model filename |
| third-party plugins | `configs/dms/plugins.lock.json` | 14 commits | `ominty-plugins/patches/*` |

The installer reports DMS as `ominty-pinned+<short-sha>`; the shell build id is
the value in `core/internal/shellembed/dist/.dankrev`.

## Bumping DMS

1. Pick the commit. Check the shell layout first: the overlay patch targets
   `DankCommon/…`. A build using `DCommon/…` is a different generation and will
   not patch.
2. Set `OMINTY_DMS_REF` in `scripts/source/dms-build.sh`.
3. Build and record the new shell id:

   ```sh
   scripts/source/dms-build.sh
   cat ~/.cache/ominty/build/DankMaterialShell/core/internal/shellembed/dist/.dankrev
   ```

4. Re-apply the overlay **by intent** to the new tree, then regenerate
   `configs/dms/shell-overlay/dms-shell.patch`:

   ```sh
   cp -a <dist> /tmp/new-shell
   # edit /tmp/new-shell, then:
   diff -ruN <dist> /tmp/new-shell > configs/dms/shell-overlay/dms-shell.patch
   ```

5. Update every place that names the old build id:
   `configs/dms/shell-overlay/README.md`, `docs/INSTALL.md`,
   `docs/AGENT-INSTALL.md` (expected values), and the `OMINTY_EXPECTED_BASE`
   default in `scripts/verify-upgrade.sh`.
6. Verify:

   ```sh
   configs/dms/shell-overlay/apply.sh --check <dist>   # 0
   ./install.sh
   scripts/smoke-dms.sh
   scripts/verify-parity.py
   ```

7. Test on both a Debian and an Ubuntu machine before merging. The shell must
   load on the Quickshell pin you ship.

**What a DMS bump can break:** the overlay patch (always), the settings schema
(compare key counts), plugin component APIs, and the shell's Qt baseline.

## Bumping Quickshell

The pinned DMS shell was validated against Quickshell **0.3.1**. Debian 13 ships
0.3.0, on which it segfaults in `QQmlTypeLoader` — that is why Quickshell is
source-built at all.

1. Set `OMINTY_QUICKSHELL_REF` in `scripts/source/quickshell-build.sh`.
2. Rebuild and smoke-test:

   ```sh
   scripts/source/quickshell-build.sh
   scripts/smoke-dms.sh --restart
   ```

3. If it fails, run the matrix on a machine with both versions available:
   `scripts/diagnose-dms-shell.sh --quickshell <path>`.
4. Update `docs/INSTALL.md`, `docs/UBUNTU.md` and `docs/AGENT-INSTALL.md` if the
   version in prose changes.

Never bump Quickshell and DMS in the same step; if the shell fails you will not
know which one caused it.

## Regenerating the plugin lock

`configs/dms/plugins.lock.json` pins third-party plugins by exact commit so a new
machine gets what was tested, not today's HEAD.

```sh
dms plugins lock -o /tmp/plugins.lock.json
```

Then **curate**: keep only plugins that are portable and safe to ship.

- Exclude operator-managed local builds (currently `aiOverviewControl`,
  `dankSoftwareDepot`, `mailReader`). On a machine that has them,
  `dms plugins lock` refuses with *"operator-managed plugin … use reviewed
  control deployment"* — that is expected; build the file from the remaining
  entries.
- Ominty's own plugins are **not** in the lock; they are symlinked from this
  repository.

Test before committing:

```sh
dms plugins restore configs/dms/plugins.lock.json   # no --prune
scripts/apply-plugin-patches.sh
```

## Adding a plugin patch

Some upstream plugins need a small local fix (the known one is DankChat's Qt 6.8
context menus). Patches are preferred over forks: they are attributable and
track upstream.

1. Patch the installed plugin, then export the diff:

   ```sh
   diff -u <upstream>/File.qml <installed>/File.qml \
     > ominty-plugins/patches/<pluginId>-<purpose>.patch
   ```

   Fix the paths so the patch applies with `-p1` from the plugin directory
   (`a/File.qml`, `b/File.qml`).

2. Confirm both directions:

   ```sh
   scripts/apply-plugin-patches.sh --check     # 0 when applied
   scripts/apply-plugin-patches.sh             # applies when missing
   ```

3. `install.sh` re-applies patches after every plugin restore, so no further
   wiring is needed. When `dms plugins update` moves the plugin, the patch will
   stop applying — regenerate it against the new version and bump the commit in
   the lockfile.

## Changing the layer manifest

Layers live in `ominty-core/cli/omintylib/inspect.py`; `install.sh` reads them
and must not keep its own list. When adding a package:

- use `binary=` when users may install it outside apt (`batcat|bat`,
  `fdfind|fd`, `zellij`);
- keep package names unique across layers (there is a test for it);
- mark genuinely optional features with `optional=True` so they warn, never
  block;
- if the package name does not exist for this release, `apt_install_resilient`
  skips it and reports — do not add it to a required layer unless it exists.

## The bootstrap uses a sparse checkout

`bootstrap.sh` clones with `--filter=blob:none` and a cone sparse checkout that
**excludes `packages/`**, because the 21 MB of `.deb`s are fetched separately
(curl or a local copy). Consequences for a maintainer:

- `packages/*.deb` will not be in the working tree of a bootstrapped clone.
  Fetch them with `git sparse-checkout add packages`.
- Bumping a `.deb` means: replace the file, update its name in `bootstrap.sh`
  (the download list is explicit), and push. Keep the filenames versioned.
- The `.debs` are deliberately not in the git download path: a single 19 MB
  promisor fetch is all-or-nothing and dies on slow links.

## Documentation drift

```sh
scripts/check-docs.sh
```

It fails when a doc claims something the code contradicts (stale names, OBS
`dms`, "four categories", `support_level: experimental`), references a script
that does not exist, links to a missing document, or when the runbooks disagree
on the verification commands. Run it before every push.

## Pre-push checklist

```sh
( cd ominty-core && python3 -m pytest -q )        # 300+ tests
( cd omi-media   && python3 -m pytest -q )        # discovery, CLI, sort
./ominty-core/cli/ominty registry validate        # 0 errors
niri validate                                     # config is valid
./install.sh --dry-run                            # plans, exits 0
scripts/apply-plugin-patches.sh --check           # all applied
scripts/smoke-dms.sh                              # shell stable
scripts/verify-upgrade.sh                         # plumbing
scripts/verify-parity.py                          # function
scripts/check-docs.sh                             # docs match code
git status --short                                # only intended changes
```

`verify-parity.py` can report failures on a development machine whose live
config differs from the shipped template (for example operator-managed plugins
in `plugin_settings.json`). That is local state, not a code defect — check the
finding rather than "fixing" the manifest.

## Release notes

There is no version file. A release is the `main` branch at a commit where the
checklist above passes on both a Debian 13 and an Ubuntu 24.04 machine. Record
the DMS/Quickshell pins and the shell build id in the commit message when they
change — that is what the agent runbooks quote.
