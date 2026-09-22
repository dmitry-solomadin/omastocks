import QtQuick
import qs.Commons
import qs.Ui as Ui
import "."

Label {
    id: root
    objectName: "extendedQuote"
    readonly property var quote: MarketStore.extended.quote || null
    visible: !!quote
    text: quote ? quote.label + "  " + StockStore.price(quote.price)
        + (quote.change !== null ? "  " + (quote.change >= 0 ? "+" : "") + StockStore.price(quote.change)
            + " (" + StockStore.percent(quote.percent) + ")" : "")
        + " · " + Qt.formatDateTime(new Date(quote.updated * 1000), "d MMM, hh:mm")
        + (MarketStore.extended.stale ? " · Saved data" : "") : ""
    font.pixelSize: Style.font.bodySmall
    color: StockStore.direction(quote ? quote.change : null)
    wrapMode: Text.WordWrap
    HoverHandler { id: hover }
    Ui.PanelToolTip {
        visible: hover.hovered
        text: "Yahoo Finance · Latest sampled extended-hours price · " + (MarketStore.extended.currency || "")
            + "\nChange versus the preceding regular-session close. Timestamp is local time. Prices may be delayed."
            + (MarketStore.extended.error ? "\n" + MarketStore.extended.error : "")
    }
}
