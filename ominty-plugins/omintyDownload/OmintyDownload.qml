import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Ominty Download Manager — native DMS plugin (daemon + overlay).
//
// Talks to a per-user aria2 RPC daemon through the helpers/ominty-dl.py
// contract (same pattern as the reader's backend): the QML holds no logic.
//
// Interaction: Ctrl+Shift+D (or IPC) opens the overlay → add a URL → the
// queue lists each download with name, status, progress and speed; pause /
// resume / remove per row; Esc closes.
PluginComponent {
    id: root

    pluginId: "omintyDownload"
    pluginService: PluginService

    readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
    readonly property string _b: "python3"
    readonly property string _p: pluginDir + "/helpers/ominty-dl.py"

    property var items: []
    property string notice: ""
    property string addText: ""
    property bool panelVisible: false
    property bool starting: false

    Timer {
        id: refreshTimer
        interval: 2000
        repeat: true
        onTriggered: root.refresh()
    }

    function dbg(m) { console.error("[omintyDownload] " + m) }

    // --------------------------------------------------------------- panel
    function toggle() { if (panelVisible) closePanel(); else openPanel() }
    function openPanel() {
        panelVisible = true
        refreshTimer.start()
        if (!starting) ensureRunning()
    }
    function closePanel() { panelVisible = false; refreshTimer.stop() }

    function ensureRunning() {
        starting = true
        startProc.running = false
        startProc.command = [root._b, root._p, "start"]
        startProc.running = true
    }
    function refresh() {
        listProc.running = false
        listProc.command = [root._b, root._p, "list"]
        listProc.running = true
    }
    function addUrl(text) {
        var url = String(text || "").trim()
        if (!/^https?:\/\//i.test(url)) { notice = "Enter a valid http(s) URL"; return }
        addText = ""
        addProc.running = false
        addProc.command = [root._b, root._p, "add", url]
        addProc.running = true
    }
    function runOp(op, gid) {
        notice = ""
        opProc.running = false
        opProc.command = [root._b, root._p, op, gid]
        opProc.running = true
    }

    // --------------------------------------------------------------- ipc
    IpcHandler {
        target: "omintyDownload"
        function toggle(): string { root.toggle(); return root.panelVisible ? "opened" : "closed" }
        function open(): string { root.openPanel(); return "opened" }
        function close(): string { root.closePanel(); return "closed" }
        function add(url: string): string { root.addUrl(url); return "ok" }
    }

    // ----------------------------------------------------------- backend
    Process {
        id: startProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.starting = false
                try { var d = JSON.parse(text); if (d.error) root.notice = String(d.error) } catch (e) {}
                root.refresh()
            }
        }
        stderr: StdioCollector {
            onStreamFinished: { root.starting = false; if (text.trim() !== "") root.notice = text.trim() }
        }
    }

    Process {
        id: listProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    if (d.error) { root.notice = String(d.error); return }
                    root.items = d.items || []
                    root.notice = ""
                } catch (e) { root.notice = "Could not read aria2 status" }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: { if (text.trim() !== "") root.notice = text.trim() }
        }
    }

    Process {
        id: addProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try { var d = JSON.parse(text); if (d.error) root.notice = String(d.error) } catch (e) {}
                root.refresh()
            }
        }
    }

    Process {
        id: opProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try { var d = JSON.parse(text); if (d.error) root.notice = String(d.error) } catch (e) {}
                root.refresh()
            }
        }
    }

    // ------------------------------------------------------------ overlay
    // No click-outside-to-close on the dim: DMS delivers a ghost click to
    // full-screen dims shortly after an exclusive-keyboard overlay mounts,
    // which used to drop the panel. Esc / × / hotkey close it instead.
    PanelWindow {
        id: dimWindow
        visible: root.panelVisible
        color: "transparent"
        WlrLayershell.namespace: "ominty:download-dim"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        anchors { top: true; bottom: true; left: true; right: true }
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
        }
    }

    PanelWindow {
        id: overlay
        visible: root.panelVisible
        color: "transparent"
        WlrLayershell.namespace: "ominty:download"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        readonly property int pw: Math.min(680, (overlay.screen ? overlay.screen.width : 1920) - 80)
        readonly property int ph: Math.min(620, (overlay.screen ? overlay.screen.height : 1080) - 80)
        readonly property int mh: Math.max(0, Math.round(((overlay.screen ? overlay.screen.width : 1920) - pw) / 2))
        readonly property int mv: Math.max(0, Math.round(((overlay.screen ? overlay.screen.height : 1080) - ph) / 2))
        anchors { top: true; bottom: true; left: true; right: true }
        margins { left: overlay.mh; right: overlay.mh; top: overlay.mv; bottom: overlay.mv }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.withAlpha(Theme.surface, 0.92)
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { root.closePanel(); event.accepted = true; }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                // header + add URL
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    StyledText {
                        text: "Downloads"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }
                    StyledText { text: "aria2 · local"; color: Theme.surfaceVariantText }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 28; height: 28; radius: 14; color: "#45475a"
                        Text { anchors.centerIn: parent; text: "\u00D7"; color: "#cdd6f4"; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; onClicked: root.closePanel() }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 6
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.outline
                        TextInput {
                            id: urlField
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            verticalAlignment: TextInput.AlignVCenter
                            color: "white"
                            text: root.addText
                            onAccepted: root.addUrl(text)
                            onTextChanged: root.addText = text
                        }
                        StyledText {
                            visible: urlField.text === ""
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Paste a URL and press Enter…"
                            color: Theme.surfaceVariantText
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 84
                        Layout.preferredHeight: 38
                        radius: 6
                        color: Theme.primary
                        StyledText {
                            anchors.centerIn: parent
                            text: "Add"
                            color: "black"
                            font.weight: Font.Bold
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.addUrl(urlField.text) }
                    }
                }

                // queue
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.items.length === 0
                        text: root.starting ? "Starting aria2…" : (root.notice !== "" ? root.notice : "No downloads yet.")
                        color: root.notice !== "" ? "#f38ba8" : Theme.surfaceVariantText
                    }

                    ListView {
                        anchors.fill: parent
                        visible: root.items.length > 0
                        clip: true
                        spacing: 4
                        model: root.items
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 64
                            radius: 8
                            color: Theme.withAlpha(Theme.surfaceVariant, 0.25)
                            property real pct: (modelData.total > 0) ? (modelData.completed * 100 / modelData.total) : 0

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name || modelData.gid
                                        elide: Text.ElideMiddle
                                        color: Theme.surfaceText
                                        font.weight: Font.Bold
                                    }
                                    StyledText {
                                        text: modelData.status
                                        color: modelData.status === "active" ? Theme.primary
                                             : modelData.status === "error" ? "#f38ba8"
                                             : (modelData.status === "complete" ? "#a6e3a1" : Theme.surfaceVariantText)
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingM
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: Theme.withAlpha(Theme.surfaceVariant, 0.6)
                                        Rectangle {
                                            width: parent.width * pct / 100
                                            height: parent.height
                                            radius: 3
                                            color: Theme.primary
                                        }
                                    }
                                    StyledText {
                                        text: (pct.toFixed(1)) + "%  ·  "
                                            + Math.round(modelData.speed / 1024) + " KiB/s"
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: 11
                                    }
                                    StyledText {
                                        text: modelData.status === "paused" ? "Resume" : "Pause"
                                        color: Theme.surfaceText
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.runOp(modelData.status === "paused" ? "resume" : "pause", modelData.gid)
                                    }
                                    StyledText { text: "\u2715"; color: Theme.surfaceText }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.runOp("remove", modelData.gid)
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Enter to add · Pause/Resume · ✕ remove · Esc close"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 11
                }
            }
        }
    }
}