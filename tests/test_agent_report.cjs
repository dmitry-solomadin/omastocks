const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const {load, plain} = require("./qml_harness.cjs")

// AgentReport backs Bull & bear (one report per stock) and the market brief.
const AnalysisStore = {preference: "default", enabled: true}
const submissions = []
const opened = []
const request = {data: {}, busy: false, submit: (args, force) => submissions.push([plain(args), force])}
const exportRequest = {data: {}, busy: false, submit: (args, force) => submissions.push([plain(args), force])}
const store = load(path.join(__dirname, "../qml/stores/AgentReport.qml"), {
    state: {saved: {}, subject: "AMD", active: true, expired: false},
    bindings: ["preference", "key", "rawReport", "report", "ready", "error", "working", "notificationBusy", "exported"],
    functions: ["show", "generate", "cancel", "notifyWhenReady", "fileUrl", "openInBrowser", "saveCopy", "remember"],
    globals: {AnalysisStore, request, exportRequest, notificationRequest: request,
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

const report = {symbol: "AMD", preference: "default", generated: 100, summary: "AMD debate", bull: [{title: "GPUs"}],
    html: "/state/bull bear/report.html"}
request.data = report
store.remember(report)
store.show()
assert.equal(submissions.length, 2, "Opening a saved report never starts research")
store.openInBrowser()
assert.deepEqual(opened, ["file:///state/bull%20bear/report.html"])

// A copy saved for an earlier report, or another subject, is not shown as this one's.
exportRequest.data = {symbol: "AMD", preference: "default", generated: 100, file: "/home/me/Downloads/AMD.html"}
assert.equal(store.exported.file, "/home/me/Downloads/AMD.html")
exportRequest.data = {symbol: "AMD", preference: "default", generated: 50, file: "/home/me/Downloads/old.html"}
assert.equal(store.exported.file, undefined)
store.saveCopy()
assert.deepEqual(submissions.at(-1), [["export", "AMD", "default"], false])

store.subject = "META"
assert.equal(store.ready, false, "A late AMD reply never renders on META")
store.remember(report)
assert.equal(store.saved["META:default"], undefined)
store.subject = "AMD"
request.data = {}
assert.equal(store.report.bull[0].title, "GPUs", "A visited stock shows its saved report")
AnalysisStore.preference = "claude"
assert.equal(store.ready, false, "Another agent's report never shows under a new agent")
AnalysisStore.preference = "default"

store.active = false
const before = submissions.length
store.show()
store.generate(true)
assert.equal(submissions.length, before, "No research starts while inactive, e.g. with AI features off")
store.active = true
console.log("PASS: reports open without new research, stay per subject and agent, and save the current copy")

// An expired report is hidden, and opening it researches it again.
store.expired = true
assert.equal(store.ready, false)
assert.equal(store.report.bull[0].title, "GPUs", "Its details stay for the backend's reply")
store.show()
assert.deepEqual(submissions.at(-1), [["start", "AMD", "default"], true], "An expired report is never reused")
store.expired = false

// The market brief expires once the S&P 500 trades on a later New York date.
const Clock = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../qml/market/MarketClock.js"), "utf8"), Clock)
const brief = load(path.join(__dirname, "../qml/stores/MarketBriefStore.qml"), {functions: ["staleBrief"], globals: {Clock}})
const at = (day, hour, minute = 0) => Date.UTC(2026, 9, day, hour + 4, minute) / 1000  // New York time in October (UTC−4)
assert.equal(brief.staleBrief({asOf: at(9, 17)}, {updated: at(9, 16)}), false, "Friday's brief after the close")
assert.equal(brief.staleBrief({asOf: at(9, 17)}, {updated: at(9, 16)}), false, "…still Friday's over the weekend, when nothing trades")
assert.equal(brief.staleBrief({asOf: at(12, 8)}, {updated: at(9, 16)}), false, "Monday's pre-market brief before the open")
assert.equal(brief.staleBrief({asOf: at(12, 8)}, {updated: at(12, 9, 31)}), false, "…stays Monday's once trading starts")
assert.equal(brief.staleBrief({asOf: at(9, 17)}, {updated: at(12, 9, 31)}), true, "Friday's brief expires at Monday's open")
assert.equal(brief.staleBrief({asOf: at(9, 17)}, {}), false, "Without a quote, nothing expires")
assert.equal(brief.staleBrief({}, {updated: at(12, 10)}), false)
console.log("PASS: an expired report is researched again, and the market brief belongs to its trading day")
