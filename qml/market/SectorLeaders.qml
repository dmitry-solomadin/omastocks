import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."
import "MarketAssets.js" as Assets

// Today's best and worst sectors from the SPDR sector ETFs. A sector opens its
// heatmap; hovering "Leading" or "Lagging" lists all eleven in order.
Flow {
    id: root
    objectName: "sectorLeaders"
    readonly property var ranked: Assets.rankedSectors(StockStore.marketQuotes)
    readonly property var leaders: ranked.slice(0, 2)
    readonly property bool ready: ranked.length > 4
    readonly property var laggards: ready ? ranked.slice(-2).reverse() : []
    signal picked(string sector)
    spacing: Style.space(6)

    component Heading: Label {
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
        height: Style.space(28)
        verticalAlignment: Text.AlignVCenter
        HoverHandler { id: headingHover }
        Ui.PanelToolTip {
            visible: headingHover.hovered
            text: "Sectors today (SPDR sector ETFs)\n" + root.ranked.map(row => StockStore.percent(row.percent) + "  " + row.name).join("\n")
        }
    }
    component Sector: ActionButton {
        required property var modelData
        implicitHeight: Style.space(28)
        padding: Style.space(6)
        font.pixelSize: Style.font.bodySmall
        text: modelData.name + "  " + StockStore.percent(modelData.percent)
        ink: StockStore.direction(modelData.percent)
        hint: "Show " + modelData.name + " in the heatmap · " + modelData.symbol
        onClicked: root.picked(modelData.sector)
        NumberAnimation on opacity { from: 0; to: 1; duration: 250 }
    }
    // Keeps the line's height while sector quotes load, so the page below never jumps.
    component Pending: Label { visible: !root.ready; text: "—"; color: Color.muted; height: Style.space(28); verticalAlignment: Text.AlignVCenter }

    Heading { text: "Leading" }
    Pending {}
    Repeater { model: root.ready ? root.leaders : []; Sector {} }
    Item { width: Style.space(12); height: 1 }
    Heading { text: "Lagging" }
    Pending {}
    Repeater { model: root.laggards; Sector {} }
}
