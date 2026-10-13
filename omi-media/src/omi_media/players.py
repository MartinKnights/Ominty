"""Player launching (Omi Media Launcher spec §11).

The selector hands the chosen playlist to a **separate player application**
(per-category ``player``, e.g. ``vlc``) and then gets out of the way.

One player at a time: the PID of the player we started is recorded, and the
next launch stops it first — so choosing a new playlist replaces what is
playing instead of layering audio on top of it.  ``omi-media stop`` stops it
too.  Players that speak MPRIS (VLC does) then surface their controls in the
desktop's media widget.
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import time
from pathlib import Path

PID_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "omi-media.pid"


def build_command(spec: dict, playlist_path: str) -> list[str]:
    player = spec.get("player") or "vlc"
    args = list(spec.get("player_args") or [])
    return [player, *args, playlist_path]


def _read_pid() -> int | None:
    try:
        return int(PID_FILE.read_text().strip())
    except Exception:
        return None


def stop(dry_run: bool = False) -> dict:
    """Stop the player that omi-media previously started, if any."""
    pid = _read_pid()
    if pid is None:
        return {"status": "idle"}
    if dry_run:
        return {"status": "would_stop", "pid": pid}
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        PID_FILE.unlink(missing_ok=True)
        return {"status": "idle"}
    for _ in range(20):  # up to 2s to exit politely
        time.sleep(0.1)
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
    else:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    PID_FILE.unlink(missing_ok=True)
    return {"status": "stopped", "pid": pid}


def launch(spec: dict, playlist_path: str, dry_run: bool = False) -> dict:
    """Stop any previous player, then launch the configured player on a playlist."""
    cmd = build_command(spec, playlist_path)
    if dry_run:
        return {
            "status": "dry_run",
            "command": cmd,
            "resolved_player": shutil.which(cmd[0]),
        }
    if not shutil.which(cmd[0]):
        return {
            "status": "error",
            "error": f"player not found: {cmd[0]}",
            "command": cmd,
            "playlist": playlist_path,
        }
    stop()
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    PID_FILE.write_text(str(proc.pid))
    return {"status": "launched", "command": cmd, "playlist": playlist_path, "pid": proc.pid}