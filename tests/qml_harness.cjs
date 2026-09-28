// Loads a QML store's real functions, bindings and change handlers into a
// node:vm context. Plain properties are watched: setting one re-evaluates the
// watched bindings and runs their on<Name>Changed handlers, as QML would.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

function memberLine(lines, pattern, what) {
    const index = lines.findIndex(line => pattern.test(line))
    assert.ok(index >= 0, `Missing ${what}`)
    return index
}

// A binding's expression: one line with any deeper-indented continuation
// lines, or a { … } block evaluated as a function body.
function expression(source, name) {
    const lines = source.split("\n")
    const index = memberLine(lines, new RegExp(`^    (readonly )?property [\\w.]+ ${name}: `), `binding ${name}`)
    const text = lines[index].slice(lines[index].indexOf(name + ": ") + name.length + 2)
    if (text.trim() === "{") {
        const end = lines.indexOf("    }", index)
        return "(() => {\n" + lines.slice(index + 1, end).join("\n") + "\n})()"
    }
    let result = text
    for (let line = index + 1; /^ {8}/.test(lines[line]); line++) result += "\n" + lines[line]
    return "(" + result + ")"
}

function functionSource(source, name) {
    const lines = source.split("\n")
    const index = memberLine(lines, new RegExp(`^    function ${name}\\(`), `function ${name}`)
    const first = lines[index]
    if ((first.match(/{/g) || []).length === (first.match(/}/g) || []).length) return first
    return lines.slice(index, lines.indexOf("    }", index) + 1).join("\n")
}

function handlerSource(source, property) {
    const name = "on" + property[0].toUpperCase() + property.slice(1) + "Changed"
    const lines = source.split("\n")
    const index = memberLine(lines, new RegExp(`^    ${name}: `), `handler ${name}`)
    assert.equal(lines.filter(line => line.startsWith(`    ${name}: `)).length, 1, `${name} is set once`)
    const code = lines[index].replace(/^ *\w+: /, "")
    if (code.trim() !== "{") return code
    return lines.slice(index, lines.indexOf("    }", index) + 1).join("\n").replace(/^ *\w+: /, "")
}

function load(file, {state = {}, bindings = [], functions = [], handlers = [], globals = {}}) {
    const source = fs.readFileSync(file, "utf8")
    const context = vm.createContext(Object.assign({}, globals))
    context.root = context
    const values = Object.assign({}, state)
    const watched = handlers.map(property => ({property, code: handlerSource(source, property)}))
    function change(name, value) {
        const before = watched.map(({property}) => context[property])
        values[name] = value
        watched.forEach(({property, code}, index) => {
            if (context[property] !== before[index]) vm.runInContext(code, context)
        })
    }
    for (const name of Object.keys(values))
        Object.defineProperty(context, name, {get: () => values[name], set: value => change(name, value), enumerable: true})
    for (const name of bindings) {
        const code = expression(source, name)
        Object.defineProperty(context, name, {get: () => vm.runInContext(code, context), enumerable: true})
    }
    for (const name of functions) vm.runInContext(functionSource(source, name), context)
    context.evaluate = code => vm.runInContext(code, context)
    context.source = source
    return context
}

// Values built inside a context have its own prototypes.
function plain(value) { return JSON.parse(JSON.stringify(value)) }

// StockStore's long-lived chart helper as a fake Process: starting it runs
// onStarted, stopping it runs onExited, and each request written to it is
// logged in context.sent in order with the store's other requests.
function chartServer(context) {
    return {
        writes: [], starts: 0, alive: false,
        get running() { return this.alive },
        set running(value) {
            if (value === this.alive) return
            this.alive = value
            if (value) { this.starts++; context.sendChart() }
            else context.chartServerExited()
        },
        write(line) {
            const request = JSON.parse(line)
            this.writes.push(request)
            context.sent.push(["chart", request.symbol, request.range])
        },
        // The helper's reply to the running request.
        answer(chart) {
            const active = context.chartActive
            context.chartReply(JSON.stringify({id: active.id, chart: chart || {symbol: active.args[1], range: active.args[2], points: [[1, 1], [2, 2]]}}))
        }
    }
}
// The state and handlers StockStore's chart lane needs.
const chartLane = {
    state: {chartActive: null, chartWaiting: null, chartSerial: 0, chartServerFailures: 0, chartServerRestUntil: 0,
        hoveredRange: "", prefetched: null},
    functions: ["requestChart", "pumpChart", "sendChart", "chartReply", "chartServerExited", "chartServerHung",
        "chartServerFailed", "stopChartServer", "receiveChart", "pending", "request", "hoverRange", "prefetchChart", "prefetchedFresh"],
    globals: () => ({chartWatchdog: {running: false, restart() { this.running = true }, stop() { this.running = false }},
        prefetchTimer: {running: false, restart() { this.running = true }, stop() { this.running = false }}})
}

module.exports = {load, plain, expression, chartServer, chartLane}
