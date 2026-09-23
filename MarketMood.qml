import QtQuick
import qs.Commons
import qs.Ui as Ui
import "."
import "PixelSprites.js" as Sprites

Item {
    id: root
    objectName: "marketMood"
    readonly property var quote: StockStore.marketQuotes["^SPX"] || {}
    readonly property var change: quote.percent
    readonly property bool known: Number.isFinite(change) && !StockStore.marketQuotesRequest.data.stale && !StockStore.marketQuotesRequest.data.error
    implicitWidth: art.implicitWidth
    implicitHeight: art.implicitHeight
    PixelArt {
        id: art
        anchors.centerIn: parent
        pixels: !root.known || root.change === 0 ? Sprites.neutral : root.change < 0 ? Sprites.bear : Sprites.bull
        ink: !root.known || root.change === 0 ? Color.muted : StockStore.direction(root.change)
        shade: Color.foreground
        opacity: root.known ? 1 : .35
    }
    HoverHandler { id: hover }
    Ui.PanelToolTip { visible: hover.hovered; text: root.known ? "S&P 500 · latest daily change " + StockStore.percent(root.change) : "Waiting for market direction" }
    Accessible.role: Accessible.StaticText
    Accessible.name: root.known ? "S&P 500 " + StockStore.percent(root.change) : "Market direction unavailable"
}
