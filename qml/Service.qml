import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

Item {
    id: root
    property var shell: null
    readonly property string launcherPath: decodeURIComponent(Qt.resolvedUrl("../install-launcher").toString().replace(/^file:\/\//, ""))
    readonly property string launcherToken: Date.now().toString(36) + "-" + Math.random().toString(36).slice(2)
    property string launcherSource: ""
    Component.onCompleted: StockStore.start()
    Component.onDestruction: {
        StockStore.stop()
        launcherInstaller.running = false
        if (launcherSource)
            Quickshell.execDetached(["bash", "-c", launcherSource, launcherPath, "remove", launcherToken])
    }
    // Cache the helper before removal can delete the plugin folder. Detached
    // cleanup outlives this service; instance ownership makes reload ordering safe.
    FileView {
        path: root.launcherPath
        onLoaded: root.launcherSource = text()
    }
    Process {
        id: launcherInstaller
        objectName: "launcherInstaller"
        command: ["bash", "-c", root.launcherSource, root.launcherPath, "install", root.launcherToken]
        running: root.launcherSource !== ""
        onExited: (code, status) => {
            if (code !== 0) console.warn("Omastocks could not install its launcher entry (exit " + code + ").")
        }
    }
    function open() {
        if (window.visible) {
            for (const toplevel of ToplevelManager.toplevels.values)
                if (toplevel.title === window.title) toplevel.activate()
        }
        window.visible = true
        window.minimized = false
        StockStore.windowOpen = true
        StockStore.refresh(false)
    }
    StocksWindow { id: window; shell: root.shell }
    Connections { target: StockStore; function onOpenRequested() { root.open() } }
    IpcHandler {
        target: "io.github.dmitry-solomadin.omastocks"
        function open(): void { root.open() }
        function close(): void { window.visible = false }
        function refresh(): void { if (window.visible) window.refresh(); else StockStore.refresh(true) }
        function status(): string {
            return JSON.stringify({open: window.visible, selected: StockStore.selected, range: StockStore.period,
                entries: StockStore.entries.length, favorites: StockStore.favorites.map(entry => entry.symbol),
                busy: StockStore.busy, error: StockStore.error, chartPoints: (StockStore.visibleChart.points || []).length})
        }
    }
}
