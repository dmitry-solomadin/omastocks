import QtQuick
import qs.Commons
import qs.Ui as Ui
import ".."

Item {
    id: root
    objectName: "analystTargetGauge"
    property var low: null
    property var high: null
    property var average: null
    property var price: null
    property string currency: "USD"
    function valid(value) { return value !== null && value !== undefined && isFinite(value) && value > 0 }
    readonly property bool validRange: valid(low) && valid(high) && high >= low
    readonly property var values: [low, high, average, price].filter(value => valid(value))
    readonly property real domainLow: values.length ? Math.min(...values) : 0
    readonly property real domainHigh: values.length ? Math.max(...values) : 0
    function position(value) {
        const fraction = domainHigh > domainLow ? (value - domainLow) / (domainHigh - domainLow) : .5
        return Style.space(6) + fraction * Math.max(0, width - Style.space(12))
    }
    function money(value) { return StockStore.financial(value, "perShare", currency) }
    implicitHeight: Style.space(56)
    Accessible.role: Accessible.Indicator
    Accessible.name: "Analyst targets: low " + money(low) + ", average " + money(average) + ", high " + money(high)
        + ". Current regular-session price " + money(price)
    Rectangle {
        x: Style.space(6); y: Style.space(14); width: Math.max(0, parent.width - Style.space(12)); height: Style.space(2)
        color: Util.alpha(Color.foreground, .12)
    }
    Rectangle {
        visible: root.validRange
        x: root.validRange ? root.position(root.low) : 0; y: Style.space(13)
        width: root.validRange ? Math.max(1, root.position(root.high) - x) : 0; height: Style.space(4)
        color: Util.alpha(Color.foreground, .4)
    }
    Rectangle {
        objectName: "analystAverageTick"
        visible: root.valid(root.average)
        x: root.valid(root.average) ? root.position(root.average) - width / 2 : 0; y: Style.space(6)
        width: Style.space(3); height: Style.space(18); color: Color.accent
    }
    Rectangle {
        objectName: "analystCurrentDot"
        visible: root.valid(root.price)
        x: root.valid(root.price) ? root.position(root.price) - width / 2 : 0; y: Style.space(15) - height / 2
        width: Style.space(10); height: width; radius: width / 2; color: Color.foreground
        border.width: 1; border.color: Color.background
    }
    Label {
        visible: root.validRange
        text: (root.low === root.high ? "Low / high " : "Low ") + root.money(root.low)
        font.pixelSize: Style.font.bodySmall; color: Tone.muted
        width: Math.min(implicitWidth, root.width / 2)
        x: root.validRange ? Math.max(0, Math.min(root.width - width, root.position(root.low) - width / 2)) : 0; y: Style.space(31)
    }
    Label {
        visible: root.validRange && root.high !== root.low
        text: "High " + root.money(root.high)
        font.pixelSize: Style.font.bodySmall; color: Tone.muted
        width: Math.min(implicitWidth, root.width / 2)
        x: root.validRange ? Math.max(0, Math.min(root.width - width, root.position(root.high) - width / 2)) : 0; y: Style.space(31)
    }
    HoverHandler { id: hover }
    Ui.PanelToolTip { visible: hover.hovered; text: root.Accessible.name }
}
