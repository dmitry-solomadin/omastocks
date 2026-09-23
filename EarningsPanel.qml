import QtQuick
import QtQuick.Controls as Controls
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
        ActionButton { text: "↻"; hint: MarketStore.earnings.error || MarketStore.earnings.notice || "Refresh earnings"; enabled: !MarketStore.eventsRequest.busy; onClicked: MarketStore.eventsRequest.reload(true) }
    }
    MarketLoading {
        Layout.fillWidth: true
        active: MarketStore.eventsRequest.busy
        text: MarketStore.earnings.next || root.lastReport ? "Updating earnings…" : "Loading earnings…"
    }
    Label {
        Layout.fillWidth: true
        visible: !!MarketStore.earnings.next || !MarketStore.eventsRequest.busy
        wrapMode: Text.WordWrap
        font.bold: true
        text: MarketStore.earnings.next ? "Next report: " + dateLabel(MarketStore.earnings.next.date) + " · Estimated"
            : "No upcoming earnings date available"
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
    RowLayout {
        Layout.fillWidth: true
        ActionButton {
            objectName: "earningsCallsToggle"
            text: (MarketStore.earningsCallsOpen ? "▾ " : "▸ ") + "Earnings calls"
            hint: "Recent earnings call transcripts"
            onClicked: MarketStore.toggleSection("calls")
        }
        Item { Layout.fillWidth: true }
        ActionButton {
            visible: MarketStore.earningsCallsOpen
            text: "↻"
            hint: MarketStore.earningsCalls.error || "Refresh earnings calls · Yahoo Finance"
            enabled: !MarketStore.callsRequest.busy
            onClicked: MarketStore.callsRequest.reload(true)
        }
    }
    ColumnLayout {
        objectName: "earningsCallsList"
        visible: MarketStore.earningsCallsOpen
        Layout.fillWidth: true
        spacing: Style.space(4)
        MarketLoading {
            Layout.fillWidth: true
            active: MarketStore.callsRequest.busy
            text: (MarketStore.earningsCalls.calls || []).length ? "Updating earnings calls…" : "Loading earnings calls…"
        }
        Label {
            Layout.fillWidth: true
            visible: !MarketStore.callsRequest.busy && (!!MarketStore.earningsCalls.error || !(MarketStore.earningsCalls.calls || []).length)
            text: MarketStore.earningsCalls.error
                ? ((MarketStore.earningsCalls.calls || []).length ? "Showing saved calls. " : "") + MarketStore.earningsCalls.error
                : "No earnings call transcripts available."
            wrapMode: Text.WordWrap
            color: Color.muted
            font.pixelSize: Style.font.bodySmall
        }
        Repeater {
            model: MarketStore.earningsCalls.calls || []
            Controls.ItemDelegate {
                id: callLink
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: contentItem.implicitHeight + padding * 2
                padding: Style.space(8)
                hoverEnabled: true
                onClicked: Qt.openUrlExternally(modelData.url)
                Accessible.role: Accessible.Link
                Accessible.name: modelData.title
                contentItem: Label {
                    text: callLink.modelData.title + " ↗"
                    wrapMode: Text.WordWrap
                    font.pixelSize: Style.font.bodySmall
                }
                background: Rectangle {
                    radius: Style.cornerRadius
                    color: callLink.hovered || callLink.activeFocus ? Util.alpha(Color.foreground, .06) : "transparent"
                }
                Ui.PanelToolTip { visible: callLink.hovered; text: "Open transcript on Yahoo Finance" }
            }
        }
    }
}
