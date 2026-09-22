import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."

RowLayout {
    id: root
    signal editRequested()
    readonly property bool popupOpen: dropdown.popupOpen
    function close() { dropdown.close() }
    spacing: Style.space(6)
    HoverHandler { id: rowHover }
    FocusScope {
        id: selector
        Layout.fillWidth: true
        Layout.preferredHeight: dropdown.implicitHeight
        readonly property bool revealed: rowHover.hovered || activeFocus || dropdown.popupOpen
        Ui.Dropdown {
            id: dropdown
            objectName: "watchlistSelector"
            anchors.fill: parent
            rowHeight: editButton.implicitHeight
            opacity: selector.revealed ? 1 : 0
            options: StockStore.watchlists.map(row=>({value:row.id,label:row.name}))
            value: StockStore.activeWatchlist
            enabled: !StockStore.busy
            onChanged: value => {
                StockStore.request(["watchlist", "select", value])
                dropdown.value = Qt.binding(() => StockStore.activeWatchlist)
            }
        }
        // Match Dropdown's Text item: border inset, baseline and renderer.
        Text {
            objectName: "watchlistRestingName"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Border.left(Border.controlSpec("hover-cursor", dropdown.foreground, dropdown.accent)) + Style.spacing.controlPaddingX
            anchors.rightMargin: Border.right(Border.controlSpec("hover-cursor", dropdown.foreground, dropdown.accent)) * 2
                + Style.spacing.controlGap + Style.spacing.md + chevronMetrics.width
            visible: !selector.revealed
            text: StockStore.watchlistName
            color: dropdown.foreground
            font.family: dropdown.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
        TextMetrics { id: chevronMetrics; text: "󰅀"; font.family: dropdown.fontFamily; font.pixelSize: Style.font.body }
    }
    ActionButton {
        id: editButton
        objectName: "editWatchlists"
        text: "\uf040"
        hint: "Manage watchlists"
        onClicked: { dropdown.close(); root.editRequested() }
    }
}
