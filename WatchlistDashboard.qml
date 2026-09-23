import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."

ColumnLayout {
    id: root
    objectName: "watchlistDashboard"
    property var verticalFlickable
    spacing: Style.space(12)
    function refresh() { overview.refresh(); calendar.refresh() }
    Label { text: "OVERVIEW"; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
    WatchlistOverview { id: overview; objectName: "watchlistOverviewSection"; Layout.fillWidth: true; verticalFlickable: root.verticalFlickable }
    Label { text: "CALENDAR"; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true; Layout.topMargin: Style.space(12) }
    EarningsCalendar { id: calendar; objectName: "watchlistCalendarSection"; Layout.fillWidth: true; verticalFlickable: root.verticalFlickable }
}
