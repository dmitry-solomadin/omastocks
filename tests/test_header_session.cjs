const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const {load, plain} = require("./qml_harness.cjs")

// The Stock page header is laid out for the session at once: from the stock's
// own quote, or before it arrives from what the app already knows.
const Clock = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../qml/market/MarketClock.js"), "utf8"), Clock)
function store(state) {
    return load(path.join(__dirname, "../qml/stores/StockStore.qml"), {
        state: Object.assign({selected: "AAPL", entries: [], favoriteEntries: [], previewQuotes: {}, marketQuotes: {}}, state),
        bindings: ["quote", "watchlistQuotes"],
        functions: ["expectedSession"],
        globals: {Clock, Date}
    })
}
// Monday 28 Sep 2026, 11:00 New York: the US regular session by the clock.
const monday = Date.UTC(2026, 8, 28, 15, 0)
const clock = context => { context.Date = {now: () => monday} }

// What the app already has decides, in order: its lists, then the Market view.
let context = store({entries: [{symbol: "AMD", marketState: "POSTPOST"}], favoriteEntries: [{symbol: "ELF", marketState: "PRE"}],
    marketQuotes: {"ES=F": {marketState: "REGULAR"}, "^N225": {marketState: "CLOSED"}, "^SPX": {marketState: "POST"}}})
assert.equal(context.expectedSession("AMD"), "POST")
assert.equal(context.expectedSession("ELF"), "PRE", "A favorite from another list")
assert.equal(context.expectedSession("ES=F"), "REGULAR", "A Market-view asset")
assert.equal(context.expectedSession("^N225"), "CLOSED")
// Crypto always trades; a US listing follows the US market.
assert.equal(context.expectedSession("BTC-USD"), "REGULAR")
assert.equal(context.expectedSession("HOOW"), "POST", "The US market's reported state")
context = store({})
clock(context)
assert.equal(context.expectedSession("HOOW"), "REGULAR", "Or its schedule, before that is known")
// Unknown until its own quote: foreign listings, contracts and indexes the app has no quote for.
for (const ticker of ["BMW.DE", "HSBA.L", "GC=F", "EURJPY=X", "^GSPC"]) assert.equal(context.expectedSession(ticker), "", ticker)

// A favorite from another list shows its quote at once; the fresher quote wins.
context = store({selected: "ELF", favoriteEntries: [{symbol: "ELF", price: 90, fetched: 100}]})
assert.equal(context.quote.price, 90)
context.previewQuotes = {ELF: {symbol: "ELF", price: 91, fetched: 200}}
assert.equal(context.quote.price, 91)
context.previewQuotes = {ELF: {symbol: "ELF", price: 80, fetched: 50}}
assert.equal(context.quote.price, 90, "Not an older quote of its own")

// The header: the stock's own quote decides, else the expected session. Unknown
// is laid out as closed with a blank caption, so a closed answer fills it in.
const windowSource = fs.readFileSync(path.join(__dirname, "../qml/StocksWindow.qml"), "utf8")
const caption = windowSource.match(/objectName: "closeLabel"\s*visible: ([^\n]+)\s*text: ([^\n]+)/)
function header(quote, expected) {
    const window = load(path.join(__dirname, "../qml/StocksWindow.qml"), {
        state: {quote}, bindings: ["session", "regularSession"],
        globals: {StockStore: {selected: quote.symbol, expectedSession: () => expected}}
    })
    window.window = window
    return window.evaluate(caption[1]) ? window.evaluate(caption[2]) : null
}
assert.equal(header({symbol: "AAPL", marketState: "REGULAR"}, "CLOSED"), null, "Its own quote wins")
assert.equal(header({symbol: "HOOW"}, "REGULAR"), null, "In session before its quote")
assert.equal(header({symbol: "HOOW"}, "POST"), "AT CLOSE")
assert.equal(header({symbol: "BMW.DE"}, ""), "", "Unknown: the caption's line kept blank")
assert.equal(header({symbol: "BMW.DE", marketState: "POSTPOST"}, ""), "AT CLOSE", "Filled in place")
console.log("PASS: the header is laid out for the session at once, from what the app already knows")

// The one change line follows the range drawn: the live quote's on 1D, the
// chart's from its first point on the others.
const ChartMath = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../qml/charts/ChartMath.js"), "utf8"), ChartMath)
function changeLine(quote, chartPeriod, points) {
    const window = load(path.join(__dirname, "../qml/StocksWindow.qml"), {
        state: {quote, chartPeriod, points},
        bindings: ["rangeChange", "dayRange", "periodChange", "periodPercent", "hasPeriodChange", "periodChangeText", "periodPhraseText"],
        globals: {ChartMath, Date, StockStore: {
            price: value => value.toFixed(2), percent: value => (value >= 0 ? "+" : "") + value.toFixed(2) + "%"}}
    })
    return [window.periodChangeText, window.periodPhraseText].filter(Boolean).join(" ")
}
const now = Date.now() / 1000
assert.equal(changeLine({change: 1.18, percent: 0.19, updated: now}, "1D", [[now - 60, 1], [now, 2]]), "+1.18 (+0.19%) today")
assert.equal(changeLine({change: null}, "1D", []), "Daily change unavailable")
assert.equal(changeLine({change: 1.18, percent: 0.19}, "1W", [[now - 86400, 200], [now, 190]]), "-10.00 (-5.00%) past week")
assert.equal(changeLine({change: 1.18, percent: 0.19}, "1W", []), "", "Blank while a new stock's chart loads")
console.log("PASS: the change line follows the range")
