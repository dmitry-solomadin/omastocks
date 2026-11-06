import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."
import "MarginChart.js" as MarginChart

// How leveraged the market is against its own history, from FINRA's monthly margin
// statistics: the level as a share of market value, the year's direction, and the
// cash customers hold against the debt.
ColumnLayout {
    id: root
    objectName: "marginDebt"
    property var report: ({})
    property bool busy: false
    property string mode: "share"
    readonly property var latest: report.latest || ({})
    readonly property var months: report.months || []
    readonly property bool known: months.length > 0 && !!latest.month
    readonly property string sinceYear: report.since ? report.since.slice(0, 4) : ""
    // A year's change needs a year of history first.
    readonly property string changeSinceYear: (months.find(row => Number.isFinite(row.change)) || {month: ""}).month.slice(0, 4)
    readonly property string headline: known ? latest.level + " leverage, " + latest.trend.toLowerCase() : ""
    readonly property color tone: ["Low", "Below average"].indexOf(latest.level) >= 0 ? StockStore.gain
        : ["Above average", "High"].indexOf(latest.level) >= 0 ? StockStore.loss : Color.foreground
    function monthLabel(month) { return month ? Qt.formatDate(new Date(month + "-15T12:00:00"), "MMM yyyy") : "" }
    function percentText(value) { return Number.isFinite(value) ? Number(value).toFixed(2) + "%" : "—" }
    function valueText(value) {
        return root.mode === "debt" ? StockStore.financial(value, "money", "USD")
            : root.mode === "change" ? StockStore.percent(value) : percentText(value)
    }
    spacing: Style.space(10)

    component Caption: Label { color: Tone.muted; font.pixelSize: Style.font.bodySmall }
    component Readout: ColumnLayout {
        id: readout
        property string title
        property string value
        property string detail
        property string hint
        property color tone: Color.foreground
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignTop
        spacing: Style.space(3)
        Caption { text: readout.title; Layout.fillWidth: true }
        Label { text: readout.value; color: readout.tone; font.bold: true }
        Caption { text: readout.detail; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone }
        HoverHandler { id: readoutHover }
        Ui.PanelToolTip { visible: readoutHover.hovered && readout.hint !== ""; text: readout.hint }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)
        SectionHeading {
            text: "MARGIN DEBT"
            Layout.fillWidth: true
            hint: "What customers have borrowed against securities at FINRA member firms.\n"
                + "Monthly, about three weeks after each month ends, so recent market moves aren't in it.\n"
                + "Leverage through options, futures, leveraged ETFs and securities-backed loans isn't counted."
        }
        Caption { visible: root.known; text: "Latest: " + root.monthLabel(root.latest.month) }
        ActionButton {
            text: "FINRA ↗"
            hint: "Open FINRA's margin statistics"
            onClicked: Qt.openUrlExternally("https://www.finra.org/rules-guidance/key-topics/margin-accounts/margin-statistics")
        }
    }
    MarketLoading { Layout.fillWidth: true; active: root.busy && !root.known; text: "Loading margin debt…" }
    Label {
        objectName: "marginDebtStatus"
        Layout.fillWidth: true
        visible: !root.busy && (!root.known || !!root.report.error)
        text: (root.known ? "Showing saved data. " : "") + (root.report.error || "Margin debt is unavailable.")
        color: Tone.muted
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        font.pixelSize: Style.font.bodySmall
    }
    Label {
        objectName: "marginDebtReading"
        visible: root.known
        Layout.fillWidth: true
        text: root.headline
        color: root.tone
        font.bold: true
    }
    GridLayout {
        objectName: "marginDebtReadouts"
        visible: root.known
        Layout.fillWidth: true
        columns: width >= Style.space(640) ? 4 : 2
        columnSpacing: Style.space(16)
        rowSpacing: Style.space(12)
        Readout {
            title: "Debt"
            value: StockStore.financial(root.latest.debt, "money", "USD")
            detail: root.latest.fromHigh === 0 ? "A record"
                : StockStore.percent(root.latest.fromHigh) + " from the " + root.monthLabel(root.latest.highMonth) + " record"
            hint: StockStore.percent(root.latest.monthChange) + " in a month. Record: "
                + StockStore.financial(root.latest.high, "money", "USD") + " in " + root.monthLabel(root.latest.highMonth) + "."
        }
        Readout {
            title: "1-year change"
            value: StockStore.percent(root.latest.yearChange)
            detail: MarginChart.ranking(root.latest.yearChangePercentile, root.changeSinceYear)
            hint: "Change from a year earlier. Below zero, investors are paying down margin debt."
        }
        Readout {
            title: "Share of market"
            value: root.percentText(root.latest.share)
            tone: root.tone
            detail: MarginChart.ranking(root.latest.sharePercentile, root.sinceYear)
            hint: "Debt against the Wilshire 5000, whose points roughly equal $1B of market value, so this is approximate.\n"
                + "Median since " + root.sinceYear + ": " + root.percentText(root.latest.shareMedian) + ".\n"
                + "Falling prices raise this reading, so read it with the 1-year change."
        }
        Readout {
            title: "Cash cushion"
            value: root.percentText(root.latest.cushion)
            detail: MarginChart.ranking(root.latest.cushionPercentile, root.monthLabel(root.latest.cushionSince))
            hint: "Customers' free credit balances as a share of margin debt.\n"
                + "Median since " + root.monthLabel(root.latest.cushionSince) + ": " + root.percentText(root.latest.cushionMedian) + ".\n"
                + "Cash swept into bank or money-market programs isn't counted."
        }
    }
    SegmentedControl {
        objectName: "marginDebtMode"
        visible: root.known
        // Its segments share out the width it's given rather than asking for one.
        Layout.preferredWidth: Math.min(Style.space(420), root.width)
        options: MarginChart.modes
        value: root.mode
        objectNamePrefix: "marginDebtMode_"
        onActivated: value => root.mode = value
    }
    Item {
        id: chart
        objectName: "marginDebtChart"
        visible: root.known
        Layout.fillWidth: true
        implicitHeight: Style.space(190)
        readonly property real axisWidth: Style.space(58)
        readonly property real footer: Style.font.bodySmall * 1.8
        readonly property real plotWidth: Math.max(1, width - axisWidth)
        readonly property real plotHeight: Math.max(1, height - footer)
        readonly property var points: MarginChart.points(root.months, root.mode)
        readonly property var bounds: MarginChart.range(points.map(point => point.value), root.mode)
        readonly property int hoverIndex: chartHover.hovered ? MarginChart.nearest(points.length, chartHover.point.position.x, plotWidth) : -1
        readonly property var hovered: hoverIndex >= 0 ? points[hoverIndex] : null
        function pointX(index) { return index / Math.max(1, points.length - 1) * plotWidth }
        function pointY(value) { return (bounds.high - value) / Math.max(1e-9, bounds.high - bounds.low) * plotHeight }
        Accessible.role: Accessible.Chart
        Accessible.name: root.headline
        Repeater {
            model: MarginChart.guides(chart.bounds, 4)
            Item {
                required property var modelData
                width: chart.width
                y: chart.pointY(modelData)
                Rectangle { width: chart.plotWidth; height: 1; color: Tone.muted; opacity: modelData === 0 ? .6 : .18 }
                Caption {
                    x: chart.plotWidth + Style.space(6)
                    y: -height / 2
                    text: MarginChart.axisLabel(modelData, root.mode)
                }
            }
        }
        // The median a reading is ranked against.
        Rectangle {
            visible: root.mode === "share"
            y: chart.pointY(root.latest.shareMedian || 0)
            width: chart.plotWidth
            height: 1
            color: Color.foreground
            opacity: .55
        }
        Caption {
            visible: root.mode === "share"
            x: Style.space(4)
            y: chart.pointY(root.latest.shareMedian || 0) - height
            text: "Median"
        }
        Repeater {
            model: MarginChart.yearMarks(chart.points, 5)
            Caption {
                required property var modelData
                x: chart.pointX(modelData.index) - width / 2
                y: chart.plotHeight + Style.space(6)
                text: modelData.year
            }
        }
        Canvas {
            id: lineCanvas
            anchors.fill: parent
            readonly property var points: chart.points
            readonly property var bounds: chart.bounds
            readonly property color lineColor: Color.accent
            readonly property color fallColor: StockStore.loss
            onPointsChanged: requestPaint()
            onBoundsChanged: requestPaint()
            onLineColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (points.length < 2) return
                if (root.mode === "change") {
                    // Shade the deleveraging: the stretches below zero.
                    ctx.beginPath()
                    ctx.moveTo(chart.pointX(0), chart.pointY(0))
                    points.forEach((point, index) => ctx.lineTo(chart.pointX(index), chart.pointY(Math.min(0, point.value))))
                    ctx.lineTo(chart.pointX(points.length - 1), chart.pointY(0))
                    ctx.closePath()
                    ctx.fillStyle = Qt.rgba(fallColor.r, fallColor.g, fallColor.b, .28)
                    ctx.fill()
                }
                ctx.strokeStyle = lineColor
                ctx.fillStyle = lineColor
                ctx.lineWidth = Math.max(1.5, Style.space(2))
                ctx.lineJoin = "round"
                ctx.beginPath()
                points.forEach((point, index) => index ? ctx.lineTo(chart.pointX(index), chart.pointY(point.value))
                                                       : ctx.moveTo(chart.pointX(index), chart.pointY(point.value)))
                ctx.stroke()
                const last = points.length - 1
                ctx.beginPath()
                ctx.arc(chart.pointX(last), chart.pointY(points[last].value), Style.space(3.5), 0, Math.PI * 2)
                ctx.fill()
            }
        }
        Rectangle {
            visible: !!chart.hovered
            x: chart.pointX(chart.hoverIndex)
            width: 1
            height: chart.plotHeight
            color: Color.foreground
            opacity: .45
        }
        HoverHandler { id: chartHover }
        Ui.PanelToolTip {
            visible: !!chart.hovered
            x: Math.max(0, Math.min(chart.width - width, chart.pointX(chart.hoverIndex) - width / 2))
            y: -implicitHeight - Style.space(6)
            delay: 0
            text: chart.hovered ? root.monthLabel(chart.hovered.month) + " · " + root.valueText(chart.hovered.value) : ""
        }
    }
}
