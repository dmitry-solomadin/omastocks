import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "."

FloatingWindow {
    id: window
    property var shell: null
    title: "Omastocks"
    visible: false
    implicitWidth: Style.space(1100)
    implicitHeight: Style.space(740)
    minimumSize: Qt.size(Style.space(720), Style.space(500))
    color: Color.background
    // A compositor close must also clear FloatingWindow's requested visibility.
    onClosed: visible = false
    onVisibleChanged: {
        StockStore.windowOpen = visible
        if (!visible) { settingsMenu.close(); list.cancelDrag() }
    }
    readonly property var quote: StockStore.quote
    readonly property var series: StockStore.visibleChart
    readonly property var points: series.points || []
    readonly property var rangeChange: points.length > 1 && points[0][1] !== 0
        ? (points[points.length - 1][1] - points[0][1]) / points[0][1] * 100 : null
    readonly property color chartColor: StockStore.direction(StockStore.period === "1D" ? quote.percent : rangeChange)
    readonly property string warning: StockStore.error || series.error || quote.error ||
        (quote.stale && quote.price !== undefined ? "Showing saved prices. Refresh to check for updates." : "")

    Item {
        id: content
        anchors.fill: parent
        focus: true
        Shortcut { sequence: "Ctrl+K"; context: Qt.ApplicationShortcut; enabled: content.Window.active && !settingsMenu.opened; onActivated: { search.forceActiveFocus(); search.selectAll() } }
        Shortcut { sequence: "Ctrl+R"; context: Qt.ApplicationShortcut; enabled: content.Window.active; onActivated: StockStore.refresh(true) }
        Shortcut { sequence: "Ctrl+W"; context: Qt.ApplicationShortcut; enabled: content.Window.active; onActivated: window.visible = false }
        Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: content.Window.active && !settingsMenu.opened; onActivated: {
            if (list.dragSymbol) list.cancelDrag()
            else if (detailChart.hasSelection) detailChart.clearSelection()
            else if (MarketStore.compareMode) MarketStore.closeComparison()
            else { search.clear(); content.forceActiveFocus() }
        } }
        Keys.onDownPressed: list.moveSelection(1)
        Keys.onUpPressed: list.moveSelection(-1)
        SettingsMenu { id: settingsMenu; parent: content; shell: window.shell }
        Rectangle {
            id: sidebar
            width: Style.space(window.width < Style.space(900) ? 245 : 300)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: Util.alpha(Color.foreground, .025)
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Util.alpha(Color.foreground, .1) }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.space(18)
                spacing: Style.space(16)
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "Omastocks"; font.pixelSize: Style.space(24); font.bold: true; Layout.fillWidth: true
                        fontSizeMode: Text.HorizontalFit; minimumPixelSize: Style.space(14)
                    }
                    ActionButton { text: "↻"; hint: "Refresh prices · Ctrl+R"; enabled: !StockStore.busy; onClicked: StockStore.refresh(true); font.pixelSize: Style.space(18) }
                    ActionButton { text: "\uf013"; hint: "Settings"; font.pixelSize: Style.space(18); onClicked: settingsMenu.open() }
                }
                Controls.TextField {
                    id: search
                    objectName: "stockSearch"
                    Layout.fillWidth: true
                    implicitHeight: Style.space(38)
                    placeholderText: "Search stocks · Ctrl+K"
                    color: Color.foreground
                    placeholderTextColor: Color.muted
                    selectionColor: Util.alpha(Color.accent, .3)
                    selectedTextColor: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    leftPadding: Style.space(12)
                    rightPadding: clearSearch.visible ? clearSearch.width + Style.space(8) : Style.space(12)
                    ActionButton {
                        id: clearSearch
                        objectName: "clearSearch"
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(2)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(36)
                        height: parent.height - Style.space(4)
                        padding: 0
                        text: "×"
                        font.pixelSize: Style.font.body * 2
                        hint: "Clear search"
                        visible: !!search.text
                        onClicked: { search.clear(); search.forceActiveFocus() }
                    }
                    background: Rectangle {
                        color: Util.alpha(Color.foreground, .04)
                        radius: Style.cornerRadius
                        border.width: 1
                        border.color: search.activeFocus ? Color.accent : Util.alpha(Color.foreground, .12)
                    }
                    onTextChanged: { list.cancelDrag(); StockStore.search(text) }
                    onAccepted: list.selectIndex(0)
                    Keys.onDownPressed: list.selectIndex(0)
                    Keys.onUpPressed: list.selectIndex(list.count - 1)
                    Accessible.name: "Search stocks by name or ticker"
                }
                ListView {
                    id: list
                    FastWheel { flickable: list }
                    objectName: "stockList"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Style.space(4)
                    readonly property var rows: {
                        const query = StockStore.searchQuery.toLowerCase()
                        if (!query) return StockStore.entries
                        const local = StockStore.entries.filter(entry => (entry.symbol + " " + entry.name).toLowerCase().indexOf(query) >= 0)
                        const symbols = local.map(entry => entry.symbol)
                        return local.concat(StockStore.results.filter(entry => symbols.indexOf(entry.symbol) < 0).map(result =>
                            StockStore.entries.find(entry => entry.symbol === result.symbol) || result))
                    }
                    model: rows
                    keyNavigationEnabled: false
                    property string dragSymbol: ""
                    property string dragName: ""
                    property bool dragging: false
                    property real pressX: 0
                    property real pressY: 0
                    property real dragX: 0
                    property real dragY: 0
                    readonly property real rowHeight: Style.space(64)
                    readonly property real rowStep: rowHeight + spacing
                    readonly property bool dropInside: dragX >= 0 && dragX <= width && dragY >= 0 && dragY <= height
                    readonly property int insertionIndex: Math.max(0, Math.min(count,
                        Math.floor((contentY - originY + dragY + rowHeight / 2) / rowStep)))
                    function beginDrag(entry, point) {
                        if (StockStore.searchQuery) return
                        // Keep the grabbed delegate alive while edge scrolling.
                        currentIndex = rows.findIndex(row => row.symbol === entry.symbol)
                        dragSymbol = entry.symbol
                        dragName = entry.name || entry.symbol
                        pressX = dragX = point.x
                        pressY = dragY = point.y
                    }
                    function updateDrag(point) {
                        if (!dragSymbol) return
                        dragX = point.x
                        dragY = point.y
                        if (Math.abs(dragY - pressY) > Style.space(6) || Math.abs(dragX - pressX) > Style.space(6)) dragging = true
                    }
                    function cancelDrag() { dragging = false; dragSymbol = ""; dragName = "" }
                    function finishDrag() {
                        const ticker = dragSymbol
                        const before = insertionIndex < rows.length ? rows[insertionIndex].symbol : ""
                        const accepted = dragging && dropInside
                        cancelDrag()
                        if (accepted) StockStore.move(ticker, before)
                    }
                    Timer {
                        interval: 30
                        repeat: true
                        running: list.dragging && list.dropInside
                        onTriggered: {
                            const edge = Style.space(32)
                            const direction = list.dragY < edge ? -1 : list.dragY > list.height - edge ? 1 : 0
                            if (direction) list.contentY = Math.max(list.originY, Math.min(
                                list.originY + Math.max(0, list.contentHeight - list.height), list.contentY + direction * Style.space(10)))
                        }
                    }
                    function selectIndex(index) {
                        if (index < 0 || index >= rows.length) return
                        currentIndex = index
                        forceActiveFocus()
                        positionViewAtIndex(index, ListView.Contain)
                        if (StockStore.selected !== rows[index].symbol) StockStore.select(rows[index].symbol)
                    }
                    function moveSelection(step) {
                        const index = rows.findIndex(entry => entry.symbol === StockStore.selected)
                        selectIndex(index < 0 ? (step > 0 ? 0 : rows.length - 1) : Math.max(0, Math.min(rows.length - 1, index + step)))
                    }
                    onModelChanged: currentIndex = rows.findIndex(entry => entry.symbol === StockStore.selected)
                    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
                    delegate: Item {
                        id: stockRow
                        required property var modelData
                        required property int index
                        width: list.width
                        height: Style.space(64)
                        opacity: list.dragging && list.dragSymbol === modelData.symbol ? .35 : 1
                        readonly property bool hasQuote: modelData.price !== undefined
                        readonly property bool tracked: StockStore.entries.some(entry => entry.symbol === modelData.symbol)
                        Rectangle {
                            anchors.fill: parent
                            radius: Style.cornerRadius
                            color: stockRow.modelData.symbol === StockStore.selected ? Util.alpha(Color.accent, .1) : rowMouse.containsMouse ? Util.alpha(Color.foreground, .05) : "transparent"
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            property bool wasDragged: false
                            preventStealing: !StockStore.searchQuery
                            cursorShape: list.dragging ? Qt.ClosedHandCursor : StockStore.searchQuery ? Qt.PointingHandCursor : Qt.OpenHandCursor
                            onPressed: mouse => {
                                wasDragged = false
                                list.beginDrag(stockRow.modelData, mapToItem(list, mouse.x, mouse.y))
                            }
                            onPositionChanged: mouse => {
                                if (!pressed) return
                                list.updateDrag(mapToItem(list, mouse.x, mouse.y))
                                if (list.dragging) wasDragged = true
                            }
                            onReleased: list.finishDrag()
                            onCanceled: list.cancelDrag()
                            onClicked: if (!wasDragged) list.selectIndex(stockRow.index)
                        }
                        Column {
                            anchors.left: parent.left; anchors.leftMargin: Style.space(12)
                            anchors.right: parent.right; anchors.rightMargin: addResult.visible ? addResult.width + Style.space(14) : Style.space(12)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.space(7)
                            RowLayout {
                                width: parent.width
                                spacing: Style.space(6)
                                Label { text: "★"; visible: stockRow.modelData.favorite === true; color: Color.accent; font.pixelSize: Style.font.bodySmall }
                                Label { text: stockRow.modelData.symbol; font.bold: true; Layout.fillWidth: true }
                                Label { text: StockStore.price(stockRow.modelData.price); visible: stockRow.hasQuote; font.bold: true }
                                Label { text: StockStore.percent(stockRow.modelData.percent); color: StockStore.direction(stockRow.modelData.percent); font.pixelSize: Style.font.bodySmall; visible: stockRow.hasQuote }
                                Label { text: stockRow.modelData.exchange || ""; color: Color.muted; font.pixelSize: Style.font.bodySmall; visible: !stockRow.hasQuote }
                            }
                            RowLayout {
                                width: parent.width
                                spacing: Style.space(8)
                                Label { text: stockRow.modelData.name; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                                PriceChart { Layout.preferredWidth: Style.space(45); Layout.preferredHeight: Style.space(20); miniature: true; points: stockRow.modelData.points || []; lineColor: StockStore.direction(stockRow.modelData.percent); visible: stockRow.hasQuote }
                            }
                        }
                        ActionButton {
                            id: addResult
                            objectName: "addResult_" + stockRow.modelData.symbol
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(4)
                            anchors.verticalCenter: parent.verticalCenter
                            width: Style.space(32)
                            padding: 0
                            text: "+"
                            font.pixelSize: Style.space(24)
                            ink: Color.accent
                            hint: "Add " + stockRow.modelData.symbol + " to watchlist"
                            visible: !!StockStore.searchQuery && !stockRow.tracked
                            enabled: !StockStore.adding(stockRow.modelData.symbol)
                            onClicked: StockStore.add(stockRow.modelData.symbol, stockRow.modelData.name)
                        }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.symbol + " " + modelData.name
                        Accessible.description: StockStore.searchQuery ? "" : "Drag to reorder your watchlist"
                    }
                    Rectangle {
                        parent: list
                        z: 3
                        visible: list.dragging && list.dropInside
                        x: Style.space(4)
                        y: Math.max(0, Math.min(list.height - height,
                            list.insertionIndex * list.rowStep - (list.contentY - list.originY) - list.spacing / 2))
                        width: list.width - Style.space(8)
                        height: Style.space(2)
                        color: Color.accent
                    }
                    Rectangle {
                        parent: list
                        z: 2
                        visible: list.dragging
                        x: Style.space(8)
                        y: Math.max(0, Math.min(list.height - height, list.dragY - height / 2))
                        width: list.width - Style.space(16)
                        height: list.rowHeight
                        radius: Style.cornerRadius
                        color: Color.background
                        border.width: 1
                        border.color: Color.accent
                        Column {
                            anchors.fill: parent
                            anchors.margins: Style.space(10)
                            spacing: Style.space(4)
                            Label { text: list.dragSymbol; font.bold: true; width: parent.width }
                            Label { text: list.dragName; color: Color.muted; font.pixelSize: Style.font.bodySmall; width: parent.width }
                        }
                    }
                    Keys.onReturnPressed: if (currentItem) StockStore.select(currentItem.modelData.symbol)
                    Keys.onDownPressed: moveSelection(1)
                    Keys.onUpPressed: moveSelection(-1)
                    Label {
                        anchors.centerIn: parent
                        width: parent.width - Style.space(20)
                        visible: list.count === 0
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: Color.muted
                        text: StockStore.searchQuery ? (StockStore.searching ? "Searching markets…" : StockStore.searchError || "No matching stocks found.") : "Your watchlist is empty.\nSearch for a stock to begin."
                    }
                }
                Label { visible: !!StockStore.searchQuery; text: StockStore.searching ? "Searching markets…" : StockStore.searchError || list.count + " RESULTS"; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
            }
        }
        Controls.ScrollView {
            FastWheel { flickable: detailScroll.contentItem }
            id: detailScroll
            objectName: "detailScroll"
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: footer.top
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: detailScroll.availableWidth
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: Style.space(24)
                    Label { text: StockStore.selected || "Your markets, at a glance"; font.pixelSize: Style.space(22); font.bold: true; Layout.fillWidth: true }
                    ActionButton { text: StockStore.starred ? "★" : "☆"; hint: StockStore.starred ? "Remove from bar favorites" : "Show in bar favorites"; ink: StockStore.starred ? Color.accent : Color.foreground; visible: StockStore.tracked; onClicked: StockStore.request(["favorite", StockStore.selected]) }
                    ActionButton { text: StockStore.tracked ? "Remove" : "+ Watchlist"; hint: StockStore.tracked ? "Remove from watchlist" : "Add to watchlist"; visible: !!StockStore.selected; enabled: !StockStore.busy; onClicked: StockStore.tracked ? StockStore.remove() : StockStore.add() }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, .09) }
                ColumnLayout {
                    visible: !!StockStore.selected
                    Layout.fillWidth: true
                    Layout.margins: Style.space(28)
                    spacing: Style.space(10)
                    Label { text: window.quote.name || StockStore.selected; font.pixelSize: Style.space(18); color: Color.muted; Layout.fillWidth: true }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Style.space(8)
                        spacing: Style.space(12)
                        Label { text: StockStore.price(window.quote.price); font.pixelSize: Style.space(48); font.bold: true }
                        Label { text: window.quote.currency || ""; color: Color.muted; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: Style.space(8) }
                        Item { Layout.fillWidth: true }
                    }
                    Label {
                        text: window.quote.change === null || window.quote.change === undefined ? "Daily change unavailable" : (window.quote.change >= 0 ? "+" : "") + StockStore.price(window.quote.change) + " (" + StockStore.percent(window.quote.percent) + ") today"
                        color: StockStore.direction(window.quote.percent)
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.topMargin: Style.space(20)
                        Layout.fillWidth: true
                        ChartTools { Layout.fillWidth: true; chart: detailChart }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(3)
                        Repeater {
                            model: ["1D", "1W", "1M", "3M", "1Y", "5Y"]
                            ActionButton { required property string modelData; text: modelData; selected: StockStore.period === modelData; onClicked: StockStore.range(modelData); Layout.fillWidth: true }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(Style.space(300), Math.min(Style.space(450), window.height - Style.space(480)))
                        PriceChart {
                            id: detailChart
                            objectName: "detailChart"
                            anchors.fill: parent
                            points: window.points
                            symbol: StockStore.selected
                            dates: window.series.dates || []
                            volumes: window.series.volumes || []
                            showVolume: MarketStore.showVolume
                            compareMode: MarketStore.compareMode
                            comparisons: MarketStore.comparisons
                            primaryColor: MarketStore.compareColors[0]
                            averages: (MarketStore.averages.series || []).filter(series => MarketStore.averageWindows.indexOf(series.window) >= 0)
                                .map(series => Object.assign({}, series, {color: MarketStore.averageColor(series.window)}))
                            events: MarketStore.showEvents ? (window.series.events || []).concat(MarketStore.earnings.events || [])
                                .concat(MarketStore.earnings.next ? [MarketStore.earnings.next] : []) : []
                            sessionStart: window.series.sessionStart === undefined ? null : window.series.sessionStart
                            sessionEnd: window.series.sessionEnd === undefined ? null : window.series.sessionEnd
                            currency: window.quote.currency || ""
                            referencePrice: StockStore.period === "1D" ? window.quote.previous : null
                            period: StockStore.period
                            lineColor: window.chartColor
                        }
                        Label {
                            anchors.centerIn: parent
                            text: StockStore.chartBusy ? "Loading chart…" : "No chart data available"
                            visible: window.points.length === 0
                            color: Color.muted
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: StockStore.period === "1D" && !detailChart.comparing
                        text: "Dashed line: previous close"
                        color: Color.muted
                        font.pixelSize: Style.font.bodySmall
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: Style.space(18); Layout.bottomMargin: Style.space(8); height: 1; color: Util.alpha(Color.foreground, .1) }
                    EarningsPanel { Layout.fillWidth: true }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: Style.space(18); Layout.bottomMargin: Style.space(8); height: 1; color: Util.alpha(Color.foreground, .1) }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Style.space(8)
                        Label { text: "MARKET DETAILS"; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                        ActionButton {
                            text: MarketStore.valuationRequest.busy ? "…" : "ⓘ"
                            hint: MarketStore.valuation.error || "Quotes: Yahoo Finance · Valuations: TradingView (US listings, cached one hour)"
                                + (MarketStore.valuation.stale ? " · Saved data" : "")
                            onClicked: MarketStore.valuationRequest.reload(true)
                        }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: window.width < Style.space(900) ? 2 : 3
                        rowSpacing: Style.space(22)
                        columnSpacing: Style.space(24)
                        Repeater {
                            model: [
                                {name: "Open", value: StockStore.price(window.quote.open)},
                                {name: "Day high", value: StockStore.price(window.quote.high)},
                                {name: "Day low", value: StockStore.price(window.quote.low)},
                                {name: "Previous close", value: StockStore.price(window.quote.previous)},
                                {name: "52-week high", value: StockStore.price(window.quote.yearHigh)},
                                {name: "52-week low", value: StockStore.price(window.quote.yearLow)},
                                {name: "Volume", value: StockStore.compact(window.quote.volume)},
                                {name: "Exchange", value: window.quote.exchange || "—"},
                                {name: "Currency", value: window.quote.currency || "—"}
                            ].concat((MarketStore.valuation.metrics || []).map(metric => ({name: metric.label,
                                value: StockStore.financial(metric.value, metric.kind, metric.currency)})))
                            .concat(MarketStore.valuation.sector ? [{name: "Sector", value: MarketStore.valuation.sector},
                                {name: "Industry", value: MarketStore.valuation.industry}] : [])
                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Style.space(6)
                                Label { text: modelData.name; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                                Label { text: modelData.value; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: Style.space(18); Layout.bottomMargin: Style.space(8); height: 1; color: Util.alpha(Color.foreground, .1) }
                    FinancialsPanel { Layout.fillWidth: true }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: Style.space(18); Layout.bottomMargin: Style.space(8); height: 1; color: Util.alpha(Color.foreground, .1) }
                    CompanyNews { Layout.fillWidth: true }
                }
                Label {
                    visible: !StockStore.selected
                    Layout.fillWidth: true
                    Layout.margins: Style.space(32)
                    text: "Make it your watchlist.\n\nSearch for a company or ticker in the sidebar\nto explore."
                    wrapMode: Text.WordWrap
                    color: Color.muted
                }
            }
        }
        Rectangle {
            id: footer
            anchors.left: sidebar.right; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: Style.space(48)
            color: window.warning ? Util.alpha(Color.urgent, .06) : "transparent"
            Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.foreground, .09) }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(24); anchors.rightMargin: Style.space(12)
                Label {
                    Layout.fillWidth: true
                    text: StockStore.removed ? "Removed " + StockStore.removed.symbol : window.warning || (StockStore.busy ? "Updating market data…" : "Yahoo Finance  ·  Prices may be delayed")
                    color: window.warning ? Color.urgent : Color.muted
                    font.pixelSize: Style.font.bodySmall
                    Ui.PanelToolTip { visible: footerMouse.containsMouse && !!window.warning; text: window.warning }
                    MouseArea { id: footerMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
                ActionButton { text: "Undo"; visible: StockStore.removed !== null; onClicked: StockStore.undo() }
                ActionButton { text: "Retry"; visible: !!window.warning && !StockStore.busy; onClicked: StockStore.refresh(true) }
            }
        }
    }
}
