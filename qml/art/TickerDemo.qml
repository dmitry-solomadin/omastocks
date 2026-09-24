import QtQuick
import qs.Commons
import ".."
import "PixelSprites.js" as Sprites

// Empty-watchlist showcase in the style of StocksIntro: a pixel prompt types a
// ticker, a pixel price line draws across a dotted baseline (green above, red
// below, dithered fill), a flag pops with the move, then the chart dissolves in
// blocks outward from the last price and the next ticker starts.
Item {
    id: root
    objectName: "tickerDemo"
    readonly property bool animating: visible && StockStore.windowOpen
    readonly property var demos: [
        {symbol: "NVDA", rising: true, percent: 3.42}, {symbol: "AAPL", rising: true, percent: 1.18},
        {symbol: "TSLA", rising: false, percent: 2.71}, {symbol: "MSFT", rising: true, percent: .86},
        {symbol: "AMD", rising: false, percent: 1.94}
    ]
    // Milliseconds within one ticker's cycle.
    readonly property int typeEnd: 540
    readonly property int lineEnd: 1765
    readonly property int flagAt: 1815
    readonly property int dissolveStart: 3165
    readonly property int total: 4065
    property real time: 0
    property int demoIndex: 0
    readonly property var demo: demos[demoIndex]
    readonly property int pixel: Math.max(3, Math.round(Style.space(4)))
    readonly property real lineProgress: Math.max(0, Math.min(1, (time - typeEnd) / (lineEnd - typeEnd)))
    readonly property bool dissolving: time >= dissolveStart
    readonly property string typed: {
        const word = demo.symbol
        if (time < typeEnd) return word.slice(0, Math.ceil(time / typeEnd * word.length))
        if (!dissolving) return word
        return word.slice(0, Math.max(0, word.length - Math.ceil((time - dissolveStart) / (total - dissolveStart - 200) * word.length)))
    }
    property var layout: null
    implicitWidth: Style.space(640)
    implicitHeight: prompt.height + pixel * 8 + Style.space(220)

    function build() {
        if (chart.width <= 0 || chart.height <= 0) return
        const p = pixel, cols = Math.floor(chart.width / p), rows = Math.floor(chart.height / p)
        const top = 3, bottom = rows - 3
        const x0 = 2, x1 = cols - 2
        const rising = demo.rising
        const baseline = Math.round(top + (bottom - top) * (rising ? .62 : .38))
        let seed = 7
        for (const ch of demo.symbol) seed = (seed * 31 + ch.charCodeAt(0)) >>> 0
        const values = Sprites.walk(x1 - x0, seed, rising)
        const ys = values.map(v => Math.round(v >= 0 ? baseline - v * (baseline - top) : baseline - v * (bottom - baseline)))
        const block = p * 4, hx = x1 * p, hy = ys[ys.length - 1] * p
        const reach = Math.hypot(Math.max(hx, chart.width - hx), Math.max(hy, chart.height - hy))
        const next = Sprites.random(seed ^ 0x9e3779b9)
        const cells = []
        for (let y = 0; y < chart.height; y += block)
            for (let x = 0; x < chart.width; x += block)
                cells.push({x: x, y: y, at: Math.hypot(x + block / 2 - hx, y + block / 2 - hy) / reach * .78 + next() * .22})
        cells.sort((a, b) => a.at - b.at)
        layout = {p: p, cols: cols, rows: rows, x0: x0, baseline: baseline, ys: ys, block: block, cells: cells}
        chart.reset()
    }
    function restart() { time = 0; build() }

    onDemoIndexChanged: build()
    onAnimatingChanged: if (animating) restart()
    Component.onCompleted: build()

    Row {
        id: prompt
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.pixel * 3
        PixelArt { pixelSize: root.pixel * 2; ink: Color.accent; pixels: Sprites.text(">") }
        PixelArt { id: word; pixelSize: root.pixel * 2; pixels: root.typed ? Sprites.text(root.typed) : [] }
        Rectangle {
            width: root.pixel * 5; height: root.pixel * 10
            color: Color.accent
            opacity: Math.floor(root.time / 300) % 2 === 0 ? 1 : 0
        }
    }

    Canvas {
        id: chart
        anchors.top: prompt.bottom
        anchors.topMargin: root.pixel * 8
        width: parent.width
        height: Style.space(220)
        antialiasing: false
        Accessible.ignored: true
        onWidthChanged: root.build()
        onHeightChanged: root.build()
        // Painted incrementally, like StocksIntro: only what the clock uncovered.
        property var done: ({})
        function reset() { done = {base: false, line: 0, front: 0, cleared: 0}; requestPaint() }
        onPaint: {
            const l = root.layout
            if (!l) return
            const ctx = getContext("2d")
            const p = l.p, t = root.time
            const dot = (x, y, color) => { ctx.fillStyle = color; ctx.fillRect(x * p, y * p, p, p) }
            if (!done.base) {
                ctx.clearRect(0, 0, width, height)
                for (let y = 2; y < l.rows; y += 6)
                    for (let x = 2; x < l.cols; x += 6) dot(x, y, Util.alpha(Color.foreground, .06))
                for (let x = l.x0; x < l.x0 + l.ys.length; x += 2) dot(x, l.baseline, Util.alpha(Color.foreground, .28))
                done.base = true
            }
            const lineNow = Math.floor(l.ys.length * root.lineProgress)
            for (let i = done.line; i < lineNow; i++) {
                const y = l.ys[i], previous = i ? l.ys[i - 1] : y, x = l.x0 + i
                const side = y < l.baseline ? StockStore.gain : StockStore.loss
                for (let row = Math.min(y, l.baseline) + 1; row < Math.max(y, l.baseline); row++) {
                    const k = Math.abs(row - y)
                    const on = k <= 1 || (k <= 4 && (row + x) % 2 === 0) || (k <= 12 && row % 2 === 0 && x % 2 === 0) || (row % 4 === 0 && x % 4 === 0)
                    if (on) dot(x, row, Util.alpha(side, k <= 1 ? .4 : .28))
                }
                for (let row = Math.min(previous, y); row <= Math.max(previous, y); row++)
                    dot(x, row, row < l.baseline ? StockStore.gain : row > l.baseline ? StockStore.loss : Color.foreground)
            }
            done.line = Math.max(done.line, lineNow)
            if (t >= root.dissolveStart) {
                const band = .06
                const front = Math.min(1, (t - root.dissolveStart) / (root.total - root.dissolveStart - 150)) * (1 + band)
                const flash = Util.alpha(root.demo.rising ? StockStore.gain : StockStore.loss, .32)
                while (done.front < l.cells.length && l.cells[done.front].at <= front) {
                    const cell = l.cells[done.front++]
                    ctx.clearRect(cell.x, cell.y, l.block, l.block)
                    ctx.fillStyle = flash
                    ctx.fillRect(cell.x + p / 2, cell.y + p / 2, l.block - p, l.block - p)
                }
                while (done.cleared < done.front && l.cells[done.cleared].at <= front - band) {
                    const cell = l.cells[done.cleared++]
                    ctx.clearRect(cell.x, cell.y, l.block, l.block)
                }
            }
        }

        // Live head: a bright pixel with a soft halo and a scan column.
        Item {
            id: head
            readonly property var l: root.layout
            readonly property int index: l ? Math.min(l.ys.length - 1, Math.floor(l.ys.length * root.lineProgress)) : 0
            readonly property int row: l ? l.ys[index] : 0
            readonly property color tone: !l || row === l.baseline ? Color.foreground : row < l.baseline ? StockStore.gain : StockStore.loss
            visible: !!l && root.lineProgress > 0
            opacity: root.dissolving ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
            x: l ? (l.x0 + index) * root.pixel : 0
            y: row * root.pixel
            Rectangle { x: 0; y: -parent.y; width: root.pixel; height: chart.height; color: Util.alpha(Color.foreground, .05) }
            Rectangle { x: -root.pixel; y: -root.pixel; width: root.pixel * 3; height: root.pixel * 3; color: Util.alpha(head.tone, .3) }
            Rectangle { width: root.pixel; height: root.pixel; color: Color.foreground }
        }

        // The move, pinned where the line ends.
        Rectangle {
            readonly property var l: root.layout
            visible: !!l && root.time >= root.flagAt
            x: l ? (l.x0 + l.ys.length) * root.pixel - width : 0
            y: l ? Math.max(0, Math.min(chart.height - height, (l.ys[l.ys.length - 1] + (root.demo.rising ? -3 : 3)) * root.pixel - (root.demo.rising ? height : 0))) : 0
            width: flagText.implicitWidth + root.pixel * 2
            height: flagText.implicitHeight + root.pixel * 2
            color: root.demo.rising ? StockStore.gain : StockStore.loss
            transformOrigin: root.demo.rising ? Item.BottomRight : Item.TopRight
            scale: visible ? 1 : 0
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            opacity: root.dissolving ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 140 } }
            PixelArt {
                id: flagText
                anchors.centerIn: parent
                pixelSize: root.pixel
                ink: Color.background
                pixels: Sprites.text((root.demo.rising ? "+" : "-") + root.demo.percent.toFixed(2) + "%")
            }
        }
    }

    Timer {
        interval: 16
        running: root.animating
        repeat: true
        onTriggered: {
            root.time += interval
            if (root.time >= root.total) {
                root.time = 0
                root.demoIndex = (root.demoIndex + 1) % root.demos.length
            }
            chart.requestPaint()
        }
    }
}
