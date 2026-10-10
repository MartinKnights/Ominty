"""Imported dictionaries list (Phase 2 registry replaces this).

Calling `omi-dict dictionaries` in a clean environment must not crash and
must report nothing installed (spec §5).
"""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "omi-dict"


def test_dictionaries_empty(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "cfg"))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    out = subprocess.run(
        [str(BIN), "dictionaries"], capture_output=True, text=True
    )
    assert out.returncode == 0
    assert "No dictionaries" in out.stdout


def test_version():
    out = subprocess.run(
        [str(BIN), "-V"], capture_output=True, text=True
    )
    assert out.returncode == 0
    assert "omi-dict" in out.stdout