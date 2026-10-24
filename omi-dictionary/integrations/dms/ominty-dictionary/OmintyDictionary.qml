import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Ominty Dictionary — DMS popup over the omi-dict service
// (Omi Dictionary Service spec §14–§18, §21).
//
// Holds NO lookup logic: it shells out to `omi-dict` (the contract) and
// renders the JSON.  Keyboard-first: Ctrl+L search, ↑/↓ candidates, Enter
// lookup, Ctrl+[ / Ctrl+] cycle dictionaries, Esc close.
//
// TWO layer surfaces on purpose:
//   - dimWindow   (ominty:dictionary-dim)  fullscreen dim backdrop + click
//                 outside to dismiss.  NOT matched by the blur layer-rule.
//   - overlay     (ominty:dictionary)      the panel, centered via 4-anchor
//                 margins so the composer blurs ONLY the panel footprint.

PluginComponent {
    id: root

    property string _query: ""
    property var _dicts: []
    property int _dictIndex: 0
    property var _candidates: []
    property int _candidateIndex: -1
    property var _result: null
    property bool _loading: false
    property string _error: ""

    readonly property string dictCli: Quickshell.env("OMI_DICT_CLI") || "omi-dict"

    readonly property var _selector: {
        const all = root._dicts.map(d => ({ "id": d.id, "name": d.name }));
        all.push({ "id": "*all*", "name": "All Dictionaries" });
        return all;
    }

    function _dictId() {
        if (root._dictIndex >= 0 && root._dictIndex < root._dicts.length)
            return root._dicts[root._dictIndex].id;
        return "*all*";
    }
    function _dictName() {
        return root._selector.length ? root._selector[root._dictIndex].name : "…";
    }

    // Show/hide both surfaces together.
    function _setVisible(v: bool) {
        dimWindow.visible = v;
        overlay.visible = v;
    }
    function _open() {
        root._setVisible(true);
        root._loadDicts();
        searchField.forceActiveFocus();
    }
    function _close() {
        root._setVisible(false);
    }

    // Rich-text body for the current result (structure: paragraphs, senses,
    // emphasis — colours stripped so it follows the active theme).
    readonly property string _displayHtml: {
        if (!root._result) return "";
        if (root._result.results) {
            return root._result.results.map(function (r, i) {
                const marker = i === 0 ? "\u25BC " : "\u25B6 ";
                return "<b>" + marker + r.dictionary.name + "</b><br>"
                    + (r.entry.display || r.entry.text || "");
            }).join("<br><br>");
        }
        return root._result.entry ? (root._result.entry.display || root._result.entry.text || "") : "";
    }

    // ---- IPC ------------------------------------------------------------
    IpcHandler {
        target: "omintyDictionary"

        function open(): string {
            root._open();
            return "opened";
        }
        function openWith(word: string): string {
            root._open();
            root._query = word.trim();
            searchField.text = root._query;
            root._lookup(root._query);
            return "opened";
        }
        function toggle(): string {
            if (overlay.visible) { root._close(); return "closed"; }
            root._open();
            return "opened";
        }
        function close(): string {
            root._close();
            return "closed";
        }
    }

    function _loadDicts() {
        dictsProc.running = false;
        dictsProc.running = true;
    }

    function _lookup(word: string) {
        const w = word.trim();
        root._query = w;
        if (w === "") { root._result = null; root._error = ""; return; }
        root._loading = true;
        root._error = "";
        lookupProc.running = false;
        const args = [root.dictCli, "lookup", w, "--json"];
        if (root._dictId() === "*all*") args.push("--all");
        else args.push("--dictionary", root._dictId());
        lookupProc.command = args;
        lookupProc.running = true;
    }

    function _search(prefix: string) {
        const p = prefix.trim();
        if (p.length < 2) { root._candidates = []; root._candidateIndex = -1; return; }
        searchProc.running = false;
        searchProc.command = [root.dictCli, "search", p, "--json", "--limit", "30"];
        searchProc.running = true;
    }

    function _friendlyError(obj) {
        const code = String((obj && obj.error) || "OMI_DICT_ERROR");
        if (code === "NO_ENTRY_FOUND") return "No entry found";
        if (code === "DICTIONARY_UNAVAILABLE" || code === "DICTIONARY_INDEX_REQUIRES_REBUILDING")
            return "Dictionary unavailable — index may need rebuilding (omi-dict import)";
        return "Dictionary lookup failed";
    }

    Process {
        id: dictsProc
        command: [root.dictCli, "dictionaries", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root._dicts = data.dictionaries || [];
                    if (root._dictIndex >= root._dicts.length) root._dictIndex = 0;
                } catch (e) { console.warn("[omintyDictionary] dict list parse failed:", e); }
            }
        }
    }

    Process {
        id: lookupProc
        command: [root.dictCli, "lookup", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root._loading = false;
                try {
                    const data = JSON.parse(text);
                    if (data.error) { root._result = null; root._error = root._friendlyError(data); }
                    else { root._result = data; root._error = ""; }
                } catch (e) {
                    root._result = null;
                    root._error = "Dictionary response could not be read";
                }
            }
        }
    }

    Process {
        id: searchProc
        command: [root.dictCli, "search", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root._candidates = (data && data.headwords) || [];
                    root._candidateIndex = root._candidates.length ? 0 : -1;
                } catch (e) { root._candidates = []; }
            }
        }
    }

    Timer {
        id: debounce
        interval: 200
        repeat: false
        onTriggered: root._search(searchField.text)
    }

    // ---- Surface 1: fullscreen dim + click-outside ----------------------
    PanelWindow {
        id: dimWindow
        visible: false
        color: "transparent"

        WlrLayershell.namespace: "ominty:dictionary-dim"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1

        anchors { top: true; bottom: true; left: true; right: true }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
            MouseArea {
                anchors.fill: parent
                onClicked: root._close()
            }
        }
    }

    // ---- Surface 2: the blurred panel (centered by 4-anchor margins) ----
    PanelWindow {
        id: overlay
        visible: false
        color: "transparent"

        WlrLayershell.namespace: "ominty:dictionary"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // Panel is the screen minus symmetric margins → centered, so the
        // composer's blur (layer-rule ominty:dictionary) covers the panel
        // and nothing else.
        readonly property int pw: Math.min(940, (overlay.screen ? overlay.screen.width : 1920) - 80)
        readonly property int ph: Math.min(700, (overlay.screen ? overlay.screen.height : 1080) - 80)
        readonly property int mh: Math.max(0, Math.round(((overlay.screen ? overlay.screen.width : 1920) - pw) / 2))
        readonly property int mv: Math.max(0, Math.round(((overlay.screen ? overlay.screen.height : 1080) - ph) / 2))

        anchors { top: true; bottom: true; left: true; right: true }
        margins { left: overlay.mh; right: overlay.mh; top: overlay.mv; bottom: overlay.mv }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root._close(); event.accepted = true;
            } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                searchField.forceActiveFocus(); event.accepted = true;
            } else if (event.key === Qt.Key_BracketLeft && (event.modifiers & Qt.ControlModifier)) {
                root._dictIndex = (root._dictIndex - 1 + root._selector.length) % root._selector.length;
                if (root._query) root._lookup(root._query);
                event.accepted = true;
            } else if (event.key === Qt.Key_BracketRight && (event.modifiers & Qt.ControlModifier)) {
                root._dictIndex = (root._dictIndex + 1) % root._selector.length;
                if (root._query) root._lookup(root._query);
                event.accepted = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.withAlpha(Theme.surface, 0.8)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    StyledText {
                        text: "Ominty Dictionary"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }
                    StyledText { text: "local · offline"; color: Theme.surfaceVariantText }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 30; height: 30; radius: 15; color: "#45475a"
                        Text { anchors.centerIn: parent; text: "\u00D7"; color: "#cdd6f4"; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; onClicked: root._close() }
                    }
                }

                // Search + dictionary selector
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM

                    Rectangle {
                        id: searchBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 6
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.outline
                        clip: false

                        TextInput {
                            id: searchField
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            verticalAlignment: TextInput.AlignVCenter
                            color: "white"
                            text: root._query
                            clip: false
                            onTextChanged: { root._query = searchField.text; debounce.restart(); }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    const w = (root._candidateIndex >= 0 && root._candidateIndex < root._candidates.length)
                                        ? root._candidates[root._candidateIndex] : searchField.text;
                                    root._candidates = [];
                                    root._lookup(w);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down && root._candidates.length) {
                                    root._candidateIndex = (root._candidateIndex + 1) % root._candidates.length;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up && root._candidates.length) {
                                    root._candidateIndex = (root._candidateIndex - 1 + root._candidates.length) % root._candidates.length;
                                    event.accepted = true;
                                }
                            }
                        }

                        StyledText {
                            visible: searchField.text === ""
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Define…  (↑/↓ candidates · Enter lookup)"
                            color: Theme.surfaceVariantText
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: searchField.forceActiveFocus()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 230
                        Layout.preferredHeight: 38
                        radius: 6
                        border.width: 1
                        border.color: Theme.outline
                        color: "transparent"
                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 40
                            elide: Text.ElideRight
                            text: root._dictName()
                            color: Theme.surfaceText
                        }
                        StyledText {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u25BE"
                            color: Theme.surfaceVariantText
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root._dictIndex = (root._dictIndex + 1) % root._selector.length;
                                if (root._query) root._lookup(root._query);
                            }
                        }
                    }
                }

                // Candidate list (interactive search)
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(170, root._candidates.length * 30)
                    visible: root._candidates.length > 0 && !root._loading
                    clip: true
                    spacing: 2
                    model: root._candidates
                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        width: ListView.view.width
                        height: 30
                        radius: 4
                        color: index === root._candidateIndex ? Theme.primary : "transparent"
                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            color: index === root._candidateIndex ? "black" : Theme.surfaceText
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { root._candidates = []; root._lookup(modelData); }
                        }
                    }
                }

                // Result
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledText {
                        anchors.centerIn: parent
                        visible: root._loading || root._error !== "" || root._displayHtml === ""
                        width: parent.width - 20
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        text: root._loading ? "Looking up…"
                            : (root._error !== "" ? root._error
                                : "Select a word and press Ctrl+Shift+A, or type to search.")
                        color: root._error !== "" ? "#f38ba8" : Theme.surfaceVariantText
                    }

                    Flickable {
                        id: resultFlick
                        anchors.fill: parent
                        visible: root._displayHtml !== "" && root._error === "" && !root._loading
                        clip: true
                        contentWidth: width
                        contentHeight: resultText.height

                        Text {
                            id: resultText
                            width: resultFlick.width
                            textFormat: Text.RichText
                            wrapMode: Text.WordWrap
                            text: root._displayHtml
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            lineHeight: 1.15
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Ctrl+L search field · ↑/↓ candidates · Enter lookup · Ctrl+[ ] dictionaries · Esc close"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 11
                }
            }
        }
    }
}