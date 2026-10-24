import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Ominty Media — playlist launcher (DMS popup over the omi-media service).
//
// A **selector only**: category tabs → filter → choose a playlist.  Choosing
// one hands it to a separate player application (vlc/mpv, per media.toml) and
// the popup closes immediately.  The player is controlled in its own window
// and via the desktop's MPRIS media widget (the small pill), not here.
//
// Single surface (no full-screen dim) so the mouse reaches the list, tabs and
// close button.
//
// Keyboard: three focus zones (tabs → filter → list) cycled with Tab/Shift+Tab.
//   tabs:   ←/→ and ↑/↓ change folder, Enter moves to the list
//   filter: type to filter, ↑/↓ move the selection, Enter plays
//   list:   ↑/↓ move, Enter plays, ←/→ change folder, typing jumps to filter
// Esc closes; Ctrl+[ / Ctrl+] still cycle folders.  Click works everywhere.
PluginComponent {
    id: root

    property string _query: ""
    property var _categories: []
    property string _activeCat: ""
    property var _playlists: []
    property int _itemIndex: -1
    property bool _loading: false
    property string _error: ""
    property bool _visible: false
    property string _zone: "filter"       // tabs | filter | list

    readonly property string mediaCli: Quickshell.env("OMI_MEDIA_CLI") || "omi-media"

    function _setVisible(v: bool) {
        root._visible = v;
    }
    function _open() {
        root._setVisible(true);
        // Always re-scan: the folder tree is the configuration, so a folder
        // added while the popup was closed has to appear on reopen.
        root._loadCats();
        root._zone = "filter";
        panelBg.forceActiveFocus();
    }

    function _setZone(z: string) {
        root._zone = z;
        // The panel always holds the keys. A focused TextInput would swallow
        // Tab before our handler saw it, which is why keyboard navigation
        // cannot depend on per-control focus.
        panelBg.forceActiveFocus();
    }
    function _setQuery(q: string) {
        root._query = q;
        root._itemIndex = 0;
    }
    function _cycleZone(delta: int) {
        const zs = ["tabs", "filter", "list"];
        root._setZone(zs[(zs.indexOf(root._zone) + delta + zs.length) % zs.length]);
    }
    function _moveCat(delta: int) {
        if (root._categories.length === 0) return;
        const i = root._categories.findIndex(c => c.id === root._activeCat);
        const n = root._categories.length;
        root._selectCat(root._categories[((i < 0 ? 0 : i) + delta + n) % n].id);
    }
    function _moveItem(delta: int) {
        if (root._filtered.length === 0) return;
        const n = root._filtered.length;
        root._itemIndex = ((root._itemIndex < 0 ? 0 : root._itemIndex) + delta + n) % n;
        listView.positionViewAtIndex(root._itemIndex, ListView.Contain);
    }
    // One handler for the panel and the filter field, so Tab/arrows behave the
    // same wherever focus happens to be.
    function _handleKey(event) {
        if (event.key === Qt.Key_Escape) { root._close(); event.accepted = true; return; }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root._cycleZone(event.key === Qt.Key_Backtab ? -1 : 1);
            event.accepted = true; return;
        }
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_BracketLeft) { root._moveCat(-1); event.accepted = true; }
            else if (event.key === Qt.Key_BracketRight) { root._moveCat(1); event.accepted = true; }
            return;
        }
        if (event.key === Qt.Key_Down) {
            if (root._zone === "tabs") root._moveCat(1); else root._moveItem(1);
            event.accepted = true; return;
        }
        if (event.key === Qt.Key_Up) {
            if (root._zone === "tabs") root._moveCat(-1); else root._moveItem(-1);
            event.accepted = true; return;
        }
        if (root._zone !== "filter" && event.key === Qt.Key_Right) {
            root._moveCat(1); event.accepted = true; return;
        }
        if (root._zone !== "filter" && event.key === Qt.Key_Left) {
            root._moveCat(-1); event.accepted = true; return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root._zone === "tabs") root._setZone("list");
            else if (root._itemIndex >= 0 && root._itemIndex < root._filtered.length)
                root._play(root._filtered[root._itemIndex].name);
            event.accepted = true; return;
        }
        if (root._zone === "filter" && event.key === Qt.Key_Backspace) {
            root._setQuery(root._query.slice(0, -1));
            event.accepted = true; return;
        }
        // A printable key starts filtering from any zone.
        if (event.text && event.text.length === 1
                && event.text.charCodeAt(0) >= 32
                && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier))) {
            root._zone = "filter";
            root._setQuery(root._query + event.text);
            event.accepted = true;
        }
    }
    function _close() {
        root._setVisible(false);
    }
    function _loadCats() {
        catsProc.running = false;
        catsProc.running = true;
    }
    function _selectCat(id: string) {
        root._activeCat = id;
        root._setQuery("");
        root._loadPlaylists(id);
    }
    function _cycleCat(dir: int) {
        if (root._categories.length === 0) return;
        let i = root._categories.findIndex(c => c.id === root._activeCat);
        i = (i + dir + root._categories.length) % root._categories.length;
        root._selectCat(root._categories[i].id);
    }
    function _loadPlaylists(id: string) {
        root._loading = true;
        root._error = "";
        listProc.running = false;
        listProc.command = [root.mediaCli, "playlists", id, "--json"];
        listProc.running = true;
    }
    // Hand the playlist to its player, then get out of the way.
    function _play(name: string) {
        if (name === "") return;
        playProc.running = false;
        playProc.command = [root.mediaCli, "play", root._activeCat, name];
        playProc.running = true;
    }

    on_FilteredChanged: root._itemIndex = root._filtered.length
        ? Math.min(Math.max(root._itemIndex, 0), root._filtered.length - 1)
        : -1

    // Client-side filter over the (already discovered) playlist list.
    readonly property var _filtered: {
        const q = root._query.trim().toLowerCase();
        if (q === "") return root._playlists;
        return root._playlists.filter(p => String(p.title).toLowerCase().includes(q));
    }

    function _activeCatName(): string {
        for (let c of root._categories) if (c.id === root._activeCat) return c.name;
        return "";
    }

    // ---- IPC ---------------------------------------------------------------
    IpcHandler {
        target: "omintyMedia"
        function open(): string { root._open(); return "opened" }
        function toggle(): string { if (root._visible) { root._close(); return "closed" } root._open(); return "opened" }
        function close(): string { root._close(); return "closed" }
        function openCategory(id: string): string { root._open(); root._selectCat(id); return "opened" }
        // Observable state for tests and scripts (zone, selection, filter).
        function status(): string {
            return JSON.stringify({
                visible: root._visible,
                zone: root._zone,
                category: root._activeCat,
                categories: root._categories.length,
                itemIndex: root._itemIndex,
                filtered: root._filtered.length,
                query: root._query
            });
        }
    }

    // ---- omi-media processes -----------------------------------------------
    Process {
        id: catsProc
        command: [root.mediaCli, "categories", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root._categories = (data.categories || []).map(c => ({
                        id: c.id, name: c.name, count: c.playlist_count
                    }));
                    if (root._categories.length === 0) {
                        root._activeCat = "";
                        root._error = "No folders with playlists — add .m3u files under ~/Playlist";
                        return;
                    }
                    const keep = root._categories.find(c => c.id === root._activeCat);
                    root._selectCat(keep ? keep.id : root._categories[0].id);
                } catch (e) {
                    console.warn("[omintyMedia] category list parse failed:", e);
                    root._error = "Could not read categories (omi-media categories)";
                }
            }
        }
    }

    Process {
        id: listProc
        command: [root.mediaCli, "playlists", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root._loading = false;
                try {
                    const data = JSON.parse(text);
                    root._playlists = (data.playlists || []).map(p => ({
                        name: p.name, title: p.title
                    }));
                    root._itemIndex = root._filtered.length ? 0 : -1;
                } catch (e) {
                    root._playlists = [];
                    root._error = "Could not read playlist list";
                }
            }
        }
    }

    Process {
        id: playProc
        running: false
        stdout: StdioCollector {
            // oi-media prints "launched: …" on success and exits — at that
            // point remove the popup so the player window is not left hidden.
            onStreamFinished: root._close()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") root._error = text.trim();
            }
        }
    }

    // ---- The panel (single surface) ----------------------------------------
    PanelWindow {
        id: overlay
        visible: root._visible
        color: "transparent"
        WlrLayershell.namespace: "ominty:media"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        readonly property int pw: Math.min(660, (overlay.screen ? overlay.screen.width : 1920) - 80)
        readonly property int ph: Math.min(600, (overlay.screen ? overlay.screen.height : 1080) - 80)
        readonly property int mh: Math.max(0, Math.round(((overlay.screen ? overlay.screen.width : 1920) - pw) / 2))
        readonly property int mv: Math.max(0, Math.round(((overlay.screen ? overlay.screen.height : 1080) - ph) / 2))
        anchors { top: true; bottom: true; left: true; right: true }
        margins { left: overlay.mh; right: overlay.mh; top: overlay.mv; bottom: overlay.mv }

        Rectangle {
            id: panelBg
            anchors.fill: parent
            radius: 12
            color: Theme.withAlpha(Theme.surface, 0.94)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.5)
            focus: true
            Keys.onPressed: event => root._handleKey(event)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    StyledText {
                        text: "Ominty Media"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 30; height: 30; radius: 15; color: "#45475a"
                        Text { anchors.centerIn: parent; text: "\u00D7"; color: "#cdd6f4"; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; onClicked: root._close() }
                    }
                }

                // Category tabs (persistent; always clickable)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS
                    Repeater {
                        model: root._categories
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: modelData.id === root._activeCat
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 8
                            color: active ? Theme.primary : "transparent"
                            border.width: active ? 0 : 1
                            border.color: root._zone === "tabs" ? Theme.primary : Theme.outline
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingS
                                StyledText {
                                    text: modelData.name
                                    color: active ? "black" : Theme.surfaceText
                                    font.weight: active ? Font.Bold : Font.Normal
                                }
                                Item { Layout.fillWidth: true }
                                StyledText { text: modelData.count; color: active ? "black" : Theme.surfaceVariantText }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { root._setZone("tabs"); root._selectCat(modelData.id); }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 2
                    radius: 1
                    color: root._zone === "tabs" ? Theme.primary : "transparent"
                }

                // Search box
                Rectangle {
                    id: searchBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 6
                    color: "transparent"
                    border.width: root._zone === "filter" ? 2 : 1
                    border.color: root._zone === "filter" ? Theme.primary : Theme.outline

                    StyledText {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: (root._query === ""
                                ? "Filter " + root._activeCatName() + "…"
                                : root._query)
                              + (root._zone === "filter" ? "\u258F" : "")
                        color: root._query === "" ? Theme.surfaceVariantText : "white"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root._setZone("filter")
                    }
                }

                // Playlist list (client-side filtered)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    StyledText {
                        anchors.centerIn: parent
                        visible: root._loading || root._error !== "" || root._filtered.length === 0
                        width: parent.width - 20
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        text: root._loading ? "Scanning…"
                            : (root._error !== "" ? root._error
                                : (root._playlists.length ? "No playlists match" : "No playlists in this folder"))
                        color: root._error !== "" ? "#f38ba8" : Theme.surfaceVariantText
                    }

                    ListView {
                        id: listView
                        anchors.fill: parent
                        visible: root._filtered.length > 0 && !root._loading && root._error === ""
                        clip: true
                        spacing: 2
                        currentIndex: root._itemIndex
                        model: root._filtered
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            width: ListView.view.width
                            height: 34
                            radius: 6
                            color: index === root._itemIndex ? Theme.primary : "transparent"
                            StyledText {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.title
                                elide: Text.ElideMiddle
                                color: index === root._itemIndex ? "black" : Theme.surfaceText
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { root._setZone("list"); root._play(modelData.name); }
                            }
                        }
                        onCountChanged: root._itemIndex = Math.min(Math.max(root._itemIndex, 0), Math.max(count - 1, -1))
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: 6
                        border.width: root._zone === "list" ? 1 : 0
                        border.color: Theme.primary
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Tab switch focus · ↑/↓ select · ←/→ folder · Enter play · Esc close"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 11
                }
            }
        }
    }
}