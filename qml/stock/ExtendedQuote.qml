import QtQuick
import qs.Commons
import qs.Ui as Ui
import ".."
import "../market/MarketClock.js" as Clock

Label {
    id: root
    objectName: "extendedQuote"
    readonly property var quote: MarketStore.extended.quote || null
    // Outside regular hours the line usually appears once data loads; keep its
    // height while loading so the page below does not jump.
    // Until the provider's session is known, the New York schedule decides, so
    // the line is not reserved (and then dropped) during regular hours.
    readonly property string session: Clock.normalize((StockStore.marketQuotes["^SPX"] || {}).marketState) || Clock.scheduled(Date.now())
    readonly property bool pending: MarketStore.stockResearchActive && MarketStore.extended.symbol !== StockStore.selected
        && session !== "REGULAR"
    visible: !!quote || pending
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
