import QtQuick
import qs.Commons
import qs.Ui as Ui
import ".."

// A small accent-tinted tag for corporate events (E, D, S) with a tooltip.
Rectangle {
    id: root
    property string text: ""
    property string hint: ""
    // Imminent events get a stronger tint and bold text.
    property bool strong: false
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + Style.space(8))
    implicitHeight: label.implicitHeight + Style.space(2)
    radius: Style.space(3)
    color: Util.alpha(Color.accent, strong ? .28 : .14)
    Label {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: Color.accent
        font.pixelSize: Style.font.bodySmall
        font.bold: root.strong
    }
    HoverHandler { id: hover }
    Ui.PanelToolTip { visible: hover.hovered && root.visible && root.hint !== ""; text: root.hint }
    Accessible.role: Accessible.StaticText
    Accessible.name: hint || text
}
