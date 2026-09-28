import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

// The pre-market or after-hours quote, set at the right edge of the price row:
// a secondary figure beside the close, a step above body text. Its caption
// lines up with the close's. It comes with the regular quote, on the same poll.
ColumnLayout {
    id: root
    objectName: "extendedQuote"
    readonly property var quote: StockStore.extendedQuote(StockStore.quote)
    visible: !!quote
    spacing: Style.space(4)
    Label {
        objectName: "extendedLabel"
        Layout.alignment: Qt.AlignRight
        text: root.quote ? root.quote.label.toUpperCase() + (StockStore.quote.stale ? " · SAVED DATA" : "") : ""
        color: Tone.muted
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
    }
    Label {
        objectName: "extendedPrice"
        Layout.alignment: Qt.AlignRight
        text: root.quote ? StockStore.price(root.quote.price) : ""
        font.pixelSize: Style.font.title
        font.bold: true
    }
    Label {
        objectName: "extendedChange"
        Layout.alignment: Qt.AlignRight
        visible: !!root.quote && root.quote.change !== null
        text: root.quote && root.quote.change !== null ? (root.quote.change >= 0 ? "+" : "") + StockStore.price(root.quote.change)
            + " (" + StockStore.percent(root.quote.percent) + ")" : ""
        color: StockStore.direction(root.quote ? root.quote.change : null)
        font.pixelSize: Style.font.bodySmall
    }
    HoverHandler { id: hover }
    Ui.PanelToolTip {
        visible: hover.hovered
        text: "Yahoo Finance · Latest extended-hours price · " + (StockStore.quote.currency || "")
            + (root.quote ? "\nAs of " + Qt.formatDateTime(new Date(root.quote.updated * 1000), "d MMM, hh:mm") + " local time" : "")
            + "\nChange versus the preceding regular-session close. Prices may be delayed."
            + (StockStore.quote.stale && StockStore.quote.error ? "\n" + StockStore.quote.error : "")
    }
}
