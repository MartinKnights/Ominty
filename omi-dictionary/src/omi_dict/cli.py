"""omi-dict CLI surface (spec §8).  Phase 1 implements the import pipeline;
lookup/search land with phases 3–4 and selection with phase 5."""

from __future__ import annotations

import argparse
import json
import sys

from . import __version__
from . import config as cfg


def _out(obj: dict, use_json: bool) -> int:
    if use_json:
        print(json.dumps(obj, indent=2))
    else:
        print(obj.get("text", ""))
    return 0


def cmd_dictionaries(args: argparse.Namespace) -> int:
    """List installed dictionary indexes (spec §5)."""
    from .registry import discovered

    dicts = discovered()
    if args.json:
        return _out({"dictionaries": dicts}, True)
    if not dicts:
        print("No dictionaries installed (run: omi-dict import <file.bgl>).")
        return 0
    for d in dicts:
        print(f"  {d['id']:<24} {d['name']}  ({d['entries']} entries)")
    return 0


def cmd_import(args: argparse.Namespace) -> int:
    """Import a BGL dictionary: convert (PyGlossary) + index (§20, ADR-001)."""
    from .index import import_bgl

    result = import_bgl(args.file, args.dictionary, force=getattr(args, "force", False))
    if args.json:
        return _out(result, True)
    if result.get("reused"):
        print(f"{result['id']}: unchanged, index reused ({result['entries']} entries).")
    else:
        print(
            f"Imported {result['id']}: {result['name']} — "
            f"{result['entries']} headwords indexed."
        )
    return 0


def cmd_lookup(args: argparse.Namespace) -> int:
    """Exact lookup (spec §8); --all queries every dictionary (§11)."""
    from .index import Index
    from .lookup import lookup, lookup_all, result_shape
    from .registry import configured_name, default_id, discovered

    if args.all:
        data = {"query": args.word, "results": [], "errors": []}
        try:
            shape = lookup_all(args.word, discovered())
        except Exception as exc:
            if getattr(args, "json", False):
                data["error"] = getattr(exc, "code", "OMI_DICT_ERROR")
            print(f"omi-dict: {exc}", file=sys.stderr)
            return 1
        if args.json:
            return _out(shape, True)
        print(shape["query"])
        for i, r in enumerate(shape["results"]):
            if i == 0:
                print(f"\n▼ {r['dictionary']['name']}")
            else:
                print(f"\n▶ {r['dictionary']['name']}")
            print(r["entry"]["text"][:2000])
        for e in shape.get("errors", []):
            print(f"\n(!) {e['id']}: {e['message']}", file=sys.stderr)
        return 0

    dict_id = args.dictionary or default_id()
    name = configured_name(dict_id)
    if not name:
        idx = Index(dict_id)
        name = idx.meta("name") if idx.exists() else dict_id
    try:
        entry = lookup(dict_id, args.word)
    except Exception as exc:  # noqa: BLE001 — structured, trace-free (§21)
        if getattr(args, "json", False):
            _out({"query": args.word, "error": getattr(exc, "code", "OMI_DICT_ERROR"),
                  "message": str(exc)}, True)
        else:
            print(f"omi-dict: {exc}", file=sys.stderr)
        return 1
    shape = result_shape(args.word, dict_id, name, entry)
    if args.json:
        return _out(shape, True)
    print(shape["entry"]["headword"])
    print(f"[{name}]")
    print()
    print(shape["entry"]["text"][:3200])
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="omi-dict",
        description="Omi dictionary service — local, keyboard-first dictionary lookup.",
    )
    p.add_argument("-V", "--version", action="version", version=f"omi-dict {__version__}")
    sub = p.add_subparsers(dest="command", required=True)

    d_p = sub.add_parser("dictionaries", help="list installed dictionaries")
    d_p.add_argument("--json", action="store_true")
    d_p.set_defaults(func=cmd_dictionaries)

    i_p = sub.add_parser("import", help="import a dictionary file into the data dir")
    i_p.add_argument("file", help="source dictionary (.bgl)")
    i_p.add_argument("--dictionary", help="target id (default: derived from the file name)")
    i_p.add_argument("--force", action="store_true", help="rebuild even if unchanged")
    i_p.add_argument("--json", action="store_true")
    i_p.set_defaults(func=cmd_import)

    l_p = sub.add_parser("lookup", help="look up an exact headword (spec §8)")
    l_p.add_argument("word")
    l_p.add_argument("--dictionary")
    l_p.add_argument("--all", action="store_true", help="query all dictionaries")
    l_p.add_argument("--json", action="store_true")
    l_p.set_defaults(func=cmd_lookup)

    s_p = sub.add_parser("search", help="search candidate headwords (Phase 3)")
    s_p.add_argument("prefix")
    s_p.add_argument("--dictionary")
    s_p.add_argument("--json", action="store_true")
    s_p.set_defaults(func=lambda a: _not_yet(a, "search"))
    return p


def _not_yet(args: argparse.Namespace, what: str) -> int:
    print(f"{what}: not implemented yet (Phase 3/4)", file=sys.stderr)
    return 2


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    cfg.ensure_dirs()
    try:
        return args.func(args)
    except Exception as exc:  # noqa: BLE001 — keep the UI free of traces (§21)
        if getattr(args, "json", False):
            _out({"error": getattr(exc, "code", "OMI_DICT_ERROR"), "message": str(exc)}, True)
        else:
            print(f"omi-dict: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())