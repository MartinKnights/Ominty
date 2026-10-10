"""Selected-text acquisition (spec §12, Phase 5; docs/wayland-selection.md).

A standalone component so future text actions reuse it.  Session-aware:

1. PRIMARY selection (rarely populated under Niri) with clipboard fallback.
2. When both are empty: controlled copy — preserve → ``Ctrl+C`` via
   ``wtype`` (Wayland) / ``xdotool`` (X11) → read → **restore** the
   clipboard so a dictionary lookup never visibly changes it.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import time

from .errors import SelectionUnavailable


def use_wayland() -> bool:
    return bool(os.environ.get("WAYLAND_DISPLAY"))


def _run(cmd: list[str], timeout: float = 2.0) -> str:
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return proc.stdout


def _read_primary() -> str:
    if use_wayland() and shutil.which("wl-paste"):
        return _run(["wl-paste", "--primary"]).strip()
    if not use_wayland():
        for tool in ("xclip", "xsel"):
            if shutil.which(tool):
                cmd = [tool, "-o", "-selection", "primary"] if tool == "xclip" else [tool, "-o", "-p"]
                return _run(cmd).strip()
    return ""


def _read_clipboard() -> str:
    if use_wayland() and shutil.which("wl-paste"):
        return _run(["wl-paste"]).strip()
    if not use_wayland():
        for tool in ("xclip", "xsel"):
            if shutil.which(tool):
                cmd = [tool, "-o", "-selection", "clipboard"] if tool == "xclip" else [tool, "-o", "-b"]
                return _run(cmd).strip()
    return ""


def _write_clipboard(text: str) -> None:
    if use_wayland() and shutil.which("wl-copy"):
        subprocess.run(["wl-copy"], input=text.encode("utf-8"), timeout=2)
    elif not use_wayland():
        for tool in ("xclip", "xsel"):
            if shutil.which(tool):
                cmd = [tool, "-selection", "clipboard"] if tool == "xclip" else [tool, "-b"]
                subprocess.run(cmd, input=text.encode("utf-8"), timeout=2)
                break


def _send_copy() -> bool:
    """Press Ctrl+C on the focused app (returns whether we could send it)."""
    if use_wayland():
        cmd = ["wtype", "-M", "ctrl", "-k", "c", "-m", "ctrl"]
    else:
        cmd = ["xdotool", "key", "ctrl+c"]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=2)
        return proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def selected_text(allow_copy_fallback: bool = True) -> str:
    """Return the currently selected text, or raise SelectionUnavailable.

    Order (spec §12): PRIMARY if populated (non-destructive); otherwise the
    controlled-copy technique — preserve the clipboard, send Ctrl+C, read,
    **restore** the clipboard — so a lookup never visibly changes it.
    """
    text = _read_primary()
    if text:
        return text.strip()

    preserved = _read_clipboard()
    try:
        if not _send_copy():
            text = preserved  # could not copy: plain clipboard is the best guess
            if not text:
                raise SelectionUnavailable(
                    "Unable to obtain selected text (no PRIMARY, copy not available)"
                )
            return text.strip()
        time.sleep(0.25)  # allow the app to update the clipboard
        text = _read_clipboard()
    finally:
        # Restore whatever the user had copied (spec §12).
        try:
            _write_clipboard(preserved)
        except Exception:  # noqa: BLE001 — restore must never break the flow
            pass
    if not text:
        raise SelectionUnavailable(
            "Unable to obtain selected text (no PRIMARY selection and no copy result)"
        )
    return text.strip()