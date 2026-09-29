import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

// A part inside a section that folds out, such as earnings calls: a full-width
// tinted row in sentence case, so it never reads as a section heading.
Controls.AbstractButton {
    id: root
    property bool open: false
    // Muted text beside the title, such as a count.
    property string detail: ""
    property string hint: ""
    padding: Style.space(12)
    implicitHeight: Style.space(38)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    hoverEnabled: true
    Accessible.name: hint || text
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    Ui.PanelToolTip { visible: root.hovered && root.hint !== ""; text: root.hint }
    background: Rectangle {
        radius: Style.cornerRadius
        color: Util.alpha(Color.foreground, root.down ? .12 : root.hovered ? .08 : .04)
    }
    contentItem: RowLayout {
        spacing: Style.space(8)
        Label { text: root.text; font: root.font }
        Label { visible: root.detail !== ""; text: root.detail; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
        Item { Layout.fillWidth: true }
        Label { text: root.open ? "Hide ▴" : "Show ▾"; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
    }
}
