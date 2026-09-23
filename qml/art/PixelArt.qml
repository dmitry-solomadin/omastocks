import QtQuick
import qs.Commons
import ".."

Canvas {
    id: root
    property var pixels: []
    property int pixelSize: Math.max(1, Math.round(Style.space(2)))
    property color ink: Color.foreground
    property color shade: Tone.muted
    property color accent: Color.accent
    property real reveal: 1
    readonly property int columns: pixels.reduce((maximum, row) => Math.max(maximum, row.length), 0)
    implicitWidth: columns * pixelSize
    implicitHeight: pixels.length * pixelSize
    antialiasing: false
    Accessible.ignored: true
    onPixelsChanged: requestPaint()
    onPixelSizeChanged: requestPaint()
    onInkChanged: requestPaint()
    onShadeChanged: requestPaint()
    onAccentChanged: requestPaint()
    onRevealChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        const edge = Math.ceil(columns * reveal)
        pixels.forEach((row, y) => {
            for (let x = 0; x < Math.min(row.length, edge); x++) {
                if (row[x] !== "1" && row[x] !== "2" && row[x] !== "3") continue
                ctx.fillStyle = row[x] === "1" ? root.ink : row[x] === "2" ? root.shade : root.accent
                ctx.fillRect(x * pixelSize, y * pixelSize, pixelSize, pixelSize)
            }
        })
    }
}
