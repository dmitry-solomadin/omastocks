const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")

// The real StockStore handlers with a fake helper process: charts are never
// saved, so a failed refresh may only keep the chart already on screen.
const source = fs.readFileSync(path.join(__dirname, "../qml/stores/StockStore.qml"), "utf8")
function store(overrides) {
    const context = vm.createContext(Object.assign({
        Date, running: true, windowOpen: true, view: "stock", selected: "AAPL", period: "1D",
        chart: {}, previewQuotes: {}, entries: [], queue: [], active: null, error: "",
        exited: true, collected: true, captured: "", quoteTransportFailures: 0, activeWatchlist: "default",
        watchdog: {stop() {}}, quoteRetry: {stop() {}, restart() {}},
        Qt: {callLater() {}, formatDateTime: (date, format) => date.toISOString() + " " + format},
        pump() {}, search() {}, select() {}, stockAdded() {}, requests: [],
        request(args) { this.requests.push(Array.from(args)) }
    }, overrides))
    context.root = context
    for (const name of ["receiveChart", "staleNote", "scheduleQuoteRetry", "finish"]) {
        const body = source.match(new RegExp(`^    function ${name}\\([^]*?^    }`, "m"))
        assert.ok(body, `Missing handler ${name}`)
        vm.runInContext(body[0], context)
    }
    return context
}
// Values built inside the context have its own prototypes.
function plain(value) { return JSON.parse(JSON.stringify(value)) }
function reply(context, args, data) {
    context.active = args
    context.captured = typeof data === "string" ? data : JSON.stringify(data)
    context.finish()
}
const shown = {symbol: "AAPL", range: "1D", points: [[1, 100], [2, 101]], fetched: 1790600000, stale: false, error: ""}

// An error for the chart on screen keeps its points and marks them stale.
let context = store({chart: shown})
reply(context, ["chart", "AAPL", "1D"], {chart: {symbol: "AAPL", range: "1D", points: [], error: "offline", stale: true}})
assert.deepEqual(plain(context.chart.points), shown.points)
assert.equal(context.chart.stale, true)
assert.equal(context.chart.error, "offline")
assert.equal(context.chart.fetched, shown.fetched, "The kept chart keeps its own time")
assert.match(context.staleNote(context.chart), /^As of .* · refresh failed$/)

// The next success replaces it and clears the stale mark.
reply(context, ["chart", "AAPL", "1D"], {chart: Object.assign({}, shown, {points: [[1, 100], [3, 102]], fetched: 1790600060})})
assert.equal(context.chart.stale, false)
assert.deepEqual(plain(context.chart.points), [[1, 100], [3, 102]])
assert.equal(context.staleNote(context.chart), "")

// An error for a chart not yet shown gives no points and the error, never
// another symbol's or range's line.
for (const onScreen of [{}, Object.assign({}, shown, {symbol: "MSFT"}), Object.assign({}, shown, {range: "1Y"})]) {
    context = store({chart: onScreen})
    reply(context, ["chart", "AAPL", "1D"], {chart: {symbol: "AAPL", range: "1D", points: [], error: "offline", stale: true}})
    assert.deepEqual(plain(context.chart.points), [])
    assert.equal(context.chart.error, "offline")
    assert.equal(context.staleNote(context.chart), "", "Nothing old to date")
}

// A crashed or timed-out helper is a failed refresh too.
context = store({chart: shown})
reply(context, ["chart", "AAPL", "1D"], {error: "Request timed out. Try refreshing again."})
assert.deepEqual(plain(context.chart.points), shown.points)
assert.equal(context.chart.stale, true)
context = store({chart: shown})
reply(context, ["chart", "AAPL", "1D"], "")
assert.equal(context.chart.stale, true)

// A reply for a stock or range no longer selected is ignored.
context = store({chart: shown, period: "1Y"})
reply(context, ["chart", "AAPL", "1D"], {chart: Object.assign({}, shown, {points: [[9, 9]]})})
assert.equal(context.chart, shown)

console.log("PASS: failed chart refreshes keep only the chart on screen, marked stale, until the next success")
