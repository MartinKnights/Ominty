import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Ominty Playlist Selector — DMS popup over the omi-media service.
//
// A **selector only**: category tabs → filter → choose a playlist.  Choosing
// one hands it to a separate player application (vlc/mpv, per media.toml) and
// the popup closes immediately.  The player is controlled in its own window
// and via the desktop's MPRIS media widget (the small pill), not here.
//
// Single surface (no full-screen dim) so the mouse reaches the list, tabs and
// close button.  Keyboard: type → filter → ↑/↓ → Enter (play), Ctrl+[ / Ctrl+]
// switch category, Esc close.  Click works everywhere.
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

    readonly property string mediaCli: Quickshell.env("OMI_MEDIA_CLI") || "omi-media"

    function _setVisible(v: bool) {
        root._visible = v;
    }
    function _open() {
        root._setVisible(true);
        if (root._categories.length === 0) root._loadCats();
        searchField.forceActiveFocus();
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
        root._query = "";
        searchField.text = "";
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
                    if (root._activeCat === "") {
                        const first = root._categories.find(c => c.count > 0) || root._categories[0];
                        if (first) root._selectCat(first.id);
                    }
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
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root._close(); event.accepted = true;
                } else if (event.key === Qt.Key_BracketLeft && (event.modifiers & Qt.ControlModifier)) {
                    root._cycleCat(-1); event.accepted = true;
                } else if (event.key === Qt.Key_BracketRight && (event.modifiers & Qt.ControlModifier)) {
                    root._cycleCat(1); event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    StyledText {
                        text: "Ominty Playlist Selector"
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
                            border.color: Theme.outline
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
                                onClicked: root._selectCat(modelData.id)
                            }
                        }
                    }
                }

                // Search box
                Rectangle {
                    id: searchBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 6
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.outline

                    TextInput {
                        id: searchField
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        verticalAlignment: TextInput.AlignVCenter
                        color: "white"
                        onTextChanged: {
                            root._query = searchField.text;
                            root._itemIndex = root._filtered.length ? 0 : -1;
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (root._itemIndex >= 0 && root._itemIndex < root._filtered.length) {
                                    root._play(root._filtered[root._itemIndex].name);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && root._filtered.length) {
                                root._itemIndex = (root._itemIndex + 1) % root._filtered.length;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && root._filtered.length) {
                                root._itemIndex = (root._itemIndex - 1 + root._filtered.length) % root._filtered.length;
                                event.accepted = true;
                            }
                        }
                    }

                    StyledText {
                        visible: searchField.text === ""
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Filter " + root._activeCatName() + "…  (↓/↑ · Enter play)"
                        color: Theme.surfaceVariantText
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: searchField.forceActiveFocus()
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
                                onClicked: root._play(modelData.name)
                            }
                        }
                        onCountChanged: root._itemIndex = Math.min(Math.max(root._itemIndex, 0), Math.max(count - 1, -1))
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "type to filter · ↑/↓ · Enter play · Ctrl+[ ] category · Esc close"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 11
                }
            }
        }
    }
}