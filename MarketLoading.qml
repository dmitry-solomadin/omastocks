import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."

RowLayout {
    id: root
    objectName: "marketLoading"
    property bool active: false
    property string text: "Loading market data…"
    property real phase: 0
    visible: active
    spacing: Style.space(14)
    implicitHeight: Style.space(48)
    Accessible.role: Accessible.StaticText
    Accessible.name: text
    NumberAnimation on phase {
        from: 0; to: 1; duration: 4800; loops: Animation.Infinite
        running: root.active && root.visible && StockStore.windowOpen
    }
    Item {
        id: chart
        Layout.preferredWidth: Style.space(78)
        Layout.preferredHeight: Style.space(40)
        clip: true
        Accessible.ignored: true
        Repeater {
            model: [ {y:20,h:10,up:true}, {y:18,h:7,up:false}, {y:12,h:13,up:true},
                {y:8,h:8,up:true}, {y:10,h:9,up:false}, {y:16,h:12,up:false},
                {y:21,h:8,up:false}, {y:15,h:12,up:true}, {y:9,h:10,up:true},
                {y:7,h:6,up:false}, {y:12,h:10,up:false}, {y:18,h:9,up:false} ]
            Item {
                id: candle
                required property var modelData
                required property int index
                readonly property real position: ((index - root.phase * 12 + 12) % 12) * Style.space(13) - Style.space(13)
                readonly property real formed: Math.max(0, Math.min(1, (chart.width - position) / Style.space(18)))
                readonly property color ink: modelData.up ? StockStore.gain : StockStore.loss
                x: position
                y: Style.space(modelData.y)
                width: Style.space(7)
                height: Style.space(modelData.h)
                opacity: .55 + .45 * (1 - formed)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -Style.space(4) * candle.formed
                    width: Style.space(1); height: parent.height + Style.space(8) * candle.formed
                    color: candle.ink
                }
                Rectangle {
                    // Only the newest candle develops; completed candles stay fixed.
                    y: candle.modelData.up ? parent.height - height : 0
                    width: parent.width; height: parent.height * (.2 + .8 * candle.formed)
                    radius: Style.space(1)
                    color: candle.ink
                }
            }
        }
    }
    Label {
        Layout.fillWidth: true
        text: root.text
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
    }
}
