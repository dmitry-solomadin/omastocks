import QtQuick
import QtQuick.Layouts
import qs.Commons
import ".."

ColumnLayout {
    id: root
    property var verticalFlickable
    property string heatmapPeriod: "1D"
    property bool heatmap: false
    readonly property var periods: ["1D", "1W", "1M", "YTD", "1Y"]
    spacing: Style.space(12)
    function value(entry, period) {
        const quote = StockStore.watchlistQuotes[entry.symbol] || {}, history = batch.rows[entry.symbol] || {}, baseline = (history.baselinePrices || {})[period]
        if (period === "1D") return quote.percent
        return baseline > 0 && quote.price !== null && quote.price !== undefined && quote.currency === history.currency
            ? (quote.price / baseline - 1) * 100 : null
    }
    function refresh() { batch.reload(true); quotes.reload(true) }
    readonly property var ordered: StockStore.sortedEntries
    readonly property var quotes: StockStore.watchlistQuotesRequest
    WatchlistBatch { id: batch; active: StockStore.windowOpen && root.visible; action: "overview"; parameter: "--keep-baselines"; symbols: StockStore.entries.map(row => row.symbol) }
    Flow {
        Layout.fillWidth: true; spacing: Style.space(4)
        Repeater {
            model: root.periods
            ActionButton { required property string modelData; visible: root.heatmap; text: modelData; selected: root.heatmapPeriod === modelData; onClicked: root.heatmapPeriod = modelData; hint: "Show " + modelData + " heatmap returns" }
        }
        ActionButton { text: root.heatmap ? "Table" : "Heatmap"; onClicked: root.heatmap = !root.heatmap }
        ActionButton { text: "↻"; enabled: !batch.busy && !quotes.busy; onClicked: root.refresh(); hint: "Refresh watchlist performance" }
    }
    Label { visible: !!quotes.data.error; text: quotes.data.error || ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Tone.muted }
    Label { visible: !StockStore.entries.length; text: "Add stocks to this watchlist to see their performance."; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Tone.muted }
    FeatureTable {
        visible: !root.heatmap && StockStore.entries.length > 0
        verticalFlickable: root.verticalFlickable
        headers: root.periods
        rows: root.ordered.map(entry => ({label: entry.symbol, symbol: entry.symbol, hint: entry.name,
            cells: root.periods.map(period => {
                const report = batch.rows[entry.symbol] || {}, quote = StockStore.watchlistQuotes[entry.symbol] || {}, amount = root.value(entry, period)
                return {text:StockStore.percent(amount),color:StockStore.direction(amount),
                    hint:quotes.data.error || quote.error || (period !== "1D" && report.error) || (period !== "1D" && (report.baselines || {})[period] ? "Baseline close: " + report.baselines[period] : "")
                        + (quote.updated ? (period !== "1D" && (report.baselines || {})[period] ? " · " : "") + "Quote " + Qt.formatDateTime(new Date(quote.updated * 1000), "d MMM yyyy hh:mm") : ""),
                    subtext:(quotes.data.stale || (period !== "1D" && report.stale)) ? "Saved" : ""}
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
                readonly property var change: root.value(modelData, root.heatmapPeriod)
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
    Timer { interval: 300000; running: StockStore.windowOpen && root.visible; repeat: true; onTriggered: batch.reload(false) }
}
