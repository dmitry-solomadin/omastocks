import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

// High-importance US releases (CPI, payrolls, Fed, GDP, PCE, ISM…) from
// TradingView, grouped by local day. Today's released events stay with their
// actuals; the list then runs ahead up to `limit` events.
ColumnLayout {
    id: root
    objectName: "economicCalendar"
    property var report: ({})
    property int limit: 10
    property double now: Date.now()
    readonly property double startOfToday: { const day = new Date(now); day.setHours(0, 0, 0, 0); return day.getTime() }
    readonly property var events: (report.events || []).filter(event => event.time * 1000 >= startOfToday).slice(0, limit)
    readonly property var days: {
        const groups = []
        events.forEach(event => {
            const key = Qt.formatDate(new Date(event.time * 1000), "yyyy-MM-dd")
            if (!groups.length || groups[groups.length - 1].key !== key) groups.push({key: key, time: event.time, events: []})
            groups[groups.length - 1].events.push(event)
        })
        return groups
    }
    spacing: Style.space(6)

    function value(event, amount) {
        if (!Number.isFinite(amount)) return ""
        const digits = Math.abs(amount) >= 100 ? 0 : Math.abs(amount) >= 10 ? 1 : 2
        const text = Number(amount).toFixed(digits)
        return (text.indexOf(".") >= 0 ? text.replace(/0+$/, "").replace(/\.$/, "") : text) + (event.scale || "") + (event.unit || "")
    }
    function dayLabel(time) {
        const date = new Date(time * 1000), today = new Date(root.now)
        const tomorrow = new Date(root.now); tomorrow.setDate(tomorrow.getDate() + 1)
        const same = (a, b) => a.toDateString() === b.toDateString()
        return same(date, today) ? "Today" : same(date, tomorrow) ? "Tomorrow" : Qt.formatDate(date, "ddd d MMM")
    }

    Label {
        visible: !root.events.length
        text: root.report.error || (root.report.fetched ? "No major US releases in the next two weeks." : "")
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: root.days
        ColumnLayout {
            id: day
            required property var modelData
            NumberAnimation on opacity { from: 0; to: 1; duration: 250 }
            Layout.fillWidth: true
            Layout.topMargin: Style.space(6)
            spacing: Style.space(2)
            Label { text: root.dayLabel(day.modelData.time); color: Color.muted; font.pixelSize: Style.font.bodySmall; font.bold: true }
            Repeater {
                model: day.modelData.events
                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool released: Number.isFinite(modelData.actual)
                    readonly property bool upcoming: !released && modelData.time * 1000 > root.now
                    Layout.fillWidth: true
                    implicitHeight: line.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: rowHover.hovered ? Util.alpha(Color.foreground, .04) : "transparent"
                    RowLayout {
                        id: line
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.space(6)
                        anchors.rightMargin: Style.space(6)
                        spacing: Style.space(12)
                        Label {
                            text: Qt.formatTime(new Date(row.modelData.time * 1000), "hh:mm")
                            color: row.upcoming ? Color.foreground : Color.muted
                            font.pixelSize: Style.font.bodySmall
                            Layout.preferredWidth: Style.space(44)
                        }
                        Label {
                            text: row.modelData.title + (row.modelData.period ? "  ·  " + row.modelData.period : "")
                            color: row.upcoming || row.released ? Color.foreground : Color.muted
                            font.pixelSize: Style.font.bodySmall
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: row.released
                            text: "Actual " + root.value(row.modelData, row.modelData.actual)
                            color: Number.isFinite(row.modelData.forecast) && row.modelData.actual !== row.modelData.forecast
                                ? StockStore.direction(row.modelData.actual - row.modelData.forecast) : Color.foreground
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                        }
                        Label {
                            text: [["Fcst", row.modelData.forecast], ["Prev", row.modelData.previous]]
                                .filter(pair => Number.isFinite(pair[1])).map(pair => pair[0] + " " + root.value(row.modelData, pair[1])).join("  ")
                            color: Color.muted
                            font.pixelSize: Style.font.bodySmall
                        }
                    }
                    HoverHandler { id: rowHover }
                    Ui.PanelToolTip {
                        visible: rowHover.hovered
                        text: Qt.formatDateTime(new Date(row.modelData.time * 1000), "ddd d MMM hh:mm") + (row.modelData.source ? " · " + row.modelData.source : "")
                            + (row.released && Number.isFinite(row.modelData.forecast) ? "\nGreen/red: actual above/below forecast (not good/bad news)" : "")
                    }
                }
            }
        }
    }
    Timer { interval: 60000; running: root.visible && StockStore.windowOpen; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() }
}
