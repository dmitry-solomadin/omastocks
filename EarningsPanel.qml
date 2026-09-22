import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."

ColumnLayout {
    id: root
    readonly property var lastReport: {
        const reports = MarketStore.earnings.events || []
        return reports.length ? reports[reports.length - 1] : null
    }
    readonly property string reportSearchUrl: lastReport ? "https://www.google.com/search?q="
        + encodeURIComponent((StockStore.quote.name || StockStore.selected) + " " + StockStore.selected
            + " earnings release " + lastReport.date + " investor relations") : ""
    spacing: Style.space(8)
    function dateLabel(date) { return Qt.formatDate(new Date(date + "T12:00:00"), "d MMM yyyy") }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "EARNINGS"; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
        ActionButton {
            text: "Earnings calls ↗"
            hint: "Open earnings call transcripts on Yahoo Finance"
            enabled: !!StockStore.selected
            onClicked: Qt.openUrlExternally("https://finance.yahoo.com/quote/" + encodeURIComponent(StockStore.selected) + "/earnings-calls/")
        }
        ActionButton { text: "↻"; hint: MarketStore.earnings.error || MarketStore.earnings.notice || "Refresh earnings"; enabled: !MarketStore.eventsRequest.busy; onClicked: MarketStore.eventsRequest.reload(true) }
    }
    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.bold: true
        text: MarketStore.earnings.next ? "Next report: " + dateLabel(MarketStore.earnings.next.date) + " · Estimated"
            : MarketStore.eventsRequest.busy ? "Loading earnings dates…" : "No upcoming earnings date available"
    }
    Label {
        id: reportLabel
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: text !== ""
        color: Color.muted
        linkColor: Color.foreground
        textFormat: Text.StyledText
        font.pixelSize: Style.font.bodySmall
        text: root.lastReport ? '<a href="' + root.reportSearchUrl + '">Last report: ' + dateLabel(root.lastReport.date) + '</a>'
            + " · EPS " + StockStore.price(root.lastReport.eps) + " vs " + StockStore.price(root.lastReport.forecast) + " est."
            + " · Revenue " + StockStore.revenue(root.lastReport.revenue, root.lastReport.revenueCurrency)
            + " vs " + StockStore.revenue(root.lastReport.revenueForecast, root.lastReport.revenueCurrency) + " est." : ""
        onLinkActivated: link => Qt.openUrlExternally(link)
        activeFocusOnTab: visible
        Keys.onReturnPressed: Qt.openUrlExternally(root.reportSearchUrl)
        Keys.onSpacePressed: Qt.openUrlExternally(root.reportSearchUrl)
        Accessible.role: Accessible.Link
        Accessible.name: root.lastReport ? "Find earnings release for " + StockStore.selected + " on " + dateLabel(root.lastReport.date) : ""
        Accessible.onPressAction: Qt.openUrlExternally(root.reportSearchUrl)
        HoverHandler { cursorShape: reportLabel.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        Ui.PanelToolTip {
            visible: !!reportLabel.hoveredLink || reportLabel.activeFocus
            text: "Search Google for this earnings release"
        }
    }
}
