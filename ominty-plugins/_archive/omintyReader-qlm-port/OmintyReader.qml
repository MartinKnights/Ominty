import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services
import "Reader.js" as Reader

// Ominty Reader — daemon.
//
// One instance per shell. Holds everything shared: the saved state, the
// library, the backend processes, the open book. The bar widget
// (ReaderWidget.qml) is a thin view; the overlay below is the reader panel.
//
// Ported from omarchy-reader's Service.qml + PanelContent.qml.  The shell
// coupling (Omarchy's `shell`, `bar`, Style/Color singletons) is replaced by
// the DMS PluginComponent/PluginService pattern, Theme palette and an
// omintyMedia-style overlay.  The Python backend (backend/, bin/reader) and
// the pure-JS Reader.js are carried over unchanged.
PluginComponent {
    id: root

    pluginId: "omintyReader"
    pluginService: PluginService

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string pluginDir: Reader.fileUrlToPath(Qt.resolvedUrl(".")).replace(/\/$/, "")
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omi/reader.json"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omi"
    readonly property string cachePath: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/omi-reader"

    property var backendCommand: ["python3", "-B", pluginDir + "/bin/reader"]
    property var openCommand: ["xdg-open"]
    property int scanTimeoutMs: 600000

    // ---- settings (DMS plugin settings; falls back to defaults)
    property string folder: (pluginData && pluginData.folder) || ""
    property int configuredFontPx: (pluginData && pluginData.fontSize) || 0

    // ---- saved state
    property var store: Reader.emptyState()
    property bool storeReady: false
    property int loadAttempts: 0

    // ---- library
    property var books: []
    property var libraryDirs: []
    property bool scanning: false
    property bool scanned: false
    property string libraryError: ""
    property bool indexRequested: false
    property double lastScan: 0

    // ---- the open book
    property var blocks: []
    property int blockCount: 0
    property string bookKey: ""
    property string bookPath: ""
    property string bookTitle: ""
    property string bookAuthor: ""
    property bool opening: false
    property string openError: ""

    // ---- view / overlay
    property string view: "library"      // "library" | "reader"
    property bool panelVisible: false

    readonly property int fontPx: store.fontPx > 0 ? store.fontPx
        : (configuredFontPx >= 6 && configuredFontPx <= 64 ? configuredFontPx : 17)
    readonly property string libraryFolder: Reader.libraryFolder(books, libraryDirs, folder, home)
    readonly property bool hasBook: blockCount > 0
    readonly property string currentTitle: hasBook ? bookTitle
        : (Reader.bookPosition(store, store.current) ? String(Reader.bookPosition(store, store.current).title || "") : "")

    function now() { return Math.floor(Date.now() / 1000) }

    // ---------------------------------------------------------------- state
    function adoptStore(text) {
        store = Reader.parseState(text)
        storeReady = true
        view = store.view === "reader" ? "reader" : "library"
    }
    function persist() {
        if (storeReady) stateFile.setText(Reader.serializeState(store))
    }
    function commit() {
        saveTimer.stop()
        if (!storeReady) return
        // Minimal, safe position save — avoids Reader.makePosition/prep.
        var next = Reader.parseState(Reader.serializeState(store))
        if (hasBook && bookKey) {
            next.current = bookKey
            if (!next.books) next.books = {}
            next.books[bookKey] = { b: 0, f: 0, p: 0, t: now(), path: bookPath, title: bookTitle }
        }
        next.view = view
        store = next
        persist()
    }

    // ---------------------------------------------------------------- panel
    function toggle() {
        if (panelVisible) closePanel(); else openPanel();
    }
    function openPanel() {
        panelVisible = true;
        indexRequested = true;
        if (!scanned && !scanning) scan();
    }
    function closePanel() {
        commit();
        panelVisible = false;
    }
    function showLibrary() {
        view = "library";
        commit();
        refreshLibrary();
    }
    function refreshLibrary() {
        indexRequested = true;
        if (!scanning && Date.now() - lastScan > 5000) scan();
    }

    // ---------------------------------------------------------------- library
    function scan() {
        scanning = true;
        var argv = backendCommand.concat(["scan"]);
        if (folder) argv = argv.concat(["--dir", Reader.expandHome(folder, home)]);
        scanJob.run(argv);
    }
    function adoptLibrary(text, fromCache) {
        var res = null;
        try { res = JSON.parse(text) } catch (e) { res = null; }
        if (!res || !Array.isArray(res.books)) {
            if (!fromCache) libraryError = (res && res.error && res.error.message)
                ? String(res.error.message) : "The library could not be read.";
            return;
        }
        if (!fromCache) libraryError = "";
        libraryDirs = Array.isArray(res.dirs) ? res.dirs : [];
        var sorted = Reader.sortBooks(res.books, store);
        if (JSON.stringify(sorted) !== JSON.stringify(books)) books = sorted;
    }

    // ---------------------------------------------------------------- book
    function openBook(path, title) {
        if (!path) return;
        view = "reader";
        commit();
        if (hasBook && path === bookPath) { openError = ""; return; }
        blockCount = 0;
        blocks = [];
        bookKey = "";
        bookPath = "";
        bookTitle = "";
        bookAuthor = "";
        opening = true;
        openError = "";
        openJob.run(backendCommand.concat(["open", path]));
    }
    function adoptBook(text) {
        var res = null;
        try { res = JSON.parse(text) } catch (e) { res = null; }
        opening = false;
        if (!res) { openError = "This book could not be read."; return; }
        bookKey = String(res.key || "");
        bookPath = String(res.path || "");
        bookTitle = String(res.title || "");
        bookAuthor = String(res.author || "");
        blocks = Array.isArray(res.blocks) ? res.blocks : [];
        blockCount = blocks.length;
        openError = "";
    }
    function failOpen(message) {
        opening = false;
        openError = message || "This book could not be opened.";
    }
    function openLibraryFolder() {
        var target = libraryFolder;
        if (!target) return;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p -- "$0" && exec xdg-open "$0"', target]);
    }

    // ---------------------------------------------------------------- ipc
    IpcHandler {
        target: "omintyReader"
        function toggle(): string { root.toggle(); return root.panelVisible ? "opened" : "closed"; }
        function open(): string { root.openPanel(); return "opened"; }
        function close(): string { root.closePanel(); return "closed"; }
        function library(): string { root.openPanel(); root.showLibrary(); return "opened"; }
        function openPath(path: string): string {
            if (!path) return "no path";
            root.openPanel();
            root.openBook(Reader.expandHome(path, root.home), "");
            return "ok";
        }
        function status(): string {
            return JSON.stringify({
                title: root.bookTitle, author: root.bookAuthor,
                books: root.books.length, blocks: root.blockCount,
                view: root.view, open: root.openError, scanning: root.scanning,
                panel: root.panelVisible, path: root.bookPath
            });
        }
    }

    Component.onCompleted: mkStateDir.running = true

    Process { id: mkStateDir; command: ["mkdir", "-p", root.stateDir] }

    // ---- state file ------------------------------------------------------
    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: root.adoptStore(text())
        onLoadFailed: {
            if (root.storeReady) return;
            root.loadAttempts++;
            if (root.loadAttempts < 3) retryLoad.restart();
            else root.adoptStore("");
        }
    }
    Timer { id: retryLoad; interval: 700; onTriggered: stateFile.reload() }
    Timer { id: saveTimer; interval: 800; onTriggered: root.commit() }

    // The previous scan's result, shown at once while a fresh scan runs.
    FileView {
        id: indexFile
        path: root.indexRequested ? root.cachePath + "/index.json" : ""
        printErrors: false
        onLoaded: if (!root.scanned) root.adoptLibrary(text(), true)
    }

    // Loads when its path is set; reload() covers a book converted again.
    FileView {
        id: bookFile
        printErrors: false
        onLoaded: {
            var loaded = String(path);
            root.adoptBook(text());
            Qt.callLater(function() { if (String(bookFile.path) === loaded) bookFile.path = ""; });
        }
        onLoadFailed: root.failOpen("This book could not be opened.")
    }

    BackendJob {
        id: scanJob
        timeoutMs: root.scanTimeoutMs
        onFinished: function(ok, output) {
            if (queued) return
            root.scanning = false
            root.scanned = true
            root.lastScan = Date.now()
            if (output) root.adoptLibrary(output, false)
            else root.libraryError = timedOut
                ? "Reading your books is taking a long time. It carries on next time."
                : "Reader's helper did not run. Is python3 installed?"
        }
    }

    BackendJob {
        id: openJob
        timeoutMs: 120000
        onFinished: function(ok, output) {
            if (queued) return
            var res = null
            try { res = JSON.parse(output) } catch (e) { res = null }
            if (ok && res && res.ok === true && res.book) {
                if (bookFile.path === String(res.book)) bookFile.reload()
                else bookFile.path = String(res.book)
            } else if (res && res.error && res.error.message) {
                root.failOpen(String(res.error.message))
            } else if (timedOut) {
                root.failOpen("This book is taking too long to open.")
            } else {
                root.failOpen("This book could not be opened.")
            }
        }
    }

    // ---- overlay (dim + panel), omintyMedia-style -------------------------
    PanelWindow {
        id: dimWindow
        visible: root.panelVisible
        color: "transparent"
        WlrLayershell.namespace: "ominty:reader-dim"
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
        WlrLayershell.namespace: "ominty:reader"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1

        readonly property int pw: Math.min(820, (overlay.screen ? overlay.screen.width : 1920) - 80)
        readonly property int ph: Math.min(760, (overlay.screen ? overlay.screen.height : 1080) - 80)
        readonly property int mh: Math.max(0, Math.round(((overlay.screen ? overlay.screen.width : 1920) - pw) / 2))
        readonly property int mv: Math.max(0, Math.round(((overlay.screen ? overlay.screen.height : 1080) - ph) / 2))
        anchors { top: true; bottom: true; left: true; right: true }
        margins { left: overlay.mh; right: overlay.mh; top: overlay.mv; bottom: overlay.mv }
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

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

                // header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    StyledText {
                        text: root.view === "reader" && root.hasBook ? root.bookTitle : "Reader"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        visible: root.view === "reader"
                        width: 28; height: 28; radius: 14
                        color: "transparent"; border.width: 1; border.color: Theme.outline
                        StyledText { anchors.centerIn: parent; text: "\u2190"; color: Theme.surfaceText }
                        MouseArea { anchors.fill: parent; onClicked: root.showLibrary() }
                    }
                    Rectangle {
                        width: 28; height: 28; radius: 14; color: "#45475a"
                        Text { anchors.centerIn: parent; text: "\u00D7"; color: "#cdd6f4"; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; onClicked: root.closePanel() }
                    }
                }

                // library view
                ListView {
                    id: library
                    visible: root.view === "library"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.books
                    delegate: Rectangle {
                        required property var modelData
                        width: library.width
                        height: 44
                        radius: 6
                        color: rowMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.18) : "transparent"
                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            StyledText {
                                width: parent.width
                                text: modelData.title || "(untitled)"
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                            }
                            StyledText {
                                width: parent.width
                                text: modelData.author || ""
                                color: Theme.surfaceVariantText
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.openBook(String(modelData.path), String(modelData.title || ""))
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: root.books.length === 0
                        width: parent.width - 40
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        text: root.scanning ? "Reading your books…"
                            : (root.libraryError !== "" ? root.libraryError
                                : "No books found. Put ebooks in ~/Books or ~/Documents/Books.")
                        color: root.libraryError !== "" ? "#f38ba8" : Theme.surfaceVariantText
                    }
                }

                // reader view
                Flickable {
                    id: readerFlick
                    visible: root.view === "reader"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: col.height

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.opening || root.openError !== "" || root.blockCount === 0
                        width: readerFlick.width - 40
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        text: root.opening ? "Opening…"
                            : (root.openError !== "" ? root.openError : "Nothing open.")
                        color: root.openError !== "" ? "#f38ba8" : Theme.surfaceVariantText
                    }

                    Column {
                        id: col
                        width: readerFlick.width
                        spacing: 10
                        Repeater {
                            model: root.blocks
                            delegate: Item {
                                required property var modelData
                                property bool isImg: modelData.k === "img"
                                property real imgW: isImg ? Math.min(col.width, Number(modelData.w) || col.width) : 0
                                width: col.width
                                height: isImg ? imgW * (Number(modelData.h) || 1) / (Number(modelData.w) || 1)
                                    : txt.implicitHeight
                                Image {
                                    visible: parent.isImg
                                    source: parent.isImg ? Reader.pathToFileUrl(String(modelData.src)) : ""
                                    width: parent.imgW
                                    height: parent.height
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                                Text {
                                    id: txt
                                    visible: !parent.isImg
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: {
                                        var t = String(modelData.t || "");
                                        if (modelData.k === "li") return "\u2022  " + t;
                                        return t;
                                    }
                                    color: Theme.surfaceText
                                    font.pixelSize: root.fontPx + (modelData.k === "h" ? 5 : 0)
                                    font.bold: modelData.k === "h"
                                    textFormat: Text.PlainText
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.view === "library"
                        ? (root.books.length + " books · click a book to read · Esc close")
                        : "← library · Esc close"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 11
                }
            }
        }
    }
}