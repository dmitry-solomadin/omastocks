import QtQuick
import qs.Commons
import qs.Ui as Ui
import ".."

// One canvas and one hover target keep thousand-stock maps lightweight.
Item {
    id: root
    objectName: "denseHeatmap"
    property var cells: []
    property string period: "1D"
    property int hovered: -1
    readonly property var hoveredEntry: hovered >= 0 && hovered < cells.length ? cells[hovered].entry : null
    readonly property color foreground: Color.foreground
    readonly property color gain: StockStore.gain
    readonly property color loss: StockStore.loss
    readonly property color muted: Color.muted
    readonly property string family: Style.font.family
    readonly property real fontSize: Style.font.bodySmall
    readonly property real scale: Style.space(1)
    function change(entry) { return period === "YTD" ? entry.ytd : entry.percent }
    function hit(x, y) {
        for (let i = 0; i < cells.length; i++) {
            const cell = cells[i]
            if (x >= cell.x && y >= cell.y && x < cell.x + cell.width && y < cell.y + cell.height) return i
        }
        return -1
    }
    onCellsChanged: { hovered = -1; canvas.requestPaint() }
    onPeriodChanged: canvas.requestPaint()
    onForegroundChanged: canvas.requestPaint()
    onGainChanged: canvas.requestPaint()
    onLossChanged: canvas.requestPaint()
    onMutedChanged: canvas.requestPaint()
    onFamilyChanged: canvas.requestPaint()
    onFontSizeChanged: canvas.requestPaint()
    onScaleChanged: canvas.requestPaint()
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            root.cells.forEach(cell => {
                const amount = root.change(cell.entry), ink = amount === null || amount === undefined ? root.muted : amount < 0 ? root.loss : root.gain
                const gap = Math.min(Style.space(2), cell.width / 12, cell.height / 12)
                ctx.globalAlpha = .12 + Math.min(Math.abs(amount || 0), 10) * .025
                ctx.fillStyle = ink
                ctx.fillRect(cell.x + gap, cell.y + gap, Math.max(0, cell.width - 2 * gap), Math.max(0, cell.height - 2 * gap))
                ctx.globalAlpha = 1
                if (cell.width < Style.space(36) || cell.height < Style.space(22)) return
                const size = Math.max(root.fontSize, Math.min(Style.space(22), Math.sqrt(cell.width * cell.height) / 10))
                const showReturn = cell.height >= Style.space(48) && cell.width >= Style.space(65)
                const cx = cell.x + cell.width / 2, cy = cell.y + cell.height / 2
                ctx.font = "bold " + Math.round(size) + "px " + JSON.stringify(root.family)
                if (ctx.measureText(cell.entry.symbol).width > cell.width - Style.space(8)) return
                ctx.fillStyle = root.foreground
                ctx.fillText(cell.entry.symbol, cx, cy - (showReturn ? root.fontSize / 2 + Style.space(2) : 0))
                if (showReturn) {
                    ctx.font = Math.round(root.fontSize) + "px " + JSON.stringify(root.family)
                    ctx.fillStyle = ink
                    ctx.fillText(StockStore.percent(amount), cx, cy + size / 2 + Style.space(2))
                }
            })
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.hoveredEntry ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPositionChanged: mouse => root.hovered = root.hit(mouse.x, mouse.y)
        onExited: root.hovered = -1
        onClicked: mouse => {
            const index = root.hit(mouse.x, mouse.y)
            if (index >= 0) StockStore.select(root.cells[index].entry.symbol)
        }
    }
    Ui.PanelToolTip {
        objectName: "denseHeatmapToolTip"
        visible: root.hoveredEntry !== null
        x: Math.max(0, Math.min(root.width - implicitWidth, pointer.mouseX + Style.space(12)))
        y: Math.max(0, Math.min(root.height - implicitHeight, pointer.mouseY + Style.space(12)))
        text: root.hoveredEntry ? root.hoveredEntry.name + " (" + root.hoveredEntry.symbol + ")\nMarket cap "
            + StockStore.compact(root.hoveredEntry.marketCap) + " · " + root.period + " " + StockStore.percent(root.change(root.hoveredEntry)) : ""
    }
}
