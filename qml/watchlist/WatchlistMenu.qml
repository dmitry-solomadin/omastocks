import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import ".."

Controls.Popup {
    id: menu
    objectName: "watchlistMenu"
    property string editingId: ""
    property string editingName: ""
    property string pendingAction: ""
    property string pendingId: ""
    property string saveError: ""
    readonly property var editingList: StockStore.watchlists.find(row => row.id === editingId)
    readonly property bool canRename: !!editingList && !!editingName.trim() && !StockStore.busy
    readonly property bool canCreate: !!newName.text.trim() && StockStore.watchlists.length < 12 && !StockStore.busy

    function editList(id) {
        editingId = id
        editingName = editingList ? editingList.name : ""
        saveError = ""
    }
    function cancelEdit() {
        editingId = ""
        editingName = ""
        saveError = ""
    }
    function save(action, id) {
        const targetId = action === "rename" ? editingId : id || ""
        if (StockStore.busy || (action === "rename" && !canRename)
            || (action === "create" && !canCreate)
            || (action === "remove" && (!StockStore.watchlists.some(row => row.id === targetId) || StockStore.watchlists.length <= 1))) return
        saveError = ""
        if (action === "rename" && editingName.trim() === editingList.name) { editingId = ""; return }
        pendingAction = action
        pendingId = targetId
        StockStore.request(["watchlist", action, targetId,
            action === "create" ? newName.text.trim() : action === "rename" ? editingName.trim() : ""])
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
            if (menu.pendingId === menu.editingId) menu.editingId = ""
        }
    }

    width: Math.min(Style.space(420), parent.width - Style.space(32))
    x: (parent.width - width) / 2
    y: Math.max(Style.space(16), (parent.height - height) / 2)
    padding: Style.space(24)
    modal: true
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    onOpened: { editingId = ""; saveError = ""; newName.clear(); closeButton.forceActiveFocus() }
    onClosed: cancelEdit()
    MouseArea {
        parent: menu.contentItem.parent
        anchors.fill: parent
        z: 100
        enabled: !!menu.editingId && !menu.pendingAction
        onPressed: mouse => {
            // Inspect the press, then pass it through to the original control.
            mouse.accepted = false
            for (let i = 0; i < watchlistRepeater.count; ++i) {
                const row = watchlistRepeater.itemAt(i)
                if (row && row.editing && row.contains(row.mapFromItem(parent, mouse.x, mouse.y))) return
            }
            menu.cancelEdit()
        }
    }
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
        id: popupContent
        spacing: Style.space(12)
        RowLayout {
            id: header
            Layout.fillWidth: true
            Label { text: "Watchlists"; font.pixelSize: Style.font.heading; font.bold: true; Layout.fillWidth: true }
            ActionButton {
                id: closeButton
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
        Controls.ScrollView {
            id: listScroll
            objectName: "watchlistRows"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(listRows.implicitHeight, Math.max(Style.space(36),
                menu.parent.height - Style.space(32) - menu.topPadding - menu.bottomPadding
                - header.implicitHeight - createRow.implicitHeight - popupContent.spacing * 5 - 2
                - (errorLabel.visible ? errorLabel.implicitHeight : 0)))
            contentWidth: availableWidth
            clip: true
            FastWheel { flickable: listScroll.contentItem }
            ColumnLayout {
                id: listRows
                width: listScroll.availableWidth
                spacing: Style.space(6)
                Repeater {
                    id: watchlistRepeater
                    model: StockStore.watchlists
                    Item {
                        id: row
                        required property var modelData
                        readonly property bool editing: menu.editingId === modelData.id
                        objectName: "watchlistRow_" + modelData.id
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.space(36)
                        HoverHandler { id: rowHover }
                        Rectangle {
                            objectName: "watchlistRowHighlight_" + row.modelData.id
                            anchors.fill: parent
                            radius: Style.cornerRadius
                            color: rowHover.hovered || rowEdit.activeFocus ? Util.alpha(Color.foreground, .07) : "transparent"
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: Style.space(4)
                            Controls.AbstractButton {
                                id: rowEdit
                                objectName: "editWatchlist_" + row.modelData.id
                                visible: !row.editing
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                implicitHeight: Style.space(36)
                                activeFocusOnTab: true
                                enabled: !StockStore.busy
                                Accessible.name: "Rename " + row.modelData.name
                                HoverHandler { cursorShape: Qt.IBeamCursor }
                                contentItem: Label {
                                    text: row.modelData.name
                                    leftPadding: Style.space(8)
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: { menu.editList(row.modelData.id); nameInput.forceActiveFocus(); nameInput.selectAll() }
                            }
                            NameField {
                                id: nameInput
                                objectName: "watchlistRenameInput_" + row.modelData.id
                                visible: row.editing
                                text: row.editing ? menu.editingName : ""
                                Accessible.name: "Rename " + row.modelData.name
                                enabled: !menu.pendingAction
                                onTextEdited: menu.editingName = text
                                onAccepted: menu.save("rename")
                                Keys.onEscapePressed: { menu.cancelEdit(); closeButton.forceActiveFocus() }
                            }
                            ActionButton {
                                objectName: "confirmWatchlist_" + row.modelData.id
                                visible: row.editing
                                text: "\uf00c"
                                hint: "Save watchlist name"
                                enabled: menu.canRename
                                onClicked: menu.save("rename")
                            }
                            ActionButton {
                                objectName: "removeWatchlist_" + row.modelData.id
                                text: "\uf1f8"
                                enabled: StockStore.watchlists.length > 1 && !StockStore.busy
                                hint: StockStore.watchlists.length <= 1 ? "Keep at least one watchlist" : "Remove " + row.modelData.name
                                onClicked: menu.save("remove", row.modelData.id)
                            }
                        }
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, .1) }
        RowLayout {
            id: createRow
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
                text: "+"
                enabled: menu.canCreate
                hint: StockStore.watchlists.length >= 12 ? "Maximum of 12 watchlists" : "Create watchlist"
                onClicked: menu.save("create")
            }
        }
        Label { id: errorLabel; visible: !!menu.saveError; text: menu.saveError; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Color.urgent }
    }
}
