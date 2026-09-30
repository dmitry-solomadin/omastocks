import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."
import "MarketAssets.js" as Assets

// CNN Fear & Greed as a five-zone gauge with its recent history, and the VIX
// term structure, with absolute level guides separate from the curve's shape.
ColumnLayout {
    id: root
    objectName: "marketSentiment"
    property var report: ({})
    readonly property bool known: Number.isFinite(report.score)
    readonly property var history: [["Prev close", report.previousClose], ["1 week", report.previousWeek],
        ["1 month", report.previousMonth], ["1 year", report.previousYear]]
    // The needle and score sweep up to each new reading rather than jumping.
    property real shown: 0
    Behavior on shown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    onKnownChanged: if (known) shown = report.score
    onReportChanged: if (known) shown = report.score
    Component.onCompleted: if (known) shown = report.score
    readonly property var curve: Assets.volatility.map(point => Object.assign({}, point, {value: (StockStore.marketQuotes[point.symbol] || {}).price}))
    readonly property bool curveKnown: curve.every(point => Number.isFinite(point.value))
    readonly property real vix: Number.isFinite(curve[1].value) ? curve[1].value : -1
    readonly property string volatilityLevel: vix < 0 ? "Volatility unavailable"
        : vix < 15 ? "Low expected volatility" : vix < 20 ? "Moderate expected volatility"
        : vix < 30 ? "Elevated expected volatility" : "High expected volatility"
    readonly property color volatilityTone: vix < 0 ? Tone.muted : vix < 15 ? StockStore.gain
        : vix < 20 ? Color.foreground : StockStore.loss
    spacing: Style.space(14)

    function zoneColor(score) {
        return score < 25 ? StockStore.loss : score < 45 ? Qt.tint(StockStore.loss, Qt.rgba(1, 1, 1, .25))
            : score <= 55 ? Tone.muted : score <= 75 ? Qt.tint(StockStore.gain, Qt.rgba(1, 1, 1, .25)) : StockStore.gain
    }
    function zoneName(score) {
        return score < 25 ? "Extreme fear" : score < 45 ? "Fear" : score <= 55 ? "Neutral" : score <= 75 ? "Greed" : "Extreme greed"
    }

    component Caption: Label { color: Tone.muted; font.pixelSize: Style.font.bodySmall }

    GridLayout {
        id: sentimentGrid
        // Keep sentiment together so VIX remains the second column.
        readonly property real vixMinimum: Style.space(300)
        Layout.fillWidth: true
        columns: width >= sentimentBlock.implicitWidth + columnSpacing + vixMinimum ? 2 : 1
        columnSpacing: Style.space(24)
        rowSpacing: Style.space(20)

        ColumnLayout {
            id: sentimentBlock
            Layout.alignment: Qt.AlignTop
            spacing: Style.space(14)
            SectionHeading { text: "SENTIMENT" }

        // Gauge, score and history stay in the sentiment column.
        RowLayout {
            id: gaugeBlock
            Layout.alignment: Qt.AlignTop
            Layout.minimumWidth: implicitWidth
            spacing: Style.space(18)
            Canvas {
                id: gauge
                Layout.preferredWidth: Style.space(150)
                Layout.preferredHeight: Style.space(84)
                readonly property real score: root.known ? root.shown : -1
                onScoreChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d"), cx = width / 2, cy = height - Style.space(5), r = Math.min(cx, cy) - Style.space(5)
                    const line = Math.max(4, Style.space(9))
                    ctx.clearRect(0, 0, width, height)
                    ctx.lineWidth = line
                    ;[[0, 25], [25, 45], [45, 55], [55, 75], [75, 100]].forEach(([from, to]) => {
                        ctx.strokeStyle = root.zoneColor((from + to) / 2)
                        ctx.globalAlpha = score >= from && (score < to || to === 100) ? .95 : .28
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, Math.PI * (1 + from / 100) + .03, Math.PI * (1 + to / 100) - .03)
                        ctx.stroke()
                    })
                    ctx.globalAlpha = 1
                    if (score < 0) return
                    const angle = Math.PI * (1 + score / 100)
                    ctx.strokeStyle = Color.foreground
                    ctx.lineWidth = Math.max(2, Style.space(3))
                    ctx.lineCap = "round"
                    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(angle) * (r - line), cy + Math.sin(angle) * (r - line)); ctx.stroke()
                    ctx.fillStyle = Color.foreground
                    ctx.beginPath(); ctx.arc(cx, cy, Style.space(4), 0, Math.PI * 2); ctx.fill()
                }
            }
            ColumnLayout {
                id: scoreColumn
                // Fixed to the widest rating, so the column count above never
                // changes as the score and rating arrive.
                readonly property real fixedWidth: Math.max(ratingMetrics.boundingRect("Extreme greed").width, sourceMetrics.boundingRect("Fear & Greed · CNN").width) + Style.space(4)
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: fixedWidth
                Layout.minimumWidth: fixedWidth
                spacing: Style.space(2)
                FontMetrics { id: ratingMetrics; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
                FontMetrics { id: sourceMetrics; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
                Label { text: root.known ? Math.round(root.shown) : "—"; font.pixelSize: Style.space(34); font.bold: true }
                Label {
                    text: root.known ? root.zoneName(root.report.score) : root.report.error ? "Unavailable" : ""
                    color: root.known ? root.zoneColor(root.report.score) : Tone.muted
                    font.bold: true
                }
                Caption {
                    id: source
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    readonly property string url: "https://www.cnn.com/markets/fear-and-greed"
                    textFormat: Text.StyledText
                    linkColor: Color.foreground
                    text: '<a href="' + url + '">Fear &amp; Greed · CNN</a>'
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    activeFocusOnTab: true
                    Keys.onReturnPressed: Qt.openUrlExternally(url)
                    Keys.onSpacePressed: Qt.openUrlExternally(url)
                    Accessible.role: Accessible.Link
                    Accessible.name: "Open CNN Fear & Greed"
                    Accessible.onPressAction: Qt.openUrlExternally(url)
                    HoverHandler { cursorShape: source.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
            }
        }

        // Recent history, each reading coloured by its zone.
        GridLayout {
            id: historyGrid
            Layout.alignment: Qt.AlignLeft
            Layout.minimumWidth: implicitWidth
            columns: 2
            columnSpacing: Style.space(18)
            rowSpacing: Style.space(5)
            Repeater {
                model: root.history
                RowLayout {
                    required property var modelData
                    spacing: Style.space(8)
                    Caption { text: modelData[0]; Layout.preferredWidth: Style.space(76) }
                    Label {
                        readonly property bool known: Number.isFinite(modelData[1])
                        Layout.preferredWidth: Style.space(26)
                        text: known ? Math.round(modelData[1]) : "—"
                        color: known ? root.zoneColor(modelData[1]) : Tone.muted
                        font.bold: true
                        font.pixelSize: Style.font.bodySmall
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                }
            }
        }
        }

        // VIX term structure.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1.2
            Layout.minimumWidth: sentimentGrid.columns === 2 ? sentimentGrid.vixMinimum : 0
            Layout.alignment: Qt.AlignTop
            spacing: Style.space(6)
            SectionHeading { text: "VIX"; Layout.fillWidth: true }
            Label {
                Layout.fillWidth: true
                text: root.volatilityLevel
                color: root.volatilityTone
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                wrapMode: Text.WordWrap
            }
            Item {
                id: curveChart
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(180)
                readonly property var values: root.curveKnown ? root.curve.map(point => point.value) : []
                // Keep ordinary readings comparable; expand only for extreme levels.
                readonly property real ceiling: Math.max(40, Math.ceil((Math.max(0, ...values) + 2) / 10) * 10)
                readonly property real labelWidth: bandMetrics.boundingRect("Moderate 15–20").width + Style.space(12)
                FontMetrics { id: bandMetrics; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
                function pointX(i) { return labelWidth + Style.space(14) + i / 3 * Math.max(0, width - labelWidth - Style.space(28)) }
                function pointY(value) {
                    return height - value / ceiling * height
                }
                Repeater {
                    model: [
                        {low: 0, high: 15, label: "Low <15", tone: StockStore.gain},
                        {low: 15, high: 20, label: "Moderate 15–20", tone: Tone.muted},
                        {low: 20, high: 30, label: "Elevated 20–30", tone: StockStore.loss},
                        {low: 30, high: curveChart.ceiling, label: "High ≥30", tone: StockStore.loss}
                    ]
                    Item {
                        required property var modelData
                        width: curveChart.width
                        y: curveChart.pointY(modelData.high)
                        height: curveChart.pointY(modelData.low) - y
                        Caption { anchors.verticalCenter: parent.verticalCenter; text: modelData.label }
                        Rectangle {
                            x: curveChart.labelWidth
                            width: Math.max(0, parent.width - x)
                            height: parent.height
                            color: modelData.tone
                            opacity: modelData.low === 30 ? .16 : .08
                        }
                        Rectangle {
                            x: curveChart.labelWidth
                            width: Math.max(0, parent.width - x)
                            height: 1
                            color: Tone.muted
                            opacity: .25
                        }
                    }
                }
                Canvas {
                    id: curveCanvas
                    anchors.fill: parent
                    readonly property var values: curveChart.values
                    readonly property color tone: Color.foreground
                    onValuesChanged: requestPaint()
                    onToneChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections {
                        target: curveChart
                        function onCeilingChanged() { curveCanvas.requestPaint() }
                        function onLabelWidthChanged() { curveCanvas.requestPaint() }
                    }
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (values.length < 2) return
                        ctx.strokeStyle = tone; ctx.fillStyle = tone
                        ctx.lineWidth = Math.max(1.5, Style.space(2)); ctx.lineJoin = "round"
                        ctx.beginPath()
                        values.forEach((value, i) => i ? ctx.lineTo(curveChart.pointX(i), curveChart.pointY(value)) : ctx.moveTo(curveChart.pointX(i), curveChart.pointY(value)))
                        ctx.stroke()
                        values.forEach((value, i) => { ctx.beginPath(); ctx.arc(curveChart.pointX(i), curveChart.pointY(value), Style.space(3), 0, Math.PI * 2); ctx.fill() })
                    }
                }
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: Style.font.bodySmall * 2.6
                Repeater {
                    model: root.curve
                    Column {
                        required property var modelData
                        required property int index
                        x: curveChart.pointX(index) - width / 2
                        Caption { anchors.horizontalCenter: parent.horizontalCenter; text: Number.isFinite(modelData.value) ? modelData.value.toFixed(1) : "—"; color: Color.foreground }
                        Caption { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name }
                    }
                }
            }
            HoverHandler { id: curveHover; parent: curveChart }
            Ui.PanelToolTip {
                id: curveTip
                parent: curveChart
                visible: curveHover.hovered
                width: Math.min(Style.space(380), parent.width)
                x: (parent.width - width) / 2
                y: -implicitHeight - Style.space(8)
                text: "VIX measures expected S&P 500 price swings, not their direction."
                    + " Higher means more expected volatility."
                    + " Left to right shows expectations for the next 9 days through 6 months, not history."
                    + " Higher near-term readings suggest more immediate uncertainty."
                contentItem: Text {
                    text: curveTip.text
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: curveTip.panelForeground
                    font.family: curveTip.fontFamily
                    font.pixelSize: curveTip.fontSize
                    padding: Style.space(12)
                }
            }
        }
    }
}
