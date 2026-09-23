import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

ColumnLayout {
    id: root
    objectName: "analystsPanel"
    readonly property bool historyOpen: MarketStore.sectionOpen("analystHistory")
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
        {key: "hold", label: "Hold", color: Tone.muted}, {key: "sell", label: "Sell", color: StockStore.loss}]
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
            onClicked: MarketStore.toggleSection("analysts")
        }
        Item { Layout.fillWidth: true }
        Label {
            visible: MarketStore.analystsOpen && (root.distribution || root.report.stale === true)
            Layout.minimumWidth: 0
            text: (root.distribution ? root.total + " analysts" : "") + (root.report.stale ? (root.distribution ? " · " : "") + "Saved data" : "")
            font.pixelSize: Style.font.bodySmall; color: Tone.muted
        }
        ActionButton {
            objectName: "analystsSourceLink"
            visible: MarketStore.analystsOpen
            text: "TipRanks ↗"
            hint: "Open analyst ratings and price targets on TipRanks"
            onClicked: Qt.openUrlExternally("https://www.tipranks.com/stocks/"
                + encodeURIComponent(StockStore.selected.toLowerCase()) + "/forecast")
        }
        ActionButton {
            objectName: "analystsRefresh"
            visible: MarketStore.analystsOpen
            text: "↻"; enabled: !MarketStore.analystsRequest.busy
            hint: root.report.error || "Refresh analysts"
            onClicked: MarketStore.analystsRequest.reload(true)
        }
    }
    ColumnLayout {
        visible: MarketStore.analystsOpen
        Layout.fillWidth: true
        spacing: Style.space(12)
        MarketLoading {
            Layout.fillWidth: true
            active: MarketStore.analystsRequest.busy
            text: root.available ? "Updating analyst outlook…" : "Loading analyst outlook…"
        }
        Label {
            visible: !root.available && !MarketStore.analystsRequest.busy
            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Tone.muted
            text: root.report.error || "No analyst recommendations available for this symbol."
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
        Row {
            objectName: "analystDistributionLabels"
            visible: root.available
            Layout.fillWidth: true
            Repeater {
                model: root.groups
                Label {
                    id: distributionLabel
                    required property var modelData
                    width: root.distribution ? parent.width * root.summary[modelData.key] / root.total : parent.width / root.groups.length
                    text: modelData.label + " " + root.count(root.summary[modelData.key])
                    color: modelData.color; font.pixelSize: Style.font.bodySmall
                    HoverHandler { id: labelHover }
                    Ui.PanelToolTip { visible: labelHover.hovered && distributionLabel.truncated; text: distributionLabel.text }
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
            font.pixelSize: Style.font.bodySmall; color: Tone.muted
        }
        ActionButton {
            objectName: "analystsHistoryToggle"
            visible: root.history.length > 0
            text: (root.historyOpen ? "▾ " : "▸ ") + "History"
            hint: "Monthly recommendation counts and average price targets"
            onClicked: MarketStore.toggleSection("analystHistory")
        }
        ColumnLayout {
            objectName: "analystsHistory"
            visible: root.historyOpen && root.history.length > 0
            Layout.fillWidth: true
            spacing: Style.space(10)
            RowLayout {
                Layout.fillWidth: true
                Label { text: "Month"; Layout.preferredWidth: Style.space(85); color: Tone.muted; font.pixelSize: Style.font.bodySmall }
                Label { text: "Avg. target"; Layout.preferredWidth: Style.space(110); color: Tone.muted; font.pixelSize: Style.font.bodySmall }
                Label { text: "Buy / Hold / Sell"; Layout.fillWidth: true; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
            }
            Repeater {
                model: root.history
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "MMM yyyy"); Layout.preferredWidth: Style.space(85); font.pixelSize: Style.font.bodySmall }
                    Label { text: root.money(modelData.average); Layout.preferredWidth: Style.space(110); font.pixelSize: Style.font.bodySmall }
                    Label { text: root.count(modelData.buy); color: StockStore.gain; font.pixelSize: Style.font.bodySmall }
                    Label { text: "/ " + root.count(modelData.hold) + " /"; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
                    Label { text: root.count(modelData.sell); color: StockStore.loss; font.pixelSize: Style.font.bodySmall }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
