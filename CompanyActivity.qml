import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import "."

ColumnLayout {
    id: root
    objectName: "companyActivity"
    property bool expanded: false
    property bool insiders: false
    readonly property var request: insiders ? insiderRequest : filingRequest
    readonly property var report: request.data
    spacing: Style.space(10)
    function refresh() { if (expanded) request.reload(true) }
    DataRequest { id: filingRequest; arguments: root.expanded && !root.insiders && root.visible && StockStore.windowOpen && StockStore.selected ? ["filings",StockStore.selected] : [] }
    DataRequest { id: insiderRequest; arguments: root.expanded && root.insiders && root.visible && StockStore.windowOpen && StockStore.selected ? ["insiders",StockStore.selected] : [] }
    RowLayout {
        Layout.fillWidth: true
        ActionButton { objectName: "activityToggle"; text: (root.expanded ? "▾ " : "▸ ") + "COMPANY ACTIVITY"; ink: Color.muted; font.pixelSize: Style.font.bodySmall; onClicked: root.expanded = !root.expanded }
        Item { Layout.fillWidth: true }
        ActionButton { visible: root.expanded; text: "↻"; enabled: !root.request.busy; hint: root.report.error || "Refresh filings or insider transactions"; onClicked: root.refresh() }
    }
    ColumnLayout {
        visible: root.expanded
        Layout.fillWidth: true
        spacing: Style.space(10)
        Flow {
            Layout.fillWidth: true; spacing: Style.space(4)
            ActionButton { text: "Filings"; selected: !root.insiders; onClicked: root.insiders = false }
            ActionButton { text: "Insiders"; selected: root.insiders; onClicked: root.insiders = true }
            ActionButton { text: "Nasdaq ↗"; hint: root.insiders ? "Open insider transactions" : "Open company filings"; onClicked: Qt.openUrlExternally("https://www.nasdaq.com/market-activity/stocks/" + encodeURIComponent(StockStore.selected.toLowerCase()) + (root.insiders ? "/insider-activity" : "/sec-filings")) }
            ActionButton { text: "SEC ↗"; visible: !root.insiders; onClicked: Qt.openUrlExternally("https://www.sec.gov/edgar/browse/?CIK=" + encodeURIComponent(StockStore.selected) + "&owner=include") }
        }
        Label {
            visible: !!root.report.error || !!root.report.notice || root.request.busy || !(root.report.rows || []).length
            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.muted; font.pixelSize: Style.font.bodySmall
            text: root.request.busy ? "Loading " + (root.insiders ? "insider activity…" : "filings…") : root.report.error || root.report.notice || "No records returned for this symbol."
        }
        Label { visible: root.insiders && !!(root.report.rows || []).length; text: "Reported transactions · dates are trade dates · types are supplied by Nasdaq"; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.muted; font.pixelSize: Style.font.bodySmall }
        Repeater {
            model: root.report.rows || []
            ColumnLayout {
                id: record
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(5)
                Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground,.09) }
                Label { text: record.modelData.date + " · " + (root.insiders ? record.modelData.type : record.modelData.form); Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Style.font.bodySmall; color: Color.muted }
                Label {
                    text: root.insiders ? record.modelData.name + (record.modelData.role ? " · " + record.modelData.role : "")
                        : (record.modelData.description || record.modelData.form) + (record.modelData.owner ? " · " + record.modelData.owner : "")
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.accent
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (record.modelData.url) Qt.openUrlExternally(record.modelData.url) }
                }
                Label {
                    visible: root.insiders
                    text: StockStore.compact(record.modelData.shares) + " shares · " + StockStore.financial(record.modelData.price,"perShare",record.modelData.currency)
                        + " · " + (record.modelData.ownership || "Ownership unspecified") + " · Held " + StockStore.compact(record.modelData.held)
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Style.font.bodySmall; color: Color.muted
                }
            }
        }
    }
}
