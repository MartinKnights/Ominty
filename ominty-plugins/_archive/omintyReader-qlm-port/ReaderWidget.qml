import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins

// Ominty Reader — bar widget.
//
// Thin on purpose: the daemon (OmintyReader.qml) holds all state, the
// library and the backend processes. This is a bar chip that toggles the
// reader overlay, and shows the open book's title/author as a tooltip.
//
//   left click   open / close the reader overlay
//
// Ported from omarchy-reader's BarWidget.qml (which used Omarchy's Panel/bar
// API) onto the DMS PluginComponent + PluginService pattern.
PluginComponent {
    id: root

    pluginId: "omintyReader"
    pluginService: PluginService

    readonly property var daemon: PluginService.pluginDaemonInstances[pluginId] ?? null
    readonly property string title: daemon?.bookTitle ?? ""
    readonly property bool active: daemon?.panelVisible ?? false

    implicitWidth: 30
    implicitHeight: 30

    Rectangle {
        id: chip
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: 6
        color: root.active ? Theme.primary : "transparent"

        Text {
            anchors.centerIn: parent
            text: "\uD83D\uDCD6"        // 📖
            font.pixelSize: 15
            color: root.active ? "black" : Theme.surfaceText
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.daemon) root.daemon.toggle();
                else Quickshell.execDetached(["dms", "ipc", "call", "omintyReader", "toggle"]);
            }
        }
    }
}