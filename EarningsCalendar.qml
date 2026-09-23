import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."

ColumnLayout {
    id: root
    property var verticalFlickable
    property string horizon: "All upcoming"
    property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    readonly property var available: StockStore.entries.map(entry => ({entry:entry, report:batch.rows[entry.symbol] || {}}))
    readonly property var undatedSymbols: available.filter(row => !StockStore.isIndex(row.entry.symbol) && batch.rows[row.entry.symbol] && (!row.report.next || row.report.next.date < root.today)).map(row => row.entry.symbol)
    readonly property var dated: available.filter(row => row.report.next && row.report.next.date >= today).sort((a,b)=>a.report.next.date.localeCompare(b.report.next.date) || a.entry.symbol.localeCompare(b.entry.symbol))
    readonly property var scheduled: dated.filter(row => {
        if (horizon === "All upcoming") return true
        const current = new Date(today + "T12:00:00"), day = new Date(row.report.next.date + "T12:00:00")
        const monday = new Date(current); monday.setDate(current.getDate() - (current.getDay() + 6) % 7)
        const offset = Math.round((day - monday) / 86400000)
        return horizon === "This week" ? offset < 7 : offset >= 7 && offset < 14
    })
    spacing: Style.space(12)
    function refresh() { batch.reload(true) }
    BulkRequest { id: batch; active: StockStore.windowOpen && root.visible; action: "calendar-bulk"; symbols: StockStore.entries.map(row=>row.symbol) }
    Flow {
        Layout.fillWidth: true; spacing: Style.space(4)
        Repeater { model: ["This week", "Next week", "All upcoming"]; ActionButton { required property string modelData; text: modelData; selected: root.horizon === modelData; onClicked: root.horizon = modelData } }
        ActionButton { text: "↻"; enabled: !batch.busy; hint: "Refresh watchlist earnings"; onClicked: root.refresh() }
    }
    Label { visible: !!batch.report.error; text: batch.report.error || ""; color: Color.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    Label { visible: !root.scheduled.length; text: batch.busy ? "" : "No upcoming reports in this period."; color: Color.muted; Layout.fillWidth: true }
    FeatureTable {
        verticalFlickable: root.verticalFlickable
        headers: ["Report date", "EPS estimate", "Revenue estimate", "Last EPS surprise", "Last revenue surprise"]
        cellWidth: Style.space(140)
        rows: root.scheduled.map(row => {
            const next = row.report.next, history = row.report.events || [], last = history.length ? history[history.length-1] : {},
                surprise = last.eps !== null && last.eps !== undefined && last.forecast !== null && last.forecast !== undefined && last.forecast !== 0
                    ? (last.eps - last.forecast) / Math.abs(last.forecast) * 100 : null,
                revenueSurprise = Number.isFinite(last.revenue) && Number.isFinite(last.revenueForecast) && last.revenueForecast !== 0
                    ? (last.revenue - last.revenueForecast) / Math.abs(last.revenueForecast) * 100 : null,
                revenueHint = batch.report.revenueNotice || ""
            return {label:row.entry.symbol,symbol:row.entry.symbol,hint:row.entry.name,cells:[
                {text:next.date,subtext:next.timing || "",hint:batch.report.error || ""},
                {text:StockStore.financial(next.forecast,"perShare",next.currency || ""),subtext:batch.report.stale ? "Saved" : ""},
                {text:StockStore.revenue(next.revenueForecast,next.revenueCurrency),subtext:batch.report.stale ? "Saved" : "",hint:revenueHint},
                {text:StockStore.percent(surprise),subtext:last.date || "",color:StockStore.direction(surprise),hint:Number.isFinite(last.eps) && Number.isFinite(last.forecast) ? "Actual " + StockStore.price(last.eps) + " · Estimate " + StockStore.price(last.forecast) : ""},
                {text:StockStore.percent(revenueSurprise),subtext:last.date || "",color:StockStore.direction(revenueSurprise),hint:revenueHint || (Number.isFinite(last.revenue) && Number.isFinite(last.revenueForecast) ? "Actual " + StockStore.revenue(last.revenue,last.revenueCurrency) + " · Estimate " + StockStore.revenue(last.revenueForecast,last.revenueCurrency) : "")}
            ]}
        })
    }
    Label {
        visible: root.undatedSymbols.length > 0
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        font.pixelSize: Style.font.bodySmall; color: Color.muted
        text: "Next report date unavailable: " + root.undatedSymbols.join(", ")
    }
    Timer { interval: 60000; running: root.visible && StockStore.windowOpen; repeat: true; onTriggered: root.today = Qt.formatDate(new Date(), "yyyy-MM-dd") }
    Timer { interval: 21600000; running: root.visible && StockStore.windowOpen; repeat: true; onTriggered: batch.reload(false) }
}
