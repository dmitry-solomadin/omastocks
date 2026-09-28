const assert = require("node:assert/strict")
const path = require("node:path")
const {load, plain} = require("./qml_harness.cjs")

// DataRequest.finish() with a fake helper: keepOnError keeps a line on screen
// after a failed refresh, marked stale, but never another symbol's line.
function request(state) {
    return load(path.join(__dirname, "../qml/data/DataRequest.qml"), {
        state: Object.assign({keepOnError: true, data: {}, revision: 1, activeRevision: 1, exited: true, collected: true, captured: ""}, state),
        functions: ["finish"],
        globals: {watchdog: {stop() {}}, Qt: {callLater() {}}, pump() {}}
    })
}
function reply(context, data) {
    context.activeRevision = context.revision
    context.captured = typeof data === "string" ? data : JSON.stringify(data)
    context.finish()
    return context.data
}
const line = {symbol: "NVDA", points: [[1, 100], [2, 101]], fetched: 1790600000, stale: false, error: ""}
const failure = {symbol: "NVDA", error: "offline", stale: true, points: []}
let data = reply(request({data: line}), failure)
assert.deepEqual(plain(data.points), line.points)
assert.equal(data.stale, true)
assert.equal(data.error, "offline")
assert.equal(data.fetched, line.fetched)
for (const crashed of [{error: "Research helper failed"}, "not json"]) {
    data = reply(request({data: line}), crashed)
    assert.deepEqual(plain(data.points), line.points, "A crashed helper's reply was for this symbol")
    assert.equal(data.stale, true)
}
data = reply(request({data: line}), Object.assign({}, failure, {symbol: "MSFT"}))
assert.deepEqual(plain(data.points), [], "Another symbol's line is never kept")
data = reply(request({data: line, keepOnError: false}), failure)
assert.deepEqual(plain(data.points), [], "Other requests show the failure as before")
data = reply(request({data: {}}), failure)
assert.equal(data.error, "offline", "Nothing on screen to keep")
let context = request({data: line})
reply(context, failure)
data = reply(context, Object.assign({}, line, {points: [[1, 100], [3, 103]], fetched: 1790600060}))
assert.equal(data.stale, false, "The next success clears the stale mark")

// A chart request reloads every active comparison once, in step with the chart.
const StockStore = {running: true, windowOpen: true, view: "stock", selected: "AAPL", period: "1D"}
context = load(path.join(__dirname, "../qml/stores/MarketStore.qml"), {
    state: {compareMode: true, compareSlots: ["NVDA", "MSFT", "", ""]},
    bindings: ["active"],
    functions: ["comparisonArguments"],
    globals: {StockStore}
})
context.comparisonRequests = [0, 1, 2, 3].map(index => ({
    reloads: [],
    get arguments() { return context.comparisonArguments(index) },
    // DataRequest.reload() skips a request without arguments.
    reload(force) { if (this.arguments.length) this.reloads.push(force) }
}))
// Extended hours off: its request has no arguments, so reloading it is a no-op.
context.extendedRequest = {arguments: [], reloads: [], reload(force) { if (this.arguments.length) this.reloads.push(force) }}
context.evaluate(context.source.match(/^ +(function onChartRequested\(force\) \{.*\})$/m)[1])
context.onChartRequested(false)
assert.deepEqual(context.comparisonRequests.map(row => row.reloads.length), [1, 1, 0, 0])
context.onChartRequested(true)
assert.deepEqual(plain(context.comparisonRequests[0].reloads), [false, true], "A manual refresh is passed on")
context.compareMode = false
context.onChartRequested(false)
assert.deepEqual(context.comparisonRequests.map(row => row.reloads.length), [2, 2, 0, 0], "No comparisons outside compare mode")
assert.deepEqual(context.extendedRequest.reloads, [])

console.log("PASS: comparison lines reload with the chart and keep their line, marked stale, after a failure")
