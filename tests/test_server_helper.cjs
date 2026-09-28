const assert = require("node:assert/strict")
const path = require("node:path")
const {load, plain} = require("./qml_harness.cjs")

// One ServerHelper with a fake process: starting it runs onStarted, stopping it
// runs onExited; the signals it emits are recorded.
function helper() {
    const events = []
    const context = load(path.join(__dirname, "../qml/data/ServerHelper.qml"), {
        state: {active: null},
        functions: ["send", "write", "read", "exited", "timedOut", "stop"],
        globals: {
            events,
            watchdog: {running: false, restart() { this.running = true }, stop() { this.running = false }},
            replied: (args, reply) => events.push(["replied", plain(args), plain(reply)]),
            lost: args => events.push(["lost", plain(args)]),
            hung: args => events.push(["hung", plain(args)])
        }
    })
    context.process = {
        writes: [], starts: 0, alive: false,
        get running() { return this.alive },
        set running(value) {
            if (value === this.alive) return
            this.alive = value
            if (value) { this.starts++; context.write() } else context.exited()
        },
        write(line) { this.writes.push(JSON.parse(line)) }
    }
    return context
}

// It starts with its first request and writes each kind as data_server.py expects.
let server = helper()
server.send(1, ["chart", "AAPL", "1D"])
assert.equal(server.process.starts, 1)
assert.equal(server.watchdog.running, true)
server.read(JSON.stringify({id: 1, chart: {symbol: "AAPL"}}))
server.send(2, ["quote", "TSLA"])
server.read(JSON.stringify({id: 2, quote: {symbol: "TSLA"}}))
server.send(3, ["search", "nvid"])
assert.equal(server.process.starts, 1, "One process for every request")
assert.deepEqual(plain(server.process.writes), [{id: 1, action: "chart", symbol: "AAPL", range: "1D"},
    {id: 2, action: "quote", symbol: "TSLA"}, {id: 3, action: "search", query: "nvid"}])

// Only the reply to the running request counts.
server = helper()
server.send(7, ["chart", "AAPL", "1D"])
server.read("not json")
server.read(JSON.stringify({id: 6, chart: {}}))
assert.notEqual(server.active, null)
assert.deepEqual(server.events, [])
server.read(JSON.stringify({id: 7, chart: {symbol: "AAPL"}}))
assert.equal(server.active, null)
assert.equal(server.watchdog.running, false)
assert.deepEqual(server.events, [["replied", ["chart", "AAPL", "1D"], {id: 7, chart: {symbol: "AAPL"}}]])

// Dying with a request running reports it; dying idle does not.
server = helper()
server.send(1, ["quote", "MSFT"])
server.process.running = false
assert.deepEqual(server.events, [["lost", ["quote", "MSFT"]]])
assert.equal(server.active, null)
server = helper()
server.send(1, ["chart", "AAPL", "1D"])
server.read(JSON.stringify({id: 1, chart: {}}))
server.process.running = false
assert.deepEqual(server.events.map(event => event[0]), ["replied"])

// After 45 s it is stopped and the request reported as hung, not lost.
server = helper()
server.send(1, ["search", "x"])
assert.equal(Number(server.source.match(/property Timer watchdog: Timer \{ interval: (\d+);/)[1]), 45000)
server.timedOut()
assert.equal(server.process.running, false)
assert.deepEqual(server.events, [["hung", ["search", "x"]]])

// Stopping drops the request without a report.
server = helper()
server.send(1, ["chart", "AAPL", "1D"])
server.stop()
assert.equal(server.process.running, false)
assert.deepEqual(server.events, [])

console.log("PASS: a data helper answers only its running request and reports deaths and hangs")
