import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."

ColumnLayout {
    id: root
    property bool editing: false
    property bool creating: false
    spacing: Style.space(6)
    RowLayout {
        Layout.fillWidth: true
        Ui.Dropdown {
            objectName: "watchlistSelector"
            Layout.fillWidth: true
            options: StockStore.watchlists.map(row=>({value:row.id,label:row.name}))
            value: StockStore.activeWatchlist
            enabled: !StockStore.busy
            onChanged: value => { root.editing = false; StockStore.request(["watchlist", "select", value]) }
        }
        ActionButton { text: "+"; hint: "Create watchlist"; enabled: !StockStore.busy; onClicked: { root.creating = true; root.editing = true; nameInput.text = ""; nameInput.forceActiveFocus() } }
        ActionButton { text: "⋯"; hint: "Rename or remove watchlist"; enabled: !StockStore.busy; onClicked: { root.creating = false; root.editing = !root.editing; nameInput.text = StockStore.watchlistName; nameInput.forceActiveFocus(); nameInput.selectAll() } }
    }
    Controls.TextField {
        id: nameInput
        visible: root.editing
        Layout.fillWidth: true
        placeholderText: "Watchlist name"
        maximumLength: 40
        color: Color.foreground; placeholderTextColor: Color.muted
        font.family: Style.font.family; font.pixelSize: Style.font.body
        selectionColor: Color.accent
        background: Rectangle { color: Util.alpha(Color.foreground,.05); radius: Style.cornerRadius; border.width: 1; border.color: Color.muted }
        onAccepted: if (text.trim() && !StockStore.busy) root.save()
    }
    function save() {
        StockStore.request(["watchlist", creating ? "create" : "rename", creating ? "" : StockStore.activeWatchlist, nameInput.text])
        editing = false
    }
    Flow {
        visible: root.editing
        Layout.fillWidth: true; spacing: Style.space(4)
        ActionButton { text: root.creating ? "Create" : "Rename"; enabled: !!nameInput.text.trim() && !StockStore.busy; onClicked: root.save() }
        ActionButton { text: "Cancel"; onClicked: root.editing = false }
        ActionButton { text: "Remove list"; visible: !root.creating; enabled: StockStore.watchlists.length > 1 && !StockStore.busy; hint: "Remove this list; other lists keep their stocks"; onClicked: { StockStore.request(["watchlist","remove",StockStore.activeWatchlist]); root.editing = false } }
    }
    Label { visible: !!StockStore.error; text: StockStore.error; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.muted; font.pixelSize: Style.font.bodySmall }
}
