import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."
import "MarketAssets.js" as Assets

// Benchmark readouts: name above a bold price and daily change. Each opens its
// index in the Stock view; wraps in narrow headers.
Flow {
    spacing: Style.space(6)
    Repeater {
        model: Assets.benchmarks
        Rectangle {
            id: tile
            required property var modelData
            readonly property var quote: StockStore.marketQuotes[modelData.symbol] || {}
            width: lines.implicitWidth + Style.space(20)
            height: lines.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            // A soft backdrop lifts the readout off the sky scene behind the header.
            color: mouse.containsMouse ? Qt.tint(Util.alpha(Color.background, .7), Util.alpha(Color.foreground, .07)) : Util.alpha(Color.background, .55)
            ColumnLayout {
                id: lines
                anchors.centerIn: parent
                spacing: Style.space(3)
                Label { text: tile.modelData.name; color: Util.alpha(Color.foreground, .75); font.pixelSize: Style.font.bodySmall }
                RowLayout {
                    spacing: Style.space(8)
                    Label { text: StockStore.price(tile.quote.price); font.bold: true }
                    Label { text: StockStore.percent(tile.quote.percent); color: StockStore.direction(tile.quote.percent); font.bold: true }
                }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: StockStore.select(tile.modelData.symbol)
            }
            Ui.PanelToolTip {
                visible: mouse.containsMouse
                text: StockStore.marketQuotesRequest.data.error || tile.quote.error
                    || "Open " + tile.modelData.name + (tile.quote.updated ? " · " + Qt.formatDateTime(new Date(tile.quote.updated * 1000), "d MMM hh:mm") : "")
            }
            Accessible.role: Accessible.Button
            Accessible.name: tile.modelData.name + " " + StockStore.price(tile.quote.price) + " " + StockStore.percent(tile.quote.percent)
        }
    }
}
