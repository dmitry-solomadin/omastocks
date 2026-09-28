const assert = require("node:assert/strict")
const path = require("node:path")
const {load, plain} = require("./qml_harness.cjs")

// The real StockStore handlers with a fake helper process and clock.
const file = path.join(__dirname, "../qml/stores/StockStore.qml")
const regular = {symbol: "AAPL", price: 100, marketState: "REGULAR"}
function store(state) {
    const emitted = []
    const context = load(file, {
        state: Object.assign({
            running: true, windowOpen: true, windowMinimized: false, view: "stock", selected: "AAPL", period: "1D",
            entries: [regular], previewQuotes: {}, chart: {}, queue: [], active: null, error: "",
            exited: true, collected: true, captured: "", quoteTransportFailures: 0, activeWatchlist: "default"
        }, state),
        bindings: ["quote", "tracked", "marketOpen", "chartShown", "chartLive"],
        functions: ["receiveChart", "staleNote", "scheduleQuoteRetry", "finish", "select", "show", "range", "refresh", "requestChart", "request"],
        handlers: ["chartShown", "chartLive"],
        globals: {
            Date, watchdog: {stop() {}}, quoteRetry: {stop() {}, restart() {}}, MarketStore: {refresh() {}},
            Qt: {callLater() {}, formatDateTime: (date, format) => date.toISOString() + " " + format},
            pump() {}, search() {}, stockAdded() {}, emitted,
            chartRequested: force => emitted.push(force)
        }
    })
    // Service.open(): the window appears and the quotes refresh.
    context.evaluate("function openRequested() { windowOpen = true; windowMinimized = false; refresh(false) }")
    const request = context.request
    context.sent = []
    context.request = args => { context.sent.push(plain(args)); request(args) }
    return context
}
const charts = context => context.sent.filter(args => args[0] === "chart")
const interval = context => context.evaluate(context.source.match(/property Timer poll: Timer \{ interval: ([^;]+);/)[1])
function reply(context, args, data) {
    context.active = args
    context.captured = typeof data === "string" ? data : JSON.stringify(data)
    context.finish()
}

// Step 2: charts are never saved, so a failed refresh may only keep the chart
// already on screen, marked stale with its own time.
const shown = {symbol: "AAPL", range: "1D", points: [[1, 100], [2, 101]], fetched: 1790600000, stale: false, error: ""}
let context = store({chart: shown})
reply(context, ["chart", "AAPL", "1D"], {chart: {symbol: "AAPL", range: "1D", points: [], error: "offline", stale: true}})
assert.deepEqual(plain(context.chart.points), shown.points)
assert.equal(context.chart.stale, true)
assert.equal(context.chart.error, "offline")
assert.equal(context.chart.fetched, shown.fetched, "The kept chart keeps its own time")
assert.match(context.staleNote(context.chart), /^As of .* · refresh failed$/)
reply(context, ["chart", "AAPL", "1D"], {chart: Object.assign({}, shown, {points: [[1, 100], [3, 102]], fetched: 1790600060})})
assert.equal(context.chart.stale, false, "The next success clears the stale mark")
assert.deepEqual(plain(context.chart.points), [[1, 100], [3, 102]])
assert.equal(context.staleNote(context.chart), "")
for (const onScreen of [{}, Object.assign({}, shown, {symbol: "MSFT"}), Object.assign({}, shown, {range: "1Y"})]) {
    context = store({chart: onScreen})
    reply(context, ["chart", "AAPL", "1D"], {chart: {symbol: "AAPL", range: "1D", points: [], error: "offline", stale: true}})
    assert.deepEqual(plain(context.chart.points), [], "Never another symbol's or range's line")
    assert.equal(context.chart.error, "offline")
    assert.equal(context.staleNote(context.chart), "")
}
for (const failure of [{error: "Request timed out. Try refreshing again."}, ""]) {
    context = store({chart: shown})
    reply(context, ["chart", "AAPL", "1D"], failure)
    assert.deepEqual(plain(context.chart.points), shown.points, "A crashed or timed-out helper is a failed refresh")
    assert.equal(context.chart.stale, true)
}
context = store({chart: shown, period: "1Y"})
reply(context, ["chart", "AAPL", "1D"], {chart: Object.assign({}, shown, {points: [[9, 9]]})})
assert.equal(context.chart, shown, "A reply for a range no longer selected is ignored")

// Step 3: one poll, every minute while a 1D chart is live.
context = store({})
assert.equal(context.chartLive, true)
assert.equal(interval(context), 60000)
for (const [change, why] of [[{period: "3M"}, "other ranges"], [{windowMinimized: true}, "minimized"],
    [{view: "market"}, "Market view"], [{windowOpen: false}, "window closed"],
    ...["CLOSED", "PREPRE", "POSTPOST"].map(state => [{entries: [Object.assign({}, regular, {marketState: state})]}, state])]) {
    context = store(change)
    assert.equal(interval(context), 300000, why)
}
for (const state of ["PRE", "REGULAR", "POST", undefined]) {
    context = store({entries: [Object.assign({}, regular, {marketState: state})]})
    assert.equal(interval(context), 60000, `${state} counts as open`)
}

// A scheduled refresh asks for the chart only while it is live.
context = store({})
context.refresh(false)
assert.deepEqual(context.sent, [["refresh"], ["chart", "AAPL", "1D"]])
for (const change of [{entries: [Object.assign({}, regular, {marketState: "CLOSED"})]}, {windowMinimized: true}, {view: "watchlist"}, {windowOpen: false}]) {
    context = store(change)
    context.refresh(false)
    assert.deepEqual(context.sent, [["refresh"]], JSON.stringify(change))
}
context = store({selected: "TSLA", previewQuotes: {TSLA: {symbol: "TSLA", marketState: "REGULAR"}}})
context.refresh(false)
assert.deepEqual(context.sent, [["refresh"], ["quote", "TSLA"], ["chart", "TSLA", "1D"]], "A stock outside the list refreshes its quote")

// Going live asks once; a second trigger while that chart runs or waits does not.
context = store({windowMinimized: true})
context.windowMinimized = false
assert.deepEqual(charts(context), [["chart", "AAPL", "1D"]])
context.refresh(false)
context.windowMinimized = true
context.windowMinimized = false
assert.equal(charts(context).length, 1, "Already queued")
context.active = context.queue.find(args => args[0] === "chart")
context.queue = []
context.refresh(false)
context.view = "market"
context.view = "stock"
assert.equal(charts(context).length, 1, "Already running")
context.active = null
context.refresh(false)
assert.equal(charts(context).length, 2, "The next poll asks again")

// The quote poll reporting the market open again resumes the chart.
context = store({entries: [Object.assign({}, regular, {marketState: "CLOSED"})]})
context.refresh(false)
assert.equal(charts(context).length, 0)
context.entries = [Object.assign({}, regular, {marketState: "PRE"})]
assert.equal(charts(context).length, 1)

// A closed market still shows the chart once when it appears: the one on
// screen may be from before the window closed.
context = store({windowOpen: false, entries: [Object.assign({}, regular, {marketState: "CLOSED"})]})
context.openRequested()
assert.deepEqual(charts(context), [["chart", "AAPL", "1D"]])
context.active = null
context.queue = []
for (let tick = 0; tick < 3; tick++) context.refresh(false)
assert.equal(charts(context).length, 1, "No periodic chart refreshes while closed")

// The new stock's chart comes first, from the Market view or a closed window.
context = store({view: "market", entries: [regular, {symbol: "NVDA", marketState: "REGULAR"}]})
context.select("NVDA")
assert.deepEqual(charts(context), [["chart", "NVDA", "1D"]])
context = store({windowOpen: false, entries: [regular, {symbol: "NVDA", marketState: "REGULAR"}]})
context.show("NVDA")
assert.deepEqual(charts(context), [["chart", "NVDA", "1D"]])
context = store({windowOpen: false})
context.show("NVDA")
assert.deepEqual(charts(context), [["chart", "NVDA", "1D"]])
assert.equal(context.queue.filter(args => args[0] === "quote" && args[1] === "NVDA").length, 1, "One quote for a stock outside the list")

// A manual refresh always asks, replacing one already waiting.
context = store({})
context.requestChart(false)
context.refresh(true)
assert.equal(charts(context).length, 2)
assert.equal(context.queue.filter(args => args[0] === "chart").length, 1)
context = store({entries: [Object.assign({}, regular, {marketState: "CLOSED"})]})
context.refresh(true)
assert.equal(charts(context).length, 1, "Even with the market closed")

// A range change asks for that range at once.
context = store({})
context.range("1Y")
assert.deepEqual(charts(context), [["chart", "AAPL", "1Y"]])

// Each chart request is announced once, for the lines that follow the chart.
context = store({})
context.requestChart(false)
context.requestChart(false)
context.refresh(true)
assert.deepEqual(plain(context.emitted), [false, true])

console.log("PASS: failed charts keep only the one on screen, marked stale; one poll refreshes quotes and the live chart")
