import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."
import "Treemap.js" as Treemap

ColumnLayout {
    id: root
    property var rows: []
    property string period: "1D"
    property bool busy: false
    property string error: ""
    spacing: Style.space(6)
    Item {
        id: map
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(Style.space(360), width * .72)
        // The map keeps its space while loading, so the page below never jumps;
        // tiles fade in once data arrives.
        readonly property bool filled: root.rows.some(row => Treemap.eligible(row))
        readonly property var cells: Treemap.layout(root.rows, width, height)
        Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Util.alpha(Color.foreground, .03)
            opacity: map.filled ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 250 } }
            Label {
                anchors.centerIn: parent
                text: root.busy ? "Loading market map…" : root.error || ""
                color: Color.muted
                font.pixelSize: Style.font.bodySmall
            }
        }
        Item {
            anchors.fill: parent
            opacity: map.filled ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
            Loader {
                anchors.fill: parent
                active: root.rows.length > 150
                sourceComponent: DenseHeatmap { cells: map.cells; period: root.period }
            }
            Repeater {
                model: root.rows.length > 150 ? [] : map.cells
                Item {
                    id: tile
                    required property var modelData
                    readonly property var entry: modelData.entry
                    objectName: "marketTile_" + entry.symbol
                    readonly property var change: root.period === "YTD" ? entry.ytd : entry.percent
                    x: modelData.x; y: modelData.y
                    width: modelData.width; height: modelData.height
                    clip: true
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Math.min(Style.space(2), tile.width / 12, tile.height / 12)
                        radius: Math.min(Style.cornerRadius, tile.width / 8, tile.height / 8)
                        color: Util.alpha(StockStore.direction(tile.change), .12 + Math.min(Math.abs(tile.change || 0), 10) * .025)
                    }
                    Column {
                        anchors.centerIn: parent
                        width: Math.max(0, parent.width - Style.space(8))
                        spacing: Style.space(4)
                        visible: tile.width >= Style.space(36) && tile.height >= Style.space(22)
                        Label {
                            width: parent.width
                            text: tile.entry.symbol; font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Math.max(Style.font.bodySmall, Math.min(Style.space(22), Math.sqrt(tile.width * tile.height) / 10))
                        }
                        Label {
                            visible: tile.height >= Style.space(48) && tile.width >= Style.space(65)
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: StockStore.percent(tile.change); color: StockStore.direction(tile.change)
                            font.pixelSize: Style.font.bodySmall
                        }
                    }
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: StockStore.select(tile.entry.symbol)
                    }
                    Ui.PanelToolTip {
                        visible: hover.containsMouse
                        text: tile.entry.name + " (" + tile.entry.symbol + ")\nMarket cap " + StockStore.compact(tile.entry.marketCap)
                            + " · " + root.period + " " + StockStore.percent(tile.change)
                    }
                }
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: Style.space(4)
        visible: missing.count > 0
        Repeater {
            id: missing
            model: root.rows.filter(row => !Treemap.eligible(row))
            ActionButton {
                required property var modelData
                text: modelData.symbol + " —"
                hint: modelData.name + " · Market cap unavailable"
                onClicked: StockStore.select(modelData.symbol)
            }
        }
    }
}
