import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import "."

Controls.ScrollView {
    id: root
    objectName: "watchlistWorkspace"
    contentWidth: availableWidth
    clip: true
    function refresh() { if (page.item) page.item.refresh() }
    FastWheel { flickable: root.contentItem }
    ColumnLayout {
        width: root.availableWidth
        spacing: Style.space(12)
        Label {
            text: StockStore.watchlistName
            Layout.fillWidth: true
            Layout.leftMargin: Style.space(24); Layout.rightMargin: Style.space(24)
            Layout.topMargin: Style.space(16); Layout.bottomMargin: Style.space(4)
            font.pixelSize: Style.space(22); font.bold: true
        }
        Loader {
            id: page
            objectName: "workspacePage"
            Layout.fillWidth: true
            Layout.leftMargin: Style.space(24); Layout.rightMargin: Style.space(24); Layout.bottomMargin: Style.space(24)
            active: root.visible
            sourceComponent: StockStore.view === "overview" ? overview : StockStore.view === "fundamentals" ? fundamentals : calendar
        }
    }
    Component { id: overview; WatchlistOverview { verticalFlickable: root.contentItem } }
    Component { id: fundamentals; FundamentalComparison { verticalFlickable: root.contentItem } }
    Component { id: calendar; EarningsCalendar { verticalFlickable: root.contentItem } }
}
