import QtQuick
import QtQuick.Layouts
import qs.Commons
import ".."

// A pick-one row of joined buttons in one bordered tray. Selecting a segment
// deselects the previous one; the selection is never empty. It is one Tab stop,
// and ← / → move the selection. Segments are ActionButtons named
// `objectNamePrefix + value`, so they are reachable over IPC like other buttons.
//
// `options` is an array of { value, label, hint? }.
Rectangle {
    id: root
    property var options: []
    property string value: ""
    property string objectNamePrefix: ""
    signal activated(string value)

    readonly property int selectedIndex: options.findIndex(option => option.value === value)
    function select(index) {
        if (index < 0 || index >= options.length || options[index].value === value) return
        activated(options[index].value)
    }

    implicitHeight: Style.space(34)
    implicitWidth: row.implicitWidth + Style.space(4)
    radius: Style.cornerRadius
    color: Util.alpha(Color.foreground, .03)
    border.width: 1
    border.color: activeFocus ? Color.accent : Tone.border
    activeFocusOnTab: true
    Keys.onLeftPressed: select(selectedIndex - 1)
    Keys.onRightPressed: select(selectedIndex + 1)
    Accessible.role: Accessible.Grouping

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Style.space(2)
        spacing: 0
        Repeater {
            model: root.options
            RowLayout {
                id: segment
                required property var modelData
                required property int index
                readonly property bool selected: index === root.selectedIndex
                spacing: 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                // Equal widths regardless of label length.
                Layout.preferredWidth: 1
                // A divider between two unselected neighbours; a selected
                // segment's tint already separates it.
                Rectangle {
                    visible: segment.index > 0
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.topMargin: Style.space(7)
                    Layout.bottomMargin: Style.space(7)
                    color: segment.selected || segment.index - 1 === root.selectedIndex ? "transparent" : Tone.border
                }
                ActionButton {
                    objectName: root.objectNamePrefix + segment.modelData.value
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: Style.space(30)
                    focusPolicy: Qt.NoFocus
                    text: segment.modelData.label
                    hint: segment.modelData.hint || ""
                    selected: segment.selected
                    enabled: root.enabled
                    onClicked: root.select(segment.index)
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: segment.selected
                }
            }
        }
    }
}
