import QtQuick
import qs.Commons

// Three rising candlesticks, the middle one hollow (a down session). `rise`
// grows them from their wicks' feet in sequence, 0..1.
Canvas {
    id: root
    property real unit: Style.space(20)
    property color color: Color.accent
    property color hollow: Color.background
    property real rise: 1
    implicitWidth: unit * 1.1
    implicitHeight: unit * 1.2
    antialiasing: true
    Accessible.ignored: true
    onRiseChanged: requestPaint()
    onColorChanged: requestPaint()
    onHollowChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        const wick = height * .1, w = width * .24
        const bars = [{x: .05, top: .55, bottom: .95, hollow: false}, {x: .42, top: .3, bottom: .75, hollow: true}, {x: .79, top: .1, bottom: .6, hollow: false}]
        ctx.lineWidth = Math.max(1.5, unit * .08)
        ctx.strokeStyle = root.color
        bars.forEach((bar, index) => {
            const amount = Math.max(0, Math.min(1, rise * 1.8 - index * .4))
            if (amount <= 0) return
            const x = bar.x * width, foot = Math.min(height, bar.bottom * height + wick)
            const reach = (foot - (bar.top * height - wick)) * amount
            ctx.save()
            ctx.beginPath(); ctx.rect(0, foot - reach, width, reach); ctx.clip()
            ctx.beginPath(); ctx.moveTo(x + w / 2, bar.top * height - wick); ctx.lineTo(x + w / 2, foot); ctx.stroke()
            ctx.beginPath(); ctx.roundedRect(x, bar.top * height, w, (bar.bottom - bar.top) * height, w * .25, w * .25)
            ctx.fillStyle = bar.hollow ? root.hollow : root.color
            ctx.fill()
            if (bar.hollow) ctx.stroke()
            ctx.restore()
        })
    }
}
