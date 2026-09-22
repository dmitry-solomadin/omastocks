import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."

ColumnLayout {
    id: root
    property var verticalFlickable
    property string sortPeriod: "1D"
    property bool descending: true
    property bool heatmap: false
    readonly property var periods: ["1D", "1W", "1M", "YTD", "1Y"]
    spacing: Style.space(12)
    function value(entry, period) { return period === "1D" ? entry.percent : ((batch.rows[entry.symbol] || {}).returns || {})[period] }
    function refresh() { batch.reload(true); benchmarks.reload(true) }
    readonly property var ordered: StockStore.entries.slice().sort((a, b) => {
        const av = value(a, sortPeriod), bv = value(b, sortPeriod)
        if (av === null || av === undefined) return bv === null || bv === undefined ? a.symbol.localeCompare(b.symbol) : 1
        if (bv === null || bv === undefined) return -1
        return (descending ? bv - av : av - bv) || a.symbol.localeCompare(b.symbol)
    })
    WatchlistBatch { id: batch; active: StockStore.windowOpen && root.visible; action: "overview"; symbols: StockStore.entries.map(row => row.symbol) }
    WatchlistBatch { id: benchmarks; active: StockStore.windowOpen && root.visible; action: "compare"; parameter: "1D"; symbols: ["^SPX", "^IXIC", "^RUT", "^VIX"] }
    Flow {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Repeater {
            model: [{symbol:"^SPX",name:"S&P 500"},{symbol:"^IXIC",name:"Nasdaq"},{symbol:"^RUT",name:"Russell 2000"},{symbol:"^VIX",name:"VIX"}]
            ActionButton {
                required property var modelData
                readonly property var quote: benchmarks.rows[modelData.symbol] || {}
                text: modelData.name + "  " + StockStore.percent(quote.percent)
                ink: StockStore.direction(quote.percent)
                hint: quote.error || "Open " + modelData.name + (quote.updated ? " · " + Qt.formatDateTime(new Date(quote.updated * 1000), "d MMM hh:mm") : "")
                onClicked: StockStore.select(modelData.symbol)
            }
        }
    }
    Flow {
        Layout.fillWidth: true; spacing: Style.space(4)
        Repeater {
            model: root.periods
            ActionButton { required property string modelData; text: modelData; selected: root.sortPeriod === modelData; onClicked: root.sortPeriod = modelData; hint: "Sort by " + modelData + " price return" }
        }
        ActionButton { text: root.descending ? "↓" : "↑"; hint: root.descending ? "Biggest gains first" : "Biggest losses first"; onClicked: root.descending = !root.descending }
        ActionButton { text: root.heatmap ? "Table" : "Heatmap"; onClicked: root.heatmap = !root.heatmap }
        ActionButton { text: "↻"; enabled: !batch.busy && !benchmarks.busy; onClicked: root.refresh(); hint: "Refresh overview and market context" }
    }
    Label { Layout.fillWidth: true; text: batch.busy ? "Loading price returns…" : "Price returns · dividends excluded"; color: Color.muted; font.pixelSize: Style.font.bodySmall }
    Label { visible: !StockStore.entries.length; text: "Add stocks to this watchlist to see their performance."; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.muted }
    FeatureTable {
        visible: !root.heatmap
        verticalFlickable: root.verticalFlickable
        headers: root.periods
        rows: root.ordered.map(entry => ({label: entry.symbol, symbol: entry.symbol, hint: entry.name,
            cells: root.periods.map(period => {
                const report = batch.rows[entry.symbol] || {}, amount = root.value(entry, period)
                return {text:StockStore.percent(amount),color:StockStore.direction(amount),
                    hint:(period === "1D" ? entry.error : report.error) || (period === "1D" ? "Versus previous close" : "Baseline close: " + ((report.baselines || {})[period] || "unavailable"))
                        + ((period === "1D" ? entry.updated : report.asOf) ? " · Quote " + Qt.formatDateTime(new Date((period === "1D" ? entry.updated : report.asOf) * 1000), "d MMM yyyy hh:mm") : ""),
                    subtext:(period === "1D" ? entry.stale : report.stale) ? "Saved" : ""}
            })}))
    }
    GridLayout {
        visible: root.heatmap
        Layout.fillWidth: true
        columns: Math.max(2, Math.floor(root.width / Style.space(130)))
        columnSpacing: Style.space(8)
        rowSpacing: Style.space(8)
        Repeater {
            model: root.ordered
            Rectangle {
                id: tile
                required property var modelData
                readonly property var change: root.value(modelData, root.sortPeriod)
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(78)
                radius: Style.cornerRadius
                color: Util.alpha(StockStore.direction(change), .12 + Math.min(Math.abs(change || 0), 10) * .025)
                Column {
                    anchors.centerIn: parent; spacing: Style.space(6)
                    Label { text: tile.modelData.symbol; font.bold: true }
                    Label { text: StockStore.percent(tile.change); color: StockStore.direction(tile.change) }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: StockStore.select(tile.modelData.symbol) }
            }
        }
    }
    Timer { interval: 300000; running: StockStore.windowOpen && root.visible; repeat: true; onTriggered: { batch.reload(false); benchmarks.reload(false) } }
}
