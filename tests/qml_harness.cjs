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

// StockStore's pool of long-lived data helpers, as fake ServerHelpers. Each
// request sent is logged in context.sent in order with the store's other
// requests; answer(), die() and hang() finish the oldest running request of an
// action (chart, quote or search).
function serverPool(context, size = 3) {
    const helpers = Array.from({length: size}, () => ({
        active: null, starts: 0, alive: false,
        get free() { return this.active === null },
        send(id, args) {
            this.active = {id, args}
            if (!this.alive) { this.alive = true; this.starts++ }
            context.sent.push(plain(args))
        },
        stop() { this.active = null; this.alive = false }
    }))
    function finish(kind) {
        const helper = helpers.filter(helper => helper.active && helper.active.args[0] === kind)
            .sort((a, b) => a.active.id - b.active.id)[0]
        assert.ok(helper, `No ${kind} request running`)
        const args = helper.active.args
        helper.active = null
        return [helper, args]
    }
    return {
        helpers,
        get starts() { return helpers.reduce((sum, helper) => sum + helper.starts, 0) },
        get alive() { return helpers.filter(helper => helper.alive).length },
        running(kind) { return helpers.filter(helper => helper.active && helper.active.args[0] === kind).length },
        answer(kind = "chart", result) {
            const [, args] = finish(kind)
            context.serverReplied(args, kind === "search" ? {search: result || {query: args[1], results: []}}
                : kind === "quote" ? result || {quote: {symbol: args[1], price: 1, marketState: "REGULAR"}}
                : {chart: result || {symbol: args[1], range: args[2], points: [[1, 1], [2, 2]]}})
        },
        die(kind = "chart") {
            const [helper, args] = finish(kind)
            helper.alive = false
            context.serverLost(args)
        },
        hang(kind = "chart") {
            const [helper, args] = finish(kind)
            helper.alive = false
            context.serverHung(args)
        }
    }
}
// The state and handlers StockStore's helper pool needs; the pool itself is
// set on the context as servers.
const serverLane = {
    state: {serverWaiting: [], serverSerial: 0, serverFailures: 0, serverRestUntil: 0,
        hoveredRange: "", prefetched: null, searchQuery: "", completedQuery: "", searchError: "", results: []},
    functions: ["serverRequests", "sendToServer", "requestChart", "requestQuote", "requestSearch", "pumpServer", "serverReplied", "serverLost", "serverHung",
        "serverFailed", "stopServer", "receiveChart", "receiveQuote", "receiveSearch", "search", "pending", "request",
        "hoverRange", "prefetchChart", "prefetchedFresh"],
    globals: () => ({prefetchTimer: {running: false, restart() { this.running = true }, stop() { this.running = false }},
        searchTimer: {running: false, restart() { this.running = true }, stop() { this.running = false }}})
}

module.exports = {load, plain, expression, serverPool, serverLane}
