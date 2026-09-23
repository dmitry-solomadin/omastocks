import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "."

FloatingWindow {
    id: window
    // Divides the Stock page's sections; the column adds its spacing on both sides.
    component SectionDivider: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(6)
        Layout.bottomMargin: Style.space(2)
        height: 1
        color: Util.alpha(Color.foreground, .1)
    }
    property var shell: null
    title: "Stocks"
    visible: false
    implicitWidth: Style.space(1100)
    implicitHeight: Style.space(740)
    minimumSize: Qt.size(Style.space(720), Style.space(500))
    color: Color.background
    // A compositor close must also clear FloatingWindow's requested visibility.
    onClosed: visible = false
    onVisibleChanged: {
        StockStore.windowOpen = visible
        if (visible) wordmark.play()
        if (!visible) { settingsMenu.close(); watchlistMenu.close(); watchlistSelector.close(); list.cancelDrag() }
    }
    readonly property var quote: StockStore.quote
    readonly property var series: MarketStore.extendedChart ? MarketStore.extended : StockStore.visibleChart
    readonly property var points: series.points || []
    readonly property var rangeChange: points.length > 1 && points[0][1] !== 0
        ? (points[points.length - 1][1] - points[0][1]) / points[0][1] * 100 : null
    readonly property color chartColor: StockStore.direction(StockStore.period === "1D" && !MarketStore.extendedChart ? quote.percent : rangeChange)
    // While a company's valuation loads, Market details keeps placeholder slots
    // in their final order, so the grid does not grow or reshuffle on arrival.
    readonly property var valuationLabels: ["Market cap", "P/E (TTM)", "Price / sales", "Price / book", "EV / EBITDA"]
    readonly property bool valuationPending: MarketStore.companyResearchActive
        && (MarketStore.valuation.symbol !== StockStore.selected || (MarketStore.valuationRequest.busy && !(MarketStore.valuation.metrics || []).length))
    readonly property string warning: StockStore.error || series.error || quote.error ||
        (quote.stale && quote.price !== undefined ? "Showing saved prices. Refresh to check for updates." : "")
    function refresh() {
        StockStore.marketQuotesRequest.reload(true)
        if (StockStore.view !== "stock") workspace.refresh()
        else {
            StockStore.refresh(true)
            if (MarketStore.compareMode) fundamentalComparison.refresh()
            else companyActivity.refresh()
        }
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true
        Shortcut { sequence: "Ctrl+K"; context: Qt.ApplicationShortcut; enabled: content.Window.active && !settingsMenu.opened && !watchlistMenu.opened; onActivated: { search.forceActiveFocus(); search.selectAll() } }
        Shortcut { sequence: "Ctrl+R"; context: Qt.ApplicationShortcut; enabled: content.Window.active; onActivated: window.refresh() }
        Shortcut { sequence: "Ctrl+W"; context: Qt.ApplicationShortcut; enabled: content.Window.active; onActivated: window.visible = false }
        Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: content.Window.active && !settingsMenu.opened && !watchlistMenu.opened && !watchlistSelector.popupOpen; onActivated: {
            if (list.dragSymbol) list.cancelDrag()
            else if (detailChart.hasSelection) detailChart.clearSelection()
            else if (MarketStore.compareMode) MarketStore.closeComparison()
            else { search.clear(); content.forceActiveFocus() }
        } }
        Keys.onDownPressed: list.moveSelection(1)
        Keys.onUpPressed: list.moveSelection(-1)
        SettingsMenu { id: settingsMenu; parent: content; shell: window.shell }
        WatchlistMenu { id: watchlistMenu; parent: content }
        Connections { target: StockStore; function onActiveWatchlistChanged() { search.clear(); list.cancelDrag() } }
        Connections {
            target: StockStore
            function onStockAdded(ticker) {
                search.clear()
                content.forceActiveFocus()
                Qt.callLater(() => {
                    list.currentIndex = list.rows.findIndex(row => row.symbol === ticker)
                    if (list.currentIndex >= 0) list.positionViewAtIndex(list.currentIndex, ListView.Contain)
                })
            }
        }
        Connections {
            target: MarketStore
            function onCompareModeChanged() {
                Qt.callLater(() => detailScroll.contentItem.contentY = detailScroll.contentItem.originY || 0)
            }
        }
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
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: wordmark.implicitHeight
                        // The icon glyphs sit slightly high in their buttons; lift the logo to
                        // share their visual centre line.
                        StocksLogo { id: wordmark; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -Style.space(1) }
                    }
                    ActionButton { text: "↻"; hint: window.warning || "Refresh prices · Ctrl+R"; ink: window.warning ? Color.urgent : Color.foreground; enabled: !StockStore.busy; onClicked: window.refresh(); font.pixelSize: Style.space(18) }
                    ActionButton { text: "\uf013"; hint: "Settings"; font.pixelSize: Style.space(18); onClicked: settingsMenu.open() }
                }
                WatchlistSelector { id: watchlistSelector; Layout.fillWidth: true; onEditRequested: watchlistMenu.open() }
                Controls.TextField {
                    id: search
                    objectName: "stockSearch"
                    Layout.fillWidth: true
                    implicitHeight: Style.space(38)
                    placeholderText: "Search stocks · Ctrl+K"
                    color: Color.foreground
                    placeholderTextColor: Tone.muted
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
                        border.color: search.activeFocus ? Color.accent : Tone.border
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
                        if (!query) return StockStore.sortedEntries
                        const local = StockStore.sortedEntries.filter(entry => (entry.symbol + " " + entry.name).toLowerCase().indexOf(query) >= 0)
                        const results = StockStore.results.map(result =>
                            StockStore.entries.find(entry => entry.symbol === result.symbol) || result)
                        const symbols = results.map(entry => entry.symbol)
                        return results.concat(local.filter(entry => symbols.indexOf(entry.symbol) < 0))
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
                        if (StockStore.searchQuery || StockStore.sortMode !== "custom") return
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
                        if (StockStore.selected !== rows[index].symbol || StockStore.view !== "stock") StockStore.select(rows[index].symbol)
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
                            cursorShape: list.dragging ? Qt.ClosedHandCursor : StockStore.searchQuery || StockStore.sortMode !== "custom" ? Qt.PointingHandCursor : Qt.OpenHandCursor
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
                                Label { text: StockStore.watchlistMetricText(stockRow.modelData); color: StockStore.watchlistDisplay === "marketCap" ? Tone.muted : StockStore.direction(StockStore.watchlistMetric(stockRow.modelData)); font.pixelSize: Style.font.bodySmall; visible: stockRow.hasQuote }
                                Label { text: stockRow.modelData.exchange || ""; color: Tone.muted; font.pixelSize: Style.font.bodySmall; visible: !stockRow.hasQuote }
                            }
                            RowLayout {
                                width: parent.width
                                spacing: Style.space(8)
                                Label { text: stockRow.modelData.name; color: Tone.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                                PriceChart {
                                    Layout.preferredWidth: Style.space(45)
                                    Layout.preferredHeight: Style.space(20)
                                    miniature: true
                                    points: stockRow.modelData.points || []
                                    sessionStart: stockRow.modelData.sessionStart ?? null
                                    sessionEnd: stockRow.modelData.sessionEnd ?? null
                                    lineColor: StockStore.direction(stockRow.modelData.percent)
                                    visible: stockRow.hasQuote
                                }
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
                            Label { text: list.dragName; color: Tone.muted; font.pixelSize: Style.font.bodySmall; width: parent.width }
                        }
                    }
                    Keys.onReturnPressed: if (currentItem) StockStore.select(currentItem.modelData.symbol)
                    Keys.onDownPressed: moveSelection(1)
                    Keys.onUpPressed: moveSelection(-1)
                    WatchlistEmpty {
                        anchors.centerIn: parent
                        width: parent.width - Style.space(20)
                        visible: list.count === 0
                        mode: !StockStore.searchQuery ? "empty" : StockStore.searching ? "searching" : "nomatch"
                        query: StockStore.searchQuery
                        error: StockStore.searchError
                    }
                }
                Label { visible: !!StockStore.searchQuery; text: StockStore.searching ? "Searching markets…" : StockStore.searchError || list.count + " RESULTS"; color: Tone.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
            }
        }
        Flow {
            id: viewNavigation
            objectName: "viewNavigation"
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(4)
            Repeater {
                model: [{id:"stock",label:"Stock"},{id:"market",label:"Market"},{id:"watchlist",label:"Watchlist"}]
                ActionButton {
                    required property var modelData
                    objectName: "view_" + modelData.id
                    text: modelData.label
                    font.pixelSize: Style.font.bodySmall
                    selected: StockStore.view === modelData.id
                    onClicked: StockStore.view = modelData.id
                }
            }
        }
        WatchlistWorkspace {
            id: workspace
            visible: StockStore.view !== "stock"
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: viewNavigation.bottom
            anchors.topMargin: Style.space(8)
            anchors.bottom: parent.bottom
        }
        Controls.ScrollView {
            FastWheel { flickable: detailScroll.contentItem }
            id: detailScroll
            objectName: "detailScroll"
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: viewNavigation.bottom
            anchors.topMargin: Style.space(8)
            anchors.bottom: parent.bottom
            visible: StockStore.view === "stock"
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: detailScroll.availableWidth
                spacing: 0
                SessionHeader {
                    id: stockHeader
                    objectName: "stockHeader"
                    visible: !MarketStore.compareMode
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(6)
                        Label { text: StockStore.selected || "Your markets, at a glance"; font.pixelSize: Style.space(22); font.bold: true; Layout.fillWidth: true }
                        MarketStatus { session: stockHeader.session }
                    }
                    ActionButton { text: StockStore.starred ? "★" : "☆"; hint: StockStore.starred ? "Remove from bar favorites" : "Show in bar favorites"; ink: StockStore.starred ? Color.accent : Color.foreground; visible: StockStore.tracked; onClicked: StockStore.request(["favorite", StockStore.selected]) }
                    ActionButton { text: StockStore.tracked ? "Remove" : "+ Watchlist"; hint: StockStore.tracked ? "Remove from watchlist" : "Add to watchlist"; visible: !!StockStore.selected; enabled: !StockStore.busy; onClicked: StockStore.tracked ? StockStore.remove() : StockStore.add() }
                }
                ColumnLayout {
                    visible: !!StockStore.selected
                    Layout.fillWidth: true
                    Layout.margins: Style.space(28)
                    spacing: Style.space(10)
                    ColumnLayout {
                        objectName: "stockQuoteSummary"
                        visible: !MarketStore.compareMode
                        Layout.fillWidth: true
                        spacing: Style.space(10)
                        Label { text: window.quote.name || StockStore.selected; font.pixelSize: Style.space(18); color: Tone.muted; Layout.fillWidth: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Style.space(8)
                            spacing: Style.space(12)
                            Label { text: StockStore.price(window.quote.price); font.pixelSize: Style.space(48); font.bold: true }
                            Label { text: window.quote.currency || ""; color: Tone.muted; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: Style.space(8) }
                            Item { Layout.fillWidth: true }
                        }
                        Label {
                            text: window.quote.change === null || window.quote.change === undefined ? "Daily change unavailable" : (window.quote.change >= 0 ? "+" : "") + StockStore.price(window.quote.change) + " (" + StockStore.percent(window.quote.percent) + ") today"
                            color: StockStore.direction(window.quote.percent)
                            Layout.fillWidth: true
                        }
                        ExtendedQuote { Layout.fillWidth: true }
                    }
                    ChartTools { Layout.fillWidth: true; chart: detailChart }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(3)
                        Repeater {
                            model: ["1D", "1W", "1M", "3M", "1Y", "5Y"]
                            ActionButton { required property string modelData; text: modelData; selected: StockStore.period === modelData; onClicked: StockStore.range(modelData); Layout.fillWidth: true }
                        }
                        ActionButton {
                            objectName: "extendedToggle"
                            visible: StockStore.period === "1D" && !MarketStore.compareMode
                            text: "Extended"
                            font.pixelSize: Style.font.bodySmall
                            selected: MarketStore.extendedChart
                            enabled: MarketStore.extended.supported === true && (MarketStore.extended.points || []).length > 0
                            hint: MarketStore.extendedRequest.busy ? "Loading extended hours…" : MarketStore.extended.error
                                || (enabled ? "Include pre-market and after-hours in 1D · Shaded regions show extended sessions"
                                    : "Extended hours unavailable for this symbol")
                            onClicked: MarketStore.showExtended = !MarketStore.showExtended
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(Style.space(300), Math.min(Style.space(450), window.height - Style.space(480)))
                        PriceChart {
                            id: detailChart
                            objectName: "detailChart"
                            anchors.fill: parent
                            // Earnings load after prices; reserve their lane where they are expected.
                            reserveEvents: MarketStore.showEvents && !StockStore.selectedIsIndex && StockStore.period !== "1D"
                            points: window.points
                            symbol: StockStore.selected
                            dates: window.series.dates || []
                            sessions: MarketStore.extendedChart ? MarketStore.extended.sessions || [] : []
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
                            referencePrice: StockStore.period === "1D" ? window.series.previous : null
                            period: StockStore.period
                            lineColor: window.chartColor
                        }
                        Label {
                            anchors.centerIn: parent
                            text: StockStore.chartBusy ? "Loading chart…" : "No chart data available"
                            visible: window.points.length === 0
                            color: Tone.muted
                        }
                    }
                    FundamentalComparison {
                        id: fundamentalComparison
                        Layout.fillWidth: true
                        visible: MarketStore.compareMode && chosen.length > 0
                        verticalFlickable: detailScroll.contentItem
                        chosen: MarketStore.compareMode && StockStore.selected ? [StockStore.selected].concat(MarketStore.compareSymbols).filter(ticker => !StockStore.isNonCompany(ticker)) : []
                    }
                    ColumnLayout {
                        objectName: "individualStockDetails"
                        visible: !MarketStore.compareMode
                        Layout.fillWidth: true
                        spacing: Style.space(10)
                        SectionDivider {}
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: Style.space(8)
                            Label { text: "MARKET DETAILS"; color: Tone.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                        }
                        GridLayout {
                            objectName: "marketDetailsGrid"
                            Layout.fillWidth: true
                            columns: window.width < Style.space(900) ? 2 : 3
                            uniformCellWidths: true
                            rowSpacing: Style.space(22)
                            columnSpacing: Style.space(24)
                            Repeater {
                                model: [
                                    {name: "Open", value: StockStore.price(window.quote.open)},
                                    {name: "Previous close", value: StockStore.price(window.quote.previous)},
                                    {name: "52-week range", range: true}
                                ].concat((window.valuationPending ? window.valuationLabels.map(label => ({label: label})) : MarketStore.valuation.metrics || [])
                                    .map(metric => ({name: metric.label, value: StockStore.financial(metric.value, metric.kind, metric.currency)})))
                                .concat([{name: "Volume", value: StockStore.compact(window.quote.volume)},
                                    {name: "Exchange", value: window.quote.exchange || "—"}])
                                .concat(MarketStore.valuation.sector || window.valuationPending ? [{name: "Sector", value: MarketStore.valuation.sector || "—"},
                                    {name: "Industry", value: MarketStore.valuation.industry || "—"}] : [])
                                ColumnLayout {
                                    required property var modelData
                                    objectName: "marketDetail_" + modelData.name
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.preferredWidth: 0
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Style.space(6)
                                    Label { text: modelData.name; color: Tone.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                                    Label { visible: !modelData.range; text: modelData.value || ""; font.bold: true; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                    RangeGauge {
                                        objectName: modelData.range ? "yearRangeGauge" : ""
                                        visible: modelData.range === true
                                        Layout.fillWidth: true
                                        low: window.quote.yearLow; high: window.quote.yearHigh; price: window.quote.price
                                    }
                                }
                            }
                        }
                        SectionDivider { visible: !StockStore.selectedIsNonCompany }
                        EarningsPanel { visible: !StockStore.selectedIsNonCompany; Layout.fillWidth: true }
                        SectionDivider { visible: !StockStore.selectedIsNonCompany }
                        FinancialsPanel { visible: !StockStore.selectedIsNonCompany; Layout.fillWidth: true; verticalFlickable: detailScroll.contentItem }
                        SectionDivider { visible: !StockStore.selectedIsNonCompany }
                        AnalystsPanel { visible: !StockStore.selectedIsNonCompany; Layout.fillWidth: true }
                        SectionDivider { visible: !StockStore.selectedIsNonCompany }
                        CompanyActivity { id: companyActivity; visible: !StockStore.selectedIsNonCompany; Layout.fillWidth: true }
                        SectionDivider {}
                        RowLayout {
                            id: feedTabs
                            Layout.fillWidth: true
                            ActionButton {
                                objectName: "newsTab"
                                text: "Latest News"
                                font.pixelSize: Style.font.bodySmall
                                Layout.minimumWidth: implicitWidth
                                selected: !MarketStore.socialOpen
                                onClicked: MarketStore.socialOpen = false
                            }
                            ActionButton {
                                objectName: "socialTab"
                                text: "Social"
                                font.pixelSize: Style.font.bodySmall
                                Layout.minimumWidth: implicitWidth
                                selected: MarketStore.socialOpen
                                onClicked: MarketStore.socialOpen = true
                            }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                visible: !MarketStore.socialOpen
                                text: "Yahoo ↗"
                                hint: "Open company news on Yahoo Finance"
                                onClicked: Qt.openUrlExternally("https://finance.yahoo.com/quote/" + encodeURIComponent(StockStore.selected) + "/news/")
                            }
                            ActionButton {
                                text: "↻"
                                hint: MarketStore.socialOpen ? "Refresh Stocktwits posts and Reddit buzz" : "Refresh company news"
                                enabled: MarketStore.socialOpen ? !MarketStore.socialRequest.busy && !MarketStore.buzzRequest.busy : !MarketStore.newsRequest.busy
                                onClicked: {
                                    if (MarketStore.socialOpen) { MarketStore.socialRequest.reload(true); MarketStore.buzzRequest.reload(true) }
                                    else MarketStore.newsRequest.reload(true)
                                }
                            }
                        }
                        Item {
                            objectName: "feedBody"
                            Layout.fillWidth: true
                            readonly property bool loading: MarketStore.socialOpen
                                ? MarketStore.socialRequest.busy || MarketStore.buzzRequest.busy : MarketStore.newsRequest.busy
                            // While a feed loads, keep a viewport below the tabs so the Flickable
                            // does not clamp contentY as the old feed disappears. Once loaded, take
                            // the feed's own height so there is no empty space at the bottom.
                            Layout.preferredHeight: Math.max(
                                MarketStore.socialOpen ? socialFeed.implicitHeight : newsFeed.implicitHeight,
                                loading ? detailScroll.availableHeight - feedTabs.height - Style.space(10) : 0)
                            CompanyNews { id: newsFeed; objectName: "newsFeed"; width: parent.width; height: implicitHeight; visible: !MarketStore.socialOpen }
                            SocialPanel { id: socialFeed; width: parent.width; height: implicitHeight; visible: MarketStore.socialOpen }
                        }
                    }
                }
                Label {
                    visible: !StockStore.selected
                    Layout.fillWidth: true
                    Layout.margins: Style.space(32)
                    text: "Make it your watchlist.\n\nSearch for a company or ticker in the sidebar\nto explore."
                    wrapMode: Text.WordWrap
                    color: Tone.muted
                }
            }
        }
    }
}
