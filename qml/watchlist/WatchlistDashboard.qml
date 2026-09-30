import QtQuick
import QtQuick.Layouts
import qs.Commons
import ".."

ColumnLayout {
    id: root
    objectName: "watchlistDashboard"
    property var verticalFlickable
    spacing: Style.space(12)
    function refresh() { overview.refresh(); calendar.refresh() }
    SectionHeading { text: "OVERVIEW"; Layout.fillWidth: true }
    WatchlistOverview { id: overview; objectName: "watchlistOverviewSection"; Layout.fillWidth: true; verticalFlickable: root.verticalFlickable }
    SectionHeading { text: "CALENDAR"; Layout.fillWidth: true; Layout.topMargin: Style.space(12) }
    EarningsCalendar { id: calendar; objectName: "watchlistCalendarSection"; Layout.fillWidth: true; verticalFlickable: root.verticalFlickable }
}
