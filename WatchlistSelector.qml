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
            opacity: selector.revealed ? 1 : 0
            options: StockStore.watchlists.map(row=>({value:row.id,label:row.name}))
            value: StockStore.activeWatchlist
            enabled: !StockStore.busy
            onChanged: value => {
                StockStore.request(["watchlist", "select", value])
                dropdown.value = Qt.binding(() => StockStore.activeWatchlist)
            }
        }
        Label {
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.controlPaddingX
            visible: !selector.revealed
            text: StockStore.watchlistName
            verticalAlignment: Text.AlignVCenter
        }
    }
    ActionButton {
        objectName: "editWatchlists"
        text: "\uf040"
        hint: "Manage watchlists"
        onClicked: { dropdown.close(); root.editRequested() }
    }
}
