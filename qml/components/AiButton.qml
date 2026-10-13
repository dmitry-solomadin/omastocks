import QtQuick
import qs.Commons
import ".."

// An action answered by the user's agent: the sparkle, then the label. The
// sparkle turns white once a saved result is waiting.
ActionButton {
    id: root
    property bool ready: false
    implicitWidth: Math.ceil(icon.implicitWidth + label.implicitWidth) + Style.space(5) + leftPadding + rightPadding
    contentItem: Row {
        spacing: Style.space(5)
        opacity: root.enabled ? 1 : .4
        AiIcon {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            color: root.ready ? "#ffffff" : root.ink
        }
        Label {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            elide: Text.ElideNone
            color: root.ink
            font: root.font
            verticalAlignment: Text.AlignVCenter
        }
    }
}
