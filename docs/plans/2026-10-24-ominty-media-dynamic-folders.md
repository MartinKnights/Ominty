# Ominty Media — Dynamic Folders and Keyboard Navigation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Ominty Media list whatever folders exist under `~/Playlist` (hiding empty ones) and make every control reachable with Tab and the arrow keys.

**Architecture:** Discovery becomes directory-first — the root's subdirectories are the category list, `media.toml` only overrides player/name/args for a folder that exists. The DMS popup gains an explicit focus-zone state machine (tabs → filter → list) driven from one `Keys.onPressed` handler on the panel.

**Tech Stack:** Python 3.11+ (tomllib), Qt 6 QML (Quickshell/DMS), pytest.

**Design:** `docs/plans/2026-10-24-ominty-media-dynamic-folders-design.md`

---

## Task 1: Discover categories from folders

**Files:**
- Modify: `omi-media/src/omi_media/discovery.py`
- Test: `omi-media/tests/test_discovery.py`

**Step 1: Write the failing tests**

Replace `test_discover_categories_order_and_counts` with:

```python
def _mk(root: Path, name: str, playlists: list[str]) -> Path:
    d = root / name
    d.mkdir(parents=True, exist_ok=True)
    for n in playlists:
        (d / n).write_text("#EXTM3U\n", encoding="utf-8")
    return d


def test_discover_categories_scans_folders_and_hides_empty(tmp_path):
    _mk(tmp_path, "Video", ["B.m3u", "A.m3u"])
    _mk(tmp_path, "Music", ["Gospel.m3u"])
    _mk(tmp_path, "Courses", [])            # empty -> hidden
    (tmp_path / ".hidden").mkdir()
    (tmp_path / ".hidden" / "x.m3u").write_text("", encoding="utf-8")
    (tmp_path / "loose.m3u").write_text("", encoding="utf-8")  # file, not a folder

    cats = discover_categories(str(tmp_path))
    assert [c["name"] for c in cats] == ["Music", "Video"]   # alphabetical
    assert [c["playlist_count"] for c in cats] == [1, 2]
    assert all(c["player"] == "vlc" for c in cats)


def test_discover_categories_missing_root_is_empty(tmp_path):
    assert discover_categories(str(tmp_path / "nope")) == []


def test_discover_categories_applies_overrides_by_name_and_directory(tmp_path):
    _mk(tmp_path, "Music", ["Gospel.m3u"])
    _mk(tmp_path, "Video", ["Film.m3u"])
    overrides = {
        "music": {"name": "Music", "player": "mpv", "player_args": ["--no-video"]},
        "films": {"directory": str(tmp_path / "Video"), "player": "vlc"},
    }
    cats = {c["id"]: c for c in discover_categories(str(tmp_path), overrides)}
    assert cats["music"]["player"] == "mpv"
    assert cats["music"]["player_args"] == ["--no-video"]
    assert cats["video"]["player"] == "vlc"
```

**Step 2: Run and watch them fail**

```bash
cd omi-media && python3 -m pytest tests/test_discovery.py -q
```
Expected: `TypeError: discover_categories() takes 1 positional argument` / `KeyError: 'video'`.

**Step 3: Implement**

```python
def slugify(name: str) -> str:
    out = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")
    return out or "category"


def _override_for(folder: Path, overrides: dict) -> dict:
    for key, spec in overrides.items():
        spec = dict(spec)
        if key.lower() == folder.name.lower():
            return spec
        if str(spec.get("name", "")).lower() == folder.name.lower():
            return spec
        directory = spec.get("directory")
        if directory and Path(str(directory)) == folder:
            return spec
    return {}


def discover_categories(root: str, overrides: dict | None = None) -> list[dict]:
    """Subdirectories of ``root`` that contain a playlist, alphabetically.

    A folder with no playlist is hidden: an empty tab is noise, and the folder
    tree is how the user chooses what exists. ``overrides`` (from media.toml)
    can change a folder's name, player or player arguments; entries for
    folders that do not exist are ignored.
    """
    overrides = overrides or {}
    base = Path(root)
    if not base.is_dir():
        return []

    folders = sorted(
        (p for p in base.iterdir() if p.is_dir() and not p.name.startswith(".")),
        key=lambda p: p.name.lower(),
    )

    out: list[dict] = []
    used: set[str] = set()
    for folder in folders:
        playlists = discover_playlists(str(folder))
        if not playlists:
            continue
        spec = _override_for(folder, overrides)
        cid = slugify(folder.name)
        while cid in used:                 # "Music" and "music" on one root
            cid = f"{cid}-2"
        used.add(cid)
        out.append({
            "id": cid,
            "name": str(spec.get("name") or folder.name),
            "directory": str(folder),
            "player": str(spec.get("player") or "vlc"),
            "player_args": [str(a) for a in (spec.get("player_args") or [])],
            "playlist_count": len(playlists),
        })
    return out
```

Add `import re` at the top.

**Step 4: Run tests**

```bash
cd omi-media && python3 -m pytest tests/test_discovery.py -q
```
Expected: PASS.

**Step 5: Commit**

```bash
git add omi-media/src/omi_media/discovery.py omi-media/tests/test_discovery.py
git commit -m "feat(media): discover categories from folders"
```

---

## Task 2: Resolve config as overrides only

**Files:**
- Modify: `omi-media/src/omi_media/config.py`
- Test: `omi-media/tests/test_cli.py` (covered in Task 3)

**Step 1: Replace `categories()` with `folder_overrides()`**

```python
def folder_overrides(cfg: dict) -> dict[str, dict]:
    """User overrides for folders under the root, keyed by config key.

    Only ``name``, ``player`` and ``player_args`` are meaningful; ``directory``
    is kept so an override can be matched to a folder by path. Units that do
    not exist on disk are ignored by discovery, not here.
    """
    root = effective_root(cfg)
    out: dict[str, dict] = {}
    for key, spec in (cfg.get("categories") or {}).items():
        item = dict(spec)
        item.setdefault("name", key)
        item.setdefault("player", "vlc")
        item.setdefault("player_args", [])
        for field in ("name", "directory"):
            if field in item:
                item[field] = str(item[field]).replace("{root}", root)
        out[str(key)] = item
    return out
```

Keep `DEFAULT_CATEGORIES` only if other code imports it; otherwise delete it and
`categories()`. **Check:** `grep -rn "DEFAULT_CATEGORIES\|cfg.categories\|categories(" omi-media/src omi-media/tests`.

**Step 2: Commit**

```bash
git add omi-media/src/omi_media/config.py
git commit -m "refactor(media): config supplies overrides, not the category list"
```

---

## Task 3: Point the CLI at discovery

**Files:**
- Modify: `omi-media/src/omi_media/cli.py:27-98`
- Test: `omi-media/tests/test_cli.py`

**Step 1: Update the failing CLI test**

In `_env`, drop the `Courses` expectation and assert it is hidden:

```python
    assert "courses" not in by_id          # empty folder is hidden
    assert by_id["video"]["player"] == "vlc"
    assert by_id["music"]["player"] == "mpv"
```

**Step 2: Run**

```bash
cd omi-media && python3 -m pytest tests/test_cli.py -q
```
Expected: FAIL (`courses` still present).

**Step 3: Implement**

```python
def _categories(args) -> list[dict]:
    from .discovery import discover_categories
    cfg_data = cfg.load_config(args.config)
    return discover_categories(
        cfg.effective_root(cfg_data), cfg.folder_overrides(cfg_data)
    )


def _find_category(args, cid: str) -> dict | None:
    return next((c for c in _categories(args) if c["id"] == cid), None)
```

`cmd_categories` uses `_categories(args)`. `cmd_playlists`/`cmd_play` replace
`cfg.categories(...).get(...)` with `_find_category(args, ...)` and read
`spec["directory"]`, `spec["player"]`, `spec["player_args"]` (keys unchanged).

**Step 4: Run the full suite**

```bash
cd omi-media && python3 -m pytest -q
```
Expected: PASS.

**Step 5: Commit**

```bash
git add omi-media/src/omi_media/cli.py omi-media/tests/test_cli.py
git commit -m "feat(media): CLI resolves categories from folders"
```

---

## Task 4: Keyboard zones in the popup

**Files:**
- Modify: `omi-media/integrations/dms/omintyMedia/OmintyMedia.qml`

**Step 1: Add zone state**

```qml
property string _zone: "filter"          // tabs | filter | list

function _setZone(z: string) {
    root._zone = z;
    if (z === "filter") searchField.forceActiveFocus();
    else if (z === "list") listView.forceActiveFocus();
    else tabsRow.forceActiveFocus();
}
function _cycleZone(delta: int) {
    const zs = ["tabs", "filter", "list"];
    root._setZone(zs[(zs.indexOf(root._zone) + delta + zs.length) % zs.length]);
}
function _moveCat(delta: int) {
    const i = root._categories.findIndex(c => c.id === root._activeCat);
    if (i < 0) return;
    const n = root._categories.length;
    root._selectCat(root._categories[(i + delta + n) % n].id);
}
function _moveItem(delta: int) {
    if (!root._filtered.length) return;
    const n = root._filtered.length;
    root._itemIndex = (root._itemIndex + delta + n) % n;
}
```

**Step 2: One key handler on the panel**

Replace the existing `Keys.onPressed` on `panelBg` with:

```qml
Keys.onPressed: event => {
    if (event.key === Qt.Key_Escape) { root._close(); event.accepted = true; return; }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        root._cycleZone(event.key === Qt.Key_Tab ? 1 : -1); event.accepted = true; return;
    }
    if (event.key === Qt.Key_BracketLeft && (event.modifiers & Qt.ControlModifier)) {
        root._moveCat(-1); event.accepted = true; return;
    }
    if (event.key === Qt.Key_BracketRight && (event.modifiers & Qt.ControlModifier)) {
        root._moveCat(1); event.accepted = true; return;
    }
    if (event.key === Qt.Key_Down) {
        if (root._zone === "tabs") root._moveCat(1); else root._moveItem(1);
        event.accepted = true; return;
    }
    if (event.key === Qt.Key_Up) {
        if (root._zone === "tabs") root._moveCat(-1); else root._moveItem(-1);
        event.accepted = true; return;
    }
    if (event.key === Qt.Key_Right) { root._moveCat(1); event.accepted = true; return; }
    if (event.key === Qt.Key_Left)  { root._moveCat(-1); event.accepted = true; return; }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root._zone === "tabs") root._setZone("list");
        else if (root._itemIndex >= 0 && root._itemIndex < root._filtered.length)
            root._play(root._filtered[root._itemIndex].name);
        event.accepted = true; return;
    }
    if (event.text.length === 1 && event.text.charCodeAt(0) >= 32
            && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        root._setZone("filter");
        searchField.text += event.text;
        event.accepted = true;
    }
}
```

**Step 3: Wire focus and the focus ring**

- `searchField`: `focus: root._zone === "filter"`, and remove its own
  `Keys.onPressed` (the panel handler now owns Up/Down/Enter).
- `tabsRow`: add `id: tabsRow; focus: root._zone === "tabs"; activeFocusOnTab: true`.
- `listView`: add `id: listView; focus: root._zone === "list"; activeFocusOnTab: true`.
- `panelBg.focus: true` stays, so the panel receives keys when no child has focus.
- Visual: tint the active zone's border with `Theme.primary` —
  tabs row `border.width/color` per zone, `searchBox.border.color`,
  and a 1 px `Rectangle` around the list `Item` shown when `_zone === "list"`.
- Clicking a zone sets it: `onClicked: root._setZone("tabs" | "filter" | "list")`
  on the existing MouseAreas.

**Step 4: Hint text**

```qml
text: "Tab switch focus · ↑/↓ select · ←/→ folder · Enter play · Esc close"
```

**Step 5: Verify by hand after `install.sh`**

Open with `Shift+Alt+M`; Tab must cycle tabs → filter → list with a visible
ring; arrows must move in each; typing from the list must jump to the filter.

**Step 6: Commit**

```bash
git add omi-media/integrations/dms/omintyMedia/OmintyMedia.qml
git commit -m "feat(media): tab and arrow navigation across zones"
```

---

## Task 5: Documentation and verification

**Files:**
- Modify: `docs/INSTALL.md`, `docs/NAMING.md` (key map), `omi-media/README.md`

**Step 1: Update the folder convention**

Replace "Drop playlist files into the matching folder: Audio/ Courses/ Music/
Video/" with: *any* subfolder of `~/Playlist` is a tab; a folder with no
playlist is hidden; the folder name is the tab name; `media.toml` can override
the player per folder.

**Step 2: Document the key map** in `NAMING.md` under Ominty Media and in
`omi-media/README.md`.

**Step 3: Full verification**

```bash
cd omi-media && python3 -m pytest -q
cd .. && ./scripts/verify-parity.py
./install.sh --dry-run
```

**Step 4: Commit and push**

```bash
git add docs omi-media
git commit -m "docs(media): folder convention and key map"
git push origin main
```

---

## Done when

- `omi-media categories --json` lists exactly the non-empty folders, alphabetically.
- Renaming `~/Playlist/Music` to `~/Playlist/02-Music` renames the tab and keeps it working.
- A folder with no playlist does not appear; adding one makes it appear on reopen.
- Tab cycles tabs → filter → list; arrows work in each; typing from the list jumps to the filter.
- `pytest`, `verify-parity.py` and a dry run all pass.
