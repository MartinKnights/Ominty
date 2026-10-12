"""Player launching (Omi Media Launcher spec §11).

Each category carries its own configured ``player`` (e.g. ``vlc`` or
``mpv``) plus optional ``player_args``.  The launcher always hands the
playlist **file** to the player — the m3u itself lists the media.

Defaults: Video/Courses → VLC; Music/Audio → mpv.  All per-category
configurable in ~/.config/omi/media.toml.
"""

from __future__ import annotations

import shutil
import subprocess


def build_command(spec: dict, playlist_path: str) -> list[str]:
    player = (spec.get("player") or "vlc")
    args = list(spec.get("player_args") or [])
    return [player, *args, playlist_path]


def launch(spec: dict, playlist_path: str, dry_run: bool = False) -> dict:
    """Launch the configured player on a playlist file.

    Returns a result dict; in dry-run mode nothing is spawned.
    """
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
    subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return {"status": "launched", "command": cmd, "playlist": playlist_path}