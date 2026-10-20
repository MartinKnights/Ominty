#!/usr/bin/env python3
"""ominty-ollama — local Ollama management helper for the Ominty Ollama plugin.

Drives the local Ollama installation: status, list/show/pull/remove models,
quick chat, service control, GPU check and backup/restore of the models
directory.  Prints one JSON object (or one JSON object per progress line while
pulling) to stdout; errors to stderr with a non-zero exit.

Machine-general by design — it detects its environment instead of assuming:

- **service scope**: prefers a *user* systemd unit (`systemctl --user
  ollama`, no privileges needed), falls back to a system unit (`pkexec
  systemctl ollama`, polkit dialog);
- **server port**: `OLLAMA_HOST` of the helper's own env, then the unit's
  `Environment=` config, then the common defaults (11434, 11435). CLI
  invocations are re-exported with the detected `OLLAMA_HOST`;
- **models directory**: `OLLAMA_MODELS` env, then the unit's config, then
  `~/.ollama/models`.

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
UNIT = "ollama"
LOG_FILE = HOME / ".ollama" / "ominty-ollama-plugin.log"
BACKUP_DIR = HOME / ".local" / "share" / "ominty-ollama" / "backups"
DEFAULT_PORTS = ["127.0.0.1:11434", "127.0.0.1:11435"]

POPULAR = [
    "llama3.1:8b", "llama3:8b", "llama3.2:3b", "gemma3:4b",
    "qwen2.5:7b", "deepseek-r1:8b", "mistral", "phi3",
]

KV_RE = re.compile(r'([A-Za-z_]+)=("[^"]*"|\S+)')
PCT_RE = re.compile(r"\b(\d{1,3})%")

_cache: dict = {}


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


def parse_env(text: str) -> dict:
    env = {}
    for key, raw in KV_RE.findall(text or ""):
        env[key] = raw.strip('"')
    return env


def systemctl_cmd(scope: str, args: list, timeout: int = 15) -> subprocess.CompletedProcess:
    """Run systemctl against the detected scope. System scope needs pkexec."""
    cmd = []
    if scope == "user":
        cmd += ["systemctl", "--user"]
    elif scope == "system":
        cmd += ["pkexec", "systemctl"]  # polkit dialog via the shell's agent
    else:
        return subprocess.CompletedProcess(cmd, 1, "", "no ollama unit found")
    return run(cmd + args, timeout=timeout)


def unit_environment(scope: str) -> dict:
    """OLLAMA_* config baked into the unit (user or system)."""
    probe = systemctl_cmd(scope, ["show", UNIT, "-p", "Environment"], timeout=10)
    if probe.returncode != 0:
        return {}
    return parse_env(probe.stdout)


def detect() -> dict:
    """Scope, unit config, candidates ports and the models directory."""
    if "detect" in _cache:
        return _cache["detect"]
    scope = "none"
    unit_env: dict = {}
    probes = [
        ("user", ["systemctl", "--user", "list-unit-files", "--type=service"]),
        ("system", ["systemctl", "list-unit-files", "--type=service"]),
    ]
    for cand, cmd in probes:
        hit = run(cmd, timeout=10).stdout
        if re.search(r"^\s*ollama\.service\b", hit or "", re.M):
            scope = cand
            unit_env = unit_environment(cand)
            break
    # env of the helper itself wins, then the unit, then defaults
    env = dict(unit_env)
    env.update({k: v for k, v in os.environ.items() if k.startswith("OLLAMA_")})
    ports = []
    if env.get("OLLAMA_HOST"):
        text = env["OLLAMA_HOST"]
        for part in text.split(","):
            part = part.strip().replace("http://", "").replace("https://", "")
            part = part.split("/")[0]
            if part and part not in ports:
                ports.append(part if ":" in part else part + ":11434")
    for port in DEFAULT_PORTS:
        if port not in ports:
            ports.append(port)
    models_dir = Path(env.get("OLLAMA_MODELS") or HOME / ".ollama" / "models")
    _cache["detect"] = {"scope": scope, "env": env, "ports": ports,
                        "modelsDir": models_dir}
    return _cache["detect"]


def models_dir() -> Path:
    return detect()["modelsDir"]


def server_up(timeout: int = 2):
    """Probe the candidate ports; returns ('host:port', True/False)."""
    ports = detect()["ports"]
    for port in ports:
        try:
            with urllib.request.urlopen(
                f"http://{port}/api/version", timeout=timeout
            ) as resp:
                resp.read()
            return port, True
        except Exception:
            continue
    return (ports[0] if ports else "127.0.0.1:11434"), False


def ollama_env() -> dict:
    """Extra env for ollama CLI: point it at the detected server."""
    env = dict(detect()["env"])
    port, up = server_up()
    if up:
        env["OLLAMA_HOST"] = port
    return env


def run(cmd: list, timeout: int = 30, inp: str | None = None,
        env: dict | None = None) -> subprocess.CompletedProcess:
    merged = None if env is None else dict(os.environ, **env)
    return subprocess.run(cmd, input=inp, timeout=timeout,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, env=merged)


def run_ollama(args: list, timeout: int = 30) -> subprocess.CompletedProcess:
    return run([ollama_bin()] + args, timeout=timeout, env=ollama_env())


def blob_size(digest: str) -> int:
    if not digest:
        return 0
    path = (models_dir() / "blobs") / ("sha256-" + digest.split(":", 1)[1]) \
        if digest.startswith("sha256:") else (models_dir() / "blobs") / digest
    try:
        return path.stat().st_size
    except OSError:
        return 0


def manifest_models() -> list:
    """Offline model list: walk <models>/manifests and sum blob sizes."""
    models = []
    manifests = models_dir() / "manifests"
    if not manifests.is_dir():
        return models
    for path in sorted(manifests.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(manifests).parts  # e.g. ollama.com/library/llama3.1/8b
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
    info = detect()
    version = "Unknown"
    proc = run_ollama(["--version"], timeout=5)
    both = (proc.stdout or "") + (proc.stderr or "")
    m = re.search(r"client version is (\S+)", both) or re.search(r"(\d+\.\d+\.\d+\S*)", both)
    if proc.returncode == 0 and m:
        version = m.group(1)
    port, up = server_up()
    service_state, enabled_state, unit_exists = "none", "none", "no"
    if info["scope"] != "none":
        unit_exists = "yes"
        active = systemctl_cmd(info["scope"], ["is-active", UNIT]).stdout.strip()
        enabled = systemctl_cmd(info["scope"], ["is-enabled", UNIT]).stdout.strip()
        service_state = active if active else "unknown"
        enabled_state = enabled if enabled in ("enabled", "disabled", "static") else "other"
    out({
        "ok": True,
        "version": version,
        "binMissing": shutil.which("ollama") is None
                     and not (HOME / ".local" / "bin" / "ollama").is_file(),
        "modelsDir": str(models_dir()),
        "serverUp": up,
        "host": port,
        "scope": info["scope"],          # user | system | none
        "serviceState": service_state,   # active|inactive|failed|...
        "unitExists": unit_exists,
        "enabledState": enabled_state,   # enabled|disabled|static|other
        "popular": POPULAR,
    })


def cmd_list(args: list | None = None) -> None:
    port, up = server_up()
    models = []
    if up:
        proc = run_ollama(["list"], timeout=15)
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
    out({"ok": True, "serverUp": up, "models": models})


def cmd_show(args: list | None = None) -> None:
    name = _dispatch(args, 1, "show <model>")
    proc = run_ollama(["show", name], timeout=30)
    if proc.returncode != 0:
        out({"err": proc.stderr.strip() or "ollama show failed (is the server running?)"})
        return
    out({"ok": True, "details": proc.stdout})


def cmd_pull(args: list | None = None) -> None:
    name = _dispatch(args, 1, "pull <model>")
    log(f"Pulling model: {name}")
    pulled = subprocess.Popen(
        [ollama_bin(), "pull", name],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        env=dict(os.environ, **ollama_env()),
    )
    pct = 0
    try:
        for line in pulled.stdout or []:
            line = line.rstrip("\n")
            if not line:
                continue
            m = PCT_RE.search(line)
            if m:
                pct = int(m.group(1))
            log(f"pull {name}: {line}")
            out({"ev": "p", "pct": pct, "line": line.strip()[:160]})
        pulled.wait()
        if pulled.returncode == 0:
            log(f"Pull complete: {name}")
            out({"ev": "done", "pct": 100, "ok": True})
        else:
            out({"ev": "done", "err": f"ollama pull exited {pulled.returncode}"})
    except Exception as exc:
        pulled.kill()
        log(f"Pull error: {exc}")
        out({"ev": "done", "err": str(exc)})


def cmd_rm(args: list | None = None) -> None:
    name = _dispatch(args, 1, "rm <model>")
    log(f"Removing model: {name}")
    port, up = server_up()
    if not up:
        out({"err": "Ollama server is not running — start it in the Server tab first."})
        return
    proc = run_ollama(["rm", name], timeout=30)
    if proc.returncode != 0:
        out({"err": proc.stderr.strip() or "Failed to remove model"})
    else:
        out({"ok": True})


def cmd_ps(args: list | None = None) -> None:
    """Models currently loaded into memory (ollama ps) — chat load feedback."""
    port, up = server_up()
    if not up:
        out({"ok": True, "serverUp": False, "running": []})
        return
    proc = run_ollama(["ps", "--json"], timeout=10)
    rows = []
    if proc.returncode == 0:
        try:
            rows = json.loads(proc.stdout or "[]") or []
        except Exception:
            rows = []
    else:
        log(f"ps failed: {proc.stderr.strip()[:120]}")
    out({"ok": True, "serverUp": up, "running": [
        {"name": r.get("name", ""),
         "processor": r.get("processor", ""),
         "vramPct": int(round(float(r.get("size_vram", 0)) * 100
                             / float(r.get("size", 1))))
         if float(r.get("size", 0)) > 0 else 0,
         } for r in rows]})


def cmd_chat(args: list | None = None) -> None:
    prompt = None
    if args and len(args) >= 2:
        name = args[0]
        prompt = " ".join(args[1:])
    elif args and len(args) == 1:
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
        proc = run_ollama(["run", name, prompt], timeout=600)
    except subprocess.TimeoutExpired:
        out({"err": "The model did not answer in time (10 min)."})
        return
    if proc.returncode != 0:
        out({"err": proc.stderr.strip() or proc.stdout.strip() or "ollama run failed"})
    else:
        out({"ok": True, "response": proc.stdout.strip()})


def cmd_gpu(args: list | None = None) -> None:
    port, up = server_up()
    if not up:
        out({"err": "Ollama server is not running — start it in the Server tab first."})
        return
    listing = run_ollama(["list"], timeout=15)
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
        answer = run_ollama(["run", model, "Reply with a single word: ready."], timeout=300)
        if answer.returncode != 0:
            out({"err": answer.stderr.strip() or "ollama run failed"})
            return
    except subprocess.TimeoutExpired:
        out({"err": "Model load timed out (5 min)."})
        return
    ps = run_ollama(["ps", "--json"], timeout=15)
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
    run_ollama(["stop", model], timeout=10)
    out({"ev": "done", "ok": True, "model": model,
         "gpuState": gpu_state, "pct": gpu_pct, "processor": detail})


SVC_ACTIONS = ["start", "stop", "restart", "enable", "disable"]


def cmd_svc(args: list | None = None) -> None:
    action = _dispatch(args, 1, "svc <start|stop|restart|enable|disable>")
    if action not in ("start", "stop", "restart", "enable", "disable"):
        out({"err": f"Unknown service action '{action}'"})
        return
    info = detect()
    if info["scope"] == "none":
        out({"err": "No ollama systemd unit found (checked user and system scope)."})
        return
    log(f"Service action '{action}' ({info['scope']} scope)")
    try:
        proc = systemctl_cmd(info["scope"], [action, UNIT], timeout=300)
    except FileNotFoundError:
        out({"err": "pkexec not found on this system."})
        return
    if proc.returncode == 126:
        out({"err": "Not authorised — the authentication dialog was cancelled or no polkit agent is available."})
    elif proc.returncode != 0:
        msg = proc.stderr.strip() or f"systemctl {action} failed"
        out({"err": msg})
    else:
        out({"ok": True, "action": action, "scope": info["scope"]})


def valid_archive(name: str) -> Path:
    """Resolve a backup archive strictly inside BACKUP_DIR."""
    target = (BACKUP_DIR / name).resolve()
    if not (target.is_file() and target.parent == BACKUP_DIR.resolve()
            and target.name.endswith(".tar.gz")):
        raise ValueError("That is not a valid backup archive.")
    return target


def cmd_backup(args: list | None = None) -> None:
    mdir = models_dir()
    mdir.parent.mkdir(parents=True, exist_ok=True)
    if not mdir.is_dir():
        out({"err": f"No models directory found at {mdir}"})
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    target = BACKUP_DIR / time.strftime("ollama_models_%Y%m%d_%H%M%S.tar.gz")
    log(f"Backing up models to {target}")
    out({"ev": "p", "line": "Creating backup archive…"})
    proc = subprocess.run(
        ["tar", "-czf", str(target), "-C", str(mdir.parent), mdir.name],
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


def cmd_restore(args: list | None = None) -> None:
    name = _dispatch(args, 1, "restore <archive-tar.gz>")
    try:
        archive = valid_archive(name)
    except ValueError as exc:
        out({"err": str(exc)})
        return
    mdir = models_dir()
    log(f"Restoring models from {archive}")
    out({"ev": "p", "line": "Restoring models from archive…"})
    shutil.rmtree(mdir, ignore_errors=True)
    mdir.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        ["tar", "-xzf", str(archive), "-C", str(mdir.parent)],
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


COMMANDS = {
    "status": cmd_status,
    "list": cmd_list,
    "ps": cmd_ps,
    "gpu": cmd_gpu,
    "backup": cmd_backup,
    "backups": cmd_backups,
    "show": cmd_show,
    "pull": cmd_pull,
    "rm": cmd_rm,
    "chat": cmd_chat,
    "svc": cmd_svc,
    "restore": cmd_restore,
}


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        out({"err": "usage: ominty-ollama.py <status|list|ps|show|pull|rm|chat|gpu|svc|backup|backups|restore> [args]"})
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
