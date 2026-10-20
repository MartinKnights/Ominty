#!/usr/bin/env python3
"""ominty-ollama — local Ollama management helper for the Ominty Ollama plugin.

Drives the local Ollama installation: status, list/show/pull/remove models,
quick chat, server (systemd) control, GPU check and backup/restore of the
models directory.  Prints one JSON object (or one JSON object per progress
line while pulling) to stdout; errors to stderr with a non-zero exit.

Uses only the standard library.  The QML holds no logic; this file is the
contract (same pattern as helpers/ominty-dl.py in omintyDownload).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
MODELS_DIR = HOME / ".ollama" / "models"
MANIFESTS_DIR = MODELS_DIR / "manifests"
BLOBS_DIR = MODELS_DIR / "blobs"
LOG_FILE = HOME / ".ollama" / "ominty-ollama-plugin.log"
BACKUP_DIR = HOME / ".local" / "share" / "ominty-ollama" / "backups"

POPULAR = [
    "llama3.1:8b", "llama3:8b", "llama3.2:3b", "gemma3:4b",
    "qwen2.5:7b", "deepseek-r1:8b", "mistral", "phi3",
]

PCT_RE = re.compile(r"\b(\d{1,3})%")


def log(msg: str) -> None:
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a") as fh:
            fh.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {msg}\n")
    except Exception:
        pass


def out(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def ollama_bin() -> str:
    return os.environ.get("OMINTY_OLLAMA") or shutil.which("ollama") \
        or str(HOME / ".local" / "bin" / "ollama")


def ollama_host() -> str:
    host = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434")
    if host.startswith("http://"):
        host_r = host[7:]
    elif host.startswith("https://"):
        host_r = host[8:]
    else:
        host_r = host
    host_r = host_r.rstrip("/").split("/")[0]
    return host_r if ":" in host_r else host_r + "11434"


def server_up(timeout: int = 2) -> bool:
    try:
        with urllib.request.urlopen(
            f"http://{ollama_host()}/api/version", timeout=timeout
        ) as resp:
            resp.read()
        return True
    except Exception:
        return False


def run(cmd: list, timeout: int = 30, inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, timeout=timeout,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True)


def blob_size(digest: str) -> int:
    if not digest:
        return 0
    path = BLOBS_DIR / ("sha256-" + digest.split(":", 1)[1]) \
        if digest.startswith("sha256:") else BLOBS_DIR / digest
    try:
        return path.stat().st_size
    except OSError:
        return 0


def manifest_models() -> list:
    """Offline model list: walk ~/.ollama/models/manifests and sum blob sizes."""
    models = []
    if not MANIFESTS_DIR.is_dir():
        return models
    for path in sorted(MANIFESTS_DIR.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(MANIFESTS_DIR).parts  # e.g. ollama.com/library/llama3.1/8b
        if len(rel) < 2:
            continue
        tag = rel[-1]
        owner = rel[1] if rel[1] != "library" else ""
        name = rel[2]
        model = ":".join(part for part in [owner, name, tag] if part)
        try:
            manifest = json.loads(path.read_text())
            size = blob_size(manifest.get("config", {}).get("digest"))
            for layer in manifest.get("layers", []):
                size += blob_size(layer.get("digest"))
        except Exception:
            size = 0
        models.append({
            "name": model,
            "size_bytes": size,
            "size_text": human(size),
            "modified": time.strftime("%Y-%m-%d", time.localtime(path.stat().st_mtime)),
        })
    return models


def human(n: int) -> str:
    if n <= 0:
        return ""
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024
    return f"{n:.1f} PB"


def cmd_status(args: list | None = None) -> None:
    version = "Unknown"
    proc = run([ollama_bin(), "--version"], timeout=5)
    both = (proc.stdout or "") + (proc.stderr or "")
    m = re.search(r"client version is (\S+)", both) or re.search(r"(\d+\.\d+\.\d+\S*)", both)
    if proc.returncode == 0 and m:
        version = m.group(1)
    up = server_up()
    unit_exists = service = "none"
    probe = run(["systemctl", "list-unit-files", "--type=service"], timeout=10)
    if probe.returncode == 0 and re.search(r"^\s*ollama\.service\b", probe.stdout, re.M):
        service = run(["systemctl", "is-active", "ollama"], timeout=10).stdout.strip() or "unknown"
        enabled = run(["systemctl", "is-enabled", "ollama"], timeout=10).stdout.strip()
        unit_exists = "yes"
        service_state = service
        enabled_state = enabled if enabled in ("enabled", "disabled") else "other"
    else:
        service_state, enabled_state = "none", "none"
    out({
        "ok": True,
        "version": version,
        "binMissing": shutil.which("ollama") is None
                     and not (HOME / ".local" / "bin" / "ollama").is_file(),
        "modelsDir": str(MODELS_DIR),
        "serverUp": up,
        "host": ollama_host(),
        "serviceState": service_state,   # active|inactive|failed|none-active...
        "unitExists": unit_exists,
        "enabledState": enabled_state,   # enabled|disabled|other
        "popular": POPULAR,
    })


def cmd_list(args: list | None = None) -> None:
    up = server_up()
    models = []
    if up:
        proc = run([ollama_bin(), "list"], timeout=15)
        if proc.returncode == 0:
            for line in proc.stdout.strip().splitlines()[1:]:
                parts = line.split()
                if len(parts) >= 4:
                    models.append({
                        "name": parts[0],
                        "size_text": parts[2],
                        "modified": " ".join(parts[3:]),
                        "size_bytes": 0,
                    })
        else:
            up = False
    if not models:
        models = manifest_models()
        up = False
    out({"ok": True, "serverUp": up, "models": models})


def cmd_show(name: str) -> None:
    proc = run([ollama_bin(), "show", name], timeout=30)
    if proc.returncode != 0:
        out({"err": proc.stderr.strip() or "ollama show failed (is the server running?)"})
        return
    out({"ok": True, "details": proc.stdout})


def cmd_pull(name: str) -> None:
    log(f"Pulling model: {name}")
    proc = subprocess.Popen(
        [ollama_bin(), "pull", name],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    pct = 0
    try:
        for line in proc.stdout or []:
            line = line.rstrip("\n")
            if not line:
                continue
            m = PCT_RE.search(line)
            if m:
                pct = int(m.group(1))
            log(f"pull {name}: {line}")
            out({"ev": "p", "pct": pct, "line": line.strip()[:160]})
        proc.wait()
        if proc.returncode == 0:
            log(f"Pull complete: {name}")
            out({"ev": "done", "pct": 100, "ok": True})
        else:
            out({"ev": "done", "err": f"ollama pull exited {proc.returncode}"})
    except Exception as exc:
        proc.kill()
        log(f"Pull error: {exc}")
        out({"ev": "done", "err": str(exc)})


def cmd_rm(name: str) -> None:
    log(f"Removing model: {name}")
    if not server_up():
        out({"err": "Ollama server is not running — start it in the Server tab first."})
        return
    proc = run([ollama_bin(), "rm", name], timeout=30)
    if proc.returncode != 0:
        out({"err": proc.stderr.strip() or "Failed to remove model"})
    else:
        out({"ok": True})


def cmd_chat(args: list | None = None) -> None:
    args = args or []
    if len(args) >= 2:
        name, prompt = args[0], " ".join(args[1:])
    elif len(args) == 1:
        name = args[0]
        prompt = sys.stdin.read()
    else:
        out({"err": "usage: ominty-ollama.py chat <model> <prompt>"})
        return
    if not prompt.strip():
        out({"err": "Empty prompt"})
        return
    log(f"Quick chat with {name}")
    try:
        proc = run([ollama_bin(), "run", name, prompt], timeout=600)
    except subprocess.TimeoutExpired:
        out({"err": "The model did not answer in time (10 min)."})
        return
    if proc.returncode != 0:
        out({"err": proc.stderr.strip() or proc.stdout.strip() or "ollama run failed"})
    else:
        out({"ok": True, "response": proc.stdout.strip()})


def cmd_gpu(args: list | None = None) -> None:
    if not server_up():
        out({"err": "Ollama server is not running — start it in the Server tab first."})
        return
    listing = run([ollama_bin(), "list"], timeout=15)
    names = [line.split()[0] for line in listing.stdout.splitlines()[1:] if line.split()]
    if not names:
        out({"err": "No models installed. Install at least one model first."})
        return
    sizes = {m["name"]: m["size_bytes"] for m in manifest_models()}
    names.sort(key=lambda n: sizes.get(n, 1 << 62))
    model = names[0]
    log(f"GPU check with model: {model}")
    out({"ev": "p", "line": f"Loading {model} and running a small prompt…"})
    try:
        answer = run([ollama_bin(), "run", model, "Reply with a single word: ready."],
                     timeout=300)
        if answer.returncode != 0:
            out({"err": answer.stderr.strip() or "ollama run failed"})
            return
    except subprocess.TimeoutExpired:
        out({"err": "Model load timed out (5 min)."})
        return
    ps = run([ollama_bin(), "ps", "--json"], timeout=15)
    gpu_state, gpu_pct, detail = "cpu", 0, ""
    if ps.returncode == 0:
        try:
            rows = json.loads(ps.stdout)
            for row in rows:
                if row.get("name", "").startswith(model.split(":")[0]):
                    size = float(row.get("size", 0))
                    vram = float(row.get("size_vram", 0))
                    if size > 0:
                        gpu_pct = int(round(vram * 100 / size))
                    gpu_state = "gpu" if gpu_pct >= 75 else ("mixed" if gpu_pct > 0 else "cpu")
                    detail = row.get("processor", "")
        except Exception as exc:
            log(f"ps parse error: {exc}")
    run([ollama_bin(), "stop", model], timeout=10)
    out({"ev": "done", "ok": True, "model": model,
         "gpuState": gpu_state, "pct": gpu_pct, "processor": detail})


SVC = {
    "start":    ["systemctl", "start", "ollama"],
    "stop":     ["systemctl", "stop", "ollama"],
    "restart":  ["systemctl", "restart", "ollama"],
    "enable":   ["systemctl", "enable", "ollama"],
    "disable":  ["systemctl", "disable", "ollama"],
}


def cmd_svc(action: str) -> None:
    cmd = SVC.get(action)
    if not cmd:
        out({"err": f"Unknown service action: {action}"})
        return
    log(f"Service action '{action}': pkexec {' '.join(cmd)}")
    try:
        proc = run(["pkexec"] + cmd, timeout=300)
    except FileNotFoundError:
        out({"err": "pkexec not found on this system."})
        return
    if proc.returncode == 126:
        out({"err": "Not authorised — the authentication dialog was cancelled or no polkit agent is available."})
    elif proc.returncode != 0:
        msg = proc.stderr.strip() or f"systemctl {action} failed"
        out({"err": msg})
    else:
        out({"ok": True, "action": action})


def valid_archive(name: str) -> Path:
    """Resolve a backup archive strictly inside BACKUP_DIR."""
    target = (BACKUP_DIR / name).resolve()
    if not (target.is_file() and target.parent == BACKUP_DIR.resolve()
            and target.name.endswith(".tar.gz")):
        raise ValueError("That is not a valid backup archive.")
    return target


def cmd_backup(args: list | None = None) -> None:
    MODELS_DIR.parent.mkdir(parents=True, exist_ok=True)
    if not MODELS_DIR.is_dir():
        out({"err": f"No models directory found at {MODELS_DIR}"})
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    target = BACKUP_DIR / time.strftime("ollama_models_%Y%m%d_%H%M%S.tar.gz")
    log(f"Backing up models to {target}")
    out({"ev": "p", "line": "Creating backup archive…"})
    proc = subprocess.run(
        ["tar", "-czf", str(target), "-C", str(MODELS_DIR.parent), "models"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    if proc.returncode != 0:
        out({"err": proc.stderr.strip() or "tar failed"})
        return
    out({"ev": "done", "ok": True, "file": target.name, "size": human(target.stat().st_size)})


def cmd_backups(args: list | None = None) -> None:
    rows = []
    if BACKUP_DIR.is_dir():
        for path in sorted(BACKUP_DIR.glob("*.tar.gz"), reverse=True):
            rows.append({
                "name": path.name,
                "size": human(path.stat().st_size),
                "date": time.strftime("%Y-%m-%d %H:%M", time.localtime(path.stat().st_mtime)),
            })
    out({"ok": True, "dir": str(BACKUP_DIR), "files": rows})


def cmd_restore(name: str) -> None:
    try:
        archive = valid_archive(name)
    except ValueError as exc:
        out({"err": str(exc)})
        return
    log(f"Restoring models from {archive}")
    out({"ev": "p", "line": "Restoring models from archive…"})
    shutil.rmtree(MODELS_DIR, ignore_errors=True)
    MODELS_DIR.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        ["tar", "-xzf", str(archive), "-C", str(MODELS_DIR.parent)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    if proc.returncode != 0:
        out({"err": proc.stderr.strip() or "tar failed"})
        return
    out({"ev": "done", "ok": True})


def _dispatch(args: list, count: int, what: str) -> str:
    if len(args) != count:
        raise SystemExit(f"usage: ominty-ollama.py {what}")
    return args[0]


def _dispatch_show(args: list) -> None:
    cmd_show(_dispatch(args, 1, "show <model>"))


def _dispatch_pull(args: list) -> None:
    cmd_pull(_dispatch(args, 1, "pull <model>"))


def _dispatch_rm(args: list) -> None:
    cmd_rm(_dispatch(args, 1, "rm <model>"))


def _dispatch_chat(args: list) -> None:
    cmd_chat(_dispatch(args, 2, "chat <model> <prompt>"))


def _dispatch_svc(args: list) -> None:
    cmd_svc(_dispatch(args, 1, "svc <start|stop|restart|enable|disable>"))


def _dispatch_restore(args: list) -> None:
    cmd_restore(_dispatch(args, 1, "restore <archive-tar.gz>"))


COMMANDS = {
    "status": cmd_status,
    "list": cmd_list,
    "gpu": cmd_gpu,
    "backup": cmd_backup,
    "backups": cmd_backups,
    "show": _dispatch_show,
    "pull": _dispatch_pull,
    "rm": _dispatch_rm,
    "chat": _dispatch_chat,
    "svc": _dispatch_svc,
    "restore": _dispatch_restore,
}


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        out({"err": "usage: ominty-ollama.py <status|list|show|pull|rm|chat|gpu|svc|backup|backups|restore> [args]"})
        sys.exit(2)
    try:
        COMMANDS[sys.argv[1]](sys.argv[2:])
    except SystemExit as exc:
        out({"err": str(exc)})
        sys.exit(2)
    except Exception as exc:
        log(f"{sys.argv[1]} error: {exc}")
        out({"err": str(exc)})
        sys.exit(1)


if __name__ == "__main__":
    main()
