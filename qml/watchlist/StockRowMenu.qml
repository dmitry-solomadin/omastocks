import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui
import ".."

// Right-click actions for a watchlist row.
Controls.Menu {
    id: menu
    objectName: "stockRowMenu"
    property var entry: ({})
    readonly property string symbol: entry.symbol || ""
    readonly property var targets: StockStore.watchlists.filter(row => row.id !== StockStore.activeWatchlist)
    width: Style.space(235)
    padding: Style.space(4)
    // "Move to" only appears when there is another list to move to.
    property bool moveShown: true
    function openFor(row) {
        entry = row
        if (!targets.length && moveShown) { takeMenu(1); moveShown = false }
        else if (targets.length && !moveShown) { insertMenu(1, moveMenu); moveShown = true }
        popup()
    }

    component Surface: Ui.BorderSurface {
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
        radius: Style.cornerRadius
    }
    component Entry: Controls.MenuItem {
        id: option
        property color ink: Color.popups.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        implicitHeight: Style.space(34)
        enabled: !StockStore.busy
        contentItem: Label {
            text: option.text
            color: option.highlighted ? Style.hoverStateColor(option.ink, Color.accent) : option.ink
            opacity: option.enabled ? 1 : .5
            verticalAlignment: Text.AlignVCenter
            leftPadding: Style.space(8)
            rightPadding: Style.space(20)
        }
        arrow: Label {
            x: option.width - width - Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            visible: !!option.subMenu
            text: "›"
            color: Color.popups.text
        }
        background: Rectangle {
            radius: Style.cornerRadius
            color: option.highlighted ? Style.hoverFillFor(option.ink, Color.accent) : "transparent"
        }
    }

    background: Surface {}
    delegate: Entry {}

    Entry {
        objectName: "rowMenu_favorite"
        text: menu.entry.favorite ? "Hide from bar" : "Show in bar"
        onTriggered: StockStore.request(["favorite", menu.symbol])
    }
    Controls.Menu {
        id: moveMenu
        title: "Move to"
        width: Style.space(200)
        padding: Style.space(4)
        enabled: !StockStore.busy
        background: Surface {}
        Instantiator {
            model: menu.targets
            delegate: Entry {
                required property var modelData
                objectName: "rowMenu_move_" + modelData.id
                text: modelData.name
                onTriggered: StockStore.transfer(menu.symbol, modelData.id)
            }
            onObjectAdded: (index, object) => moveMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => moveMenu.removeItem(object)
        }
    }
    Controls.MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Util.alpha(Color.popups.text, .12) }
    }
    Entry {
        objectName: "rowMenu_remove"
        text: "Remove from watchlist"
        ink: StockStore.loss
        onTriggered: StockStore.remove(menu.symbol)
    }
}
