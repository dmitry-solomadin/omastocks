const assert = require("node:assert/strict")
const path = require("node:path")
const {load, plain} = require("./qml_harness.cjs")

const StockStore = {selected: "AMD", period: "1Y", barSettings: {}, quote: {}, extendedQuote: () => null}
const submissions = []
const request = {data: {}, busy: false, submit: (args, force) => submissions.push([plain(args), force])}
const MarketStore = {companyResearchActive: true}
const store = load(path.join(__dirname, "../qml/stores/AnalysisStore.qml"), {
    state: {saved: {}, now: 2000},
    bindings: ["enabled", "active", "preference", "key", "rawReport", "sessionExpired", "report", "error", "working", "stale", "notificationBusy"],
    functions: ["show", "generate", "cancel", "notifyWhenReady", "remember", "contextChanged", "expiredSession"],
    globals: {StockStore, MarketStore, request, notificationRequest: request, openRequested() {}}
})

// Opening during the initial local status read must still enqueue generation.
request.busy = true
store.show()
assert.deepEqual(submissions[0], [["start", "AMD", "claude"], false])
assert.equal(submissions[0][0].includes("1Y"), false, "Chart range is never part of the analysis request")
request.busy = false
request.data = {symbol: "AMD", preference: "claude", pending: true, job: "job1"}
store.generate(true)
assert.equal(submissions.length, 1, "A pending job cannot be duplicated")
store.cancel()
assert.deepEqual(submissions[1], [["cancel", "AMD", "claude", "job1"], false])
store.notifyWhenReady()
assert.deepEqual(submissions[2], [["notify", "AMD", "claude", "job1"], false])

const result = {symbol: "AMD", preference: "claude", summary: "AMD research", generated: 1500, session: {kind: "regular", updated: 1400, percent: 2}}
request.data = result
store.remember(result)
StockStore.selected = "META"
assert.equal(store.report.summary, undefined, "A late AMD reply never renders on META")
store.remember(result)
assert.equal(store.saved["META:claude"], undefined)
StockStore.selected = "AMD"
request.data = {}
assert.equal(store.report.summary, "AMD research", "Previously visited stock displays its cache")
StockStore.barSettings = {analysisAgent: "codex"}
request.data = result
assert.equal(store.report.summary, undefined, "An old provider's result never displays under a new provider")
store.remember(result)
assert.equal(store.saved["AMD:codex"], undefined)
StockStore.barSettings = {analysisAgent: "opencode"}
assert.equal(store.preference, "claude", "OpenCode is reached through the Omarchy default, not chosen directly")
StockStore.barSettings = {}
assert.equal(store.stale, false)
store.now = 2500
assert.equal(store.stale, true, "Age is checked even without another backend request")
assert.equal(store.contextChanged(result, {updated: 1500, percent: -1}), true, "A material change marks the explanation as earlier context")

StockStore.barSettings = {aiEnabled: false}
assert.equal(store.active, false, "Turning AI features off stops the analysis store")
const count = submissions.length
store.show()
store.generate(true)
assert.equal(submissions.length, count, "No research starts while AI features are off")
StockStore.barSettings = {}
assert.equal(store.active, true, "AI features are on by default")
console.log("PASS: latest-move requests, cache isolation, cancellation and stale context")
StockStore.quote = {sessionStart: 3000}
store.now = 2999
assert.equal(store.report.summary, result.summary, "Retain research before the exchange session starts")
store.now = 3000
assert.equal(store.report.summary, "", "Clear the cached paragraph and icon at the session open")
store.generate(false)
assert.equal(submissions.at(-1)[1], true, "Expired in-memory research cannot reuse the backend cache")
assert.equal(store.expiredSession({asOf: 2990, generated: 3010}, StockStore.quote, 3010), true,
    "Research spanning the open belongs to its snapshot, not completion time")
