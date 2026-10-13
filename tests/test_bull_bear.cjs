const assert = require("node:assert/strict")
const path = require("node:path")
const {load, plain} = require("./qml_harness.cjs")

const StockStore = {selected: "AMD"}
const AnalysisStore = {preference: "default", enabled: true}
const MarketStore = {companyResearchActive: true}
const submissions = []
const opened = []
const request = {data: {}, busy: false, submit: (args, force) => submissions.push([plain(args), force])}
const exportRequest = {data: {}, busy: false, submit: (args, force) => submissions.push([plain(args), force])}
const store = load(path.join(__dirname, "../qml/stores/BullBearStore.qml"), {
    state: {saved: {}},
    bindings: ["active", "preference", "key", "report", "ready", "error", "working", "notificationBusy", "exported"],
    functions: ["show", "generate", "cancel", "notifyWhenReady", "fileUrl", "openInBrowser", "saveCopy", "remember"],
    globals: {StockStore, AnalysisStore, MarketStore, request, exportRequest, notificationRequest: request,
        openRequested() {}, Qt: {openUrlExternally: url => opened.push(url)}}
})

// Opening with no report starts one; the backend reuses any saved report.
store.show()
assert.deepEqual(submissions[0], [["start", "AMD", "default"], false])
request.data = {symbol: "AMD", preference: "default", pending: true, job: "job1"}
store.show()
store.generate(true)
assert.equal(submissions.length, 1, "A pending job is never duplicated")
store.cancel()
assert.deepEqual(submissions[1], [["cancel", "AMD", "default", "job1"], false])

const report = {symbol: "AMD", preference: "default", generated: 100, bull: [{title: "GPUs"}], bear: [{title: "Valuation"}],
    html: "/state/bull bear/report.html"}
request.data = report
store.remember(report)
store.show()
assert.equal(submissions.length, 2, "Opening a saved report never starts research")
store.openInBrowser()
assert.deepEqual(opened, ["file:///state/bull%20bear/report.html"])

// A copy saved for an earlier report, or another stock, is not shown as this one's.
exportRequest.data = {symbol: "AMD", preference: "default", generated: 100, file: "/home/me/Downloads/AMD.html"}
assert.equal(store.exported.file, "/home/me/Downloads/AMD.html")
exportRequest.data = {symbol: "AMD", preference: "default", generated: 50, file: "/home/me/Downloads/old.html"}
assert.equal(store.exported.file, undefined)
store.saveCopy()
assert.deepEqual(submissions.at(-1), [["export", "AMD", "default"], false])

StockStore.selected = "META"
assert.equal(store.ready, false, "A late AMD reply never renders on META")
store.remember(report)
assert.equal(store.saved["META:default"], undefined)
StockStore.selected = "AMD"
request.data = {}
assert.equal(store.report.bull[0].title, "GPUs", "A visited stock shows its saved report")
AnalysisStore.preference = "claude"
assert.equal(store.ready, false, "Another agent's report never shows under a new agent")

AnalysisStore.enabled = false
const before = submissions.length
store.show()
store.generate(true)
assert.equal(submissions.length, before, "No research starts while AI features are off")
AnalysisStore.enabled = true

console.log("PASS: bull & bear reports open without new research, stay per stock and agent, and save the current copy")
