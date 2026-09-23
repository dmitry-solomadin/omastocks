import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."
import "MarketAssets.js" as Assets

// Today's best and worst sectors from the SPDR sector ETFs. A sector opens its
// heatmap; hovering "Leading" or "Lagging" lists all eleven in order.
Flow {
    id: root
    objectName: "sectorLeaders"
    readonly property var ranked: Assets.rankedSectors(StockStore.marketQuotes)
    readonly property var leaders: ranked.slice(0, 2)
    readonly property var laggards: ranked.length > 4 ? ranked.slice(-2).reverse() : []
    signal picked(string sector)
    visible: ranked.length > 4
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
    }

    Heading { text: "Leading" }
    Repeater { model: root.leaders; Sector {} }
    Item { width: Style.space(12); height: 1 }
    Heading { text: "Lagging" }
    Repeater { model: root.laggards; Sector {} }
}
