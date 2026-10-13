import QtQuick
import QtQuick.Layouts
import qs.Commons
import ".."

// The bull and bear case: two tinted cards of headed, sourced points.
ReportPopup {
    id: root
    name: "bullBear"
    title: "Bull & bear · " + StockStore.selected
    store: BullBearStore
    note: Date.now() / 1000 - (report.generated || 0) > 7 * 86400 ? "Over a week old — refresh for the latest" : ""

    component Case: Rectangle {
        id: card
        property string title
        property color tone
        property var points: []
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: cardContent.implicitHeight + Style.space(36)
        radius: Style.cornerRadius
        color: Util.alpha(tone, .05)
        border.width: 1
        border.color: Util.alpha(tone, .3)
        ColumnLayout {
            id: cardContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(18)
            spacing: Style.space(16)
            Label {
                text: card.title
                color: card.tone
                font.bold: true
                font.letterSpacing: Style.space(1)
                font.pixelSize: Style.font.bodySmall
            }
            Repeater {
                model: card.points
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Style.space(4)
                    Label {
                        text: modelData.title
                        font.bold: true
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                    CitedText { detail: modelData.detail; cited: modelData.sources; sources: root.sources }
                }
            }
        }
    }

    GridLayout {
        objectName: "bullBearCases"
        Layout.fillWidth: true
        columns: root.width > Style.space(720) ? 2 : 1
        uniformCellWidths: true
        columnSpacing: Style.space(16)
        rowSpacing: Style.space(16)
        Case { objectName: "bullCase"; title: "▲  BULL CASE"; tone: "#4caf50"; points: root.report.bull || [] }
        Case { objectName: "bearCase"; title: "▼  BEAR CASE"; tone: "#ef5350"; points: root.report.bear || [] }
    }
}
