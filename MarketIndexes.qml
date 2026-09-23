import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."

RowLayout {
    spacing: Style.space(8)
    MarketMood { Layout.alignment: Qt.AlignVCenter; Layout.rightMargin: Style.space(8) }
    Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Repeater {
        model: [{symbol:"^SPX",name:"S&P 500"},{symbol:"^IXIC",name:"Nasdaq"},{symbol:"^RUT",name:"Russell 2000"},{symbol:"^VIX",name:"VIX"}]
        ActionButton {
            required property var modelData
            readonly property var quote: StockStore.watchlistQuotes[modelData.symbol] || {}
            text: modelData.name + "  " + StockStore.percent(quote.percent)
            ink: StockStore.direction(quote.percent)
            hint: StockStore.watchlistQuotesRequest.data.error || quote.error || "Open " + modelData.name + (quote.updated ? " · " + Qt.formatDateTime(new Date(quote.updated * 1000), "d MMM hh:mm") : "")
            onClicked: StockStore.select(modelData.symbol)
        }
    }
    }
}
