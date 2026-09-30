const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

// The watchlist's arrow keys, from StocksWindow.qml: the first press opens the
// next stock at once; presses repeating faster than 150 ms only move the
// highlight, and the stock opens where they stop.
const source = fs.readFileSync(path.join(__dirname, "../qml/StocksWindow.qml"), "utf8")
const member = name => source.match(new RegExp(`^ {20}function ${name}\\([^]*?^ {20}\\}$`, "m"))[0]
const trigger = source.match(/property Timer keyPause: Timer \{\s*interval: (\d+)\s*onTriggered: ([^\n]+)/)
assert.equal(Number(trigger[1]), 150)

function list(symbols, selected) {
    const opened = []
    const context = vm.createContext({
        rows: symbols.map(symbol => ({symbol})), currentIndex: symbols.indexOf(selected), keyTarget: "",
        keyPause: {running: false, restart() { this.running = true }, stop() { this.running = false }},
        StockStore: {selected, view: "stock", select(symbol) { this.selected = symbol; opened.push(symbol) }},
        positionViewAtIndex() {}, forceActiveFocus() {}, ListView: {Contain: 1}, opened
    })
    context.list = context
    vm.runInContext(member("selectIndex") + "\n" + member("moveSelection"), context)
    context.pause = () => { context.keyPause.running = false; vm.runInContext(trigger[2], context) }
    return context
}
const rows = ["AMD", "ELF", "AFRM", "MU", "AAPL", "MSFT"]

// A single press opens the next stock at once.
let keys = list(rows, "AMD")
keys.moveSelection(1)
assert.deepEqual(keys.opened, ["ELF"])
keys.pause()
assert.deepEqual(keys.opened, ["ELF"], "Nothing more once the keys stop")

// Holding a key: the first row opens, the highlight follows, the last row opens.
keys = list(rows, "AMD")
keys.moveSelection(1)
for (let step = 0; step < 3; step++) keys.moveSelection(1)
assert.deepEqual(keys.opened, ["ELF"])
assert.equal(keys.keyTarget, "AAPL", "The highlight follows the key")
assert.equal(keys.currentIndex, 4)
keys.pause()
assert.deepEqual(keys.opened, ["ELF", "AAPL"])
assert.equal(keys.keyTarget, "")

// The ends of the list hold, and a click while the keys run wins.
keys = list(rows, "AFRM")
keys.moveSelection(-1)
keys.moveSelection(-1)
keys.moveSelection(-1)
assert.equal(keys.keyTarget, "AMD")
keys.selectIndex(3)
assert.deepEqual(keys.opened, ["ELF", "MU"])
keys.pause()
assert.deepEqual(keys.opened, ["ELF", "MU"], "The click replaced the keyboard's stock")

console.log("PASS: arrow keys open the next stock at once and pace a held key to where it stops")

// Typing a letter or digit outside a text field starts a new search with it.
const typing = source.match(/^ {8}Keys\.onPressed: event => \{\n([^]*?)^ {8}\}$/m)[1]
function typed(text, modifiers = 0, open = {}) {
    const search = {text: "old query", cursorPosition: 0, focused: false, forceActiveFocus() { this.focused = true }}
    const event = {text, modifiers, accepted: false}
    const context = vm.createContext({event, search, Qt: {ShiftModifier: 0x02000000, KeypadModifier: 0x20000000},
        settingsMenu: {opened: !!open.settings}, watchlistMenu: {opened: false}, rowMenu: {opened: false},
        watchlistSelector: {popupOpen: false}})
    vm.runInContext(`(() => {\n${typing}\n})()`, context)
    return [search.focused ? search.text : null, event.accepted]
}
assert.deepEqual(typed("n"), ["n", true], "Replaces the old query")
assert.deepEqual(typed("N", 0x02000000), ["N", true], "With Shift")
assert.deepEqual(typed("7", 0x20000000), ["7", true], "From the keypad")
assert.deepEqual(typed("r", 0x04000000), [null, false], "Not with Ctrl, so shortcuts still work")
for (const text of ["é", "ж", " ", "-", ""]) assert.deepEqual(typed(text), [null, false], JSON.stringify(text))
assert.deepEqual(typed("n", 0, {settings: true}), [null, false], "Not while a menu is open")
console.log("PASS: typing a letter or digit starts a search")

// Accepting a tracked result restores its position in the unfiltered watchlist.
for (const tracked of [true, false]) {
    const keys = list(["MU", "NEW"], "AMD")
    const deferred = []
    keys.StockStore.entries = rows.map(symbol => ({symbol}))
    keys.StockStore.searchQuery = "query"
    keys.Qt = {callLater(fn) { deferred.push(fn) }}
    keys.search = {clear() {
        keys.StockStore.searchQuery = ""
        keys.rows = rows.map(symbol => ({symbol}))
    }}
    vm.runInContext(member("acceptIndex"), keys)
    keys.acceptIndex(tracked ? 0 : 1)
    deferred.forEach(fn => fn())
    assert.equal(keys.StockStore.selected, tracked ? "MU" : "NEW")
    assert.equal(keys.StockStore.searchQuery, tracked ? "" : "query")
    assert.equal(keys.currentIndex, tracked ? 3 : 1)
    keys.pause()
    assert.deepEqual(keys.opened, [tracked ? "MU" : "NEW"])
}
console.log("PASS: Enter restores tracked results to the watchlist and keeps untracked results in search")
