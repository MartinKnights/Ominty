# Migrating from Cinnamon to Niri

Ominty's desktop layer is Niri, but most users arrive from Linux Mint's
Cinnamon (X11). Almost everything survives the change, but several Cinnamon
assumptions do not hold under Niri — and they fail **silently**. No error is
printed; the feature simply does not appear. This document records what has to
be carried across, and the traps that cost us time.

Validated on a Dell Precision T7910 running Linux Mint 22.3 (Ubuntu family),
Niri 26.04 and DMS/Quickshell 0.3.1. Ubuntu-family systems are an
**experimental** target (see [UBUNTU.md](UBUNTU.md)); the same migration applies
to LMDE 7.

> The migration rule is the same as the installation rule: **infer, then
> confirm.** Detect what the user has in Cinnamon, propose the Niri equivalent,
> and never overwrite user configuration without a
> `.bak-ominty-<timestamp>` backup.

---

## 1. Niri does not run XDG autostart

Cinnamon starts `~/.config/autostart/*.desktop` at login. **Niri does not read
XDG autostart at all.** Anything the user expects to be running is simply
absent, and the common symptom is *"my tray icon is missing"* — when the real
problem is that the app never started.

The reference machine had eleven entries. Each needs an explicit decision:

| Entry | Migration |
| --- | --- |
| `piper-daemon`, `piper-indicator` | → `spawn-at-startup` (see §6) |
| `vorta`, `mullvad-vpn` | → `spawn-at-startup` + floating window rules (see §3) |
| `kdeconnect` | → `spawn-at-startup "kdeconnectd"`; DMS has a native plugin |
| `ulauncher` | started, but its tray icon was disabled (see §3) |
| `artha`, `Handy`, `blueman`, `lm-studio`, `remmina-applet` | user decides |

Port each one you keep as a line in `~/.config/niri/config.kdl`:

```kdl
spawn-at-startup "vorta" "--daemonize"
spawn-at-startup "/opt/Mullvad VPN/mullvad-vpn"
spawn-at-startup "mintupdate"
```

Anything started this way inherits Niri's environment (including
`WAYLAND_DISPLAY` and the session D-Bus), which matters for §6.

---

## 2. The tray protocol is different

Cinnamon's panel tray speaks the classic **XEmbed** protocol. Niri has **no
tray of its own** — the tray in an Ominty session is DMS's `systemTray` bar
widget, which is a Quickshell **StatusNotifierItem (SNI)** host. An icon only
survives if the app speaks SNI.

| App | Protocol it registers | Appears in the DMS tray? |
| --- | --- | --- |
| Piper TTS indicator | libayatana (`org/ayatana/NotificationItem/…`) | yes |
| Remmina | libayatana | yes |
| Handy | libayatana (icon path) | yes |
| **Vorta** | Qt (`org.kde.StatusNotifierItem-<pid>-1`) | **no** |
| **KeePassXC** | Qt | **no** |
| **Mullvad VPN** | Qt | **no** |
| **Update Manager** | XApp (`XApp.StatusIcon`) | **no** |

The Qt-style regressions are a **Quickshell 0.3.1 limitation**, not a
configuration error. Quickshell receives the registration but fails to load the
item:

```text
WARN quickshell.service.sni.item: Failed to load tray item "org.kde.StatusNotifierItem-…"
WARN quickshell.service.sni.item: Unable to create pixmap for tray icon
```

Notably, libayatana items register with an object path on a unique connection
(`:1.x/org/ayatana/…`), while Qt items register a well-known bus name plus
`/StatusNotifierItem`; it is the latter form Quickshell mishandles. There is
nothing to configure around this — it is a fix in Quickshell, or in DMS's
`trayrecovery` service (`core/internal/server/trayrecovery/`), which already
scans D-Bus for unregistered SNI items but only runs at boot.

**Mitigation until it is fixed:** float these apps' windows and treat the
window as the UI. See §3.

---

## 3. Windows that cannot be minimised

Niri is a tiling compositor and has **no minimise**. For tray apps the usual
escape hatch is *close-to-tray*, which requires a working tray icon — so the
apps in §2 have no way to hide. Give them floating window rules instead:

```kdl
window-rule {
    match app-id=r#"^vorta$"#
    match app-id=r#"^Vorta$"#
    match app-id=r#"^com\.borgbase\.Vorta$"#
    open-floating true
}
window-rule {
    match app-id=r#"^mullvad-vpn$"#
    open-floating true
}
```

They then overlay the tiled columns instead of taking one. Both apps are
daemons, so **closing the window leaves the app running** — that is the closest
thing to "minimise" until the tray works.

Get an app's real `app-id` from a live window, not from the desktop file:

```sh
niri msg --json windows | jq '.[] | {app_id, title}'
```

Ulauncher is the opposite case: it *does* appear (SNI), but its tray icon is
unwanted. Disable it in `~/.config/ulauncher/settings.json`:

```json
"show-indicator-icon": false
```

---

## 4. Keyboard shortcuts live in two different systems

Cinnamon stores shortcuts in dconf (`/org/cinnamon/desktop/keybindings/`).
Niri reads only its own `binds { }` block. **Niri never reads dconf**, so every
script shortcut silently disappears unless it is re-declared.

The reference machine had four custom bindings; all four now exist in both
sessions:

| Cinnamon name | Chord | Command |
| --- | --- | --- |
| Script Command Centre | `Super+S` | `/home/martin/Scripts/script_command_centre.sh` |
| Read Selection | `Ctrl+Alt+S` | `/home/martin/bin/read-selection` |
| Artha Dictionary | `Ctrl+Alt+A` | `/usr/bin/artha` |
| Screen OCR | `Ctrl+Alt+R` | `/home/martin/.local/bin/screen-ocr` |

```kdl
binds {
    Mod+S       { spawn "/home/martin/Scripts/script_command_centre.sh"; }
    Ctrl+Alt+S  { spawn "/home/martin/bin/read-selection"; }
    Ctrl+Alt+A  { spawn "/usr/bin/artha"; }
    Ctrl+Alt+R  { spawn "/home/martin/.local/bin/screen-ocr"; }
}
```

Put these in the **user-owned** part of `config.kdl`, not in the DMS or
Ominty-generated fragments — those are regenerated and would drop them.

Check for collisions before adding: a chord already used by DMS will win.
`Super+S` moved off Cinnamon's `<Shift><Super>p`, which clashed with DMS's
`Mod+Shift+P` (power-off-monitors).

---

## 5. Clipboard, screenshots and PRIMARY selection

X11 has a **PRIMARY selection** (the "select to speak" buffer). Wayland does
not expose it generally, so scripts that read it must fall back to the regular
clipboard.

`clip-tool` dispatches on the session, so callers stay unchanged:

| Session | Clipboard |
| --- | --- |
| X11 (Cinnamon) | `xclip`, then `xsel` |
| Wayland (Niri) | `wl-copy` / `wl-paste` |

Two consequences when porting Cinnamon scripts:

- **`read-selection`** (TTS) reads the primary selection. Under Wayland this
  degrades to the regular clipboard — it still works, but the user must copy
  before invoking it.
- **`screen-ocr`** uses `grim` + `slurp` on Wayland and `gnome-screenshot` on
  X11. `slurp` performs an interactive area selection, so it can only be tested
  from inside the session.
- **Artha** (`Ctrl+Alt+A`) opens but cannot receive the selected word under
  Wayland, because there is no PRIMARY selection to read.

---

## 6. Screen locking, idle and suspend

Cinnamon brings its own lock screen. Niri does not, so the session needs
`swayidle` (idle/suspend) and `swaylock` (the locker), driven from
`~/.config/swaylock/config`.

Two traps:

- **`swayidle` needs `WAYLAND_DISPLAY`.** A systemd user unit does not inherit
  it, so start `swayidle` through a small wrapper that imports the session
  environment first, and start it from `config.kdl` rather than enabling the
  unit globally — otherwise it also runs under Cinnamon, which already locks.
- **Rebind the lock shortcut.** DMS ships a `Mod+Alt+L` binding that calls the
  DMS lock; point it at `swaylock` (or remove it) so both sessions lock the
  same way.

---

## 7. Single-instance daemons

Switching between Cinnamon and Niri can leave an old session's process alive.
For TTS this is user-visible — two daemons both consume the queue and the text
is spoken twice. Guard any long-running helper with a lock that is released on
exit:

```sh
LOCK_FILE="/tmp/piper_daemon.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0     # another instance already holds it
```

`flock` releases automatically when the process dies, so the next session takes
over cleanly without manual cleanup.

---

## 8. Verifying the migration

Connector names and geometry are **identical** between the X11 and Niri
sessions on the reference machine, so the output layout does not need
translating. Confirm it from inside Niri:

```sh
niri msg --json outputs                     # keys are the connector names
niri validate -c ~/.config/niri/config.kdl  # must report a valid config
```

`ominty-core/cli/ominty inspect` re-runs the audit; the session check inside it
is only meaningful from inside Niri. Then confirm by hand in the running
session:

- the ported `spawn-at-startup` apps are running;
- each script shortcut responds;
- the clipboard helper round-trips (`clip-tool copy` then `clip-tool paste`);
- `swayidle` locks the screen after the idle timeout, and on suspend.

---

## 9. Known limitations

- **Qt-style SNI tray icons do not appear** (Vorta, KeePassXC, Mullvad, Update
  Manager). Quickshell 0.3.1 cannot load them; a fix belongs in Quickshell or in
  DMS's `trayrecovery` service. Until then those apps run without a tray icon.
- **No minimise.** Tray apps cannot hide without a working tray icon; use
  floating window rules and close-to-background (§3).
- **No PRIMARY selection** under Wayland, so "select then act" tools lose the
  selection; they must be reworked to read the regular clipboard.
