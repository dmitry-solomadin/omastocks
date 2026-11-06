import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import ".."

Controls.Menu {
    id: menu
    objectName: "watchlistSortMenu"
    width: Style.space(235)
    padding: Style.space(4)
    readonly property var choices: [
        {value:"custom", label:"Custom"},
        {value:"change", label:"Price Change"},
        {value:"percent", label:"Percentage Change"},
        {value:"marketCap", label:"Market Cap"},
        {value:"symbol", label:"Symbol"},
        {value:"name", label:"Name"}
    ]
    background: Ui.BorderSurface {
        color: Commons.Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
        radius: Style.cornerRadius
    }
    Instantiator {
        model: menu.choices
        delegate: Controls.MenuItem {
            id: option
            required property var modelData
            objectName: "watchlistSort_" + modelData.value
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            text: modelData.label
            implicitHeight: Style.space(34)
            enabled: !StockStore.busy
            onTriggered: StockStore.setSortMode(modelData.value)
            contentItem: Label {
                text: (StockStore.sortMode === option.modelData.value ? "✓ " : "  ") + option.text
                color: option.highlighted ? Style.hoverStateColor(Commons.Color.popups.text, Commons.Color.accent) : Commons.Color.popups.text
                verticalAlignment: Text.AlignVCenter
                leftPadding: Style.space(8)
            }
            background: Rectangle {
                radius: Style.cornerRadius
                color: option.highlighted ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent) : "transparent"
            }
        }
        onObjectAdded: (index, object) => menu.insertItem(index, object)
        onObjectRemoved: (index, object) => menu.removeItem(object)
    }
}
