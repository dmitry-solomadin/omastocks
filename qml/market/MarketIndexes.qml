import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."
import "MarketAssets.js" as Assets

// Benchmark readouts: name above a bold price and daily change. Each opens its
// instrument in the Stock view; wraps in narrow headers. Outside the regular
// session the equity indexes show their futures, tagged FUT.
Flow {
    id: root
    property MarketSession session: null
    readonly property bool offHours: !!session && session.state !== "" && !session.opened
    spacing: Style.space(6)
    Repeater {
        model: Assets.benchmarks
        Rectangle {
            id: tile
            required property var modelData
            readonly property var asset: Assets.benchmark(modelData, root.offHours)
            readonly property var quote: StockStore.marketQuotes[asset.symbol] || {}
            objectName: "benchmark_" + modelData.symbol
            width: lines.implicitWidth + Style.space(20)
            height: lines.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            // A soft backdrop lifts the readout off the sky scene behind the header.
            color: mouse.containsMouse ? Qt.tint(Util.alpha(Color.background, .7), Util.alpha(Color.foreground, .07)) : Util.alpha(Color.background, .55)
            ColumnLayout {
                id: lines
                anchors.centerIn: parent
                spacing: Style.space(3)
                RowLayout {
                    spacing: Style.space(6)
                    Label { text: tile.asset.name; color: Util.alpha(Color.foreground, .75); font.pixelSize: Style.font.bodySmall }
                    Rectangle {
                        visible: !!tile.asset.futures
                        implicitWidth: tag.implicitWidth + Style.space(8)
                        implicitHeight: tag.implicitHeight + Style.space(2)
                        radius: Style.cornerRadius
                        color: "transparent"
                        border.width: 1
                        border.color: Util.alpha(Color.foreground, .35)
                        Label { id: tag; anchors.centerIn: parent; text: "FUT"; color: Util.alpha(Color.foreground, .75); font.pixelSize: Style.font.bodySmall * .8 }
                    }
                }
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
                onClicked: StockStore.select(tile.asset.symbol)
            }
            Ui.PanelToolTip {
                visible: mouse.containsMouse
                text: StockStore.marketQuotesRequest.data.error || tile.quote.error
                    || (tile.asset.futures ? tile.asset.name + " futures (" + tile.asset.symbol + "), shown while the cash index is closed.\n" : "")
                    + "Open " + tile.asset.symbol + (tile.quote.updated ? " · " + Qt.formatDateTime(new Date(tile.quote.updated * 1000), "d MMM hh:mm") : "")
            }
            Accessible.role: Accessible.Button
            Accessible.name: tile.asset.name + (tile.asset.futures ? " futures " : " ") + StockStore.price(tile.quote.price) + " " + StockStore.percent(tile.quote.percent)
        }
    }
}
