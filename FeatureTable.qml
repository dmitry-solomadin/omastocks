import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."

// Shared presentation only; each feature owns its data and transforms.
Flickable {
    id: root
    property var headers: []
    property var rows: []
    property var verticalFlickable
    property real firstWidth: Style.space(155)
    property real cellWidth: Style.space(105)
    property real rowHeight: Style.space(56)
    readonly property real actualCellWidth: Math.max(cellWidth, (width - firstWidth) / Math.max(1, headers.length))
    Layout.fillWidth: true
    Layout.preferredHeight: table.height + Style.space(12)
    contentWidth: firstWidth + headers.length * actualCellWidth
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    FastWheel { flickable: root.verticalFlickable }
    Controls.ScrollBar.horizontal: Controls.ScrollBar {}
    Column {
        id: table
        width: root.contentWidth
        Row {
            height: Style.space(36)
            Item { width: root.firstWidth; height: 1 }
            Repeater {
                model: root.headers
                Label { required property string modelData; text: modelData; width: root.actualCellWidth; height: Style.space(36); verticalAlignment: Text.AlignVCenter; color: Color.muted; font.pixelSize: Style.font.bodySmall }
            }
        }
        Repeater {
            model: root.rows
            Item {
                id: tableRow
                required property var modelData
                width: table.width
                height: root.rowHeight
                Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.foreground, .08) }
                Item {
                    width: root.firstWidth - Style.space(8)
                    height: parent.height
                    Label { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: tableRow.modelData.label; wrapMode: Text.WordWrap; font.pixelSize: Style.font.bodySmall; color: Color.foreground }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: tableRow.modelData.symbol ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (tableRow.modelData.symbol) StockStore.select(tableRow.modelData.symbol)
                    }
                    Ui.PanelToolTip { visible: rowMouse.containsMouse && !!tableRow.modelData.hint; text: tableRow.modelData.hint || "" }
                }
                Row {
                    x: root.firstWidth
                    height: parent.height
                    Repeater {
                        model: tableRow.modelData.cells
                        Item {
                            id: cell
                            required property var modelData
                            width: root.actualCellWidth; height: tableRow.height
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Style.space(8)
                                spacing: Style.space(3)
                                Label { width: parent.width; text: cell.modelData.text || "—"; color: cell.modelData.color || Color.foreground; font.pixelSize: Style.font.bodySmall }
                                Label { width: parent.width; visible: !!cell.modelData.subtext; text: cell.modelData.subtext || ""; color: Color.muted; font.pixelSize: Style.font.bodySmall }
                            }
                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent; hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                            Ui.PanelToolTip { visible: cellMouse.containsMouse && !!cell.modelData.hint; text: cell.modelData.hint || "" }
                        }
                    }
                }
            }
        }
    }
}
