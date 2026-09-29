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
const changeLine = windowSource.match(/objectName: "dailyChange"\s*visible: ([^\n]+)/)[1]
function header(quote, expected) {
    const window = load(path.join(__dirname, "../qml/StocksWindow.qml"), {
        state: {quote}, bindings: ["session", "regularSession"],
        globals: {StockStore: {selected: quote.symbol, expectedSession: () => expected}}
    })
    window.window = window
    return {caption: window.evaluate(caption[1]) ? window.evaluate(caption[2]) : null, change: window.evaluate(changeLine)}
}
assert.deepEqual(header({symbol: "AAPL", marketState: "REGULAR"}, "CLOSED"), {caption: null, change: true}, "Its own quote wins")
assert.deepEqual(header({symbol: "HOOW"}, "REGULAR"), {caption: null, change: true}, "In session before its quote")
assert.deepEqual(header({symbol: "HOOW"}, "POST"), {caption: "AT CLOSE", change: false})
assert.deepEqual(header({symbol: "BMW.DE"}, ""), {caption: "", change: false}, "Unknown: the caption's line kept blank")
assert.deepEqual(header({symbol: "BMW.DE", marketState: "POSTPOST"}, ""), {caption: "AT CLOSE", change: false}, "Filled in place")

console.log("PASS: the header is laid out for the session at once, from what the app already knows")
