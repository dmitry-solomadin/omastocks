pragma Singleton
import QtQuick
import qs.Commons
import "."
import "ChartMath.js" as ChartMath

QtObject {
    id: root
    readonly property bool active: StockStore.running && StockStore.windowOpen && StockStore.view === "stock" && !!StockStore.selected
    readonly property bool stockResearchActive: active && !compareMode
    readonly property bool showVolume: StockStore.barSettings.showVolume !== false
    readonly property bool showEvents: StockStore.barSettings.showEvents !== false
    readonly property bool averagesAvailable: ChartMath.dailyAveragesSupported(StockStore.period)
    property var averageWindows: []
    property bool compareMode: false
    property var compareSlots: ["", "", "", ""]
    readonly property var compareSymbols: compareSlots.filter(ticker => !!ticker)
    readonly property var compareColors: ["#4e9eff", "#f6bf4f", "#be8cff", "#41c9b4", "#f07eaa"]
    property string compareValidation: ""
    readonly property var news: newsRequest.data
    property bool socialOpen: false
    readonly property var social: socialRequest.data
    readonly property var buzz: buzzRequest.data
    readonly property var earnings: eventsRequest.data
    property bool earningsCallsOpen: false
    readonly property var earningsCalls: callsRequest.data
    readonly property var averages: averagesRequest.data
    property bool financialsOpen: false
    property string financialFrequency: "quarterly"
    readonly property var financials: financialsRequest.data
    readonly property var valuation: valuationRequest.data
    property bool analystsOpen: false
    readonly property var analysts: analystsRequest.data
    property bool showExtended: false
    readonly property var extended: extendedRequest.data
    readonly property bool extendedChart: showExtended && StockStore.period === "1D" && !compareMode
        && extended.supported === true && (extended.points || []).length > 0
    readonly property var comparisonRequests: [compareOne, compareTwo, compareThree, compareFour]
    readonly property var comparisons: comparisonRequests.map((request, index) => ({
        symbol: compareSlots[index], color: compareColors[index + 1], data: request.data, busy: request.busy
    })).filter(entry => !!entry.symbol)
    function averageColor(window) { return StockStore.chartColors[[20, 50, 200].indexOf(window)] || Color.foreground }
    function toggleAverage(window) {
        averageWindows = averageWindows.indexOf(window) >= 0 ? averageWindows.filter(value => value !== window)
            : averageWindows.concat([window]).sort((a, b) => a - b)
    }
    function compare(value) {
        const ticker = value.trim().toUpperCase()
        compareValidation = ""
        if (ticker && !/^[A-Z0-9^][A-Z0-9.^=\-]{0,29}$/.test(ticker)) {
            compareValidation = "Enter a ticker symbol, such as MSFT or SPY."
            return false
        }
        if (!ticker || ticker === StockStore.selected || compareSymbols.indexOf(ticker) >= 0) {
            compareValidation = "Choose a stock that is not already in the comparison."
            return false
        }
        const index = compareSlots.indexOf("")
        if (index < 0) { compareValidation = "Maximum five stocks, including the selected stock."; return false }
        const slots = compareSlots.slice()
        slots[index] = ticker
        compareSlots = slots
        compareMode = true
        return true
    }
    function removeComparison(ticker) {
        compareSlots = compareSlots.map(value => value === ticker ? "" : value)
        compareValidation = ""
    }
    function closeComparison() {
        compareMode = false
        compareSlots = ["", "", "", ""]
        compareValidation = ""
    }
    function comparisonArguments(index) {
        return active && compareMode && compareSlots[index] ? ["compare", compareSlots[index], StockStore.period] : []
    }
    function refresh(force) {
        newsRequest.reload(force)
        socialRequest.reload(force)
        buzzRequest.reload(force)
        eventsRequest.reload(force)
        callsRequest.reload(force)
        averagesRequest.reload(force)
        financialsRequest.reload(force)
        valuationRequest.reload(force)
        extendedRequest.reload(force)
        analystsRequest.reload(force)
        comparisonRequests.forEach(request => request.reload(force))
    }
    property DataRequest newsRequest: DataRequest { arguments: root.stockResearchActive && !root.socialOpen ? ["news", StockStore.selected] : [] }
    property DataRequest socialRequest: DataRequest { arguments: root.stockResearchActive && root.socialOpen ? ["social", StockStore.selected] : [] }
    property DataRequest buzzRequest: DataRequest { arguments: root.stockResearchActive && root.socialOpen ? ["buzz", "ALL"] : [] }
    property Timer socialPoll: Timer { interval: 300000; running: root.stockResearchActive && root.socialOpen; repeat: true; onTriggered: root.socialRequest.reload(false) }
    property Timer buzzPoll: Timer { interval: 1800000; running: root.stockResearchActive && root.socialOpen; repeat: true; onTriggered: root.buzzRequest.reload(false) }
    property DataRequest financialsRequest: DataRequest {
        arguments: root.stockResearchActive && root.financialsOpen ? ["financials", StockStore.selected, root.financialFrequency] : []
    }
    property DataRequest valuationRequest: DataRequest { arguments: root.stockResearchActive ? ["valuation", StockStore.selected] : [] }
    property DataRequest analystsRequest: DataRequest { arguments: root.stockResearchActive && root.analystsOpen ? ["analysts", StockStore.selected] : [] }
    property Timer analystsPoll: Timer { interval: 3600000; running: root.stockResearchActive && root.analystsOpen; repeat: true; onTriggered: root.analystsRequest.reload(false) }
    property DataRequest extendedRequest: DataRequest { arguments: root.stockResearchActive ? ["extended", StockStore.selected] : [] }
    property Timer extendedPoll: Timer { interval: 60000; running: root.stockResearchActive; repeat: true; onTriggered: root.extendedRequest.reload(false) }
    property DataRequest eventsRequest: DataRequest { arguments: root.stockResearchActive ? ["events", StockStore.selected] : [] }
    property DataRequest callsRequest: DataRequest { arguments: root.stockResearchActive && root.earningsCallsOpen ? ["calls", StockStore.selected] : [] }
    property DataRequest averagesRequest: DataRequest { arguments: root.stockResearchActive && root.averagesAvailable && root.averageWindows.length ? ["averages", StockStore.selected] : [] }
    property DataRequest compareOne: DataRequest { arguments: root.comparisonArguments(0) }
    property DataRequest compareTwo: DataRequest { arguments: root.comparisonArguments(1) }
    property DataRequest compareThree: DataRequest { arguments: root.comparisonArguments(2) }
    property DataRequest compareFour: DataRequest { arguments: root.comparisonArguments(3) }
    property Connections selection: Connections {
        target: StockStore
        function onSelectedChanged() { root.removeComparison(StockStore.selected) }
    }
    property Timer newsPoll: Timer { interval: 600000; running: root.stockResearchActive && !root.socialOpen; repeat: true; onTriggered: root.newsRequest.reload(false) }
    property Timer chartPoll: Timer {
        interval: 300000; running: root.active; repeat: true
        onTriggered: { root.comparisonRequests.forEach(request => request.reload(false)); root.averagesRequest.reload(false); root.eventsRequest.reload(false) }
    }
}
