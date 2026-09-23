import QtQuick
import qs.Commons
import ".."

// Sidebar logo: vector candles beside "Stocks". The candles rise in sequence on
// play().
Row {
    id: root
    objectName: "stocksLogo"
    property real unit: Style.space(20)
    spacing: unit * .45
    Accessible.role: Accessible.StaticText
    Accessible.name: "Stocks"
    function play() { grow.restart() }
    CandleMark { id: mark; unit: root.unit; anchors.verticalCenter: parent.verticalCenter }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Stocks"
        color: Color.foreground
        font.family: "Adwaita Sans"
        font.weight: Font.Bold
        font.pixelSize: root.unit * 1.05
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }
    NumberAnimation { id: grow; target: mark; property: "rise"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
}
