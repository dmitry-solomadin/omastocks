import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

ColumnLayout {
    id: root
    objectName: "companyActivity"
    readonly property bool expanded: MarketStore.sectionOpen("insiders")
    readonly property var request: insiderRequest
    readonly property var report: request.data
    readonly property var summary: report.summary || {}
    readonly property bool hasNet: Number.isFinite(summary.netShares)
    readonly property string verdict: !hasNet ? "Buy/sell summary unavailable"
        : summary.netShares < 0 ? "Net selling · " + StockStore.compact(-summary.netShares) + " shares"
        : summary.netShares > 0 ? "Net buying · " + StockStore.compact(summary.netShares) + " shares"
        : summary.boughtShares === 0 && summary.soldShares === 0 ? "No reported buys or sells" : "Balanced buying and selling"
    spacing: Style.space(10)
    function refresh() { if (expanded) request.reload(true) }
    DataRequest { id: insiderRequest; arguments: root.expanded && root.visible && MarketStore.companyResearchActive ? ["insiders",StockStore.selected] : [] }
    RowLayout {
        Layout.fillWidth: true
        ActionButton { objectName: "activityToggle"; text: (root.expanded ? "▾ " : "▸ ") + "INSIDER ACTIVITY"; font.pixelSize: Style.font.bodySmall; onClicked: MarketStore.toggleSection("insiders") }
        Item { Layout.fillWidth: true }
        ActionButton { visible: root.expanded; text: "↻"; enabled: !root.request.busy; hint: root.report.error || "Refresh insider activity · Nasdaq" + (root.report.fetched ? " · Retrieved " + Qt.formatDateTime(new Date(root.report.fetched * 1000), "d MMM yyyy hh:mm") : ""); onClicked: root.refresh() }
    }
    ColumnLayout {
        visible: root.expanded
        Layout.fillWidth: true
        spacing: Style.space(10)
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "Past 3 months"; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true
            }
            ActionButton { text: "Nasdaq ↗"; hint: "Open insider activity"; onClicked: Qt.openUrlExternally("https://www.nasdaq.com/market-activity/stocks/" + encodeURIComponent(StockStore.selected.toLowerCase()) + "/insider-activity") }
        }
        ColumnLayout {
            visible: !!root.report.summary
            Layout.fillWidth: true; spacing: Style.space(8)
            Label {
                objectName: "insiderVerdict"
                text: root.verdict; font.bold: true; color: root.hasNet && root.summary.netShares !== 0 ? StockStore.direction(root.summary.netShares) : Color.muted
                Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: Style.space(5)
                visible: Number.isFinite(root.summary.buyFraction)
                color: StockStore.loss
                Rectangle { height: parent.height; width: parent.width * (root.summary.buyFraction || 0); color: StockStore.gain }
                HoverHandler { id: mixHover }
                Ui.PanelToolTip { visible: mixHover.hovered; text: "Bought " + ((root.summary.buyFraction || 0) * 100).toFixed(1) + "% · Sold " + ((1 - (root.summary.buyFraction || 0)) * 100).toFixed(1) + "% of reported buy/sell shares" }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.space(16)
                Repeater {
                    model: [{label:"Bought",shares:root.summary.boughtShares,trades:root.summary.buyTrades,kind:"open-market buys",ink:StockStore.gain},
                        {label:"Sold",shares:root.summary.soldShares,trades:root.summary.sellTrades,kind:"sales",ink:StockStore.loss}]
                    ColumnLayout {
                        id: total
                        required property var modelData
                        Layout.fillWidth: true; Layout.preferredWidth: 0
                        spacing: Style.space(3)
                        Label {
                            text: total.modelData.label + " " + StockStore.compact(total.modelData.shares)
                            color: total.modelData.ink; Layout.fillWidth: true
                            HoverHandler { id: totalHover }
                            Ui.PanelToolTip { visible: totalHover.hovered; text: total.modelData.label + ": " + (Number.isFinite(total.modelData.shares) ? Number(total.modelData.shares).toLocaleString(Qt.locale(), 'f', 0) : "Unavailable") + " shares" }
                        }
                        Label { text: (Number.isFinite(total.modelData.trades) ? total.modelData.trades : "—") + " " + total.modelData.kind; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                }
            }
            Label { text: "By shares · provider totals include automatic sales"; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        MarketLoading {
            Layout.fillWidth: true
            active: root.request.busy
            text: root.report.summary ? "Updating insider activity…" : "Loading insider activity…"
        }
        Label {
            visible: !root.request.busy && (!!root.report.error || !!root.report.notice || !(root.report.rows || []).length)
            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.muted; font.pixelSize: Style.font.bodySmall
            text: root.report.error || root.report.notice || "No recent transactions returned for this symbol."
        }
        Label { visible: !!(root.report.rows || []).length; text: "Latest reported transactions · trade dates"; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.muted; font.pixelSize: Style.font.bodySmall }
        Repeater {
            model: root.report.rows || []
            ColumnLayout {
                id: record
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(5)
                Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground,.09) }
                Label { text: record.modelData.date + " · " + record.modelData.type; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Style.font.bodySmall; color: Color.muted }
                Label {
                    text: record.modelData.name + (record.modelData.role ? " · " + record.modelData.role : "")
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.accent
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (record.modelData.url) Qt.openUrlExternally(record.modelData.url) }
                }
                Label {
                    text: StockStore.compact(record.modelData.shares) + " shares · " + StockStore.financial(record.modelData.price,"perShare",record.modelData.currency)
                        + " · " + (record.modelData.ownership || "Ownership unspecified") + " · Held " + StockStore.compact(record.modelData.held)
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Style.font.bodySmall; color: Color.muted
                }
            }
        }
    }
}
