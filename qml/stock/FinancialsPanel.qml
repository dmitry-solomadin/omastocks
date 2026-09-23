import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import ".."

ColumnLayout {
    id: root
    objectName: "financialsPanel"
    property var verticalFlickable: null
    property string section: "income"
    property string selectedMetric: "TotalRevenue"
    readonly property var statement: (MarketStore.financials.statements || []).find(row => row.id === section) || {dates: [], rows: []}
    readonly property var metric: statement.rows.find(row => row.key === selectedMetric) || statement.rows[0] || null
    readonly property real nameWidth: Style.space(190)
    readonly property real cellWidth: Math.max(Style.space(115), (width - nameWidth) / Math.max(1, statement.dates.length))
    spacing: Style.space(10)
    RowLayout {
        Layout.fillWidth: true
        ActionButton {
            objectName: "financialsToggle"
            text: (MarketStore.financialsOpen ? "▾ " : "▸ ") + "FINANCIALS"
            font.pixelSize: Style.font.bodySmall
            hint: "Income statements, balance sheets and cash flow"
            onClicked: MarketStore.toggleFinancials()
        }
        Item { Layout.fillWidth: true }
        ActionButton {
            objectName: "financialsSourceLink"
            visible: MarketStore.financialsOpen
            text: "Yahoo ↗"
            hint: "Open this statement on Yahoo Finance"
            onClicked: Qt.openUrlExternally("https://finance.yahoo.com/quote/" + encodeURIComponent(StockStore.selected)
                + "/" + ({income: "financials", balance: "balance-sheet", cash: "cash-flow"}[root.section] || "financials") + "/")
        }
        ActionButton {
            visible: MarketStore.financialsOpen
            text: "Filings ↗"
            hint: "Company filings on SEC EDGAR"
            onClicked: Qt.openUrlExternally("https://www.sec.gov/edgar/browse/?CIK=" + encodeURIComponent(StockStore.selected) + "&owner=exclude")
        }
        ActionButton {
            visible: MarketStore.financialsOpen
            text: "↻"; enabled: !MarketStore.financialsRequest.busy
            hint: MarketStore.financials.error || "Refresh financials"
            onClicked: MarketStore.financialsRequest.reload(true)
        }
    }
    ColumnLayout {
        visible: MarketStore.financialsOpen
        Layout.fillWidth: true
        spacing: Style.space(12)
        Flow {
            Layout.fillWidth: true
            spacing: Style.space(4)
            Repeater {
                model: [{id: "income", text: "Income"}, {id: "balance", text: "Balance Sheet"}, {id: "cash", text: "Cash Flow"}]
                ActionButton {
                    required property var modelData
                    objectName: "financialSection_" + modelData.id
                    text: modelData.text; selected: root.section === modelData.id
                    onClicked: root.section = modelData.id
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            ActionButton { objectName: "financialQuarterly"; text: "Quarterly"; selected: MarketStore.financialFrequency === "quarterly"; onClicked: MarketStore.financialFrequency = "quarterly" }
            ActionButton { objectName: "financialAnnual"; text: "Annual"; selected: MarketStore.financialFrequency === "annual"; onClicked: MarketStore.financialFrequency = "annual" }
            Item { Layout.fillWidth: true }
            Label {
                text: MarketStore.financials.stale ? "Saved data" : ""
                color: Tone.muted; font.pixelSize: Style.font.bodySmall
            }
        }
        MarketLoading {
            Layout.fillWidth: true
            active: MarketStore.financialsRequest.busy
            text: root.statement.rows.length ? "Updating financials…" : "Loading financials…"
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            visible: !root.statement.rows.length && !MarketStore.financialsRequest.busy
            text: MarketStore.financials.error || "No financial statements available for this symbol."
            color: Tone.muted
        }
        Label {
            text: root.metric ? root.metric.label : ""
            visible: !!root.metric
            font.bold: true
        }
        MetricChart {
            Layout.fillWidth: true
            visible: !!root.metric
            metric: root.metric; dates: root.statement.dates
        }
        Controls.ScrollView {
            id: tableScroll
            objectName: "financialsTable"
            Layout.fillWidth: true
            visible: root.statement.rows.length > 0
            implicitHeight: table.implicitHeight + (contentWidth > availableWidth ? Style.space(14) : 0)
            contentWidth: root.nameWidth + root.cellWidth * root.statement.dates.length
            contentHeight: table.implicitHeight
            clip: true
            Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AlwaysOff
            Column {
                id: table
                width: tableScroll.contentWidth
                // Handle vertical wheel input before the nested horizontal ScrollView consumes it.
                FastWheel { flickable: root.verticalFlickable }
                Row {
                    Label { width: root.nameWidth; height: Style.space(32); text: "Period ended"; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
                    Repeater {
                        model: root.statement.dates
                        Label {
                            required property string modelData
                            width: root.cellWidth; height: Style.space(32)
                            horizontalAlignment: Text.AlignRight
                            text: Qt.formatDate(new Date(modelData + "T12:00:00"), "d MMM yyyy")
                            color: Tone.muted; font.pixelSize: Style.font.bodySmall
                        }
                    }
                }
                Repeater {
                    model: root.statement.rows
                    Controls.ItemDelegate {
                        id: row
                        required property var modelData
                        objectName: "financialMetric_" + modelData.key
                        width: table.width; height: Style.space(36)
                        padding: 0
                        hoverEnabled: true
                        onClicked: root.selectedMetric = modelData.key
                        Accessible.name: modelData.label + ": show history"
                        background: Rectangle { color: root.metric && row.modelData.key === root.metric.key ? Util.alpha(Color.accent, .1) : row.hovered ? Util.alpha(Color.foreground, .04) : "transparent" }
                        contentItem: Row {
                            Label { width: root.nameWidth; height: row.height; verticalAlignment: Text.AlignVCenter; text: row.modelData.label; font.pixelSize: Style.font.bodySmall }
                            Repeater {
                                model: row.modelData.values
                                Label {
                                    required property var modelData
                                    required property int index
                                    width: root.cellWidth; height: row.height
                                    horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Style.font.bodySmall
                                    text: StockStore.financial(modelData, row.modelData.kind, row.modelData.currencies[index])
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
