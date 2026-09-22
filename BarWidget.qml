import QtQuick
import qs.Commons
import qs.Ui as Ui
import "." as Stocks

Ui.BarWidget {
    id: root
    moduleName: "io.github.dmitry-solomadin.omastocks"
    onSettingsChanged: Stocks.StockStore.barSettings = Object.assign({}, settings)
    Component.onCompleted: Stocks.StockStore.barSettings = Object.assign({}, settings)
    readonly property bool stripEnabled: setting("showStrip", true) !== false
    readonly property bool showPrice: setting("showPrice", false) === true
    readonly property bool showPercent: setting("showPercent", true) !== false
    readonly property bool showChange: setting("showChange", false) === true
    readonly property var favorites: Stocks.StockStore.favorites
    readonly property real maxWidth: Math.max(40, Math.min(800, Number(setting("maxWidth", 360)) || 360))
    readonly property real entryGap: Style.space(18)
    readonly property var tickerEntries: favorites.map(entry => {
        const parts = [entry.symbol]
        if (showPrice) parts.push(Stocks.StockStore.price(entry.price))
        if (showPercent) parts.push(Stocks.StockStore.percent(entry.percent))
        if (showChange) parts.push(changeText(entry))
        if (entry.stale) parts.push("◷")
        const text = parts.join(" ")
        return {text: text, percent: entry.percent, width: Math.ceil(metrics.advanceWidth(text))}
    })
    readonly property real contentWidth: tickerEntries.reduce((sum, entry) => sum + entry.width, 0)
        + Math.max(0, tickerEntries.length - 1) * entryGap
    readonly property real cycleWidth: contentWidth + entryGap
    readonly property bool overflowing: !vertical && favorites.length > 0 && contentWidth > viewport.width + .5
    property real scrollOffset: 0
    readonly property string fullText: favorites.map(entry => entry.symbol + "  " + Stocks.StockStore.price(entry.price)
        + "  " + Stocks.StockStore.percent(entry.percent) + "  " + changeText(entry) + (entry.stale ? "  ◷" : "")).join("\n")
    function changeText(entry) {
        if (entry.change === undefined || entry.change === null) return "—"
        const symbols = {USD: "$", GBP: "£", EUR: "€", JPY: "¥", CNY: "¥"}
        const unit = symbols[entry.currency] || (entry.currency ? entry.currency + " " : "")
        return (entry.change < 0 ? "−" : "+") + unit + Stocks.StockStore.price(Math.abs(entry.change))
    }
    onCycleWidthChanged: { if (marquee.running) marquee.restart(); else scrollOffset = 0 }
    onOverflowingChanged: if (!overflowing) scrollOffset = 0
    FontMetrics { id: metrics; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body }
    implicitWidth: !stripEnabled ? 0 : !vertical && favorites.length
        ? Math.min(Style.space(maxWidth), contentWidth + button.scaledHorizontalMargin * 2) : button.implicitWidth
    implicitHeight: stripEnabled ? button.implicitHeight : 0
    NumberAnimation {
        id: marquee
        target: root
        property: "scrollOffset"
        from: 0
        to: root.cycleWidth
        duration: Math.max(1, Math.round(root.cycleWidth / Style.spaceReal(30) * 1000))
        loops: Animation.Infinite
        running: root.overflowing && root.stripEnabled && root.visible && !button.concealed
        paused: running && button.tooltipHovered
        onStopped: root.scrollOffset = 0
    }
    Ui.WidgetButton {
        id: button
        visible: root.stripEnabled
        bar: root.bar
        width: root.width
        text: "\uf201"
        labelVisible: root.vertical || !root.favorites.length
        tooltipText: "Stocks\n" + (root.fullText || "Star stocks in the app to show them here")
        onPressed: mouseButton => { if (mouseButton === Qt.MiddleButton) Stocks.StockStore.refresh(true); else Stocks.StockStore.openRequested() }
        Item {
            id: viewport
            anchors.fill: parent
            anchors.leftMargin: button.scaledHorizontalMargin
            anchors.rightMargin: button.scaledHorizontalMargin
            clip: true
            visible: !button.labelVisible
            Item {
                x: -root.scrollOffset
                height: parent.height
                Repeater {
                    model: root.overflowing ? 2 : 1
                    Row {
                        required property int index
                        x: index * root.cycleWidth
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.entryGap
                        Repeater {
                            model: root.tickerEntries
                            Text {
                                required property var modelData
                                text: modelData.text
                                width: modelData.width
                                textFormat: Text.PlainText
                                renderType: Text.NativeRendering
                                font.family: metrics.font.family
                                font.pixelSize: metrics.font.pixelSize
                                color: Stocks.StockStore.direction(modelData.percent)
                            }
                        }
                    }
                }
            }
        }
    }
}
