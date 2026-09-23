import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui
import ".."

Controls.Button {
    id: root
    property bool selected: false
    property string hint: ""
    property color ink: selected ? Color.accent : Color.foreground
    implicitHeight: Style.space(34)
    implicitWidth: label.implicitWidth + Style.space(24)
    padding: Style.space(10)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    hoverEnabled: true
    Ui.PanelToolTip { visible: root.hovered && root.hint !== ""; text: root.hint }
    Accessible.name: hint || text
    background: Rectangle {
        radius: Style.cornerRadius
        color: root.down ? Util.alpha(Color.foreground, .16) : root.selected ? Util.alpha(Color.accent, .12) : root.hovered ? Util.alpha(Color.foreground, .07) : "transparent"
    }
    contentItem: Label {
        id: label
        text: root.text
        color: root.ink
        font.family: root.font.family
        font.pixelSize: root.font.pixelSize
        font.bold: root.selected
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: root.enabled ? 1 : .4
    }
}
