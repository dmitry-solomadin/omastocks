import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."
import "ChartMath.js" as ChartMath

Item {
    id: root
    property var points: []
    property var referencePrice: null
    property color lineColor: StockStore.gain
    property bool miniature: false
    property string period: "1D"
    property string currency: ""
    property string symbol: ""
    property var dates: []
    property var volumes: []
    property bool showVolume: false
    property var averages: []
    property var events: []
    // Keep the event lane even before markers load, so the plot does not
    // shrink when earnings arrive after the price data.
    property bool reserveEvents: false
    property var sessions: []
    property bool compareMode: false
    property var comparisons: []
    property color primaryColor: "#4e9eff"
    // How far past its sides the chart still takes the pointer, as into the
    // page margin, so a sweep past either end holds that end's reading.
    property real hoverReach: 0
    // Why the line may be old, e.g. "As of 27 Sep 15:52 · refresh failed". It
    // follows the readout on the top line, short of the width kept at the right.
    property string note: ""
    property real reservedRight: 0
    readonly property bool comparing: !miniature && compareMode
    readonly property var normalized: comparing ? ChartMath.compareMany(
        [{symbol: symbol, currency: currency, color: primaryColor, points: points, dates: dates}]
            .concat(comparisons.filter(row => row.data.points && row.data.points.length > 1)
                .map(row => ({symbol: row.symbol, currency: row.data.currency || "", color: row.color,
                    points: row.data.points, dates: row.data.dates || []}))), period) : null
    readonly property var compareLines: normalized ? normalized.series : []
    readonly property var legendEntries: [{symbol: symbol, color: primaryColor, data: note ? {error: note} : {}, busy: !points.length, primary: true}].concat(comparisons)
    readonly property var averageLines: miniature || comparing || !ChartMath.dailyAveragesSupported(period) ? [] : averages.map(series => ({window: series.window,
        color: series.color, points: ChartMath.projectAverage(points, dates, series, period)}))
    readonly property var eventMarkers: miniature || comparing ? [] : ChartMath.eventPositions(points, dates, events, period)
    readonly property var markerGroups: {
        const groups = []
        for (const event of eventMarkers) {
            const group = groups.find(group => group.index === event.index)
            if (group) group.events.push(event)
            else groups.push({index: event.index, events: [event]})
        }
        return groups
    }
    readonly property var volumeSeries: ChartMath.volumeSeries(points, volumes, period)
    readonly property bool hasVolume: volumeSeries.volumes.some(value => value !== null && value !== undefined && value > 0)
    readonly property real volumeHeight: !miniature && !comparing && showVolume && hasVolume ? Style.space(52) : 0
    readonly property real eventHeight: !miniature && (eventMarkers.length || (reserveEvents && !comparing)) ? Style.space(22) : 0
    readonly property real volumeTop: topInset + plotHeight + Style.space(8)
    readonly property real eventTop: height - bottomInset - eventHeight
    readonly property real maxVolume: Math.max(1, ...volumeSeries.volumes.map(value => value || 0))
    property var sessionStart: null
    property var sessionEnd: null
    property double now: Date.now() / 1000
    readonly property var timeDomain: ChartMath.timeDomain(points, period, sessionStart, sessionEnd, now)
    property int anchorIndex: -1
    property int selectionIndex: -1
    property bool dragging: false
    readonly property var comparison: ChartMath.comparison(points, anchorIndex, selectionIndex)
    readonly property bool hasSelection: comparison !== null
    readonly property var periodComparison: ChartMath.comparison(points, 0, points.length - 1)
    readonly property string readoutText: hasSelection ? changeText() : comparing
        ? compareLines.map(row => row.symbol + " " + StockStore.percent(row.points[row.points.length - 1][1])).join(" · ")
        : StockStore.percent(periodComparison ? periodComparison.percent : null) + " over this period"
    readonly property color selectionColor: comparison ? StockStore.direction(comparison.change) : lineColor
    readonly property real leftInset: miniature ? 2 : Style.space(4)
    // The price axis is as wide as its widest label, so the plot and labels run
    // to the chart's right edge.
    readonly property real axisWidth: [0, 1, 2, 3].map(index => axisMetrics.advanceWidth(axisLabel(extent[1] - (extent[1] - extent[0]) * index / 3)))
        .concat(volumeHeight ? [axisMetrics.advanceWidth("Vol"), axisMetrics.advanceWidth(StockStore.compact(maxVolume))] : [])
        .reduce((widest, width) => Math.max(widest, width), 0)
    readonly property real rightInset: miniature ? 2 : Math.ceil(axisWidth) + 1 + Style.space(6)
    readonly property real topInset: miniature ? 2 : comparing ? legend.implicitHeight + Style.space(16) : Style.space(30)
    readonly property real bottomInset: miniature ? 2 : Style.space(19)
    readonly property real plotWidth: Math.max(1, width - leftInset - rightInset)
    readonly property real plotHeight: Math.max(1, height - topInset - bottomInset - eventHeight - (volumeHeight ? volumeHeight + Style.space(12) : 0))
    readonly property var extent: {
        const values = comparing ? compareLines.reduce((all, row) => all.concat(row.points.map(point => point[1])), []) : points.map(point => point[1])
        // Keep enabled averages visible on the same price scale as the stock.
        for (const series of averageLines) for (const point of series.points) {
            if (!comparing || (point[0] >= normalized.first && point[0] <= normalized.last)) values.push(axisValue(point[1]))
        }
        if (comparing) values.push(0)
        else if (referencePrice !== null && referencePrice !== undefined) values.push(referencePrice)
        if (!values.length) return [0, 1]
        const low = Math.min.apply(null, values), high = Math.max.apply(null, values)
        const padding = Math.max((high - low) * .12, Math.abs(high) * .0005, .01)
        return [low - padding, high + padding]
    }
    // Anywhere level with the plot, beside the line reads its nearest end.
    readonly property int hoveredIndex: !hasSelection && pointer.containsMouse && points.length
        && pointer.mouseY >= topInset && pointer.mouseY <= topInset + plotHeight
        ? indexAtX(pointer.chartX) : -1
    readonly property var hoveredPoint: hoveredIndex >= 0 ? points[hoveredIndex] : null
    readonly property var hoverRows: legendEntries.map(entry => {
        const row = compareLines.find(row => row.symbol === entry.symbol)
        const point = row ? row.points.find(point => point[0] === hoveredIndex) : null
        return {symbol: entry.symbol, color: entry.color, currency: row ? row.currency : "", price: point ? point[2] : null, percent: point ? point[1] : null}
    })
    // Rows of the hover box: every compared stock, or the volume below the
    // price. Yields and currencies report zero volume throughout, so none shows.
    readonly property var hoverLines: {
        if (!hoveredPoint) return []
        if (comparing) return hoverRows.map(row => ({label: row.symbol, color: row.color, value: hoverPrice(row)}))
        const extended = sessions.some(session => session.kind !== "regular" && hoveredPoint[0] >= session.start && hoveredPoint[0] < session.end)
        const volume = volumes[hoveredIndex]
        return showVolume && hasVolume && !extended && volume !== null && volume !== undefined
            ? [{label: "Volume", color: "transparent", value: StockStore.compact(volume)}] : []
    }
    function pointX(index) { return leftInset + ChartMath.pointFraction(points, index, period, timeDomain) * plotWidth }
    function axisValue(value) { return comparing && normalized ? (value / normalized.base - 1) * 100 : value }
    function axisY(value) { return topInset + (extent[1] - value) / (extent[1] - extent[0]) * plotHeight }
    function pointY(value) { return axisY(axisValue(value)) }
    function indexAtX(x) {
        const index = ChartMath.nearestIndex(points, (x - leftInset) / plotWidth, period, timeDomain)
        if (!comparing) return index
        if (!normalized) return -1
        return compareLines[0].points.reduce((best, point) => Math.abs(point[0] - index) < Math.abs(best - index) ? point[0] : best, normalized.first)
    }
    function inPlot(x, y) { return x >= leftInset && x <= leftInset + plotWidth && y >= topInset && y <= topInset + plotHeight }
    function clearSelection() { dragging = false; anchorIndex = -1; selectionIndex = -1 }
    function changeText() {
        if (!comparison) return ""
        const unit = currency === "USD" ? "$" : currency ? currency + " " : ""
        return (comparison.change < 0 ? "−" : "+") + unit + StockStore.price(Math.abs(comparison.change))
            + "  (" + StockStore.percent(comparison.percent) + ")"
    }
    function selectionTime(timestamp) {
        return Qt.formatDateTime(new Date(timestamp * 1000), period === "1D" ? "hh:mm" : period === "1W" ? "d MMM, hh:mm" : "d MMM yyyy")
    }
    function hoverTime(timestamp) {
        const session = sessions.find(session => timestamp >= session.start && timestamp < session.end)
        return (session ? session.label + " · " : "")
            + Qt.formatDateTime(new Date(timestamp * 1000), period === "1D" || period === "1W" || period === "1M" ? "d MMM yyyy, hh:mm" : "d MMM yyyy")
    }
    function timeLabel(timestamp) {
        return Qt.formatDateTime(new Date(timestamp * 1000), period === "1D" ? "hh:mm" : period === "ALL" ? "yyyy" : period === "2Y" || period === "5Y" ? "MMM yyyy" : "d MMM")
    }
    function eventText(event) {
        const day = Qt.formatDate(new Date(event.date + "T12:00:00"), "d MMM yyyy")
        if (event.type === "earnings") return "Earnings · " + day + (event.estimated ? " (estimated)" : "")
            + (event.eps !== null && event.eps !== undefined ? "\nEPS: " + StockStore.price(event.eps) : "")
            + (event.forecast !== null && event.forecast !== undefined ? " vs " + StockStore.price(event.forecast) + " est." : "")
            + (event.revenue !== null && event.revenue !== undefined || event.revenueForecast !== null && event.revenueForecast !== undefined
                ? "\nRevenue: " + StockStore.revenue(event.revenue, event.revenueCurrency)
                    + " vs " + StockStore.revenue(event.revenueForecast, event.revenueCurrency) + " est." : "")
        if (event.type === "dividend") return "Ex-dividend · " + day + "\n" + StockStore.price(event.amount) + " " + currency
        return "Stock split · " + day + "\n" + event.ratio
    }
    function legendText(entry) {
        const line = compareLines.find(row => row.symbol === entry.symbol)
        return entry.symbol + (entry.busy ? " …" : entry.data.error ? " !" : line
            ? " " + StockStore.percent(line.points[line.points.length - 1][1]) : " —")
    }
    function hoverPrice(row) {
        if (row.price === null || row.price === undefined) return "—"
        return (row.currency === "USD" ? "$" : row.currency ? row.currency + " " : "") + StockStore.price(row.price)
    }
    function axisLabel(value) {
        return comparing ? StockStore.percent(value) : StockStore.price(value)
    }
    onPointsChanged: { clearSelection(); now = Date.now() / 1000; canvas.requestPaint() }
    onPeriodChanged: clearSelection()
    onTimeDomainChanged: canvas.requestPaint()
    onExtentChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onComparisonChanged: canvas.requestPaint()
    onAverageLinesChanged: canvas.requestPaint()
    onNormalizedChanged: { clearSelection(); canvas.requestPaint() }
    onVolumesChanged: canvas.requestPaint()
    onVolumeSeriesChanged: canvas.requestPaint()
    onSessionsChanged: canvas.requestPaint()
    onPlotHeightChanged: canvas.requestPaint()
    onComparingChanged: { clearSelection(); canvas.requestPaint() }
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    Connections { target: Color; function onForegroundChanged() { canvas.requestPaint() } }
    Connections {
        target: StockStore
        function onGainChanged() { canvas.requestPaint() }
        function onLossChanged() { canvas.requestPaint() }
    }
    FontMetrics { id: axisMetrics; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
    Timer { interval: 30000; running: root.period === "1D" && root.visible && StockStore.windowOpen; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() / 1000 }
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!root.points.length) return
            if (!root.miniature) {
                if (!root.comparing && root.timeDomain[1] > root.timeDomain[0]) {
                    ctx.fillStyle = Util.alpha(Color.foreground, .045)
                    for (const session of root.sessions) {
                        if (session.kind === "regular") continue
                        const span = root.timeDomain[1] - root.timeDomain[0]
                        const start = Math.max(0, Math.min(1, (session.start - root.timeDomain[0]) / span))
                        const end = Math.max(0, Math.min(1, (session.end - root.timeDomain[0]) / span))
                        ctx.fillRect(root.leftInset + start * root.plotWidth, root.topInset, (end - start) * root.plotWidth, root.plotHeight)
                    }
                }
                ctx.strokeStyle = Util.alpha(Color.foreground, .09)
                ctx.lineWidth = 1
                for (let i = 0; i < 4; i++) {
                    const y = root.topInset + root.plotHeight * i / 3
                    ctx.beginPath(); ctx.moveTo(root.leftInset, y); ctx.lineTo(root.leftInset + root.plotWidth, y); ctx.stroke()
                }
            }
            // Sparklines draw the baseline only when given one (the bar preview).
            if (root.comparing || (root.referencePrice !== null && root.referencePrice !== undefined)) {
                const y = root.comparing ? root.axisY(0) : root.pointY(root.referencePrice)
                ctx.strokeStyle = Util.alpha(Color.foreground, .3)
                ctx.lineWidth = 1
                ctx.setLineDash(root.comparing ? [] : root.miniature ? [3, 3] : [4, 5])
                ctx.beginPath(); ctx.moveTo(root.leftInset, y); ctx.lineTo(root.leftInset + root.plotWidth, y); ctx.stroke()
                ctx.setLineDash([])
            }
            // The line and the gradient beneath it. A dragged selection draws
            // its stretch in the selection's own trend colour.
            const selection = root.miniature || root.comparing ? null : root.comparison
            const last = root.points.length - 1
            const segments = !selection ? [[0, last, root.lineColor, false]]
                : [[0, selection.first, root.lineColor, false], [selection.first, selection.last, root.selectionColor, true],
                    [selection.last, last, root.lineColor, false]].filter(segment => segment[1] > segment[0])
            if (!root.comparing) for (const [from, to, color, selected] of segments) {
                ctx.beginPath()
                for (let index = from; index <= to; index++) {
                    const x = root.pointX(index), y = root.pointY(root.points[index][1])
                    if (index === from) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.strokeStyle = color
                ctx.lineWidth = root.miniature ? 1.5 : 2
                ctx.lineJoin = "round"
                ctx.stroke()
                if (root.miniature || to === from) continue
                ctx.lineTo(root.pointX(to), root.topInset + root.plotHeight)
                ctx.lineTo(root.pointX(from), root.topInset + root.plotHeight)
                ctx.closePath()
                const gradient = ctx.createLinearGradient(0, root.topInset, 0, root.topInset + root.plotHeight)
                gradient.addColorStop(0, Util.alpha(color, selected ? .3 : .15))
                gradient.addColorStop(1, Util.alpha(color, 0))
                ctx.fillStyle = gradient
                ctx.fill()
            }
            if (!root.comparing && root.points.length === 1) {
                ctx.beginPath()
                ctx.arc(root.pointX(0), root.pointY(root.points[0][1]), 2, 0, Math.PI * 2)
                ctx.fillStyle = root.lineColor
                ctx.fill()
            }
            if (root.comparing) {
                for (const line of root.compareLines) {
                    ctx.beginPath()
                    line.points.forEach((point, index) => {
                        const x = root.pointX(point[0]), y = root.axisY(point[1])
                        if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    })
                    ctx.strokeStyle = line.color
                    ctx.stroke()
                }
            }
            ctx.save()
            ctx.beginPath()
            ctx.rect(root.leftInset, root.topInset, root.plotWidth, root.plotHeight)
            ctx.clip()
            for (const series of root.averageLines) {
                ctx.beginPath()
                let started = false
                for (const point of series.points) {
                    if (root.comparing && (point[0] < root.normalized.first || point[0] > root.normalized.last)) continue
                    const x = root.pointX(point[0]), y = root.pointY(point[1])
                    if (!started) { ctx.moveTo(x, y); started = true } else ctx.lineTo(x, y)
                }
                ctx.strokeStyle = series.color
                ctx.lineWidth = 1.3
                ctx.stroke()
            }
            ctx.restore()
            if (root.volumeHeight) {
                root.volumeSeries.points.forEach((point, index) => {
                    const volume = root.volumeSeries.volumes[index]
                    if (volume === null || volume === undefined) return
                    const barWidth = ChartMath.volumeBarWidth(root.volumeSeries.points, index, root.period, root.timeDomain, root.plotWidth, Style.space(8))
                    const height = volume / root.maxVolume * root.volumeHeight
                    const x = root.leftInset + ChartMath.pointFraction(root.volumeSeries.points, index, root.period, root.timeDomain) * root.plotWidth
                    ctx.fillStyle = Util.alpha(root.volumeSeries.falling[index] ? StockStore.loss : StockStore.gain, .5)
                    ctx.fillRect(x - barWidth / 2, root.volumeTop + root.volumeHeight - height, barWidth, height)
                })
            }
        }
    }
    Repeater {
        model: root.miniature || !root.points.length ? 0 : 4
        Label {
            required property int index
            x: root.width - root.rightInset + Style.space(6)
            y: root.topInset + root.plotHeight * index / 3 - height / 2
            width: root.rightInset - Style.space(6)
            text: root.axisLabel(root.extent[1] - (root.extent[1] - root.extent[0]) * index / 3)
            color: Tone.muted
            font.pixelSize: Style.font.bodySmall
        }
    }
    Label {
        visible: root.volumeHeight > 0
        x: root.width - root.rightInset + Style.space(6)
        // Level with the bars' base, clear of the lowest price label.
        y: root.volumeTop + root.volumeHeight - height
        width: root.rightInset - Style.space(6)
        text: "Vol\n" + StockStore.compact(root.maxVolume)
        color: Tone.muted
        font.pixelSize: Style.font.bodySmall
    }
    Repeater {
        model: root.miniature || !root.points.length ? 0 : 3
        Label {
            required property int index
            readonly property int pointIndex: Math.round(index / 2 * (root.points.length - 1))
            readonly property double timestamp: root.period === "1D"
                ? root.timeDomain[0] + (root.timeDomain[1] - root.timeDomain[0]) * index / 2
                : root.points.length ? root.points[pointIndex][0] : 0
            x: Math.max(root.leftInset, Math.min(root.leftInset + root.plotWidth - width, root.leftInset + root.plotWidth * index / 2 - width / 2))
            y: root.height - root.bottomInset + Style.space(3)
            text: root.timeLabel(timestamp)
            font.pixelSize: Style.font.bodySmall
            color: Tone.muted
        }
    }
    Repeater {
        model: !root.miniature && root.comparison ? [root.comparison.first, root.comparison.last] : []
        Item {
            required property int modelData
            readonly property var point: root.points[modelData] || null
            x: root.pointX(modelData)
            y: root.topInset
            width: 1
            height: root.plotHeight
            Rectangle { anchors.fill: parent; color: Util.alpha(root.selectionColor, .65) }
            Rectangle {
                x: -width / 2
                y: parent.point ? root.pointY(parent.point[1]) - root.topInset - height / 2 : 0
                width: Style.spaceReal(10.4); height: width; radius: width / 2
                color: root.selectionColor
                border.width: 2
                border.color: Color.background
            }
        }
    }
    Rectangle {
        visible: !root.miniature && root.hoveredPoint !== null
        x: root.pointX(root.hoveredIndex)
        y: root.topInset
        width: 1
        height: root.plotHeight
        color: Util.alpha(Color.foreground, .35)
    }
    Rectangle {
        visible: !root.miniature && !root.comparing && root.hoveredPoint !== null
        x: root.pointX(root.hoveredIndex) - width / 2
        y: root.hoveredPoint ? root.pointY(root.hoveredPoint[1]) - height / 2 : 0
        width: Style.spaceReal(10.4); height: width; radius: width / 2
        color: root.lineColor
        border.color: Color.background
        border.width: 2
    }
    // One line above the plot: the period's change, or a dragged selection's
    // change and time range, centred over the dragged point.
    Row {
        visible: !root.miniature && !root.comparing
        x: root.hasSelection ? Math.max(root.leftInset, Math.min(root.leftInset + root.plotWidth - implicitWidth,
            root.pointX(root.selectionIndex) - implicitWidth / 2)) : root.leftInset
        y: 0
        spacing: Style.space(12)
        Label {
            id: readout
            objectName: "chartReadout"
            text: root.readoutText
            color: StockStore.direction(root.hasSelection ? root.comparison.change : root.periodComparison ? root.periodComparison.percent : null)
            font.bold: true
        }
        Label {
            objectName: "chartSelectionRange"
            visible: root.hasSelection
            anchors.baseline: readout.baseline
            text: root.comparison ? root.selectionTime(root.points[root.comparison.first][0]) + " → "
                + root.selectionTime(root.points[root.comparison.last][0]) : ""
            color: Tone.muted
            font.pixelSize: Style.font.bodySmall
        }
        Label {
            objectName: "chartNote"
            visible: !!root.note && !root.hasSelection
            anchors.baseline: readout.baseline
            width: Math.min(implicitWidth, Math.max(0, root.width - root.reservedRight - root.leftInset - readout.implicitWidth - Style.space(24)))
            text: root.note
            color: Tone.muted
            font.pixelSize: Style.font.bodySmall
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        anchors.leftMargin: -root.hoverReach
        anchors.rightMargin: -root.hoverReach
        readonly property real chartX: x + mouseX
        hoverEnabled: !root.miniature
        enabled: !root.miniature
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: containsMouse && root.inPlot(chartX, mouseY) ? Qt.CrossCursor : Qt.ArrowCursor
        onPressed: mouse => {
            root.clearSelection()
            if (root.comparing) { mouse.accepted = false; return }
            if (root.points.length < 2 || !root.inPlot(x + mouse.x, mouse.y)
                || x + mouse.x > root.pointX(root.points.length - 1)) {
                mouse.accepted = false
                return
            }
            root.anchorIndex = root.indexAtX(x + mouse.x)
            root.selectionIndex = root.anchorIndex
            root.dragging = true
        }
        onPositionChanged: mouse => { if (pressed && root.dragging) root.selectionIndex = root.indexAtX(x + mouse.x) }
        onReleased: mouse => {
            if (root.dragging) root.selectionIndex = root.indexAtX(x + mouse.x)
            root.dragging = false
        }
        onCanceled: root.clearSelection()
    }
    Flow {
        id: legend
        objectName: "comparisonLegend"
        visible: root.comparing
        x: root.leftInset
        width: root.width - root.leftInset
        spacing: Style.space(10)
        Repeater {
            model: root.comparing ? root.legendEntries : []
            Row {
                id: entry
                required property var modelData
                height: Style.space(26)
                spacing: Style.space(5)
                Rectangle { width: Style.space(9); height: width; anchors.verticalCenter: parent.verticalCenter; color: entry.modelData.color }
                Label {
                    text: root.legendText(entry.modelData)
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Style.font.bodySmall
                    HoverHandler { id: legendHover }
                    Ui.PanelToolTip {
                        visible: legendHover.hovered
                        text: entry.modelData.data.error || (entry.modelData.busy ? "Loading " + entry.modelData.symbol
                            : !root.normalized ? "No shared trading intervals" : "Percentage return from the first shared interval")
                    }
                }
                ActionButton {
                    objectName: "removeComparison_" + entry.modelData.symbol
                    visible: !entry.modelData.primary
                    text: "×"
                    implicitWidth: Style.space(22)
                    implicitHeight: Style.space(26)
                    hint: "Remove " + entry.modelData.symbol
                    onClicked: MarketStore.removeComparison(entry.modelData.symbol)
                }
            }
        }
    }
    Label {
        anchors.centerIn: parent
        visible: root.comparing && root.points.length > 0 && !root.normalized
        text: "No shared trading intervals"
        color: Tone.muted
    }
    Repeater {
        model: root.comparing && root.hoveredPoint ? root.hoverRows.filter(row => row.price !== null) : []
        Rectangle {
            required property var modelData
            x: root.pointX(root.hoveredIndex) - width / 2
            y: root.axisY(modelData.percent) - height / 2
            width: Style.spaceReal(10.4); height: width; radius: width / 2
            color: modelData.color
            border.width: 2; border.color: Color.background
        }
    }
    Rectangle {
        objectName: "chartHoverBox"
        visible: !root.miniature && root.hoveredPoint !== null
        // Right of the cursor, or left of it where the box would run past the plot.
        readonly property real cursorX: root.pointX(root.hoveredIndex)
        x: Math.max(root.leftInset, cursorX + Style.space(16) + width <= root.leftInset + root.plotWidth
            ? cursorX + Style.space(16) : cursorX - Style.space(16) - width)
        y: Math.max(root.topInset, Math.min(root.topInset + root.plotHeight - height, pointer.mouseY - height - Style.space(12)))
        width: hoverContent.implicitWidth + Style.space(24)
        height: hoverContent.implicitHeight + Style.space(20)
        color: Color.background
        border.width: 1; border.color: Util.alpha(Color.foreground, .2)
        radius: Style.cornerRadius
        ColumnLayout {
            id: hoverContent
            anchors.centerIn: parent
            spacing: Style.space(5)
            Label {
                objectName: "chartHoverPrice"
                visible: !root.comparing
                text: root.hoveredPoint ? root.hoverPrice({price: root.hoveredPoint[1], currency: root.currency}) : ""
                font.bold: true
                font.pixelSize: Style.font.heading
            }
            Label { text: root.hoveredPoint ? root.hoverTime(root.hoveredPoint[0]) : ""; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
            Repeater {
                model: root.hoverLines
                RowLayout {
                    required property var modelData
                    spacing: Style.space(12)
                    Rectangle { implicitWidth: Style.space(8); implicitHeight: implicitWidth; color: modelData.color }
                    Label { text: modelData.label; Layout.fillWidth: true; font.pixelSize: Style.font.bodySmall }
                    Label { text: modelData.value; font.pixelSize: Style.font.bodySmall; font.bold: root.comparing }
                }
            }
        }
    }
    Repeater {
        model: root.markerGroups
        EventBadge {
            id: marker
            required property var modelData
            x: Math.max(root.leftInset, Math.min(root.leftInset + root.plotWidth - width, root.pointX(modelData.index) - width / 2))
            y: root.eventTop + Math.round((Style.space(20) - height) / 2)
            text: modelData.events.length > 1 ? "+" : modelData.events[0].type === "earnings" ? "E" : modelData.events[0].type === "dividend" ? "D" : "S"
            hint: modelData.events.map(event => root.eventText(event)).join("\n\n")
        }
    }
}
