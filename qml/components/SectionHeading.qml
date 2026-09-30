import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui
import ".."

// A section's title: spaced capitals, flush with the content's left edge. A
// collapsible section sets `collapsible`; its chevron trails the title, so every
// title starts at the same x whether it folds or not. A `hint` shows on hover;
// only a collapsible title brightens and shows the hand cursor.
Controls.AbstractButton {
    id: root
    property bool collapsible: false
    property bool open: true
    property string hint: ""
    enabled: collapsible || hint !== ""
    hoverEnabled: enabled
    padding: 0
    implicitWidth: row.implicitWidth
    implicitHeight: Style.space(34)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    Accessible.name: text
    Accessible.role: collapsible ? Accessible.Button : Accessible.StaticText
    Accessible.description: hint
    HoverHandler { enabled: root.collapsible; cursorShape: Qt.PointingHandCursor }
    Ui.PanelToolTip { visible: root.hovered && root.hint !== ""; text: root.hint }
    contentItem: Item {
        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Label {
                text: root.text
                color: root.hovered && root.collapsible ? Color.foreground : Tone.muted
                font.family: root.font.family
                font.pixelSize: root.font.pixelSize
                font.bold: true
                font.letterSpacing: Style.space(1)
            }
            Label {
                visible: root.collapsible
                anchors.verticalCenter: parent.verticalCenter
                text: root.open ? "▾" : "▸"
                color: root.hovered && root.collapsible ? Color.foreground : Tone.muted
                font.pixelSize: root.font.pixelSize
            }
        }
    }
    background: null
}
