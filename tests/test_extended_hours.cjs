const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const {load, plain} = require("./qml_harness.cjs")

const qml = name => path.join(__dirname, "../qml", name)

// The header's pre-market or after-hours price comes from the quote.
const quotes = load(qml("stores/StockStore.qml"), {functions: ["extendedQuote"]})
const extendedQuote = quote => plain(quotes.extendedQuote(quote))
const post = {postPrice: 101, postChange: 1, postPercent: 1, postUpdated: 1100}
const pre = {prePrice: 99, preChange: -1, prePercent: -1, preUpdated: 1200}
assert.deepEqual(extendedQuote(Object.assign({marketState: "PRE", updated: 1000}, pre)),
    {label: "Pre-market", price: 99, change: -1, percent: -1, updated: 1200})
assert.equal(extendedQuote(Object.assign({marketState: "PREPRE", updated: 1000}, pre)).label, "Pre-market")
assert.equal(extendedQuote(Object.assign({marketState: "PRE", updated: 1000}, post, {postUpdated: 900})), null,
    "Before pre-market trades, yesterday's after-hours price is not shown")
assert.deepEqual(extendedQuote(Object.assign({marketState: "POST", updated: 1000}, post)),
    {label: "After hours", price: 101, change: 1, percent: 1, updated: 1100})
assert.equal(extendedQuote(Object.assign({marketState: "CLOSED", updated: 1000}, post)).label, "After hours",
    "Friday's after-hours price over the weekend")
assert.equal(extendedQuote(Object.assign({marketState: "POST", updated: 1200}, post)), null, "Not after the last regular trade")
assert.equal(extendedQuote(Object.assign({marketState: "REGULAR", updated: 1000}, post, pre)), null)
for (const quote of [{}, {marketState: "POST"}, {marketState: "POST", updated: 1000, postPrice: null, postUpdated: 1100},
    {marketState: "POST", postPrice: 101, postUpdated: 1100}]) {
    assert.equal(extendedQuote(quote), null, JSON.stringify(quote))
}
assert.equal(extendedQuote({marketState: "POST", updated: 1000, postPrice: 101, postUpdated: 1100}).change, null)

// StockStore, MarketStore and the Extended button, wired as in the app. Fake
// DataRequests count loads: new arguments drop their data and load, as
// DataRequest.onRequestKeyChanged does, and reloads in the same moment share
// one run, as its debounce does.
const windowSource = fs.readFileSync(qml("StocksWindow.qml"), "utf8")
const optionsSource = fs.readFileSync(qml("charts/ChartOptions.qml"), "utf8")
function nested(source, name) {
    return source.match(new RegExp(`^ {8}(function ${name}\\(.*\\) \\{(?:.*\\}$|[^]*?^ {8}\\}$))`, "m"))[1]
}
function app({entries, marketState = "REGULAR", showExtended = false}) {
    const stock = load(qml("stores/StockStore.qml"), {
        state: {running: true, windowOpen: true, windowMinimized: false, view: "stock", selected: "AAPL", period: "1D",
            entries: entries || [{symbol: "AAPL", marketState}], previewQuotes: {}, chart: {}, queue: [], active: null, activeWatchlist: "default"},
        bindings: ["quote", "tracked", "marketOpen", "chartShown", "chartLive", "visibleChart", "watchlistQuotes"],
        functions: ["select", "range", "refresh", "requestChart", "request"],
        handlers: ["chartShown", "chartLive"],
        globals: {pump() {}, MarketStore: {refresh() {}}, chartRequested: force => market.onChartRequested(force)}
    })
    const market = load(qml("stores/MarketStore.qml"), {
        state: {compareMode: false, compareSlots: ["", "", "", ""], compareValidation: "", showExtended, noExtended: {}, extendedClicked: ""},
        bindings: ["active", "stockResearchActive", "wantExtended", "extended", "extendedChart"],
        functions: ["extendedUnavailable", "comparisonArguments", "removeComparison"],
        globals: {StockStore: stock}
    })
    function request(code) {
        const fake = {loads: 0, data: {}, busy: false, key: "[]", pending: false,
            get arguments() { return market.evaluate(code) },
            reload() { if (this.arguments.length) this.pending = true },
            sync() {
                const key = JSON.stringify(this.arguments)
                if (key !== this.key) {
                    this.key = key
                    this.data = {}
                    this.reload()
                }
                if (this.pending) this.loads++
                this.pending = false
            }}
        fake.sync()
        return fake
    }
    market.extendedRequest = request(market.source.match(/extendedRequest: DataRequest \{ arguments: ([^;]+);/)[1])
    market.comparisonRequests = [0, 1, 2, 3].map(index => request(`root.comparisonArguments(${index})`))
    for (const name of ["onSelectedChanged", "onPeriodChanged", "onChartRequested", "onDataChanged"]) market.evaluate(nested(market.source, name))
    // The Extended button's enabled, selected and hint bindings and its click.
    const toggle = optionsSource.slice(optionsSource.indexOf('objectName: "extendedToggle"'))
    const binding = name => {
        const lines = toggle.split("\n")
        const index = lines.findIndex(line => line.startsWith(`        ${name}: `))
        let code = lines[index].slice(10 + name.length)
        for (let line = index + 1; /^ {12}/.test(lines[line]); line++) code += "\n" + lines[line]
        return code
    }
    const button = vm.createContext({MarketStore: market, StockStore: stock})
    for (const name of ["enabled", "selected", "hint"]) {
        const code = binding(name)
        Object.defineProperty(button, name, {get: () => vm.runInContext(code, button)})
    }
    const click = toggle.match(/onClicked: \{([^]*?)\n {8}\}/)[1]
    const settle = () => [market.extendedRequest].concat(market.comparisonRequests).forEach(fake => fake.sync())
    const series = windowSource.match(/readonly property var series: (.+)/)[1]
    return {
        stock, market, button, settle,
        extended: market.extendedRequest,
        series: () => vm.runInContext(series, vm.createContext({MarketStore: market, StockStore: stock})),
        click() { vm.runInContext(click, button); settle() },
        select(ticker) { stock.select(ticker); market.onSelectedChanged(); settle() },
        // A minute of the shared poll; the chart request then completes.
        tick(times = 1) {
            for (let i = 0; i < times; i++) { stock.refresh(false); stock.active = null; stock.queue = []; settle() }
        },
        reply(data) { market.extendedRequest.data = data; market.onDataChanged(); settle() }
    }
}

// Arguments only for the Extended chart on 1D, outside compare mode, for a
// stock not ruled out.
let world = app({})
assert.deepEqual(plain(world.extended.arguments), [])
world.market.showExtended = true
assert.deepEqual(plain(world.extended.arguments), ["extended", "AAPL"])
world.stock.period = "1W"
assert.deepEqual(plain(world.extended.arguments), [])
world.stock.period = "1D"
world.market.compareMode = true
assert.deepEqual(plain(world.extended.arguments), [])
world.market.compareMode = false
world.market.noExtended = {AAPL: true}
assert.deepEqual(plain(world.extended.arguments), [])
world = app({showExtended: true, entries: [{symbol: "AAPL", marketState: "REGULAR", extendedData: false}]})
assert.deepEqual(plain(world.extended.arguments), [], "Ruled out by the quote")

// Extended off: a live 1D chart refreshing every minute fetches no extended hours.
world = app({})
world.tick(60)
assert.equal(world.extended.loads, 0)
// Extended on: each chart refresh reloads it once; none while the market is closed.
world = app({showExtended: true})
assert.equal(world.extended.loads, 1)
world.tick(3)
assert.equal(world.extended.loads, 4)
world = app({showExtended: true, marketState: "CLOSED"})
world.tick(3)
assert.equal(world.extended.loads, 1, "Loaded once when shown, then no periodic reloads")

// The caveat: Extended clicked on a stock not yet known to lack the data.
world = app({})
const regular = {symbol: "AAPL", range: "1D", points: [[1, 100], [2, 101]]}
world.stock.chart = regular
assert.equal(world.button.enabled, true)
world.click()
assert.equal(world.button.selected, true, "On at once")
assert.equal(world.extended.loads, 1, "One extended request")
assert.equal(world.series(), world.stock.visibleChart, "The regular chart stays while it loads")
world.reply({symbol: "AAPL", supported: false, points: [], sessions: [], quote: null})
assert.equal(world.market.noExtended.AAPL, true)
assert.equal(world.button.enabled, false)
assert.equal(world.button.selected, false)
assert.deepEqual(plain(world.extended.arguments), [])
assert.equal(world.button.hint, "No extended-hours data for AAPL")
assert.equal(world.series(), world.stock.visibleChart, "The regular chart never changes")
world.tick(5)
assert.equal(world.extended.loads, 1, "No more requests for that stock")
assert.equal(world.market.showExtended, true, "Still the user's choice for other stocks")

// Switching to a stock with extended data still shows the extended chart.
world.stock.entries = [{symbol: "AAPL", marketState: "REGULAR"}, {symbol: "MSFT", marketState: "REGULAR", extendedData: true},
    {symbol: "BMW.DE", marketState: "REGULAR"}]
world.select("MSFT")
assert.equal(world.extended.loads, 2)
assert.equal(world.button.selected, true)
const sessions = {symbol: "MSFT", supported: true, points: [[1, 400], [2, 401]], sessions: [{kind: "pre"}]}
world.reply(sessions)
assert.equal(world.market.extendedChart, true)
assert.equal(world.series(), world.market.extended)
assert.doesNotMatch(world.button.hint, /No extended-hours data/)

// Extended already on when switching to a stock without the data: no message.
world.select("BMW.DE")
world.reply({symbol: "BMW.DE", supported: false, points: []})
assert.equal(world.button.enabled, false)
assert.doesNotMatch(world.button.hint, /No extended-hours data/)
// Back on the stock whose click found nothing: known in advance, no message.
world.select("AAPL")
assert.equal(world.button.enabled, false)
assert.doesNotMatch(world.button.hint, /No extended-hours data/)
// Ruled out by the quote: greyed out from the start, without a message.
world = app({entries: [{symbol: "AAPL", marketState: "REGULAR", extendedData: false}]})
assert.equal(world.button.enabled, false)
assert.doesNotMatch(world.button.hint, /No extended-hours data/)
assert.equal(world.extended.loads, 0)

console.log("PASS: extended hours come from the quote, and the Extended chart is fetched only while shown")
