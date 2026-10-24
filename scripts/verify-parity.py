#!/usr/bin/env python3
"""Ominty — is the desktop actually functional, not just installed?

verify-upgrade.sh checks plumbing (unit, overlay, files). This checks the
things a user notices: does every registered action have the program it
needs, does every configured plugin exist, does every generated keybinding
point at something real, and are the TTS/STT/dictionary/media stacks complete?

It is read-only and needs no sudo.

Usage:
    scripts/verify-parity.py [--json]

Exit: 0 when nothing failed, 1 otherwise.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ACTIONS = REPO / "ominty-core" / "actions"
CONFIG_HOME = Path.home() / ".config"
DMS_CONFIG = CONFIG_HOME / "DankMaterialShell"
PLUGIN_DIR = DMS_CONFIG / "plugins"
GENERATED_BINDINGS = CONFIG_HOME / "ominty" / "generated" / "niri" / "bindings.kdl"
PATCH_DIR = REPO / "ominty-plugins" / "patches"

OMINTY_PLUGINS = {
    "omintyActions": "ominty-core/shell/dms/ominty-actions",
    "omintyKeybinds": "ominty-core/shell/dms/ominty-keybinds",
    "omintyMedia": "omi-media/integrations/dms/omintyMedia",
    "omintyDictionary": "omi-dictionary/integrations/dms/ominty-dictionary",
    "omintyDownload": "ominty-plugins/omintyDownload",
    "omintyOllama": "ominty-plugins/omintyOllama",
}

results: list[tuple[str, str, str]] = []   # (status, label, detail)
PATH = os.environ.get("PATH", "")
for extra in (Path.home() / ".local/bin", Path.home() / "bin"):
    PATH = f"{extra}:{PATH}"


def ok(label: str, detail: str = "") -> None:
    results.append(("PASS", label, detail))


def bad(label: str, detail: str = "") -> None:
    results.append(("FAIL", label, detail))


def skip(label: str, detail: str = "") -> None:
    results.append(("SKIP", label, detail))


def have(binary: str) -> str | None:
    return shutil.which(binary, path=PATH)


def section(name: str) -> None:
    results.append(("", name, ""))


def check_actions() -> None:
    section("Action requirements")
    if not ACTIONS.is_dir():
        bad("action registry", f"{ACTIONS} is missing")
        return
    seen = 0
    for toml_file in sorted(ACTIONS.glob("*.toml")):
        try:
            data = tomllib.loads(toml_file.read_text())
        except Exception as exc:  # noqa: BLE001
            bad(f"{toml_file.name} parses", str(exc))
            continue
        for action_id, action in data.get("action", {}).items():
            for req in action.get("requires", []):
                seen += 1
                if have(req):
                    ok(f"{action_id} needs {req}")
                else:
                    bad(f"{action_id} needs {req}", "not found on PATH")
    if seen == 0:
        skip("no action requirements declared")


def check_plugins() -> None:
    section("DMS plugins")
    for name, rel in OMINTY_PLUGINS.items():
        target = REPO / rel
        if not (target / "plugin.json").is_file():
            bad(f"{name} exists in the repo", f"{rel}/plugin.json")
        elif (PLUGIN_DIR / name).exists():
            ok(f"{name} is installed")
        else:
            bad(f"{name} is installed", "missing from the DMS plugins directory")

    settings = DMS_CONFIG / "plugin_settings.json"
    if settings.is_file():
        try:
            configured = set(json.loads(settings.read_text()))
        except Exception as exc:  # noqa: BLE001
            bad("plugin_settings.json parses", str(exc))
            configured = set()
        missing = sorted(p for p in configured if not (PLUGIN_DIR / p).exists())
        if missing:
            bad("configured plugins are installed", ", ".join(missing))
        else:
            ok(f"all {len(configured)} configured plugins are installed")


def check_patches() -> None:
    """Third-party plugins need local patches that dms plugins restore resets."""
    section("Plugin patches")
    if not PATCH_DIR.is_dir():
        skip("no patches directory")
        return
    for patch_file in sorted(PATCH_DIR.glob("*.patch")):
        plugin = patch_file.name.split("-")[0]
        target = PLUGIN_DIR / plugin
        if not target.is_dir():
            skip(f"{patch_file.name}", f"plugin {plugin} not installed")
            continue
        with patch_file.open("rb") as fh:
            probe = subprocess.run(
                ["patch", "-d", str(target), "-p1", "--dry-run", "--reverse",
                 "--forward"],
                stdin=fh, capture_output=True,
            )
        if probe.returncode == 0:
            ok(f"{patch_file.name} applied")
        else:
            bad(f"{patch_file.name} applied",
                "run scripts/apply-plugin-patches.sh")

    # A patch can apply and still leave the UI broken; ask the plugin itself.
    dms = have("dms")
    if dms and (PLUGIN_DIR / "dankChat").is_dir():
        try:
            proc = subprocess.run(
                [dms, "ipc", "call", "dankChat", "viewStatus"],
                capture_output=True, text=True, timeout=6,
            )
            state = json.loads(proc.stdout or "{}")
        except Exception:  # noqa: BLE001
            skip("dankChat view loads", "no running shell to ask")
            return
        if state.get("loaded"):
            ok("dankChat view loads")
        else:
            bad("dankChat view loads", (state.get("error") or "unknown").strip()[:160])


def check_bindings() -> None:
    section("Generated keybindings")
    if not GENERATED_BINDINGS.is_file():
        skip("generated bindings", "run `ominty registry build`")
        return
    unresolved = set()
    total = 0
    for line in GENERATED_BINDINGS.read_text().splitlines():
        line = line.strip()
        if not line.startswith("spawn "):
            continue
        parts = line.split('"')
        if len(parts) < 2:
            continue
        cmd = parts[1]
        total += 1
        # `dms` and `sh` come from the system; everything else must resolve.
        if cmd in {"dms", "sh", "bash"} or cmd.startswith("/"):
            if cmd.startswith("/") and not Path(cmd).exists():
                unresolved.add(cmd)
            continue
        if not have(cmd):
            unresolved.add(cmd)
    if total == 0:
        skip("generated bindings", "no spawn entries")
    elif unresolved:
        bad("every generated binding resolves", ", ".join(sorted(unresolved)))
    else:
        ok(f"all {total} generated bindings resolve")


def check_stack() -> None:
    section("TTS / STT / media / dictionary")
    piper = Path.home() / ".piper-venv" / "bin" / "piper"
    voices = Path.home() / ".local" / "share" / "piper" / "voices"
    if piper.is_file() and any(voices.glob("*.onnx")):
        ok("Piper + a voice model")
    elif piper.is_file():
        bad("TTS voice model", f"no .onnx in {voices}")
    else:
        skip("Piper", "optional tts layer not installed")

    whisper = have("whisper-cli") or (
        Path.home() / ".local" / "bin" / "whisper-cli"
        if (Path.home() / ".local" / "bin" / "whisper-cli").is_file()
        else None
    )
    model = Path.home() / ".local" / "share" / "ominty" / "models" / "ggml-base.en.bin"
    if whisper and model.is_file():
        ok("whisper.cpp + model")
    elif whisper and not model.is_file():
        bad("STT model", f"missing {model}")
    else:
        skip("whisper.cpp", "optional dictation engine not installed")
    for tool in ("ffmpeg", "pw-record", "wtype"):
        if have(tool):
            ok(f"STT tool {tool}")
        else:
            skip(f"STT tool {tool}", "only needed for dictation")

    for cli, probe in (
        ("omi-media", ["categories", "--json"]),
        ("omi-dict", ["dictionaries"]),
    ):
        binary = have(cli)
        if not binary:
            bad(cli, "not installed")
            continue
        try:
            proc = subprocess.run(
                [binary, *probe], capture_output=True, text=True, timeout=10
            )
        except Exception as exc:  # noqa: BLE001
            bad(f"{cli} runs", str(exc))
            continue
        if proc.returncode == 0 and proc.stdout.strip():
            ok(f"{cli} runs")
        else:
            bad(f"{cli} runs", (proc.stderr or proc.stdout).strip()[:120])


def main() -> int:
    as_json = "--json" in sys.argv[1:]
    check_actions()
    check_plugins()
    check_patches()
    check_bindings()
    check_stack()

    passed = sum(1 for s, _, _ in results if s == "PASS")
    failed = sum(1 for s, _, _ in results if s == "FAIL")
    skipped = sum(1 for s, _, _ in results if s == "SKIP")

    if as_json:
        print(json.dumps(
            {
                "results": [
                    {"status": s, "label": l, "detail": d}
                    for s, l, d in results
                ],
                "summary": {
                    "passed": passed, "failed": failed, "skipped": skipped
                },
            },
            indent=2,
        ))
        return 1 if failed else 0

    colours = {"PASS": "\033[32m", "FAIL": "\033[31m", "SKIP": "\033[33m"}
    for status, label, detail in results:
        if status == "":
            print(f"\n\033[1m{label}\033[0m")
            continue
        mark = f"{colours[status]}{status}\033[0m"
        print(f"  {mark}  {label}" + (f"  ({detail})" if detail else ""))
    print(
        f"\n\033[1mSummary:\033[0m {passed} passed, {failed} failed, "
        f"{skipped} skipped"
    )
    if failed:
        print("Result: \033[31mNOT FUNCTIONAL\033[0m — see the failures above.")
        return 1
    print("Result: \033[32mOK\033[0m")
    return 0


if __name__ == "__main__":
    sys.exit(main())
