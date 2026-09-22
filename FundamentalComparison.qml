import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."

ColumnLayout {
    id: root
    property var verticalFlickable
    property var chosen: []
    property string frequency: "annual"
    readonly property string listKey: JSON.stringify([StockStore.activeWatchlist, StockStore.entries.map(row=>row.symbol)])
    onListKeyChanged: {
        const symbols = StockStore.entries.map(row=>row.symbol)
        chosen = chosen.filter(ticker=>symbols.indexOf(ticker)>=0)
        if (!chosen.length) chosen = symbols.slice(0, Math.min(3, symbols.length))
    }
    readonly property var metrics: [
        ["revenueGrowth","Revenue growth YoY"],["grossMargin","Gross margin"],["operatingMargin","Operating margin"],
        ["netMargin","Net margin"],["fcfMargin","Free cash flow margin"],["TotalRevenue","Revenue"],
        ["FreeCashFlow","Free cash flow"],["NetDebt","Net debt"],["debtEquity","Debt / equity"],
        ["valuation0","Market cap"],["valuation1","P/E (TTM)"],["valuation2","Price / sales"],
        ["valuation3","Price / book"],["valuation4","EV / EBITDA"]]
    spacing: Style.space(12)
    function refresh() { batch.reload(true) }
    WatchlistBatch { id: batch; active: StockStore.windowOpen && root.visible; action: "fundamentals"; parameter: root.frequency; symbols: root.chosen }
    Flow {
        Layout.fillWidth: true; spacing: Style.space(4)
        Repeater {
            model: StockStore.entries
            ActionButton {
                required property var modelData
                text: modelData.symbol
                selected: root.chosen.indexOf(modelData.symbol) >= 0
                enabled: selected || root.chosen.length < 5
                hint: "Compare up to five companies from this watchlist"
                onClicked: root.chosen = selected ? root.chosen.filter(ticker=>ticker !== modelData.symbol) : root.chosen.concat([modelData.symbol])
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        ActionButton { text: "Annual"; selected: root.frequency === "annual"; onClicked: root.frequency = "annual" }
        ActionButton { text: "Quarterly"; selected: root.frequency === "quarterly"; onClicked: root.frequency = "quarterly" }
        Item { Layout.fillWidth: true }
        ActionButton { text: "↻"; enabled: !batch.busy; hint: "Refresh fundamental comparison"; onClicked: root.refresh() }
    }
    Label {
        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.muted; font.pixelSize: Style.font.bodySmall
        text: batch.busy ? "Loading company fundamentals…" : "Latest reported " + (root.frequency === "annual" ? "12-month" : "3-month") + " periods · fiscal dates and currencies shown per cell · valuation ratios use provider definitions"
    }
    Label { visible: !root.chosen.length; text: "Choose up to five stocks to compare."; color: Color.muted; Layout.fillWidth: true }
    FeatureTable {
        verticalFlickable: root.verticalFlickable
        headers: root.chosen
        cellWidth: Style.space(145)
        firstWidth: Style.space(160)
        rows: root.metrics.map(metric=>({label:metric[1],cells:root.chosen.map(ticker=>{
            const report = batch.rows[ticker] || {}, cell = (report.cells || []).find(c=>c.key === metric[0]) || {}
            return {text:StockStore.financial(cell.value,cell.kind,cell.currency),subtext:cell.date || "",
                hint:report.error || report.notice || (report.stale ? "Saved · " : "") + (report.source || "Loading…") + " · " + (cell.date || "Period unavailable")}
        })}))
    }
    Repeater {
        model: root.chosen.filter(ticker => (batch.rows[ticker] || {}).error || (batch.rows[ticker] || {}).notice)
        Label { required property string modelData; text: modelData + " · " + (batch.rows[modelData].error || batch.rows[modelData].notice); Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.muted; font.pixelSize: Style.font.bodySmall }
    }
}
