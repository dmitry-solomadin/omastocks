import QtQuick
import QtQuick.Layouts
import qs.Commons
import ".."

RowLayout {
    id: root
    objectName: "marketLoading"
    property bool active: false
    property string text: "Loading market data…"
    visible: active
    spacing: Style.space(14)
    implicitHeight: Style.space(48)
    Accessible.role: Accessible.StaticText
    Accessible.name: text

    // A small live market: completed bars shift left one at a time while the
    // newest bar ticks like a real quote. Prices are a random walk, so the
    // strip never visibly repeats; the scale eases to keep it in frame.
    readonly property int bars: 7
    readonly property int stepMs: 420
    readonly property int tickMs: 52
    property var history: []
    property real open: 0
    property real close: 0
    property real high: 0
    property real low: 0
    property real drift: 0
    property real elapsed: 0
    property real sinceTick: 0
    property real scaleLow: -1
    property real scaleHigh: 1

    function seed() {
        let price = 0
        const list = []
        for (let i = 0; i < bars; ++i) {
            const next = price + (Math.random() - .5) * 2.4
            list.push({ open: price, close: next,
                high: Math.max(price, next) + Math.random() * .7,
                low: Math.min(price, next) - Math.random() * .7 })
            price = next
        }
        history = list
        startBar(price)
        fitScale(true)
    }
    function startBar(price) {
        open = close = high = low = price
        // Short trends make the strip read as a market rather than noise.
        if (Math.random() < .35) drift = (Math.random() - .5) * .7
    }
    function tick() {
        // Mean reversion keeps the walk near the frame between rescales.
        const pull = -close * .03
        close += drift + pull + (Math.random() - .5) * 1.4
        // Brief spikes between ticks leave wicks beyond the body.
        high = Math.max(high, close + Math.random() * Math.random() * 1.2)
        low = Math.min(low, close - Math.random() * Math.random() * 1.2)
    }
    function commit() {
        history = history.slice(1).concat([{ open: open, close: close, high: high, low: low }])
        startBar(close)
    }
    function fitScale(snap) {
        let lo = low, hi = high
        for (const bar of history) { lo = Math.min(lo, bar.low); hi = Math.max(hi, bar.high) }
        const pad = Math.max(.6, (hi - lo) * .12)
        const ease = snap ? 1 : .12
        scaleLow += (lo - pad - scaleLow) * ease
        scaleHigh += (hi + pad - scaleHigh) * ease
    }
    function yOf(price) { return Math.round((scaleHigh - price) / Math.max(.001, scaleHigh - scaleLow) * chart.height) }

    onActiveChanged: if (active) seed()
    Component.onCompleted: if (active) seed()

    FrameAnimation {
        running: root.active && root.visible && StockStore.windowOpen
        onTriggered: {
            const ms = Math.min(frameTime, .1) * 1000
            root.elapsed += ms
            root.sinceTick += ms
            if (root.elapsed >= root.stepMs) {
                root.elapsed -= root.stepMs
                root.commit()
            }
            while (root.sinceTick >= root.tickMs) {
                root.sinceTick -= root.tickMs
                root.tick()
            }
            root.fitScale(false)
        }
    }

    Item {
        id: chart
        Layout.preferredWidth: Style.space(78)
        Layout.preferredHeight: Style.space(34)
        Accessible.ignored: true
        readonly property real pitch: Style.space(10)
        readonly property real barWidth: Style.space(6)
        // The live bar sits left of the price marker; completed bars trail it.
        readonly property real liveX: width - Style.space(20)
        // Each new bar slides the chart over in the first part of its step.
        readonly property real shift: {
            const t = Math.min(1, root.elapsed / (root.stepMs * .28))
            return (1 - Math.pow(1 - t, 3)) * pitch - pitch
        }

        Repeater {
            model: root.bars + 1
            Item {
                id: bar
                required property int index
                readonly property bool live: index === root.bars
                readonly property var ohlc: live ? { open: root.open, close: root.close, high: root.high, low: root.low } : root.history[index]
                readonly property bool up: ohlc ? ohlc.close >= ohlc.open : true
                readonly property color ink: up ? StockStore.gain : StockStore.loss
                readonly property real centre: chart.liveX - (root.bars - index) * chart.pitch - (live ? 0 : chart.shift)
                readonly property real fade: Math.max(0, Math.min(1, (centre - chart.barWidth) / (chart.pitch * 1.6)))
                visible: !!ohlc
                x: Math.round(centre - chart.barWidth / 2)
                width: chart.barWidth
                height: chart.height
                opacity: live ? 1 : fade * (.4 + .45 * index / root.bars)
                Rectangle {
                    x: Math.floor((parent.width - width) / 2)
                    y: bar.ohlc ? root.yOf(bar.ohlc.high) : 0
                    width: Style.space(1)
                    height: bar.ohlc ? Math.max(1, root.yOf(bar.ohlc.low) - y) : 0
                    color: bar.ink
                }
                Rectangle {
                    y: bar.ohlc ? root.yOf(Math.max(bar.ohlc.open, bar.ohlc.close)) : 0
                    width: parent.width
                    height: bar.ohlc ? Math.max(Style.space(2), root.yOf(Math.min(bar.ohlc.open, bar.ohlc.close)) - y) : 0
                    radius: Style.space(1)
                    color: bar.ink
                }
            }
        }

        // Last price: a dotted guide from the live bar to a pulsing marker.
        Item {
            id: marker
            readonly property color ink: root.close >= root.open ? StockStore.gain : StockStore.loss
            readonly property real y0: root.yOf(root.close)
            x: chart.liveX + chart.barWidth / 2 + Style.space(2)
            width: chart.width - x
            y: y0
            Row {
                spacing: Style.space(2)
                Repeater {
                    model: Math.max(0, Math.floor((marker.width - Style.space(6)) / Style.space(4)))
                    Rectangle { width: Style.space(2); height: Style.space(1); color: marker.ink; opacity: .6 }
                }
            }
            Rectangle {
                id: dot
                x: marker.width - width
                y: Math.round(-height / 2 + Style.space(1) / 2)
                width: Style.space(4); height: width; radius: width / 2
                color: marker.ink
            }
            Rectangle {
                anchors.centerIn: dot
                width: dot.width * (1 + 1.6 * pulse); height: width; radius: width / 2
                color: "transparent"
                border.width: Style.space(1)
                border.color: marker.ink
                opacity: .7 * (1 - pulse)
                readonly property real pulse: root.elapsed / root.stepMs
            }
        }
    }
    Label {
        Layout.fillWidth: true
        text: root.text
        color: Tone.muted
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
    }
}
