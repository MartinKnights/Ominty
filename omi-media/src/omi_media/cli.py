"""omi-media CLI surface (Omi Media Launcher spec §9–§11).

The stable command-line contract between playlist discovery, the player
launcher and every presentation layer (the DMS "Ominty Playlist Selector",
scripts, later a Pi agent).  Usable with no desktop session at all.
"""

from __future__ import annotations

import argparse
import json
import sys

from . import __version__
from . import config as cfg
from .players import launch, stop


def _out(obj: dict, use_json: bool) -> int:
    if use_json:
        print(json.dumps(obj, indent=2))
    else:
        print(obj.get("text", ""))
    return 0


def _categories(args: argparse.Namespace) -> list[dict]:
    """Folders under the root that contain playlists, with overrides applied."""
    from .discovery import discover_categories

    data = cfg.load_config(args.config)
    return discover_categories(cfg.effective_root(data), cfg.folder_overrides(data))


def _category(args: argparse.Namespace, cid: str) -> dict | None:
    return next((c for c in _categories(args) if c["id"] == cid), None)


def cmd_categories(args: argparse.Namespace) -> int:
    """List discovered categories with live playlist counts (spec §9)."""
    items = _categories(args)
    if args.json:
        return _out({"categories": items}, True)
    if not items:
        print("No media categories configured.")
        return 0
    for c in items:
        print(f"  {c['name']:<10}{c['playlist_count']:>5} playlists  ({c['player']})")
    return 0


def cmd_playlists(args: argparse.Namespace) -> int:
    """List the playlists in one category (spec §10)."""
    from .discovery import discover_playlists

    spec = _category(args, args.category)
    if not spec:
        print(f"omi-media: unknown category '{args.category}'", file=sys.stderr)
        return 1
    items = discover_playlists(spec["directory"])
    if args.json:
        return _out({
            "category": args.category,
            "name": spec["name"],
            "directory": spec["directory"],
            "player": spec["player"],
            "playlists": items,
        }, True)
    if not items:
        print(f"(no playlists in {spec['directory']})")
        return 0
    for p in items:
        print(f"  {p['title']}")
    return 0


def cmd_play(args: argparse.Namespace) -> int:
    """Hand a playlist to its category's player (spec §11)."""
    from .discovery import discover_playlists

    spec = _category(args, args.category)
    if not spec:
        print(f"omi-media: unknown category '{args.category}'", file=sys.stderr)
        return 1
    playlists = discover_playlists(spec["directory"])
    target = args.playlist
    match = next(
        (p for p in playlists if target in (p["name"], p["title"], p["path"])),
        None,
    )
    if not match:
        print(
            f"omi-media: no playlist '{target}' in '{spec['directory']}'",
            file=sys.stderr,
        )
        return 1
    result = launch(spec, match["path"], dry_run=args.dry_run)
    if args.json:
        return _out(result, True)
    if result["status"] == "dry_run":
        print(" ".join(result["command"]))
        return 0
    if result["status"] == "error":
        print(f"omi-media: {result['error']}", file=sys.stderr)
        return 1
    print("launched:", " ".join(result["command"]))
    return 0


def cmd_stop(args: argparse.Namespace) -> int:
    """Stop the player that omi-media started (spec §11)."""
    result = stop(dry_run=args.dry_run)
    if args.json:
        return _out(result, True)
    print(result["status"])
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="omi-media",
        description="Omi media launcher — discover playlists and hand them to a player.",
    )
    p.add_argument("-V", "--version", action="version", version=f"omi-media {__version__}")
    p.add_argument("--config", help="path to media.toml (default: ~/.config/omi/media.toml)")
    sub = p.add_subparsers(dest="command", required=True)

    c_p = sub.add_parser("categories", help="list configured categories")
    c_p.add_argument("--json", action="store_true")
    c_p.set_defaults(func=cmd_categories)

    l_p = sub.add_parser("playlists", help="list playlists in a category")
    l_p.add_argument("category")
    l_p.add_argument("--json", action="store_true")
    l_p.set_defaults(func=cmd_playlists)

    pl_p = sub.add_parser("play", help="play a playlist in its category's player")
    pl_p.add_argument("category")
    pl_p.add_argument("playlist", help="playlist file name, title, or full path")
    pl_p.add_argument("--dry-run", action="store_true", help="print the command, do not launch")
    pl_p.add_argument("--json", action="store_true")
    pl_p.set_defaults(func=cmd_play)

    st_p = sub.add_parser("stop", help="stop the player omi-media started")
    st_p.add_argument("--dry-run", action="store_true")
    st_p.add_argument("--json", action="store_true")
    st_p.set_defaults(func=cmd_stop)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except Exception as exc:  # noqa: BLE001 — structured exit, no traceback to the user
        print(f"omi-media: {exc}", file=sys.stderr)
        return 1