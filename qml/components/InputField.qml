import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import ".."

// The app's text input: stock search, watchlist names. A trailing button
// (such as clear) goes inside and widens `rightPadding`.
Controls.TextField {
    id: root
    implicitHeight: Style.space(38)
    color: Color.foreground
    placeholderTextColor: Tone.muted
    selectionColor: Util.alpha(Color.accent, .3)
    selectedTextColor: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    leftPadding: Style.space(12)
    rightPadding: Style.space(12)
    background: Rectangle {
        color: Util.alpha(Color.foreground, .04)
        radius: Style.cornerRadius
        border.width: 1
        border.color: root.activeFocus ? Color.accent : Tone.border
    }
}
