import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import ".."

Controls.ScrollView {
    id: root
    objectName: "watchlistWorkspace"
    contentWidth: availableWidth
    clip: true
    readonly property var page: StockStore.view === "market" ? marketPage : watchlistPage
    function refresh() { if (page.item) page.item.refresh() }
    // Each page is created on its first visit and then kept, so returning to a
    // tab shows its last data at once while it refreshes in the background.
    property bool marketVisited: false
    property bool watchlistVisited: false
    function visit() {
        if (!visible) return
        if (StockStore.view === "market") marketVisited = true
        else watchlistVisited = true
    }
    onVisibleChanged: visit()
    Connections { target: StockStore; function onViewChanged() { root.visit() } }
    Component.onCompleted: visit()
    FastWheel { flickable: root.contentItem }
    ColumnLayout {
        width: root.availableWidth
        spacing: Style.space(12)
        SessionHeader {
            id: marketHeader
            objectName: "marketHeader"
            visible: StockStore.view === "market"
            Layout.fillWidth: true
            MarketMood { Layout.alignment: Qt.AlignVCenter }
            ColumnLayout {
                spacing: Style.space(6)
                Label { text: "Market"; font.pixelSize: Style.space(22); font.bold: true }
                MarketStatus { session: marketHeader.session }
            }
            MarketIndexes { session: marketHeader.session; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
        }
        Label {
            visible: StockStore.view !== "market"
            text: StockStore.watchlistName
            Layout.fillWidth: true
            Layout.leftMargin: Style.space(24); Layout.rightMargin: Style.space(24)
            Layout.topMargin: Style.space(16); Layout.bottomMargin: Style.space(4)
            font.pixelSize: Style.space(22); font.bold: true
        }
        Loader {
            id: marketPage
            objectName: "workspacePage"
            visible: StockStore.view === "market"
            Layout.fillWidth: true
            Layout.topMargin: Style.space(4)
            Layout.leftMargin: Style.space(24); Layout.rightMargin: Style.space(24); Layout.bottomMargin: Style.space(24)
            active: root.marketVisited
            sourceComponent: MarketOverview { verticalFlickable: root.contentItem }
        }
        Loader {
            id: watchlistPage
            visible: StockStore.view !== "market"
            Layout.fillWidth: true
            Layout.leftMargin: Style.space(24); Layout.rightMargin: Style.space(24); Layout.bottomMargin: Style.space(24)
            active: root.watchlistVisited
            sourceComponent: WatchlistDashboard { verticalFlickable: root.contentItem }
        }
    }
}
