import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."
import "MarketAssets.js" as Assets

// CNN Fear & Greed as a five-zone gauge with its recent history, and the VIX
// term structure: an upward curve (contango) is the calm norm; an inverted one
// signals near-term stress.
ColumnLayout {
    id: root
    objectName: "marketSentiment"
    property var report: ({})
    readonly property bool known: Number.isFinite(report.score)
    readonly property var history: [["Prev close", report.previousClose], ["1 week ago", report.previousWeek],
        ["1 month ago", report.previousMonth], ["1 year ago", report.previousYear]].filter(pair => Number.isFinite(pair[1]))
    readonly property var curve: Assets.volatility.map(point => Object.assign({}, point, {value: (StockStore.marketQuotes[point.symbol] || {}).price}))
    readonly property bool curveKnown: curve.every(point => Number.isFinite(point.value))
    readonly property bool inverted: curveKnown && curve[1].value > curve[2].value
    spacing: Style.space(14)

    function zoneColor(score) {
        return score < 25 ? StockStore.loss : score < 45 ? Qt.tint(StockStore.loss, Qt.rgba(1, 1, 1, .25))
            : score <= 55 ? Color.muted : score <= 75 ? Qt.tint(StockStore.gain, Qt.rgba(1, 1, 1, .25)) : StockStore.gain
    }
    function zoneName(score) {
        return score < 25 ? "Extreme fear" : score < 45 ? "Fear" : score <= 55 ? "Neutral" : score <= 75 ? "Greed" : "Extreme greed"
    }

    component Caption: Label { color: Color.muted; font.pixelSize: Style.font.bodySmall }

    Caption { text: "SENTIMENT" }
    GridLayout {
        Layout.fillWidth: true
        columns: width >= Style.space(820) ? 3 : 1
        columnSpacing: Style.space(40)
        rowSpacing: Style.space(20)

        // Gauge, score and rating.
        RowLayout {
            Layout.alignment: Qt.AlignTop
            spacing: Style.space(18)
            Canvas {
                id: gauge
                Layout.preferredWidth: Style.space(150)
                Layout.preferredHeight: Style.space(84)
                readonly property real score: root.known ? root.report.score : -1
                onScoreChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d"), cx = width / 2, cy = height - Style.space(5), r = Math.min(cx, cy) - Style.space(5)
                    const line = Math.max(4, Style.space(9))
                    ctx.clearRect(0, 0, width, height)
                    ctx.lineWidth = line
                    ;[[0, 25], [25, 45], [45, 55], [55, 75], [75, 100]].forEach(([from, to]) => {
                        ctx.strokeStyle = root.zoneColor((from + to) / 2)
                        ctx.globalAlpha = score < 0 || (score >= from && (score < to || to === 100)) ? .95 : .28
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
                Layout.alignment: Qt.AlignVCenter
                spacing: Style.space(2)
                Label { text: root.known ? Math.round(root.report.score) : "—"; font.pixelSize: Style.space(34); font.bold: true }
                Label {
                    text: root.known ? root.zoneName(root.report.score) : root.report.error ? "Unavailable" : ""
                    color: root.known ? root.zoneColor(root.report.score) : Color.muted
                    font.bold: true
                }
                Caption {
                    id: source
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
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Style.space(6)
            columns: 2
            columnSpacing: Style.space(24)
            rowSpacing: Style.space(8)
            Repeater {
                model: root.history
                RowLayout {
                    required property var modelData
                    spacing: Style.space(8)
                    Caption { text: modelData[0]; Layout.preferredWidth: Style.space(92) }
                    Label { text: Math.round(modelData[1]); color: root.zoneColor(modelData[1]); font.bold: true; font.pixelSize: Style.font.bodySmall }
                }
            }
        }

        // VIX term structure.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Style.space(4)
            spacing: Style.space(6)
            RowLayout {
                Layout.fillWidth: true
                Caption { text: "VIX term structure"; Layout.fillWidth: true }
                Label {
                    visible: root.curveKnown
                    text: root.inverted ? "Inverted" : "Calm"
                    color: root.inverted ? StockStore.loss : StockStore.gain
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                }
            }
            Canvas {
                id: curveChart
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(40)
                readonly property var values: root.curveKnown ? root.curve.map(point => point.value) : []
                onValuesChanged: requestPaint()
                onWidthChanged: requestPaint()
                function pointX(i) { return Style.space(14) + i / Math.max(1, values.length - 1) * (width - Style.space(28)) }
                function pointY(value) {
                    const low = Math.min(...values), high = Math.max(...values), pad = Style.space(6)
                    return height - pad - (value - low) / Math.max(1e-6, high - low) * (height - pad * 2)
                }
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    if (values.length < 2) return
                    const tone = root.inverted ? StockStore.loss : StockStore.gain
                    ctx.strokeStyle = tone; ctx.fillStyle = tone
                    ctx.lineWidth = Math.max(1.5, Style.space(2)); ctx.lineJoin = "round"
                    ctx.beginPath()
                    values.forEach((value, i) => i ? ctx.lineTo(pointX(i), pointY(value)) : ctx.moveTo(pointX(i), pointY(value)))
                    ctx.stroke()
                    values.forEach((value, i) => { ctx.beginPath(); ctx.arc(pointX(i), pointY(value), Style.space(3), 0, Math.PI * 2); ctx.fill() })
                }
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: Style.font.bodySmall * 2.6
                Repeater {
                    model: root.curveKnown ? root.curve : []
                    Column {
                        required property var modelData
                        required property int index
                        x: curveChart.pointX(index) - width / 2
                        Caption { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value.toFixed(1); color: Color.foreground }
                        Caption { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name }
                    }
                }
            }
            HoverHandler { id: curveHover }
            Ui.PanelToolTip {
                visible: curveHover.hovered
                text: root.inverted ? "Near-term volatility is priced above 3-month: typical of stress or a selloff."
                    : "Volatility rises with horizon (contango): the normal, calm shape."
            }
        }
    }
}
