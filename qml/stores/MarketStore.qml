pragma Singleton
import QtQuick
import qs.Commons
import ".."
import "../charts/ChartMath.js" as ChartMath

QtObject {
    id: root
    readonly property bool active: StockStore.running && StockStore.windowOpen && StockStore.view === "stock" && !!StockStore.selected
    readonly property bool stockResearchActive: active && !compareMode
    readonly property bool companyResearchActive: stockResearchActive && !StockStore.selectedIsNonCompany
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
    property var expandedSections: ({})
    function sectionOpen(section) {
        return (expandedSections[StockStore.selected] || {})[section] === true
    }
    function toggleSection(section) {
        if (!StockStore.selected) return
        const sections = Object.assign({}, expandedSections[StockStore.selected] || {}, {[section]: !sectionOpen(section)})
        expandedSections = Object.assign({}, expandedSections, {[StockStore.selected]: sections})
    }
    readonly property bool earningsCallsOpen: sectionOpen("calls")
    readonly property var earningsCalls: callsRequest.data
    readonly property var averages: averagesRequest.data
    readonly property bool financialsOpen: sectionOpen("financials")
    function toggleFinancials() { toggleSection("financials") }
    property string financialFrequency: "quarterly"
    readonly property var financials: financialsRequest.data
    readonly property var valuation: valuationRequest.data
    readonly property bool analystsOpen: sectionOpen("analysts")
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
        [newsRequest, socialRequest, buzzRequest, eventsRequest, callsRequest,
            averagesRequest, financialsRequest, valuationRequest, extendedRequest, analystsRequest]
            .concat(comparisonRequests).forEach(request => request.reload(force))
    }
    property DataRequest newsRequest: DataRequest { arguments: root.stockResearchActive && !root.socialOpen ? ["news", StockStore.selected] : []; refreshInterval: 600000 }
    property DataRequest socialRequest: DataRequest { arguments: root.stockResearchActive && root.socialOpen ? ["social", StockStore.selected] : []; refreshInterval: 300000 }
    property DataRequest buzzRequest: DataRequest { arguments: root.stockResearchActive && root.socialOpen ? ["buzz", "ALL"] : []; refreshInterval: 1800000 }
    property DataRequest financialsRequest: DataRequest {
        arguments: root.companyResearchActive && root.financialsOpen ? ["financials", StockStore.selected, root.financialFrequency] : []
    }
    property DataRequest valuationRequest: DataRequest { arguments: root.companyResearchActive ? ["valuation", StockStore.selected] : [] }
    property DataRequest analystsRequest: DataRequest { arguments: root.companyResearchActive && root.analystsOpen ? ["analysts", StockStore.selected] : []; refreshInterval: 3600000 }
    property DataRequest extendedRequest: DataRequest { arguments: root.stockResearchActive ? ["extended", StockStore.selected] : []; refreshInterval: 60000 }
    property DataRequest eventsRequest: DataRequest { arguments: root.companyResearchActive ? ["events", StockStore.selected] : []; refreshInterval: 300000 }
    property DataRequest callsRequest: DataRequest { arguments: root.companyResearchActive && root.earningsCallsOpen ? ["calls", StockStore.selected] : [] }
    property DataRequest averagesRequest: DataRequest { arguments: root.stockResearchActive && root.averagesAvailable && root.averageWindows.length ? ["averages", StockStore.selected] : []; refreshInterval: 300000 }
    property DataRequest compareOne: DataRequest { arguments: root.comparisonArguments(0); refreshInterval: 300000 }
    property DataRequest compareTwo: DataRequest { arguments: root.comparisonArguments(1); refreshInterval: 300000 }
    property DataRequest compareThree: DataRequest { arguments: root.comparisonArguments(2); refreshInterval: 300000 }
    property DataRequest compareFour: DataRequest { arguments: root.comparisonArguments(3); refreshInterval: 300000 }
    property Connections selection: Connections {
        target: StockStore
        function onSelectedChanged() { root.removeComparison(StockStore.selected) }
    }
}
