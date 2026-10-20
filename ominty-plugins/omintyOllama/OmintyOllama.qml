import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Ominty Ollama Manager — native DMS plugin (daemon + overlay).
//
// Manages the local Ollama installation through the helpers/ominty-ollama.py
// contract (QML holds no logic, same pattern as omintyDownload): status,
// list/pull/remove models with live pull progress, model details, quick chat,
// systemd server control (user unit preferred; system unit falls back to
// pkexec → DMS polkit dialog), GPU check and backup/restore of the models
// directory.
//
// Interaction: IPC (or palette action omintyOllama toggle) opens the overlay;
// three tabs — Models / Server / Backup; Esc closes.
PluginComponent {
    id: root

    pluginId: "omintyOllama"
    pluginService: PluginService

    readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
    readonly property string _b: "python3"
    readonly property string _p: pluginDir + "/helpers/ominty-ollama.py"

    property var status: ({})
    property var models: []
    property var backups: []
    property string view: "models"          // models | server | backup
    property string subview: ""             // "" | chat | details
    property string detailsText: ""
    property string detailsModel: ""
    property string chatModel: ""
    property string chatLog: ""
    property string promptText: ""

    property bool pulling: false
    property real pullPct: 0
    property string pullLine: ""
    property string pullModel: ""

    property bool busyChat: false
    property bool busyGpu: false
    property bool busySvc: false
    property bool busyBackup: false
    property string restoreConfirm: ""

    property string notice: ""
    property bool noticeErr: false
    property bool panelVisible: false

    function dbg(m) { console.error("[omintyOllama] " + m) }
    function say(msg, err) {
        notice = msg
        noticeErr = err === true
    }
    function notify(title, body, err) {
        // visible even with the panel closed (svc flow closed it)
        notifProc.running = false
        notifCmd = ["/usr/bin/notify-send", "-a", "Ollama Manager",
                    (err ? "-u" : "-t"), (err ? "critical" : "normal"),
                    "Ollama Manager — " + title, body]
        notifProc.command = notifCmd
        notifProc.running = true
        say(body, err)
    }

    // --------------------------------------------------------------- panel
    function toggle() { if (panelVisible) closePanel(); else openPanel() }
    function openPanel() {
        panelVisible = true
        say("")
        refresh()
        refreshBackups()
        refreshTimer.start()
    }
    function closePanel() { panelVisible = false; refreshTimer.stop() }

    function refresh() {
        run(statusProc, [root._b, root._p, "status"])
        run(listProc, [root._b, root._p, "list"])
    }
    function refreshBackups() { run(backupListProc, [root._b, root._p, "backups"]) }

    function run(proc, cmd) { proc.running = false; proc.command = cmd; proc.running = true }
    function pull(name) {
        var m = String(name || pullField.text || "").trim()
        if (m === "") { say("Enter a model name to pull", true); return }
        pullField.text = ""
        pulling = true; pullModel = m; pullPct = 0; pullLine = "Contacting registry…"
        dbg("pull: " + m)
        pullProc.running = false
        pullProc.command = [root._b, root._p, "pull", m]
        pullProc.running = true
    }
    function removeModel(name) {
        dbg("remove: " + name)
        run(rmProc, [root._b, root._p, "rm", name])
    }
    function openDetails(name) {
        dbg("details: " + name)
        detailsModel = name; subview = "details"; detailsText = "Loading…"
        run(showProc, [root._b, root._p, "show", name])
    }
    function openChat(name) {
        dbg("chat: " + name)
        chatModel = name; subview = "chat"; chatLog = "Starting " + name + "…\n\n"
        promptField.focus = true
    }
    function sendChat() {
        if (promptText.trim() === "" || busyChat) return
        chatLog += "You: " + promptText.trim() + "\n\n…Starting " + chatModel + " (may take a while on first load)…\n"
        run(chatProc, [root._b, root._p, "chat", chatModel, promptText.trim()])
        promptText = ""
        busyChat = true
    }
    function svc(action) {
        dbg("svc: " + action)
        // Close the panel first: it holds an exclusive keyboard layer that
        // would cover the polkit auth dialog pkexec is about to raise. The
        // helper keeps running (svcProc is daemon-level); a desktop
        // notification reports the outcome.
        if (panelVisible) closePanel()
        busySvc = true
        run(svcProc, [root._b, root._p, "svc", action])
    }
    function gpuCheck() {
        dbg("gpu check")
        busyGpu = true; say("GPU check: loading the smallest model…")
        run(gpuProc, [root._b, root._p, "gpu"])
    }
    function backupNow() {
        dbg("backup now")
        busyBackup = true
        say("Creating backup…")
        run(backupProc, [root._b, root._p, "backup"])
    }
    function restore(name) {
        dbg("restore: " + name)
        busyBackup = true
        run(restoreProc, [root._b, root._p, "restore", name])
    }

    function popLastJson(t) {
        var lines = String(t).trim().split("\n")
        for (var i = lines.length - 1; i >= 0; i--) {
            var s = lines[i].trim()
            if (s.charAt(0) === "{") return s
        }
        return "{}"
    }

    // --------------------------------------------------------------- ipc
    IpcHandler {
        target: "omintyOllama"
        function toggle(): string { root.toggle(); return root.panelVisible ? "opened" : "closed" }
        function open(): string { root.openPanel(); return "opened" }
        function close(): string { root.closePanel(); return "closed" }
        function pull(model: string): string { root.openPanel(); root.pull(model); return "ok" }
        function view(view: string): string { root.view = view; root.openPanel(); return "ok" }
    }

    // ----------------------------------------------------------- backend
    property var notifCmd: []

    Process {
        id: notifProc
        running: false
        command: notifCmd
    }

    Timer {
        id: refreshTimer
        interval: 4000
        repeat: true
        onTriggered: { if (!root.pulling && !root.busyChat) root.refresh() }
    }

    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(root.popLastJson(text))
                    if (d.err) root.say(d.err, true)
                    else root.status = d
                } catch (e) { root.dbg("status parse: " + e) }
            }
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(root.popLastJson(text))
                    if (d.err) root.say(d.err, true); else root.models = d.models || []
                } catch (e) { root.dbg("list parse: " + e) }
            }
        }
    }

    Process {
        id: pullProc
        stdout: SplitParser {
            onRead: data => {
                var s = String(data).trim()
                if (s === "") return
                try {
                    var d = JSON.parse(s)
                    if (d.ev === "p") { root.pullPct = d.pct; root.pullLine = d.line }
                    else if (d.ev === "done") {
                        root.pulling = false
                        if (d.err) { root.say("Pull failed: " + d.err, true) }
                        else root.say("Model pulled: " + root.pullModel)
                        root.refresh()
                    }
                } catch (e) { root.dbg("pull line: " + e) }
            }
        }
    }

    Process {
        id: rmProc
        stdout: StdioCollector {
            onStreamFinished: {
                var d = JSON.parse(root.popLastJson(text))
                if (d.err) root.say(d.err, true)
                else { root.say("Model removed"); root.refresh() }
            }
        }
    }

    Process {
        id: showProc
        stdout: StdioCollector {
            onStreamFinished: {
                var d = JSON.parse(root.popLastJson(text))
                if (d.err) { root.detailsText = "Error: " + d.err }
                else root.detailsText = d.details
            }
        }
    }

    Process {
        id: chatProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busyChat = false
                var d = JSON.parse(root.popLastJson(text))
                if (d.err) root.chatLog += "\n— " + d.err
                else root.chatLog += "\n" + root.chatModel + ": " + d.response + "\n\n"
            }
        }
        onExited: root.busyChat = false
    }

    Process {
        id: gpuProc
        onExited: root.busyGpu = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.busyGpu = false
                var d = JSON.parse(root.popLastJson(text))
                if (d.ev === "done") {
                    if (d.gpuState === "gpu") root.say("GPU in use: " + d.pct + "% of " + d.model + " offloaded to VRAM (" + d.processor + ")", false)
                    else if (d.gpuState === "mixed") root.say("Mixed CPU/GPU: " + d.pct + "% on GPU (" + d.processor + ")", true)
                    else root.say("CPU only — no clear GPU usage detected (" + d.processor + ")", true)
                } else root.say(d.err || "", true)
            }
        }
    }

    Process {
        id: svcProc
        onExited: root.busySvc = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.busySvc = false
                var d = JSON.parse(root.popLastJson(text))
                if (d.err) root.notify(d.action, d.err, true)
                else {
                    var msg = "Ollama service '" + d.action + "' done. Open the manager (Super+Shift+O) to see the new state."
                    root.notify(d.action, msg, false)
                }
                root.refresh()
            }
        }
    }

    Process {
        id: backupProc
        onExited: root.busyBackup = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.busyBackup = false
                var d = JSON.parse(root.popLastJson(text))
                if (d.err) root.say(d.err, true)
                else { root.say("Backup created: " + d.file + " (" + d.size + ")"); root.refreshBackups() }
            }
        }
    }

    Process {
        id: restoreProc
        onExited: root.busyBackup = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.busyBackup = false
                var d = JSON.parse(root.popLastJson(text))
                if (d.err) root.say(d.err, true)
                else { root.say("Models restored"); root.restoreConfirm = ""; root.refresh() }
            }
        }
    }

    Process {
        id: backupListProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(root.popLastJson(text))
                    if (d.err) root.say(d.err, true); else root.backups = d.files || []
                } catch (e) { root.dbg("backups parse: " + e) }
            }
        }
    }

    // ------------------------------------------------------------ overlay
    // ONE single layer window containing dim + centred sheet: two sibling
    // Overlay-layer surfaces (dim + panel) mapped in the same commit stack
    // in an arbitrary order in niri, and if the dim lands on top it eats
    // every click on the output (observed). Single window = no race. No
    // click-outside-to-close (DMS ghost-click bug): close via Esc / × only.
    PanelWindow {
        id: overlay
        visible: root.panelVisible
        color: "transparent"
        WlrLayershell.namespace: "ominty:ollama"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
            // no MouseArea here: the dim intentionally ignores clicks
        }

        Rectangle {
            id: sheet
            anchors.centerIn: parent
            width: Math.min(760, (overlay.screen ? overlay.screen.width : 1920) - 80)
            height: Math.min(680, (overlay.screen ? overlay.screen.height : 1080) - 80)
            radius: 12
            color: Theme.withAlpha(Theme.surface, 0.92)
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (root.subview !== "") root.subview = ""
                    else root.closePanel()
                    event.accepted = true
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                // -------------------------------------------------- header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    StyledText {
                        text: "Ollama"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }
                    // status dot + summary
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: root.status.serverUp === true ? "#a6e3a1"
                             : root.status.unitExists === "yes" ? "#f9e2af"
                             : "#f38ba8"
                    }
                    StyledText {
                        Layout.preferredWidth: 360
                        text: {
                            var v = (root.status.version || "?")
                            if (root.status.unitExists !== "yes")
                                return v + " · no systemd service"
                            var st = root.status.serviceState === "active" ? "service active" : "service " + root.status.serviceState
                            return v + " · " + st
                        }
                        color: Theme.surfaceVariantText
                        elide: Text.ElideMiddle
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 28; height: 28; radius: 14; color: "#45475a"
                        Text { anchors.centerIn: parent; text: "\u00D7"; color: "#cdd6f4"; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; onClicked: root.closePanel() }
                    }
                }

                // -------------------------------------------------- tabs
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS
                    Repeater {
                        model: [{ id: "models", label: "Models" }, { id: "server", label: "Server" }, { id: "backup", label: "Backup" }]
                        Rectangle {
                            required property var modelData
                            width: 96; height: 30; radius: 6
                            color: root.view === modelData.id ? Theme.primary : Theme.withAlpha(Theme.surfaceVariant, 0.3)
                            StyledText { anchors.centerIn: parent; text: modelData.label; color: root.view === modelData.id ? "black" : Theme.surfaceText }
                            MouseArea { anchors.fill: parent; onClicked: { dbg("tab: " + modelData.id); root.view = modelData.id; root.subview = "" } }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: "~/.ollama"
                        color: Theme.surfaceVariantText
                        font.pixelSize: 11
                    }
                }

                // -------------------------------------------------- notice
                StyledText {
                    visible: root.notice !== ""
                    Layout.fillWidth: true
                    text: root.notice
                    color: root.noticeErr ? "#f38ba8" : "#a6e3a1"
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                }

                // -------------------------------------------------- body
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // =============== MODELS TAB ===============
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.view === "models" && root.subview === ""
                        spacing: Theme.spacingM

                        // pull row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: 6
                                color: Theme.withAlpha(Theme.surfaceVariant, 0.25)
                                border.width: 1
                                border.color: Theme.outline
                                TextInput {
                                    id: pullField
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: "white"
                                    onAccepted: root.pull()
                                    clip: true
                                }
                                StyledText {
                                    visible: pullField.text === ""
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Model to pull, e.g. llama3.1:8b…"
                                    color: Theme.surfaceVariantText
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: 84
                                Layout.preferredHeight: 38
                                radius: 6
                                color: Theme.primary
                                StyledText { anchors.centerIn: parent; text: "Pull"; color: "black"; font.weight: Font.Bold }
                                MouseArea { anchors.fill: parent; onClicked: root.pull() }
                            }
                        }

                        // popular chips
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.status.popular || []
                                Rectangle {
                                    required property string modelData
                                    height: 26
                                    width: chipLabel.implicitWidth + 18
                                    radius: 13
                                    color: Theme.withAlpha(Theme.surfaceVariant, 0.4)
                                    StyledText {
                                        id: chipLabel
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: Theme.surfaceText
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: { pullField.text = modelData; root.pull() }
                                    }
                                }
                            }
                        }

                        // pull progress
                        ColumnLayout {
                            visible: root.pulling
                            Layout.fillWidth: true
                            spacing: 4
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                radius: 3
                                color: Theme.withAlpha(Theme.surfaceVariant, 0.6)
                                Rectangle {
                                    width: root.pullPct > 0 ? parent.width * root.pullPct / 100 : 40
                                    height: parent.height
                                    radius: 3
                                    color: Theme.primary
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Pulling " + root.pullModel + " · " + Math.round(root.pullPct) + "%"
                                color: Theme.surfaceVariantText
                                font.pixelSize: 11
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.pullLine
                                color: Theme.surfaceVariantText
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                            }
                        }

                        // model list
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            StyledText {
                                anchors.centerIn: parent
                                visible: root.models.length === 0
                                text: "No models installed. Pull one above."
                                color: Theme.surfaceVariantText
                            }
                            ListView {
                                anchors.fill: parent
                                visible: root.models.length > 0
                                clip: true
                                spacing: 4
                                model: root.models
                                delegate: Rectangle {
                                    required property var modelData
                                    width: ListView.view.width
                                    height: 56
                                    radius: 8
                                    color: Theme.withAlpha(Theme.surfaceVariant, 0.25)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingM
                                        spacing: Theme.spacingM
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            color: Theme.surfaceText
                                            font.weight: Font.Bold
                                            elide: Text.ElideMiddle
                                        }
                                        StyledText {
                                            text: (modelData.size_text !== "" ? modelData.size_text : "—")
                                                + (modelData.modified !== "" ? "  ·  " + modelData.modified : "")
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: 11
                                        }
                                        Rectangle {
                                            width: 28; height: 26; radius: 6
                                            color: Theme.withAlpha(Theme.primary, 0.25)
                                            StyledText { anchors.centerIn: parent; text: "💬"; font.pixelSize: 12 }
                                            MouseArea { anchors.fill: parent; onClicked: root.openChat(modelData.name) }
                                        }
                                        Rectangle {
                                            width: 28; height: 26; radius: 6
                                            color: Theme.withAlpha(Theme.surfaceVariant, 0.5)
                                            StyledText { anchors.centerIn: parent; text: "ⓘ"; color: Theme.surfaceText; font.pixelSize: 12 }
                                            MouseArea { anchors.fill: parent; onClicked: root.openDetails(modelData.name) }
                                        }
                                        Rectangle {
                                            width: 28; height: 26; radius: 6
                                            color: Theme.withAlpha("#f38ba8", 0.25)
                                            StyledText { anchors.centerIn: parent; text: "✕"; color: Theme.surfaceText; font.pixelSize: 12 }
                                            MouseArea { anchors.fill: parent; onClicked: root.removeModel(modelData.name) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // =============== CHAT SUBVIEW ===============
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.subview === "chat"
                        spacing: Theme.spacingM
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM
                            Rectangle {
                                width: 56; height: 26; radius: 6
                                color: Theme.withAlpha(Theme.surfaceVariant, 0.4)
                                StyledText { anchors.centerIn: parent; text: "← Back"; color: Theme.surfaceText; font.pixelSize: 12 }
                                MouseArea { anchors.fill: parent; onClicked: root.subview = "" }
                            }
                            StyledText {
                                text: "Chat — " + root.chatModel
                                color: Theme.surfaceText
                                font.weight: Font.Bold
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: Theme.withAlpha(Theme.surfaceVariant, 0.2)
                            ScrollView {
                                anchors.fill: parent
                                TextArea {
                                    id: chatArea
                                    readOnly: true
                                    text: root.chatLog
                                    color: Theme.surfaceText
                                    wrapMode: TextArea.WordWrap
                                    background: null
                                    padding: Theme.spacingM
                                    onTextChanged: cursorPosition = text.length
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: 6
                                color: Theme.withAlpha(Theme.surfaceVariant, 0.25)
                                border.width: 1
                                border.color: Theme.outline
                                TextInput {
                                    id: promptField
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: "white"
                                    text: root.promptText
                                    enabled: !root.busyChat
                                    onTextChanged: root.promptText = text
                                    onAccepted: root.sendChat()
                                    clip: true
                                }
                                StyledText {
                                    visible: promptField.text === ""
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Type a prompt and press Enter…"
                                    color: Theme.surfaceVariantText
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 38
                                radius: 6
                                color: root.busyChat ? Theme.withAlpha(Theme.primary, 0.4) : Theme.primary
                                StyledText { anchors.centerIn: parent; text: root.busyChat ? "…" : "Send"; color: "black"; font.weight: Font.Bold }
                                MouseArea { anchors.fill: parent; enabled: !root.busyChat; onClicked: root.sendChat() }
                            }
                        }
                    }

                    // =============== DETAILS SUBVIEW ===============
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.subview === "details"
                        spacing: Theme.spacingM
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM
                            Rectangle {
                                width: 56; height: 26; radius: 6
                                color: Theme.withAlpha(Theme.surfaceVariant, 0.4)
                                StyledText { anchors.centerIn: parent; text: "← Back"; color: Theme.surfaceText; font.pixelSize: 12 }
                                MouseArea { anchors.fill: parent; onClicked: root.subview = "" }
                            }
                            StyledText {
                                text: "Details — " + root.detailsModel
                                color: Theme.surfaceText
                                font.weight: Font.Bold
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: Theme.withAlpha(Theme.surfaceVariant, 0.2)
                            ScrollView {
                                anchors.fill: parent
                                TextArea {
                                    readOnly: true
                                    text: root.detailsText
                                    color: Theme.surfaceText
                                    wrapMode: TextArea.NoWrap
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    background: null
                                    padding: Theme.spacingM
                                }
                            }
                        }
                    }

                    // =============== SERVER TAB ===============
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.view === "server"
                        spacing: Theme.spacingL

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText {
                                text: "API server: " + (root.status.serverUp === true ? "up (" + (root.status.host || "127.0.0.1:11434") + ")" : "down")
                                color: root.status.serverUp === true ? "#a6e3a1" : "#f38ba8"
                            }
                            StyledText {
                                text: "Systemd service: " + (root.status.unitExists === "yes"
                                    ? root.status.serviceState + " · auto-start " + root.status.enabledState
                                    : "not installed")
                                color: root.status.serviceState === "active" ? "#a6e3a1" : Theme.surfaceVariantText
                            }
                            StyledText {
                                text: "Models directory: " + (root.status.modelsDir || "~/.ollama/models")
                                color: Theme.surfaceVariantText
                                font.pixelSize: 11
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM
                            ActionButton { label: "Start"; w: 96; busy: root.busySvc; act: () => root.svc("start") }
                            ActionButton { label: "Stop"; w: 96; busy: root.busySvc; act: () => root.svc("stop") }
                            ActionButton { label: "Restart"; w: 96; busy: root.busySvc; act: () => root.svc("restart") }
                            Item { Layout.fillWidth: true }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM
                            ActionButton { label: "Enable auto-start"; w: 150; busy: root.busySvc; act: () => root.svc("enable") }
                            ActionButton { label: "Disable auto-start"; w: 150; busy: root.busySvc; act: () => root.svc("disable") }
                            Item { Layout.fillWidth: true }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Started via your " + (root.status.scope === "user" ? "user" : "system") + " systemd unit — start/stop needs no administrator rights on user units; system units show an authentication prompt."
                            color: Theme.surfaceVariantText
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.surfaceVariant, 0.5) }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM
                            ActionButton {
                                label: root.busyGpu ? "Checking…" : "GPU check"
                                w: 110
                                busy: root.busyGpu
                                act: () => root.gpuCheck()
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Loads the smallest installed model with a one-word prompt, then reads `ollama ps` to see how much sits in VRAM."
                            color: Theme.surfaceVariantText
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                        Item { Layout.fillHeight: true }
                    }

                    // =============== BACKUP TAB ===============
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.view === "backup"
                        spacing: Theme.spacingM

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM
                            ActionButton {
                                label: root.busyBackup ? "Working…" : "Backup models now"
                                w: 170
                                busy: root.busyBackup
                                act: () => root.backupNow()
                            }
                            StyledText { text: "~/.local/share/ominty-ollama/backups"; color: Theme.surfaceVariantText; font.pixelSize: 11 }
                            Item { Layout.fillWidth: true }
                        }

                        // restore confirmation
                        Rectangle {
                            visible: root.restoreConfirm !== ""
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            radius: 8
                            color: Theme.withAlpha("#f9e2af", 0.15)
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Restore '" + root.restoreConfirm + "'? This REPLACES the whole models directory."
                                    color: Theme.surfaceText
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 12
                                }
                                ActionButton { label: "Cancel"; w: 76; busy: root.busyBackup; act: () => root.restoreConfirm = "" }
                                ActionButton { label: "Restore"; w: 86; busy: root.busyBackup; act: () => root.restore(root.restoreConfirm) }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            StyledText {
                                anchors.centerIn: parent
                                visible: root.backups.length === 0
                                text: root.busyBackup ? "Working…" : "No backups yet."
                                color: Theme.surfaceVariantText
                            }
                            ListView {
                                anchors.fill: parent
                                visible: root.backups.length > 0
                                clip: true
                                spacing: 4
                                model: root.backups
                                delegate: Rectangle {
                                    required property var modelData
                                    width: ListView.view.width
                                    height: 48
                                    radius: 8
                                    color: Theme.withAlpha(Theme.surfaceVariant, 0.25)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingM
                                        spacing: Theme.spacingM
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            color: Theme.surfaceText
                                            elide: Text.ElideMiddle
                                        }
                                        StyledText {
                                            text: modelData.size + "  ·  " + modelData.date
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: 11
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 64
                                            Layout.preferredHeight: 26
                                            radius: 6
                                            color: Theme.withAlpha("#f9e2af", 0.3)
                                            StyledText { anchors.centerIn: parent; text: "Restore"; color: Theme.surfaceText; font.pixelSize: 11 }
                                            MouseArea { anchors.fill: parent; onClicked: root.restoreConfirm = modelData.name }
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "Backups archive ~/.ollama/models with tar.gz. Restore overwrites the live models directory — pull progress is not interrupted by backups but you cannot restore while a pull runs."
                            color: Theme.surfaceVariantText
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // -------------------------------------------------- footer
                StyledText {
                    Layout.fillWidth: true
                    text: "Esc close · pull streams live progress · systemctl actions prompt for auth"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 11
                }

                Timer {
                    interval: 100
                    running: root.panelVisible
                    repeat: false
                    onTriggered: sheet.forceActiveFocus()
                }
            }
        }
    }

    // shared small button component
    component ActionButton: Rectangle {
        id: abButton
        property string label: ""
        property int w: 96
        property bool busy: false
        property var act
        width: w
        height: 32
        radius: 6
        color: busy ? Theme.withAlpha(Theme.primary, 0.4) : Theme.primary
        StyledText { anchors.centerIn: parent; text: abButton.busy ? "…" : abButton.label; color: "black"; font.weight: Font.Bold; font.pixelSize: 12 }
        MouseArea {
            anchors.fill: parent
            enabled: !abButton.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: if (abButton.act) abButton.act()
        }
    }
}
