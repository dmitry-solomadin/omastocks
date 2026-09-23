import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."

ColumnLayout {
    id: root
    objectName: "marketOverview"
    property var verticalFlickable
    property string sector: "sp500"
    property string period: "1D"
    property string sizeLimit: "50"
    readonly property bool active: StockStore.windowOpen && visible
    readonly property var report: request.data
    readonly property var group: (catalog.data.sectors || []).find(row => row.value === root.sector) || ({})
    readonly property var displayedRows: {
        const rows = (report.rows || []).slice()
        if (group.kind !== "index" || sizeLimit === "all") return rows
        return rows.sort((a,b) => (b.marketCap || 0) - (a.marketCap || 0) || a.symbol.localeCompare(b.symbol)).slice(0, Number(sizeLimit))
    }
    spacing: Style.space(12)
    function refresh() { request.reload(true); StockStore.watchlistQuotesRequest.reload(true); news.reload(true) }
    DataRequest { id: catalog; arguments: ["sectors", "ALL"] }
    DataRequest { id: request; arguments: root.active && root.group.kind ? [root.group.kind === "index" ? "market-index" : "sector", root.sector] : [] }
    DataRequest { id: news; arguments: root.active ? ["market-news", "ALL"] : [] }
    MarketIndexes { Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)
        Ui.Dropdown {
            id: selector
            objectName: "marketSectorSelector"
            Layout.fillWidth: true
            Layout.minimumWidth: Style.space(135)
            Layout.preferredWidth: Style.space(220)
            Layout.maximumWidth: Style.space(250)
            Layout.preferredHeight: refreshButton.height
            Layout.alignment: Qt.AlignVCenter
            rowHeight: height
            options: catalog.data.sectors || []
            value: root.sector
            onChanged: value => { root.sector = value; selector.value = Qt.binding(() => root.sector) }
        }
        Repeater {
            model: ["1D", "YTD"]
            ActionButton { required property string modelData; objectName: "marketPeriod_" + modelData; text: modelData; selected: root.period === modelData; onClicked: root.period = modelData }
        }
        ActionButton {
            id: refreshButton
            objectName: "marketRefresh"
            text: request.busy ? "…" : (root.report.error || catalog.data.error) ? "!" : "↻"
            enabled: !request.busy
            hint: root.report.error || catalog.data.error || "Refresh " + (root.group.label || "heatmap")
            onClicked: root.refresh()
        }
        Label {
            objectName: "marketRetrieved"
            Layout.alignment: Qt.AlignVCenter
            color: Color.muted
            font.pixelSize: Style.font.bodySmall
            text: root.report.fetched ? "Retrieved " + Qt.formatDateTime(new Date(root.report.fetched * 1000), "hh:mm") : ""
            HoverHandler { id: timeHover }
            Ui.PanelToolTip {
                visible: timeHover.hovered
                text: (root.report.stale ? "Saved data · " : "") + (root.report.fetched ? Qt.formatDateTime(new Date(root.report.fetched * 1000), "d MMM yyyy hh:mm") : "")
                    + (root.report.error ? "\n" + root.report.error : "")
            }
        }
    }
    Flow {
        visible: root.group.kind === "index"
        Layout.fillWidth: true
        spacing: Style.space(4)
        Repeater {
            model: [{value:"50",label:"Top 50"},{value:"100",label:"Top 100"},{value:"all",label:"All"}]
            ActionButton {
                required property var modelData
                text: modelData.label
                selected: root.sizeLimit === modelData.value
                hint: "Show " + modelData.label.toLowerCase() + " constituents by company market cap"
                onClicked: root.sizeLimit = modelData.value
            }
        }
    }
    SectorHeatmap { Layout.fillWidth: true; rows: root.displayedRows; period: root.period }
    Label { text: "MARKET NEWS"; color: Color.muted; font.pixelSize: Style.font.bodySmall }
    CompanyNews { Layout.fillWidth: true; report: news.data; busy: news.busy; subject: "market" }
    MarketSkyline { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: Style.space(12); Layout.bottomMargin: Style.space(8) }
    Timer { interval: 900000; running: root.active; repeat: true; onTriggered: request.reload(false) }
    Timer { interval: 600000; running: root.active; repeat: true; onTriggered: news.reload(false) }
}
