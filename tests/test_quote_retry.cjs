const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")

// Exercise the real store handlers with a fake clock/process/timer: a backend
// deadline must schedule recovery without waiting for the five-minute poll.
const source = fs.readFileSync(path.join(__dirname, "../qml/stores/StockStore.qml"), "utf8")
const timer = {running: false, interval: 0, stop() { this.running = false }, restart() { this.running = true }}
const requests = []
const context = vm.createContext({
    Date: {now: () => 1000000}, running: true, quoteRetry: timer,
    quoteTransportFailures: 0, exited: true, collected: true,
    watchdog: {stop() {}}, Qt: {callLater() {}}, pump() {},
    queue: [], entries: [], selected: "", activeWatchlist: "default", error: "",
    request(args) { requests.push(Array.from(args)) }
})
context.root = context
for (const name of ["scheduleQuoteRetry", "finish"]) {
    const body = source.match(new RegExp(`^    function ${name}\\([^]*?^    }`, "m"))
    assert.ok(body, `Missing handler ${name}`)
    vm.runInContext(body[0], context)
}
function reply(data) {
    context.active = ["retry-quotes"]
    context.captured = typeof data === "string" ? data : JSON.stringify(data)
    context.finish()
}
reply({entries: [], favoriteEntries: [], quoteRetryAfter: 1001})
assert.equal(timer.running, true)
assert.equal(timer.interval, 1000)
const trigger = source.match(/property Timer quoteRetry: Timer \{ onTriggered: ([^\n]+) \}/)[1]
vm.runInContext(trigger, context)
assert.deepEqual(requests, [["retry-quotes"]])
reply({entries: [], favoriteEntries: [], quoteRetryAfter: 1120})
assert.equal(timer.interval, 120000, "Provider cooldown takes precedence over quick retries")
reply({entries: [], favoriteEntries: [], quoteRetryAfter: 0})
assert.equal(timer.running, false, "Successful recovery stops retry scheduling")
for (const delay of [1, 2, 4, 8, 16, 32, 64, 128, 256, 300, 300]) {
    reply("truncated helper response")
    assert.equal(timer.running, true)
    assert.equal(timer.interval, delay * 1000, "Helper failures also recover exponentially")
}
reply({entries: [], favoriteEntries: [], quoteRetryAfter: 0})
reply({error: "helper timed out"})
assert.equal(timer.interval, 1000, "Success resets the helper failure backoff")
context.running = false
reply({entries: [], quoteRetryAfter: 1001})
assert.equal(timer.running, false, "An unloaded store cannot schedule retries")
console.log("PASS: quote deadlines, recovery dispatch, cooldowns, helper failures, reset and unload")
