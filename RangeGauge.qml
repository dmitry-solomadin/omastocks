import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."

RowLayout {
    id: root
    property var low: null
    property var high: null
    property var price: null
    readonly property bool validRange: low !== null && low !== undefined && isFinite(low)
        && high !== null && high !== undefined && isFinite(high) && high >= low
    readonly property bool validPrice: price !== null && price !== undefined && isFinite(price)
    readonly property real fraction: validRange && validPrice
        ? high === low ? .5 : Math.max(0, Math.min(1, (price - low) / (high - low))) : .5
    spacing: Style.space(10)
    Accessible.role: Accessible.Indicator
    Accessible.name: "52-week low " + StockStore.price(low) + ", high " + StockStore.price(high)
        + ", current price " + StockStore.price(price)
    Label { text: StockStore.price(root.low); font.bold: true }
    Item {
        Layout.fillWidth: true
        implicitHeight: Style.space(12)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: Style.space(2)
            color: Util.alpha(Color.foreground, root.validRange ? .3 : .1)
        }
        Rectangle {
            objectName: "rangePriceDot"
            visible: root.validRange && root.validPrice
            width: Style.space(9); height: width; radius: width / 2
            x: root.fraction * Math.max(0, parent.width - width)
            anchors.verticalCenter: parent.verticalCenter
            color: Color.foreground
        }
    }
    Label { text: StockStore.price(root.high); font.bold: true }
    HoverHandler { id: hover }
    Ui.PanelToolTip { visible: hover.hovered; text: root.Accessible.name }
}
