import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."
import "PixelSprites.js" as Sprites

RowLayout {
    id: root
    objectName: "marketSession"
    property double now: Date.now() / 1000
    readonly property var report: StockStore.watchlistQuotesRequest.data
    readonly property var quote: StockStore.watchlistQuotes["^SPX"] || {}
    readonly property bool fresh: !!report.fetched && !report.stale && !report.error && now - report.fetched < 600
    readonly property string state: fresh ? (quote.marketState || "") : ""
    readonly property bool opened: state === "REGULAR"
    readonly property string status: opened ? "Market open" : ["PRE", "PREPRE"].indexOf(state) >= 0 ? "Pre-market"
        : ["POST", "POSTPOST"].indexOf(state) >= 0 ? "After hours" : state === "CLOSED" ? "Market closed"
        : StockStore.watchlistQuotesRequest.busy ? "Checking market…" : "Market status unavailable"
    property bool initialized: false
    property string previousState: ""
    spacing: Style.space(10)
    onStateChanged: {
        if (state) {
            if (initialized && previousState !== "REGULAR" && opened) ring.restart()
            previousState = state
            initialized = true
        }
    }
    PixelArt {
        id: bell
        pixels: Sprites.bell
        pixelSize: Math.max(1, Math.round(Style.space(1)))
        ink: root.opened ? StockStore.gain : Color.muted
        shade: root.opened ? Color.foreground : Color.muted
        transformOrigin: Item.Top
        SequentialAnimation {
            id: ring
            NumberAnimation { target: bell; property: "rotation"; to: -14; duration: 85 }
            NumberAnimation { target: bell; property: "rotation"; to: 12; duration: 140 }
            NumberAnimation { target: bell; property: "rotation"; to: -8; duration: 120 }
            NumberAnimation { target: bell; property: "rotation"; to: 5; duration: 100 }
            NumberAnimation { target: bell; property: "rotation"; to: 0; duration: 90 }
        }
    }
    Label { text: root.status; color: root.opened ? StockStore.gain : Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
    HoverHandler { id: hover }
    Ui.PanelToolTip { visible: hover.hovered; text: "US market · S&P 500 session" + (root.report.fetched ? "\nChecked " + Qt.formatDateTime(new Date(root.report.fetched * 1000), "hh:mm") : "") }
    Timer { interval: 30000; running: StockStore.windowOpen && root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() / 1000 }
    onVisibleChanged: if (!visible) { ring.stop(); bell.rotation = 0 }
}
