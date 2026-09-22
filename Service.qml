import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

Item {
    id: root
    property var shell: null
    Component.onCompleted: StockStore.start()
    Component.onDestruction: StockStore.stop()
    function open() {
        if (window.visible) {
            for (const toplevel of ToplevelManager.toplevels.values)
                if (toplevel.title === "Omastocks") toplevel.activate()
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
        function refresh(): void { StockStore.refresh(true) }
        function status(): string {
            return JSON.stringify({open: window.visible, selected: StockStore.selected, range: StockStore.period,
                entries: StockStore.entries.length, favorites: StockStore.favorites.map(entry => entry.symbol),
                busy: StockStore.busy, error: StockStore.error, chartPoints: (StockStore.visibleChart.points || []).length})
        }
    }
}
