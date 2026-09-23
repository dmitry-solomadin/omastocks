import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

ColumnLayout {
    id: root
    readonly property var lastReport: {
        const reports = MarketStore.earnings.events || []
        return reports.length ? reports[reports.length - 1] : null
    }
    // Google's "I'm Feeling Lucky" first result is reliably the company's own
    // earnings release. The backend resolves its redirect so the browser opens
    // the release directly, without Google's "Redirect notice"; the Google link
    // itself is the fallback if resolving fails or takes too long.
    readonly property string reportSearchUrl: lastReport ? "https://www.google.com/search?btnI=1&q="
        + encodeURIComponent(StockStore.selected + " earnings release " + lastReport.date + " investor relations") : ""
    property var releaseArguments: []
    property string releaseFallback: ""
    function openRelease() {
        if (!lastReport) return
        const wanted = ["release", StockStore.selected, lastReport.date]
        if (JSON.stringify(wanted) === JSON.stringify(releaseArguments) && release.data.url && !release.data.error) {
            Qt.openUrlExternally(release.data.url)
            return
        }
        releaseFallback = reportSearchUrl
        if (JSON.stringify(wanted) === JSON.stringify(releaseArguments)) release.reload(false)
        else releaseArguments = wanted
        releaseTimeout.restart()
    }
    function settleRelease(url) {
        if (!releaseFallback) return
        Qt.openUrlExternally(url || releaseFallback)
        releaseFallback = ""
        releaseTimeout.stop()
    }
    DataRequest {
        id: release
        arguments: root.releaseArguments
        onDataChanged: if (data.url || data.error) root.settleRelease(data.error ? "" : data.url)
    }
    Timer { id: releaseTimeout; interval: 4000; onTriggered: root.settleRelease("") }
    spacing: Style.space(8)
    function dateLabel(date) { return Qt.formatDate(new Date(date + "T12:00:00"), "d MMM yyyy") }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "EARNINGS"; color: Tone.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
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
    // The link is its own label so its tooltip centres over the link rather
    // than over the whole row.
    RowLayout {
        visible: !!root.lastReport
        Layout.fillWidth: true
        spacing: 0
        Label {
            id: reportLabel
            Layout.alignment: Qt.AlignTop
            color: Tone.muted
            linkColor: Color.foreground
            textFormat: Text.StyledText
            font.pixelSize: Style.font.bodySmall
            text: root.lastReport ? '<a href="' + root.reportSearchUrl + '">Last report: ' + dateLabel(root.lastReport.date) + '</a>' : ""
            onLinkActivated: root.openRelease()
            activeFocusOnTab: visible
            Keys.onReturnPressed: root.openRelease()
            Keys.onSpacePressed: root.openRelease()
            Accessible.role: Accessible.Link
            Accessible.name: root.lastReport ? "Open the earnings release for " + StockStore.selected + " on " + dateLabel(root.lastReport.date) : ""
            Accessible.onPressAction: root.openRelease()
            HoverHandler { cursorShape: root.releaseFallback ? Qt.BusyCursor : reportLabel.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            Ui.PanelToolTip {
                visible: !!reportLabel.hoveredLink || reportLabel.activeFocus
                text: root.releaseFallback ? "Finding the earnings release…" : "Open the earnings release (Google's first result)"
            }
        }
        Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            wrapMode: Text.WordWrap
            color: Tone.muted
            font.pixelSize: Style.font.bodySmall
            text: root.lastReport ? " · EPS " + StockStore.price(root.lastReport.eps) + " vs " + StockStore.price(root.lastReport.forecast) + " est."
                + " · Revenue " + StockStore.revenue(root.lastReport.revenue, root.lastReport.revenueCurrency)
                + " vs " + StockStore.revenue(root.lastReport.revenueForecast, root.lastReport.revenueCurrency) + " est." : ""
        }
    }
    RowLayout {
        Layout.fillWidth: true
        ActionButton {
            objectName: "earningsCallsToggle"
            implicitHeight: Style.space(28)
            text: (MarketStore.earningsCallsOpen ? "▾ " : "▸ ") + "Earnings calls"
            hint: "Recent earnings call transcripts"
            onClicked: MarketStore.toggleSection("calls")
        }
        Item { Layout.fillWidth: true }
        // Same height as the toggle, so the row does not grow when this appears.
        ActionButton {
            visible: MarketStore.earningsCallsOpen
            implicitHeight: Style.space(28)
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
            color: Tone.muted
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
