import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."

ColumnLayout {
    id: root
    objectName: "analystsPanel"
    property bool historyOpen: false
    readonly property var report: MarketStore.analysts
    readonly property var summary: report.summary || {}
    readonly property var history: report.history || []
    readonly property var total: summary.total
    readonly property bool distribution: total !== undefined && total !== null && total > 0
    readonly property bool available: distribution || valid(summary.average) || valid(summary.low) || valid(summary.high)
        || groups.some(group => valid(summary[group.key]))
    readonly property var currentPrice: StockStore.quote.currency === report.currency && valid(StockStore.quote.price) ? StockStore.quote.price : null
    readonly property var upside: valid(summary.average) && currentPrice !== null ? (summary.average / currentPrice - 1) * 100 : null
    readonly property var groups: [{key: "buy", label: "Buy", color: StockStore.gain},
        {key: "hold", label: "Hold", color: Color.muted}, {key: "sell", label: "Sell", color: StockStore.loss}]
    function valid(value) { return value !== null && value !== undefined && isFinite(value) && value > 0 }
    function count(value) { return value === null || value === undefined ? "—" : String(value) }
    function money(value) { return StockStore.financial(value, "perShare", report.currency || "USD") }
    spacing: Style.space(12)
    RowLayout {
        Layout.fillWidth: true
        ActionButton {
            objectName: "analystsToggle"
            text: (MarketStore.analystsOpen ? "▾ " : "▸ ") + "ANALYSTS"
            font.pixelSize: Style.font.bodySmall
            hint: "Analyst recommendations and price targets · Nasdaq / TipRanks"
            onClicked: MarketStore.analystsOpen = !MarketStore.analystsOpen
        }
        Item { Layout.fillWidth: true }
        Label {
            visible: MarketStore.analystsOpen && (root.distribution || root.report.stale === true)
            Layout.minimumWidth: 0
            text: (root.distribution ? root.total + " analysts" : "") + (root.report.stale ? (root.distribution ? " · " : "") + "Saved data" : "")
            font.pixelSize: Style.font.bodySmall; color: Color.muted
        }
        ActionButton {
            objectName: "analystsSourceLink"
            visible: MarketStore.analystsOpen
            text: "Nasdaq ↗"
            hint: "Open analyst ratings and price targets on Nasdaq"
            onClicked: Qt.openUrlExternally("https://www.nasdaq.com/market-activity/stocks/"
                + encodeURIComponent(StockStore.selected.toLowerCase()) + "/analyst-research")
        }
        ActionButton {
            objectName: "analystsRefresh"
            visible: MarketStore.analystsOpen
            text: "↻"; enabled: !MarketStore.analystsRequest.busy
            hint: "Nasdaq / TipRanks · USD price targets · Cached one day"
                + (root.report.fetched ? "\nRetrieved " + Qt.formatDateTime(new Date(root.report.fetched * 1000), "d MMM yyyy, hh:mm") : "")
                + "\nCounts and targets use the same feed. History contains monthly snapshots, not individual rating changes."
                + (root.report.error ? "\n" + root.report.error : "")
            onClicked: MarketStore.analystsRequest.reload(true)
        }
    }
    ColumnLayout {
        visible: MarketStore.analystsOpen
        Layout.fillWidth: true
        spacing: Style.space(12)
        Label {
            visible: !root.available
            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.muted
            text: MarketStore.analystsRequest.busy ? "Loading analyst recommendations…"
                : root.report.error || "No analyst recommendations available for this symbol."
        }
        Row {
            objectName: "analystDistribution"
            visible: root.distribution
            Layout.fillWidth: true; Layout.preferredHeight: Style.space(8)
            Repeater {
                model: root.groups
                Rectangle {
                    required property var modelData
                    width: root.distribution ? parent.width * root.summary[modelData.key] / root.total : 0
                    height: parent.height; color: modelData.color
                    HoverHandler { id: hover }
                    Ui.PanelToolTip {
                        visible: hover.hovered
                        text: modelData.label + ": " + root.count(root.summary[modelData.key])
                            + (root.distribution ? " (" + (root.summary[modelData.key] / root.total * 100).toFixed(1) + "%)" : "")
                    }
                }
            }
        }
        RowLayout {
            visible: root.available
            Layout.fillWidth: true
            Repeater {
                model: root.groups
                Label {
                    required property var modelData
                    Layout.fillWidth: true; Layout.preferredWidth: 0
                    text: modelData.label + " " + root.count(root.summary[modelData.key])
                    color: modelData.color; font.pixelSize: Style.font.bodySmall
                }
            }
        }
        Flow {
            visible: root.available
            Layout.fillWidth: true
            spacing: Style.space(14)
            Label { text: "Avg. target " + root.money(root.summary.average); font.bold: true; color: Color.accent }
            Label {
                text: StockStore.percent(root.upside) + " implied"
                visible: root.upside !== null
                color: StockStore.direction(root.upside)
                HoverHandler { id: upsideHover }
                Ui.PanelToolTip { visible: upsideHover.hovered; text: "Average analyst target versus the current regular-session price." }
            }
        }
        AnalystTargetGauge {
            Layout.fillWidth: true
            visible: root.available
            low: root.summary.low; high: root.summary.high; average: root.summary.average
            price: root.currentPrice; currency: root.report.currency || "USD"
        }
        Label {
            visible: root.available && root.currentPrice !== null
            text: "● Current " + root.money(root.currentPrice)
            font.pixelSize: Style.font.bodySmall; color: Color.muted
        }
        ActionButton {
            objectName: "analystsHistoryToggle"
            visible: root.history.length > 0
            text: (root.historyOpen ? "▾ " : "▸ ") + "History"
            hint: "Monthly recommendation counts and average price targets"
            onClicked: root.historyOpen = !root.historyOpen
        }
        ColumnLayout {
            objectName: "analystsHistory"
            visible: root.historyOpen && root.history.length > 0
            Layout.fillWidth: true
            spacing: Style.space(10)
            RowLayout {
                Layout.fillWidth: true
                Label { text: "Month"; Layout.preferredWidth: Style.space(85); color: Color.muted; font.pixelSize: Style.font.bodySmall }
                Label { text: "Avg. target"; Layout.preferredWidth: Style.space(110); color: Color.muted; font.pixelSize: Style.font.bodySmall }
                Label { text: "Buy / Hold / Sell"; Layout.fillWidth: true; color: Color.muted; font.pixelSize: Style.font.bodySmall }
            }
            Repeater {
                model: root.history
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "MMM yyyy"); Layout.preferredWidth: Style.space(85); font.pixelSize: Style.font.bodySmall }
                    Label { text: root.money(modelData.average); Layout.preferredWidth: Style.space(110); font.pixelSize: Style.font.bodySmall }
                    Label { text: root.count(modelData.buy); color: StockStore.gain; font.pixelSize: Style.font.bodySmall }
                    Label { text: "/ " + root.count(modelData.hold) + " /"; color: Color.muted; font.pixelSize: Style.font.bodySmall }
                    Label { text: root.count(modelData.sell); color: StockStore.loss; font.pixelSize: Style.font.bodySmall }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
