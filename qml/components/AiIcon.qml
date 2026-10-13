import QtQuick
import qs.Commons

// Two four-point sparkles, shared by AI features and tinted by their control.
Canvas {
    id: root
    property color color: Color.accent
    implicitWidth: Style.space(16)
    implicitHeight: implicitWidth
    antialiasing: true
    Accessible.ignored: true
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.save()
        ctx.scale(width / 24, height / 24)
        ctx.fillStyle = root.color
        function sparkle(x, y, radius) {
            ctx.beginPath()
            ctx.moveTo(x, y - radius)
            ctx.quadraticCurveTo(x, y, x + radius, y)
            ctx.quadraticCurveTo(x, y, x, y + radius)
            ctx.quadraticCurveTo(x, y, x - radius, y)
            ctx.quadraticCurveTo(x, y, x, y - radius)
            ctx.closePath()
            ctx.fill()
        }
        sparkle(9, 14, 8)
        sparkle(19, 5, 4)
        ctx.restore()
    }
}
