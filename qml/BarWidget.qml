import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "." as Stocks

Ui.BarWidget {
    id: root
    moduleName: "io.github.dmitry-solomadin.omastocks"
    onSettingsChanged: Stocks.StockStore.barSettings = Object.assign({}, settings)
    Component.onCompleted: Stocks.StockStore.barSettings = Object.assign({}, settings)
    readonly property bool stripEnabled: setting("showStrip", true) !== false
    readonly property bool showPrice: setting("showPrice", false) === true
    readonly property bool showPercent: setting("showPercent", true) !== false
    readonly property bool showChange: setting("showChange", false) === true
    readonly property var favorites: Stocks.StockStore.favorites
    readonly property real maxWidth: Math.max(40, Math.min(800, Number(setting("maxWidth", 360)) || 360))
    readonly property real entryGap: Style.space(18)
    readonly property var tickerEntries: favorites.map(entry => {
        const parts = [entry.symbol]
        if (showPrice) parts.push(Stocks.StockStore.price(entry.price))
        if (showPercent) parts.push(Stocks.StockStore.percent(entry.percent))
        if (showChange) parts.push(changeText(entry))
        if (entry.stale) parts.push("◷")
        const text = parts.join(" ")
        return {symbol: entry.symbol, text: text, percent: entry.percent, width: Math.ceil(metrics.advanceWidth(text))}
    })
    readonly property real contentWidth: tickerEntries.reduce((sum, entry) => sum + entry.width, 0)
        + Math.max(0, tickerEntries.length - 1) * entryGap
    readonly property real cycleWidth: contentWidth + entryGap
    readonly property bool overflowing: !vertical && favorites.length > 0 && contentWidth > viewport.width + .5
    property real scrollOffset: 0
    // The ticker under the pointer: a click opens it and hovering previews it.
    property Item hoveredTicker: null
    readonly property var previewEntry: favorites.find(entry => entry.symbol === preview.symbol) || null
    function changeText(entry) {
        if (entry.change === undefined || entry.change === null) return "—"
        const symbols = {USD: "$", GBP: "£", EUR: "€", JPY: "¥", CNY: "¥"}
        const unit = symbols[entry.currency] || (entry.currency ? entry.currency + " " : "")
        return (entry.change < 0 ? "−" : "+") + unit + Stocks.StockStore.price(Math.abs(entry.change))
    }
    function showPreview() {
        if (!hoveredTicker) return
        preview.target = hoveredTicker
        sparkline.now = Date.now() / 1000
        preview.shown = true
        preview.anchor.updateAnchor()
    }
    function hidePreview() {
        previewDelay.stop()
        preview.shown = false
    }
    // Moving between neighbouring tickers leaves one before entering the next;
    // a short grace period keeps an open preview from flickering between them.
    onHoveredTickerChanged: {
        if (hoveredTicker) {
            previewHide.stop()
            if (preview.shown) showPreview()
            else previewDelay.restart()
        } else {
            previewDelay.stop()
            previewHide.restart()
        }
    }
    // Hovering the bar's center section reveals its hidden indicators, which
    // widens the section and slides these tickers under the pointer. Hold the
    // strip still while it is hovered, unless the indicators were already
    // showing before the pointer arrived (collapsing them would slide it back).
    readonly property bool stripHovered: stripHover.hovered && !button.labelVisible
    property bool holdingReveal: false
    property real revealedAt: 0
    function holdReveal(hold) {
        if (!bar || typeof bar.setCenterHoverRevealSuppressed !== "function" || hold === holdingReveal) return
        // Another widget, such as an open clock panel, already suppresses it.
        if (hold && (bar.centerHoverRevealSuppressed || (bar.centerSectionRevealHeld && Date.now() - revealedAt > 150))) return
        holdingReveal = hold
        bar.setCenterHoverRevealSuppressed(hold)
    }
    // Release after the bar's own 120 ms collapse, so leaving the bar from the
    // strip does not flash the indicators.
    onStripHoveredChanged: {
        if (stripHovered) { revealRelease.stop(); holdReveal(true) }
        else revealRelease.restart()
    }
    Timer { id: revealRelease; interval: 150; onTriggered: root.holdReveal(false) }
    Component.onDestruction: holdReveal(false)
    Connections {
        target: root.bar
        ignoreUnknownSignals: true
        function onCenterSectionRevealHeldChanged() { if (root.bar.centerSectionRevealHeld) root.revealedAt = Date.now() }
    }
    Timer { id: previewDelay; interval: 400; onTriggered: root.showPreview() }
    Timer { id: previewHide; interval: 120; onTriggered: if (!root.hoveredTicker) preview.shown = false }
    onCycleWidthChanged: { if (marquee.running) marquee.restart(); else scrollOffset = 0 }
    onOverflowingChanged: if (!overflowing) scrollOffset = 0
    FontMetrics { id: metrics; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body }
    implicitWidth: !stripEnabled ? 0 : !vertical && favorites.length
        ? Math.min(Style.space(maxWidth), contentWidth + button.scaledHorizontalMargin * 2) : button.implicitWidth
    implicitHeight: stripEnabled ? button.implicitHeight : 0
    NumberAnimation {
        id: marquee
        target: root
        property: "scrollOffset"
        from: 0
        to: root.cycleWidth
        duration: Math.max(1, Math.round(root.cycleWidth / Style.spaceReal(30) * 1000))
        loops: Animation.Infinite
        running: root.overflowing && root.stripEnabled && root.visible && !button.concealed
        paused: running && button.tooltipHovered
        onStopped: root.scrollOffset = 0
    }
    Ui.WidgetButton {
        id: button
        visible: root.stripEnabled
        bar: root.bar
        width: root.width
        text: ""
        labelVisible: root.vertical || !root.favorites.length
        tooltipText: ""
        onPressed: mouseButton => {
            root.hidePreview()
            if (mouseButton === Qt.MiddleButton) Stocks.StockStore.refresh(true)
            else if (mouseButton === Qt.LeftButton && root.hoveredTicker) Stocks.StockStore.show(root.hoveredTicker.modelData.symbol)
            else Stocks.StockStore.openRequested()
        }
        Item {
            id: viewport
            anchors.fill: parent
            anchors.leftMargin: button.scaledHorizontalMargin
            anchors.rightMargin: button.scaledHorizontalMargin
            clip: true
            visible: !button.labelVisible
            HoverHandler { id: stripHover }
            Item {
                x: -root.scrollOffset
                height: parent.height
                Repeater {
                    model: root.overflowing ? 2 : 1
                    Row {
                        required property int index
                        x: index * root.cycleWidth
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.entryGap
                        Repeater {
                            model: root.tickerEntries
                            Text {
                                id: ticker
                                required property var modelData
                                text: modelData.text
                                width: modelData.width
                                textFormat: Text.PlainText
                                renderType: Text.NativeRendering
                                font.family: metrics.font.family
                                font.pixelSize: metrics.font.pixelSize
                                color: Stocks.StockStore.direction(modelData.percent)
                                // Half of each gap belongs to the ticker beside it.
                                HoverHandler {
                                    margin: root.entryGap / 2
                                    onHoveredChanged: {
                                        if (hovered) root.hoveredTicker = ticker
                                        else if (root.hoveredTicker === ticker) root.hoveredTicker = null
                                    }
                                }
                                Component.onDestruction: if (root.hoveredTicker === ticker) root.hoveredTicker = null
                            }
                        }
                    }
                }
            }
        }
    }
    PopupWindow {
        id: preview
        property bool shown: false
        property Item target: null
        // Derived from the ticker itself: a handler reacting to a hover change
        // could otherwise pair the new position with the previous symbol.
        readonly property string symbol: target ? target.modelData.symbol : ""
        readonly property var entry: root.previewEntry || ({})
        visible: shown && !!target && !!root.previewEntry && root.stripEnabled && !button.concealed
        color: "transparent"
        implicitWidth: Math.ceil(card.implicitWidth)
        implicitHeight: Math.ceil(card.implicitHeight)
        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1
            onAnchoring: {
                const window = root.QsWindow.window
                if (!preview.target || !window) return
                const gap = Style.space(6)
                const top = root.bar && root.bar.position === "bottom" ? -preview.implicitHeight - gap : button.height + gap
                const x = window.contentItem.mapFromItem(preview.target, preview.target.width / 2 - preview.implicitWidth / 2, 0).x
                preview.anchor.rect.x = Math.round(x)
                preview.anchor.rect.y = Math.round(window.contentItem.mapFromItem(button, 0, top).y)
            }
        }
        Ui.BorderSurface {
            id: card
            implicitWidth: Style.space(260)
            implicitHeight: details.implicitHeight + Style.space(24)
            color: Color.tooltip.background
            borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
            radius: Style.cornerRadius
            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(8)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(10)
                    Stocks.Label { text: preview.symbol; font.bold: true; color: Color.tooltip.text }
                    Item { Layout.fillWidth: true }
                    Stocks.Label { text: Stocks.StockStore.price(preview.entry.price) + (preview.entry.currency ? " " + preview.entry.currency : ""); font.bold: true; color: Color.tooltip.text }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(10)
                    Stocks.Label { text: preview.entry.name || ""; color: Stocks.Tone.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                    Stocks.Label {
                        text: root.changeText(preview.entry) + " (" + Stocks.StockStore.percent(preview.entry.percent) + ")"
                        color: Stocks.StockStore.direction(preview.entry.percent)
                        font.pixelSize: Style.font.bodySmall
                    }
                }
                Stocks.PriceChart {
                    id: sparkline
                    visible: (preview.entry.points || []).length > 1
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(56)
                    miniature: true
                    points: preview.entry.points || []
                    sessionStart: preview.entry.sessionStart ?? null
                    sessionEnd: preview.entry.sessionEnd ?? null
                    referencePrice: preview.entry.previous ?? null
                    lineColor: Stocks.StockStore.direction(preview.entry.percent)
                }
                Stocks.Label { text: "Day range"; color: Stocks.Tone.muted; font.pixelSize: Style.font.bodySmall }
                Stocks.RangeGauge {
                    Layout.fillWidth: true
                    title: "Day"
                    low: preview.entry.low ?? null
                    high: preview.entry.high ?? null
                    price: preview.entry.price ?? null
                }
                Stocks.Label {
                    text: (preview.entry.updated ? Qt.formatDateTime(new Date(preview.entry.updated * 1000), "d MMM, hh:mm") : "")
                        + (preview.entry.stale ? " · saved price" : "") + (preview.entry.updated || preview.entry.stale ? " · " : "") + "Click to open"
                    color: Stocks.Tone.muted
                    font.pixelSize: Style.font.bodySmall
                    Layout.fillWidth: true
                }
            }
        }
    }
}
