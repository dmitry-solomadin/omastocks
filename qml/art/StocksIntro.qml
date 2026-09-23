import QtQuick
import qs.Commons
import ".."
import "PixelSprites.js" as Sprites

// Header opening, painted over the header: a pixel price line draws across a
// dotted previous-close baseline (green above, red below, dithered fill), a flag
// shows the S&P 500's real daily move, then the layer dissolves in blocks
// outward from the last price to reveal the header. It never takes input, so
// the header stays usable throughout.
Item {
    id: root
    objectName: "stocksIntro"
    readonly property int total: 700
    readonly property int dissolveStart: 420
    property real time: total
    property bool playing: false
    property var layout: null
    property int seed: 1
    // Direction is fixed per play so a quote arriving mid-animation cannot flip it.
    readonly property bool rising: layout ? layout.rising : true
    readonly property var quote: StockStore.marketQuotes["^SPX"] || {}
    readonly property bool known: Number.isFinite(quote.percent)
    readonly property int pixel: Math.max(2, Math.round(Style.space(3)))
    readonly property real lineProgress: Math.max(0, Math.min(1, (time - 20) / 280))
    readonly property bool dissolving: playing && time >= dissolveStart
    visible: playing

    function clamp(value) { return Math.max(0, Math.min(1, value)) }

    function play() {
        seed = Math.floor(Math.random() * 1e9)
        layout = null
        time = 0
        playing = true
        build()
        canvas.reset()
        timeline.restart()
    }
    function stop() { timeline.stop(); time = total; playing = false }

    function build() {
        if (width <= 0 || height <= 0) return
        const p = pixel, cols = Math.floor(width / p), rows = Math.floor(height / p)
        const top = 3, bottom = rows - 3
        const x0 = Math.round(cols * .03), x1 = Math.round(cols * .97)
        const rising = !known || quote.percent >= 0
        const baseline = Math.round(top + (bottom - top) * (rising ? .62 : .38))
        const values = Sprites.walk(x1 - x0, seed, rising)
        const ys = values.map(v => Math.round(v >= 0 ? baseline - v * (baseline - top) : baseline - v * (bottom - baseline)))
        // Dissolve blocks ordered by distance from the last price, with jitter.
        const block = p * 4, hx = x1 * p, hy = ys[ys.length - 1] * p
        const reach = Math.hypot(Math.max(hx, width - hx), Math.max(hy, height - hy))
        const next = Sprites.random(seed ^ 0x9e3779b9)
        const cells = []
        for (let y = 0; y < height; y += block)
            for (let x = 0; x < width; x += block)
                cells.push({x: x, y: y, at: Math.hypot(x + block / 2 - hx, y + block / 2 - hy) / reach * .78 + next() * .22})
        cells.sort((a, b) => a.at - b.at)
        layout = {p: p, cols: cols, rows: rows, x0: x0, rising: rising, baseline: baseline, ys: ys, block: block, cells: cells}
    }

    onWidthChanged: if (playing) { build(); canvas.reset() }
    onHeightChanged: if (playing) { build(); canvas.reset() }
    onTimeChanged: if (playing) canvas.requestPaint()

    // Holds the first frame while the compositor maps and fades in the window.
    SequentialAnimation {
        id: timeline
        PauseAnimation { duration: 350 }
        NumberAnimation { target: root; property: "time"; from: 0; to: root.total; duration: root.total }
        ScriptAction { script: root.stop() }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: false
        // Everything is painted incrementally: only what the clock uncovered
        // since the previous frame.
        property var done: ({})
        function reset() { done = {base: false, line: 0, front: 0, cleared: 0}; requestPaint() }
        onPaint: {
            const l = root.layout
            if (!l || !root.playing) return
            const ctx = getContext("2d")
            const p = l.p, t = root.time
            const dot = (x, y, color) => { ctx.fillStyle = color; ctx.fillRect(x * p, y * p, p, p) }
            if (!done.base) {
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = Color.background
                ctx.fillRect(0, 0, width, height)
                for (let y = 2; y < l.rows; y += 6)
                    for (let x = 2; x < l.cols; x += 6) dot(x, y, Util.alpha(Color.foreground, .06))
                for (let x = l.x0; x < l.x0 + l.ys.length; x += 2) dot(x, l.baseline, Util.alpha(Color.foreground, .28))
                done.base = true
            }
            const lineNow = Math.floor(l.ys.length * root.lineProgress)
            for (let i = done.line; i < lineNow; i++) {
                const y = l.ys[i], previous = i ? l.ys[i - 1] : y, x = l.x0 + i
                const up = y < l.baseline
                const side = up ? StockStore.gain : StockStore.loss
                // Dithered fill between the line and the baseline, densest at the line.
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
                const front = root.clamp((t - root.dissolveStart) / (root.total - root.dissolveStart - 20)) * (1 + band)
                const flash = Util.alpha(root.rising ? StockStore.gain : StockStore.loss, .32)
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
    }

    // Live head of the line: a bright pixel with a soft halo and scan column.
    Item {
        id: head
        readonly property int index: root.layout ? Math.min(root.layout.ys.length - 1, Math.floor(root.layout.ys.length * root.lineProgress)) : 0
        readonly property int row: root.layout ? root.layout.ys[index] : 0
        readonly property color tone: !root.layout || row === root.layout.baseline ? Color.foreground : row < root.layout.baseline ? StockStore.gain : StockStore.loss
        visible: !!root.layout && root.lineProgress > 0
        opacity: root.dissolving ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
        x: root.layout ? (root.layout.x0 + index) * root.pixel : 0
        y: row * root.pixel
        Rectangle { x: 0; y: -parent.y; width: root.pixel; height: root.height; color: Util.alpha(Color.foreground, .05) }
        Rectangle { x: -root.pixel; y: -root.pixel; width: root.pixel * 3; height: root.pixel * 3; color: Util.alpha(head.tone, .3) }
        Rectangle { width: root.pixel; height: root.pixel; color: Color.foreground }
    }

    // Price flag with the benchmark's actual move, pinned where the line ends.
    Rectangle {
        id: flag
        readonly property var l: root.layout
        // A quote that lands mid-animation is shown only if it agrees with the drawn line.
        readonly property bool agrees: root.known && !!l && (root.quote.percent >= 0) === l.rising
        visible: agrees && root.time >= 300
        x: l ? (l.x0 + l.ys.length) * root.pixel - width : 0
        y: l ? Math.max(0, Math.min(root.height - height, (l.ys[l.ys.length - 1] + (root.rising ? -3 : 3)) * root.pixel - (root.rising ? height : 0))) : 0
        width: flagText.implicitWidth + root.pixel * 2
        height: flagText.implicitHeight + root.pixel * 2
        color: root.rising ? StockStore.gain : StockStore.loss
        transformOrigin: root.rising ? Item.BottomRight : Item.TopRight
        scale: visible ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        opacity: root.time >= 600 ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 140 } }
        PixelArt {
            id: flagText
            anchors.centerIn: parent
            pixelSize: root.pixel
            ink: Color.background
            pixels: Sprites.text((root.rising ? "+" : "-") + Math.abs(root.quote.percent || 0).toFixed(2) + "%")
        }
    }
}
