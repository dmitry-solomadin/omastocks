import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."
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
    property var sessions: []
    property bool compareMode: false
    property var comparisons: []
    property color primaryColor: "#4e9eff"
    readonly property bool comparing: !miniature && compareMode
    readonly property var normalized: comparing ? ChartMath.compareMany(
        [{symbol: symbol, currency: currency, color: primaryColor, points: points, dates: dates}]
            .concat(comparisons.filter(row => row.data.points && row.data.points.length > 1)
                .map(row => ({symbol: row.symbol, currency: row.data.currency || "", color: row.color,
                    points: row.data.points, dates: row.data.dates || []}))), period) : null
    readonly property var compareLines: normalized ? normalized.series : []
    readonly property var legendEntries: [{symbol: symbol, color: primaryColor, data: {}, busy: !points.length, primary: true}].concat(comparisons)
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
    readonly property bool hasVolume: volumes.some(value => value !== null && value !== undefined && value > 0)
    readonly property real volumeHeight: !miniature && !comparing && showVolume && hasVolume ? Style.space(52) : 0
    readonly property real eventHeight: !miniature && eventMarkers.length ? Style.space(25) : 0
    readonly property real volumeTop: topInset + plotHeight + Style.space(8)
    readonly property real eventTop: height - bottomInset - eventHeight
    readonly property real maxVolume: Math.max(1, ...volumes.map(value => value || 0))
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
    readonly property real rightInset: miniature ? 2 : Style.space(comparing ? 88 : 72)
    readonly property real topInset: miniature ? 2 : comparing ? legend.implicitHeight + Style.space(16) : Style.space(52)
    readonly property real bottomInset: miniature ? 2 : Style.space(30)
    readonly property real plotWidth: Math.max(1, width - leftInset - rightInset)
    readonly property real plotHeight: Math.max(1, height - topInset - bottomInset - eventHeight - (volumeHeight ? volumeHeight + Style.space(12) : 0))
    readonly property var extent: {
        const values = comparing ? compareLines.reduce((all, row) => all.concat(row.points.map(point => point[1])), []) : points.map(point => point[1])
        // Keep enabled averages visible on the same price scale as the stock.
        for (const series of averageLines) for (const point of series.points) {
            if (!comparing || (point[0] >= normalized.first && point[0] <= normalized.last)) values.push(axisValue(point[1]))
        }
        if (comparing) values.push(0)
        else if (referencePrice !== null && referencePrice !== undefined && !miniature) values.push(referencePrice)
        if (!values.length) return [0, 1]
        const low = Math.min.apply(null, values), high = Math.max.apply(null, values)
        const padding = Math.max((high - low) * .12, Math.abs(high) * .0005, .01)
        return [low - padding, high + padding]
    }
    readonly property int hoveredIndex: !hasSelection && pointer.containsMouse && points.length
        && inPlot(pointer.mouseX, pointer.mouseY) && pointer.mouseX <= pointX(points.length - 1)
        ? indexAtX(pointer.mouseX) : -1
    readonly property var hoveredPoint: hoveredIndex >= 0 ? points[hoveredIndex] : null
    readonly property var hoverRows: legendEntries.map(entry => {
        const row = compareLines.find(row => row.symbol === entry.symbol)
        const point = row ? row.points.find(point => point[0] === hoveredIndex) : null
        return {symbol: entry.symbol, color: entry.color, currency: row ? row.currency : "", price: point ? point[2] : null, percent: point ? point[1] : null}
    })
    function pointX(index) { return leftInset + ChartMath.pointFraction(points, index, miniature ? "" : period, timeDomain) * plotWidth }
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
            + Qt.formatDateTime(new Date(timestamp * 1000), period === "1D" || period === "1W" ? "d MMM yyyy, hh:mm" : "d MMM yyyy")
    }
    function hoverText(index) {
        const point = points[index]
        if (!point) return ""
        const extended = sessions.some(session => session.kind !== "regular" && point[0] >= session.start && point[0] < session.end)
        return StockStore.price(point[1]) + "  ·  " + hoverTime(point[0])
            + (showVolume && !extended ? "  ·  Vol " + StockStore.compact(volumes[index]) : "")
    }
    function timeLabel(timestamp) {
        return Qt.formatDateTime(new Date(timestamp * 1000), period === "1D" ? "hh:mm" : period === "5Y" ? "MMM yyyy" : "d MMM")
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
    onAverageLinesChanged: canvas.requestPaint()
    onNormalizedChanged: { clearSelection(); canvas.requestPaint() }
    onVolumesChanged: canvas.requestPaint()
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
    Timer { interval: 30000; running: !root.miniature && root.period === "1D"; repeat: true; onTriggered: root.now = Date.now() / 1000 }
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
                if (root.comparing || (root.referencePrice !== null && root.referencePrice !== undefined)) {
                    const y = root.comparing ? root.axisY(0) : root.pointY(root.referencePrice)
                    ctx.strokeStyle = Util.alpha(Color.foreground, .3)
                    ctx.setLineDash(root.comparing ? [] : [4, 5])
                    ctx.beginPath(); ctx.moveTo(root.leftInset, y); ctx.lineTo(root.leftInset + root.plotWidth, y); ctx.stroke()
                    ctx.setLineDash([])
                }
            }
            ctx.beginPath()
            const main = root.comparing ? [] : root.points.map((point, index) => [index, point[1]])
            main.forEach((point, index) => {
                const x = root.pointX(point[0]), y = root.comparing ? root.axisY(point[1]) : root.pointY(point[1])
                if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            })
            ctx.strokeStyle = root.lineColor
            ctx.lineWidth = root.miniature ? 1.5 : 2
            ctx.lineJoin = "round"
            ctx.stroke()
            if (!root.comparing && root.points.length === 1) {
                ctx.beginPath()
                ctx.arc(root.pointX(0), root.pointY(root.points[0][1]), 2, 0, Math.PI * 2)
                ctx.fillStyle = root.lineColor
                ctx.fill()
            }
            if (!root.miniature && !root.comparing && root.points.length > 1) {
                ctx.lineTo(root.pointX(root.points.length - 1), root.topInset + root.plotHeight)
                ctx.lineTo(root.pointX(0), root.topInset + root.plotHeight)
                ctx.closePath()
                const gradient = ctx.createLinearGradient(0, root.topInset, 0, root.topInset + root.plotHeight)
                gradient.addColorStop(0, Util.alpha(root.lineColor, .15))
                gradient.addColorStop(1, Util.alpha(root.lineColor, 0))
                ctx.fillStyle = gradient
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
                const barWidth = Math.max(1, Math.min(Style.space(8), (root.points.length > 1 ? root.pointX(1) - root.pointX(0) : root.plotWidth) * .7))
                root.points.forEach((point, index) => {
                    const volume = root.volumes[index]
                    if (volume === null || volume === undefined) return
                    const height = volume / root.maxVolume * root.volumeHeight
                    ctx.fillStyle = Util.alpha(index && point[1] < root.points[index - 1][1] ? StockStore.loss : StockStore.gain, .5)
                    ctx.fillRect(root.pointX(index) - barWidth / 2, root.volumeTop + root.volumeHeight - height, barWidth, height)
                })
            }
        }
    }
    Repeater {
        model: root.miniature || !root.points.length ? 0 : 4
        Label {
            required property int index
            x: root.width - root.rightInset + Style.space(12)
            y: root.topInset + root.plotHeight * index / 3 - height / 2
            width: root.rightInset - Style.space(12)
            text: root.axisLabel(root.extent[1] - (root.extent[1] - root.extent[0]) * index / 3)
            color: Color.muted
            font.pixelSize: Style.font.bodySmall
        }
    }
    Label {
        visible: root.volumeHeight > 0
        x: root.width - root.rightInset + Style.space(12)
        y: root.volumeTop
        width: root.rightInset - Style.space(12)
        text: "Vol\n" + StockStore.compact(root.maxVolume)
        color: Color.muted
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
            y: root.height - root.bottomInset + Style.space(12)
            text: root.timeLabel(timestamp)
            font.pixelSize: Style.font.bodySmall
            color: Color.muted
        }
    }
    Rectangle {
        visible: !root.miniature && root.hasSelection
        x: root.comparison ? root.pointX(root.comparison.first) : 0
        y: root.topInset
        width: root.comparison ? root.pointX(root.comparison.last) - x : 0
        height: root.plotHeight
        color: Util.alpha(root.selectionColor, .1)
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
                width: Style.space(8); height: width; radius: width / 2
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
        width: Style.space(8); height: width; radius: width / 2
        color: root.lineColor
        border.color: Color.background
        border.width: 2
    }
    Label {
        objectName: "chartHoverReadout"
        visible: !root.miniature && !root.comparing && root.hoveredPoint !== null
        x: root.leftInset; y: Style.space(23)
        width: root.plotWidth
        text: root.hoverText(root.hoveredIndex)
        color: root.lineColor
        font.pixelSize: Style.font.bodySmall
    }
    Label {
        objectName: "chartReadout"
        visible: !root.miniature && !root.comparing
        x: root.leftInset; y: 0
        width: root.width - root.leftInset
        text: root.readoutText
        color: root.comparing && !root.hasSelection ? Color.foreground
            : StockStore.direction(root.hasSelection ? root.comparison.change : root.periodComparison ? root.periodComparison.percent : null)
        font.bold: true
    }
    Label {
        visible: !root.miniature && root.hasSelection
        x: root.leftInset; y: Style.space(23)
        width: root.width - root.leftInset
        text: root.comparison ? root.selectionTime(root.points[root.comparison.first][0]) + " → "
            + root.selectionTime(root.points[root.comparison.last][0]) : ""
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: !root.miniature
        enabled: !root.miniature
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: containsMouse && root.inPlot(mouseX, mouseY) ? Qt.CrossCursor : Qt.ArrowCursor
        onPressed: mouse => {
            root.clearSelection()
            if (root.comparing) { mouse.accepted = false; return }
            if (root.points.length < 2 || !root.inPlot(mouse.x, mouse.y)
                || mouse.x > root.pointX(root.points.length - 1)) {
                mouse.accepted = false
                return
            }
            root.anchorIndex = root.indexAtX(mouse.x)
            root.selectionIndex = root.anchorIndex
            root.dragging = true
        }
        onPositionChanged: mouse => { if (pressed && root.dragging) root.selectionIndex = root.indexAtX(mouse.x) }
        onReleased: mouse => {
            if (root.dragging) root.selectionIndex = root.indexAtX(mouse.x)
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
        color: Color.muted
    }
    Repeater {
        model: root.comparing && root.hoveredPoint ? root.hoverRows.filter(row => row.price !== null) : []
        Rectangle {
            required property var modelData
            x: root.pointX(root.hoveredIndex) - width / 2
            y: root.axisY(modelData.percent) - height / 2
            width: Style.space(8); height: width; radius: width / 2
            color: modelData.color
            border.width: 2; border.color: Color.background
        }
    }
    Rectangle {
        visible: root.comparing && root.hoveredPoint !== null
        x: Math.max(root.leftInset, Math.min(root.width - width, root.pointX(root.hoveredIndex) + Style.space(16)))
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
            Label { text: root.hoveredPoint ? root.hoverTime(root.hoveredPoint[0]) : ""; color: Color.muted; font.pixelSize: Style.font.bodySmall }
            Repeater {
                model: root.hoverRows
                RowLayout {
                    required property var modelData
                    spacing: Style.space(12)
                    Rectangle { width: Style.space(8); height: width; color: modelData.color }
                    Label { text: modelData.symbol; Layout.fillWidth: true; font.pixelSize: Style.font.bodySmall }
                    Label { text: root.hoverPrice(modelData); font.pixelSize: Style.font.bodySmall }
                }
            }
        }
    }
    Repeater {
        model: root.markerGroups
        Rectangle {
            id: marker
            required property var modelData
            x: Math.max(root.leftInset, Math.min(root.leftInset + root.plotWidth - width, root.pointX(modelData.index) - width / 2))
            y: root.eventTop
            width: Style.space(20); height: width
            radius: Style.cornerRadius
            color: Color.background
            border.width: 1
            border.color: Color.accent
            Label { anchors.centerIn: parent; text: marker.modelData.events.length > 1 ? "+" : marker.modelData.events[0].type === "earnings" ? "E" : marker.modelData.events[0].type === "dividend" ? "D" : "S"; color: Color.accent; font.pixelSize: Style.font.bodySmall }
            MouseArea { id: markerMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            Ui.PanelToolTip { visible: markerMouse.containsMouse; text: marker.modelData.events.map(event => root.eventText(event)).join("\n\n") }
        }
    }
}
