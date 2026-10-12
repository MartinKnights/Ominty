#!/usr/bin/env python3
"""ominty-dl — local aria2 RPC helper for the Ominty download manager.

Spawns a per-user aria2 RPC daemon (JSON-RPC over the loopback) the first
time it is needed, then drives it: add URLs, list active/waiting/stopped
downloads, pause/resume/remove.  Prints one JSON object to stdout; errors to
stderr with a non-zero exit.

Uses only the standard library.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

RPC_HOST = "127.0.0.1"
RPC_PORT = "6801"
SECRET = "ominty"
RPC_URL = f"http://{RPC_HOST}:{RPC_PORT}/jsonrpc"
TOKEN = "token:" + SECRET

HOME = os.path.expanduser("~")
DIR = os.environ.get("OMINTY_DL_DIR", os.path.join(HOME, "Downloads"))
STATE = Path(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state"))) / "omi-download"
SESSION = STATE / "session"
ARIA2 = os.environ.get("OMINTY_ARIA2", os.path.join(HOME, ".local", "bin", "aria2c-wrapper"))


def rpc(method: str, params: list, timeout: int = 8):
    payload = json.dumps({
        "jsonrpc": "2.0", "id": "ominty", "method": method,
        "params": [TOKEN] + params,
    }).encode()
    req = urllib.request.Request(RPC_URL, data=payload,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        # JSON-RPC errors come back as HTTP 400 with the error in the body.
        try:
            data = json.loads(exc.read().decode() or "{}")
        except Exception:
            raise RuntimeError(f"aria2 RPC error: HTTP {exc.code}") from exc
    except Exception as exc:  # connection refused, timeout, bad json
        raise RuntimeError(f"aria2 RPC unavailable: {exc}") from exc
    if "error" in data:
        err = data["error"] or {}
        raise RuntimeError(str(err.get("message", err)))
    return data.get("result")


def reachable() -> bool:
    try:
        rpc("aria2.getVersion", [], timeout=2)
        return True
    except Exception:
        return False


def start() -> dict:
    if reachable():
        return {"status": "running"}
    STATE.mkdir(parents=True, exist_ok=True)
    args = [
        ARIA2,
        "--enable-rpc=true", "--rpc-listen-all=false",
        f"--rpc-listen-port={RPC_PORT}", f"--rpc-secret={SECRET}",
        f"--dir={DIR}", "--continue=true", "--max-concurrent-downloads=3",
        f"--save-session={SESSION}", "--auto-save-interval=30",
        "--daemon=true", "--console-log-level=warn",
    ]
    if SESSION.is_file():
        args.append(f"--input-file={SESSION}")
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(120):  # up to ~12s: wrapper + aria2 --daemon fork can be slow
        if reachable():
            return {"status": "started", "dir": DIR}
        time.sleep(0.1)
    if proc.poll() is not None:
        raise RuntimeError("aria2 RPC daemon failed to start")
    raise RuntimeError("aria2 RPC daemon did not come up")


def _name(gid: dict) -> str:
    bt = gid.get("bittorrent") or {}
    info = bt.get("info") or {} if isinstance(bt, dict) else {}
    name = info.get("name") or ""
    if not name:
        for f in (gid.get("files") or []):
            path = f.get("path") or ""
            if path:
                name = os.path.basename(path) or path
                break
    return name or gid.get("gid", "")


def _norm(gid: dict) -> dict:
    return {
        "gid": gid.get("gid", ""),
        "name": _name(gid),
        "status": gid.get("status", ""),
        "completed": int(gid.get("completedLength", 0) or 0),
        "total": int(gid.get("totalLength", 0) or 0),
        "speed": int(gid.get("downloadSpeed", 0) or 0),
        "error": int(gid.get("errorCode", 0) or 0),
    }


def list_downloads() -> dict:
    items = []
    try:
        for gid in rpc("aria2.tellActive", []):
            items.append(_norm(gid))
    except Exception:
        pass
    try:
        for gid in rpc("aria2.tellWaiting", [0, 200]):
            items.append(_norm(gid))
    except Exception:
        pass
    try:
        for gid in rpc("aria2.tellStopped", [0, 200]):
            items.append(_norm(gid))
    except Exception:
        pass
    items.sort(key=lambda i: i["status"], reverse=True)
    return {"running": reachable(), "items": items, "dir": DIR}


def main(argv: list[str]) -> int:
    cmd = argv[0] if argv else ""
    try:
        if cmd == "start":
            print(json.dumps(start()))
        elif cmd == "add":
            url = argv[1] if len(argv) > 1 else ""
            if not url:
                raise RuntimeError("add needs a URL")
            result = rpc("aria2.addUri", [[url]])
            print(json.dumps({"gid": result}))
        elif cmd == "list":
            print(json.dumps(list_downloads()))
        elif cmd == "pause":
            rpc("aria2.pause", [argv[1]]); print('{"ok": true}')
        elif cmd == "resume":
            rpc("aria2.unpause", [argv[1]]); print('{"ok": true}')
        elif cmd == "remove":
            try:
                rpc("aria2.remove", [argv[1]])
            except RuntimeError:
                # Stopped/errored downloads have no live GID — clear its result.
                rpc("aria2.removeDownloadResult", [argv[1]])
            print('{"ok": true}')
        else:
            raise RuntimeError(f"unknown command: {cmd}")
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"error": str(exc)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))