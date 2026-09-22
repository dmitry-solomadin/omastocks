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
    WatchlistBatch { id: batch; active: StockStore.windowOpen && root.visible; action: "calendar"; symbols: StockStore.entries.map(row=>row.symbol) }
    Flow {
        Layout.fillWidth: true; spacing: Style.space(4)
        Repeater { model: ["This week", "Next week", "All upcoming"]; ActionButton { required property string modelData; text: modelData; selected: root.horizon === modelData; onClicked: root.horizon = modelData } }
        ActionButton { text: "↻"; enabled: !batch.busy; hint: "Refresh watchlist earnings"; onClicked: root.refresh() }
    }
    Label { text: batch.busy ? "Loading earnings dates…" : "Nasdaq / Zacks · dates are estimated"; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
    Label { visible: !root.scheduled.length; text: batch.busy ? "" : "No upcoming reports in this period."; color: Color.muted; Layout.fillWidth: true }
    FeatureTable {
        verticalFlickable: root.verticalFlickable
        headers: ["Report date", "EPS estimate", "Last EPS surprise"]
        cellWidth: Style.space(140)
        rows: root.scheduled.map(row => {
            const next = row.report.next, history = row.report.events || [], last = history.length ? history[history.length-1] : {},
                surprise = last.eps !== null && last.eps !== undefined && last.forecast !== null && last.forecast !== undefined && last.forecast !== 0
                    ? (last.eps - last.forecast) / Math.abs(last.forecast) * 100 : null
            return {label:row.entry.symbol,symbol:row.entry.symbol,hint:row.entry.name,cells:[
                {text:next.date,subtext:next.timing || "Time unavailable",hint:row.report.error || "Estimated report date · " + (row.report.source || "Nasdaq / Zacks")},
                {text:StockStore.financial(next.forecast,"perShare",next.currency || ""),subtext:row.report.stale ? "Saved" : ""},
                {text:StockStore.percent(surprise),subtext:last.date || "",color:StockStore.direction(surprise),hint:row.report.notice || "EPS actual vs consensus; negative estimates use their absolute value as the denominator"}
            ]}
        })
    }
    Repeater {
        model: root.available.filter(row => batch.rows[row.entry.symbol] && (!row.report.next || row.report.next.date < root.today))
        Label {
            required property var modelData
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            font.pixelSize: Style.font.bodySmall; color: Color.muted
            text: modelData.entry.symbol + " · " + (modelData.report.error || modelData.report.notice || "Next report date unavailable")
        }
    }
    Timer { interval: 60000; running: root.visible && StockStore.windowOpen; repeat: true; onTriggered: root.today = Qt.formatDate(new Date(), "yyyy-MM-dd") }
    Timer { interval: 21600000; running: root.visible && StockStore.windowOpen; repeat: true; onTriggered: batch.reload(false) }
}
