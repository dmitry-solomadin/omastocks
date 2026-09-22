import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."

Controls.Popup {
    id: menu
    objectName: "watchlistMenu"
    property string editingId: ""
    property string pendingAction: ""
    property string saveError: ""
    readonly property var editingList: StockStore.watchlists.find(row => row.id === editingId)
    readonly property bool canRename: !!editingList && !!nameInput.text.trim()
        && nameInput.text.trim() !== editingList.name && !StockStore.busy
    readonly property bool canCreate: !!newName.text.trim() && StockStore.watchlists.length < 12 && !StockStore.busy

    function selectList(id) {
        editingId = id
        nameInput.text = editingList ? editingList.name : ""
        saveError = ""
    }
    function save(action) {
        if (StockStore.busy || (action === "rename" && !canRename)
            || (action === "create" && !canCreate)
            || (action === "remove" && (!editingList || StockStore.watchlists.length <= 1))) return
        saveError = ""
        pendingAction = action
        StockStore.request(["watchlist", action, action === "create" ? "" : editingId,
            action === "create" ? newName.text.trim() : action === "rename" ? nameInput.text.trim() : ""])
    }
    Connections {
        target: StockStore
        function onBusyChanged() {
            if (StockStore.busy || !menu.pendingAction) return
            const action = menu.pendingAction
            menu.pendingAction = ""
            menu.saveError = StockStore.error
            if (menu.saveError) return
            if (action === "create") newName.clear()
            menu.selectList(action === "rename" ? menu.editingId : StockStore.activeWatchlist)
        }
    }

    width: Math.min(Style.space(420), parent.width - Style.space(32))
    x: (parent.width - width) / 2
    y: Math.max(Style.space(16), (parent.height - height) / 2)
    padding: Style.space(24)
    modal: true
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    onOpened: { selectList(StockStore.activeWatchlist); newName.clear(); nameInput.forceActiveFocus(); nameInput.selectAll() }
    Controls.Overlay.modal: Rectangle { color: Util.alpha(Color.background, .55) }
    background: Rectangle {
        color: Color.background
        radius: Style.cornerRadius
        border.width: 1
        border.color: Util.alpha(Color.foreground, .2)
    }
    component NameField: Controls.TextField {
        Layout.fillWidth: true
        implicitHeight: Style.space(36)
        maximumLength: 40
        color: Color.foreground
        placeholderTextColor: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        selectionColor: Util.alpha(Color.accent, .3)
        selectedTextColor: Color.foreground
        background: Rectangle {
            color: Util.alpha(Color.foreground, .05)
            radius: Style.cornerRadius
            border.width: 1
            border.color: parent.activeFocus ? Color.accent : Color.muted
        }
    }
    contentItem: ColumnLayout {
        spacing: Style.space(12)
        RowLayout {
            Layout.fillWidth: true
            Label { text: "Watchlists"; font.pixelSize: Style.font.heading; font.bold: true; Layout.fillWidth: true }
            ActionButton {
                objectName: "closeWatchlists"
                text: "×"
                font.pixelSize: Style.font.body * 2
                Layout.preferredWidth: Style.space(36)
                Layout.preferredHeight: Style.space(34)
                padding: 0
                hint: "Close watchlists"
                onClicked: menu.close()
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, .1) }
        Ui.Dropdown {
            id: listDropdown
            objectName: "manageWatchlistSelector"
            Layout.fillWidth: true
            options: StockStore.watchlists.map(row => ({value: row.id, label: row.name}))
            value: menu.editingId
            enabled: !StockStore.busy
            onChanged: value => {
                menu.selectList(value)
                listDropdown.value = Qt.binding(() => menu.editingId)
            }
        }
        NameField {
            id: nameInput
            objectName: "watchlistRenameInput"
            placeholderText: "Watchlist name"
            Accessible.name: "Watchlist name"
            enabled: !!menu.editingList && !menu.pendingAction
            onAccepted: menu.save("rename")
        }
        RowLayout {
            Layout.fillWidth: true
            ActionButton { objectName: "renameWatchlist"; text: "Rename"; enabled: menu.canRename; onClicked: menu.save("rename") }
            Item { Layout.fillWidth: true }
            ActionButton {
                objectName: "removeWatchlist"
                text: "Remove"
                enabled: !!menu.editingList && StockStore.watchlists.length > 1 && !StockStore.busy
                hint: StockStore.watchlists.length <= 1 ? "Keep at least one watchlist" : "Remove this list; other lists keep their stocks"
                onClicked: menu.save("remove")
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, .1) }
        RowLayout {
            Layout.fillWidth: true
            NameField {
                id: newName
                objectName: "watchlistCreateInput"
                placeholderText: "New watchlist"
                Accessible.name: "New watchlist name"
                enabled: !menu.pendingAction && StockStore.watchlists.length < 12
                onAccepted: menu.save("create")
            }
            ActionButton {
                objectName: "createWatchlist"
                text: "Add"
                enabled: menu.canCreate
                hint: StockStore.watchlists.length >= 12 ? "Maximum of 12 watchlists" : "Create watchlist"
                onClicked: menu.save("create")
            }
        }
        Label { visible: !!menu.saveError; text: menu.saveError; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.urgent }
    }
}
