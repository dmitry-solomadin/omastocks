const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const {load, plain, serverPool, serverLane} = require("./qml_harness.cjs")

// The real StockStore handlers with fake helper processes.
const Clock = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../qml/market/MarketClock.js"), "utf8"), Clock)
const file = path.join(__dirname, "../qml/stores/StockStore.qml")
const regular = {symbol: "AAPL", price: 100, marketState: "REGULAR"}
function store(state) {
    const emitted = []
    const context = load(file, {
        state: Object.assign({
            running: true, windowOpen: true, windowMinimized: false, view: "stock", selected: "AAPL", period: "1D",
            entries: [regular], favoriteEntries: [], previewQuotes: {}, marketQuotes: {}, chart: {}, queue: [], active: null, error: "",
            exited: true, collected: true, captured: "", quoteTransportFailures: 0, activeWatchlist: "default",
            marketStarted: true, marketRetries: 0, nextPollAt: 0
        }, serverLane.state, state),
        bindings: ["quote", "tracked", "chartShown", "chartLive", "extendedLive", "quotesLive", "pollInterval", "chartLoading", "visibleChart"],
        functions: ["staleNote", "scheduleQuoteRetry", "finish", "select", "show", "range", "refresh"].concat(serverLane.functions),
        handlers: ["chartShown", "chartLive", "extendedLive", "windowOpen"],
        globals: {
            ...serverLane.globals(), Date, Clock, watchdog: {stop() {}}, quoteRetry: {stop() {}, restart() {}},
            marketQuotesRequest: {reload() {}}, marketRetryTimer: {stop() {}},
            MarketStore: {refresh() {}, wantExtended: false, extendedRequest: {reload() {}}},
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
    context.pool = serverPool(context)
    context.servers = context.pool.helpers
    return context
}
const charts = context => context.sent.filter(args => args[0] === "chart")
const interval = context => context.pollInterval
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

// Step 3: one poll, every minute while a 1D chart is live. Only the regular
// session moves the chart; pre-market and after hours do not.
const inState = state => ({entries: [Object.assign({}, regular, {marketState: state})]})
context = store({})
assert.equal(context.chartLive, true)
assert.equal(interval(context), 60000)
for (const [change, why] of [[{windowMinimized: true}, "minimized"], [{windowOpen: false}, "window closed"],
    ...["PRE", "POST", "CLOSED", "PREPRE", "POSTPOST"].map(state => [inState(state), state])]) {
    context = store(change)
    assert.equal(interval(context), 300000, why)
}
// Prices move all session: quotes every minute on any range or view.
for (const [change, why] of [[{period: "3M"}, "other ranges"], [{view: "market"}, "Market view"],
    [{entries: [], selected: "BMW.DE", marketQuotes: {"^SPX": {marketState: "REGULAR"}}}, "the US market trading"]]) {
    context = store(change)
    assert.equal(interval(context), 60000, why)
}
for (const state of ["REGULAR", undefined]) {
    context = store(inState(state))
    assert.equal(interval(context), 60000, `${state} is the regular session`)
}

// The poll runs on a wall-clock deadline, whatever pace the QML timer keeps.
const tick = context => context.evaluate("(() => {" + context.source.match(/property Timer poll: Timer \{[^]*?onTriggered: \{([^]*?)\n        \}/)[1] + "})()")
context = store({})
context.nextPollAt = Date.now() + 5000
tick(context)
assert.deepEqual(context.sent, [], "Not before its deadline")
context.nextPollAt = Date.now() - 1
tick(context)
assert.deepEqual(context.sent[0], ["refresh"])
assert.ok(context.nextPollAt > Date.now() + 59000, "The next deadline is a full interval on")

// A scheduled refresh asks for the chart only while it is live.
context = store({})
context.refresh(false)
assert.deepEqual(context.sent, [["refresh"], ["chart", "AAPL", "1D"]])
for (const change of [inState("POST"), inState("PRE"), inState("CLOSED"), {windowMinimized: true}, {view: "watchlist"}, {windowOpen: false}]) {
    context = store(change)
    context.refresh(false)
    assert.deepEqual(context.sent, [["refresh"]], JSON.stringify(change))
}
context = store({selected: "TSLA", previewQuotes: {TSLA: {symbol: "TSLA", marketState: "REGULAR"}}})
context.refresh(false)
assert.deepEqual(context.sent, [["refresh"], ["chart", "TSLA", "1D"], ["quote", "TSLA"]], "Its chart and quote together, on two helpers")

// Other ranges' charts refresh every five minutes; their quotes every minute.
context = store({period: "3M", chart: {symbol: "AAPL", range: "3M", points: [[1, 1]], fetched: Date.now() / 1000 - 60}})
context.refresh(false)
assert.deepEqual(context.sent, [["refresh"]])
context.chart = Object.assign({}, context.chart, {fetched: Date.now() / 1000 - 300})
context.refresh(false)
assert.deepEqual(charts(context), [["chart", "AAPL", "3M"]])

// Going live asks once; a second trigger while that chart runs or waits does not.
context = store({windowMinimized: true})
context.windowMinimized = false
assert.deepEqual(charts(context), [["chart", "AAPL", "1D"]])
context.refresh(false)
context.windowMinimized = true
context.windowMinimized = false
context.view = "market"
context.view = "stock"
assert.equal(charts(context).length, 1, "Already running")
context.range("1W")
context.range("1M")
assert.deepEqual(charts(context).slice(1), [["chart", "AAPL", "1W"], ["chart", "AAPL", "1M"]], "Each on a free helper")
context.requestChart(false)
assert.equal(charts(context).length, 3, "1M is already running")
context.range("1Y")
assert.deepEqual(plain(context.serverWaiting), [["chart", "AAPL", "1Y"]], "With every helper busy, it waits")
context.pool.answer()
assert.deepEqual(charts(context).slice(-1), [["chart", "AAPL", "1Y"]], "Then runs on the one freed")
while (context.pool.running("chart")) context.pool.answer()
context.refresh(false)
assert.equal(charts(context).length, 5, "The next poll asks again")

// The quote poll reporting the regular session resumes the chart; its end
// fetches the chart once more, for the closing price, then nothing after hours.
context = store(inState("PRE"))
context.refresh(false)
assert.equal(charts(context).length, 0)
context.entries = inState("REGULAR").entries
assert.equal(charts(context).length, 1)
context.pool.answer()
context.entries = inState("POST").entries
assert.equal(charts(context).length, 2, "The closing price")
context.pool.answer()
for (let tick = 0; tick < 3; tick++) context.refresh(false)
assert.equal(charts(context).length, 2)

// After hours with the Extended chart shown: only it refreshes, every minute.
const reloads = []
context = store(inState("POST"))
context.MarketStore = {refresh() {}, wantExtended: true, extendedRequest: {reload: force => reloads.push(force)}}
assert.equal(context.extendedLive, true)
assert.equal(interval(context), 60000)
for (let tick = 0; tick < 3; tick++) context.refresh(false)
assert.deepEqual(plain(reloads), [false, false, false])
assert.equal(charts(context).length, 0, "Not the regular chart, which does not move")

// A closed market still shows the chart once when it appears: the one on
// screen may be from before the window closed.
context = store({windowOpen: false, entries: [Object.assign({}, regular, {marketState: "CLOSED"})]})
context.openRequested()
assert.deepEqual(charts(context), [["chart", "AAPL", "1D"]])
context.pool.answer()
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
assert.deepEqual(context.sent.filter(args => args[0] === "quote"), [["quote", "NVDA"]], "One quote, with the chart")

// A stock outside the list: its chart and quote download together.
context = store({})
context.select("TSLA")
assert.deepEqual(context.sent, [["chart", "TSLA", "1D"], ["quote", "TSLA"]])
assert.equal(context.pool.alive, 2)

// A manual refresh always asks again, even with the same chart running.
context = store({})
context.requestChart(false)
context.refresh(true)
assert.equal(charts(context).length, 2)
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

// The helpers start with the requests that need them. One request of each
// kind runs at a time, on the first free helper.
const shownChart = {symbol: "AAPL", range: "1D", points: [[1, 100], [2, 101]], fetched: 1790600000}
context = store({})
context.requestChart(false)
assert.equal(context.pool.starts, 1)
assert.equal(context.chartLoading, true)
context.pool.answer("chart", shownChart)
assert.deepEqual(plain(context.chart.points), shownChart.points)
assert.equal(context.chartLoading, false)
context.range("1W")
context.pool.answer()
assert.equal(context.pool.starts, 1, "The same helper, already running, takes the next")
context.range("1M")
context.requestQuote("TSLA")
context.requestSearch("ts")
assert.equal(context.pool.alive, 3, "Three requests at once")
context.range("1Y")
assert.deepEqual(plain(context.serverWaiting), [["chart", "AAPL", "1Y"]], "A fourth waits for a free helper")
context.pool.answer("quote")
assert.deepEqual(charts(context).slice(-1), [["chart", "AAPL", "1Y"]], "Whichever frees first")

// If a helper dies, its request goes to a one-shot helper; its next request
// starts it again.
context = store({})
context.requestChart(false)
context.pool.die("chart")
assert.deepEqual(plain(context.queue), [["chart", "AAPL", "1D"]], "Through the one-shot helper")
assert.equal(context.chartLoading, true)
assert.equal(context.serverFailures, 1)
context.queue = []
context.range("1W")
assert.equal(context.pool.starts, 2)
context.pool.answer()
assert.equal(context.serverFailures, 0, "A reply resets the count")

// If one hangs, it is stopped and the chart fails like any refresh.
context = store({chart: shownChart})
context.requestChart(false)
context.pool.hang("chart")
assert.deepEqual(plain(context.chart.points), shownChart.points)
assert.match(context.chart.error, /took too long/)
assert.equal(context.chart.stale, true)
assert.equal(context.queue.length, 0, "No one-shot retry of a hung download")

// After three failures in a row they rest for ten minutes; one-shot helpers
// do their work meanwhile.
context = store({})
for (const range of ["1W", "1M", "3M"]) {
    context.range(range)
    context.pool.die("chart")
    context.queue = []
}
assert.ok(context.serverRestUntil > Date.now() + 590000)
const restingStarts = context.pool.starts
context.range("1Y")
assert.deepEqual(plain(context.queue), [["chart", "AAPL", "1Y"]])
assert.equal(context.pool.starts, restingStarts)
context.queue = []
context.serverRestUntil = Date.now() - 1
context.range("2Y")
assert.equal(context.pool.starts, restingStarts + 1, "Back once the rest is over")

// Closing the window stops them, without a one-shot retry of what they ran.
context = store({})
context.requestChart(false)
context.requestQuote("TSLA")
context.range("1W")
context.requestSearch("x")
context.windowOpen = false
assert.equal(context.pool.alive, 0)
assert.ok(context.servers.every(helper => helper.free))
assert.deepEqual(plain(context.serverWaiting), [])
assert.equal(context.queue.length, 0)
assert.equal(context.serverFailures, 0)

// Pausing on a range button loads that range ahead of the click.
const dwell = context => {
    const trigger = context.source.match(/prefetchTimer: Timer \{ interval: \d+; onTriggered: ([^}]+) \}/)[1]
    if (context.prefetchTimer.running) { context.prefetchTimer.running = false; context.evaluate(trigger) }
}
const year = () => ({symbol: "AAPL", range: "1Y", points: [[1, 80], [2, 90]], fetched: Date.now() / 1000})
context = store({chart: shownChart})
context.hoverRange("1Y", true)
dwell(context)
assert.deepEqual(charts(context), [["chart", "AAPL", "1Y"]])
assert.deepEqual(plain(context.emitted), [], "Not announced: the lines that follow the chart are for the range shown")
context.pool.answer("chart", year())
assert.equal(context.chart, shownChart, "The chart on screen stays until the click")
context.range("1Y")
assert.deepEqual(plain(context.chart.points), [[1, 80], [2, 90]], "Shown at once")
assert.equal(charts(context).length, 1, "Without another request")
assert.equal(context.prefetched, null)
// A click while it downloads takes over that request.
context = store({chart: shownChart})
context.hoverRange("5Y", true)
dwell(context)
context.range("5Y")
assert.equal(charts(context).length, 1)
context.pool.answer("chart", {symbol: "AAPL", range: "5Y", points: [[1, 1], [2, 2]], fetched: Date.now() / 1000})
assert.equal(context.chart.range, "5Y")
// Over ten seconds old, it is fetched again.
context = store({chart: shownChart})
context.hoverRange("1Y", true)
dwell(context)
context.pool.answer("chart", Object.assign(year(), {fetched: Date.now() / 1000 - 11}))
context.range("1Y")
assert.equal(charts(context).length, 2)
assert.equal(context.chart, shownChart, "Until the new one arrives")
// Nothing for the range shown, while a chart runs, or with the chart hidden.
for (const [state, value, why] of [[{}, "1D", "the range shown"], [{windowMinimized: true}, "1Y", "minimized"], [{view: "market"}, "1Y", "Market view"]]) {
    context = store(state)
    context.hoverRange(value, true)
    dwell(context)
    assert.equal(charts(context).length, 0, why)
}
context = store({})
context.requestChart(true)
context.hoverRange("1Y", true)
dwell(context)
assert.equal(charts(context).length, 2, "Beside a chart running, on a free helper")
context = store({})
context.requestChart(true)
context.requestQuote("TSLA")
context.requestSearch("x")
context.hoverRange("1Y", true)
dwell(context)
assert.equal(charts(context).length, 1, "Not while every helper is busy")
assert.deepEqual(plain(context.serverWaiting), [], "Nor queued ahead of real requests")
// Passing over a button fetches nothing; entering the next before leaving the last keeps it.
context = store({})
context.hoverRange("1W", true)
context.hoverRange("1W", false)
assert.equal(context.prefetchTimer.running, false)
context.hoverRange("1M", true)
context.hoverRange("1W", false)
dwell(context)
assert.deepEqual(charts(context), [["chart", "AAPL", "1M"]])
// Another stock never gets the last one's range.
context = store({entries: [regular, {symbol: "MSFT", marketState: "REGULAR"}]})
context.hoverRange("1Y", true)
dwell(context)
context.pool.answer("chart", year())
context.select("MSFT")
context.pool.answer("chart", {symbol: "MSFT", range: "1D", points: [[1, 1], [2, 2]], fetched: Date.now() / 1000})
context.range("1Y")
assert.deepEqual(charts(context).slice(-1), [["chart", "MSFT", "1Y"]])

// Search goes through the same helper once typing pauses for 250 ms.
const searchDelay = Number(context.source.match(/property Timer searchTimer: Timer \{ interval: (\d+);/)[1])
assert.equal(searchDelay, 250)
const typed = (context, query) => {
    context.search(query)
    const trigger = context.source.match(/property Timer searchTimer: Timer \{ interval: \d+; onTriggered: ([^}]+) \}/)[1]
    if (context.searchTimer.running) { context.searchTimer.running = false; context.evaluate(trigger) }
}
context = store({})
typed(context, "nvid")
assert.deepEqual(context.sent, [["search", "nvid"]], "Not through the watchlist queue")
context.pool.answer("search", {query: "nvid", results: [{symbol: "NVDA"}], error: ""})
assert.deepEqual(plain(context.results), [{symbol: "NVDA"}])
assert.equal(context.completedQuery, "nvid")
// Then the results' prices, in one request, kept with other untracked quotes.
assert.deepEqual(context.sent.slice(-1), [["quotes", "NVDA"]])
context.pool.answer("quotes", {rows: [{symbol: "NVDA", price: 180, fetched: Date.now() / 1000}]})
assert.equal(context.previewQuotes.NVDA.price, 180)
// Not for watchlist stocks, nor prices from the last minute.
context = store({})
context.entries = [{symbol: "AAPL"}]
context.previewQuotes = {NVDA: {symbol: "NVDA", fetched: Date.now() / 1000 - 10}, AMD: {symbol: "AMD", fetched: Date.now() / 1000 - 90}}
typed(context, "a")
context.pool.answer("search", {query: "a", results: [{symbol: "AAPL"}, {symbol: "NVDA"}, {symbol: "AMD"}, {symbol: "ARM"}], error: ""})
assert.deepEqual(context.sent.slice(-1), [["quotes", "AMD", "ARM"]])
// A search price never replaces a newer quote of the stock.
context.receiveQuote({symbol: "NVDA", price: 1, fetched: Date.now() / 1000 - 20})
assert.equal(context.previewQuotes.NVDA.price, undefined)
// While the helpers rest, search results go without prices.
context = store({})
context.request(["quotes", "X"])
assert.deepEqual(plain(context.queue), [])
// A search runs beside a chart and other searches; a reply for an older query
// never replaces the results.
context = store({})
context.requestChart(false)
typed(context, "a")
assert.deepEqual(context.sent, [["chart", "AAPL", "1D"], ["search", "a"]], "Beside the chart")
typed(context, "ap")
typed(context, "app")
assert.deepEqual(plain(context.serverWaiting), [["search", "app"]], "Waits for a free helper")
context.pool.answer("search", {query: "a", results: [{symbol: "A"}], error: ""})
assert.deepEqual(plain(context.results), [], "The query has moved on")
assert.deepEqual(context.sent.slice(-1), [["search", "app"]])
context.pool.answer("search", {query: "ap", results: [{symbol: "AP"}], error: ""})
assert.deepEqual(plain(context.results), [])
context.pool.answer("search", {query: "app", results: [{symbol: "APP"}], error: ""})
assert.deepEqual(plain(context.results), [{symbol: "APP"}])
// Clearing the box ignores a late reply.
context = store({})
typed(context, "x")
context.search("")
context.pool.answer("search", {query: "x", results: [{symbol: "X"}], error: ""})
assert.deepEqual(plain(context.results), [])
// If its helper dies, the search goes to a one-shot helper; if it hangs, it fails.
context = store({})
typed(context, "msft")
context.pool.die("search")
assert.deepEqual(plain(context.queue), [["search", "msft"]])
context.queue = []
typed(context, "tsla")
context.pool.hang("search")
assert.match(context.searchError, /took too long/)
assert.equal(context.completedQuery, "tsla")

// A stock outside the watchlist: its header quote downloads beside its chart.
context = store({})
context.select("TSLA")
assert.deepEqual(context.sent, [["chart", "TSLA", "1D"], ["quote", "TSLA"]])
context.pool.answer("quote", {quote: {symbol: "TSLA", price: 250, marketState: "CLOSED"}})
assert.equal(context.quote.price, 250, "The header shows it")
assert.equal(context.chartLive, false, "Its market state decides the chart's refreshes")
context.pool.answer("chart")
assert.equal(charts(context).length, 1, "The chart already downloading is the closing one")
context.requestQuote("TSLA")
context.requestQuote("TSLA")
assert.deepEqual(context.sent.filter(args => args[0] === "quote"), [["quote", "TSLA"], ["quote", "TSLA"]], "One more, not two")
context.pool.answer("quote", {error: "Watchlist is locked"})
assert.equal(context.error, "Watchlist is locked")
// A dead helper's quote goes to a one-shot helper; a hung one is reported.
context = store({})
context.requestQuote("MSFT")
context.pool.die("quote")
assert.deepEqual(plain(context.queue), [["quote", "MSFT"]])
context.queue = []
context.requestQuote("AMZN")
context.pool.hang("quote")
assert.match(context.error, /quote took too long/)

console.log("PASS: failed charts keep only the one on screen, marked stale; one poll refreshes quotes and the live chart")
