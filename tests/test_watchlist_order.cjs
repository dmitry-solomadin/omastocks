const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")
const order = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../qml/watchlist/WatchlistOrder.js"), "utf8"), order)
const rows = [
    {symbol:"CCC",name:"alpha",change:3,percent:9},
    {symbol:"AAA",name:"Zulu",change:2,percent:4},
    {symbol:"BBB",name:"Beta",change:-1,percent:-2},
    {symbol:"DDD",name:"beta"}
]
const quotes = {CCC:{change:-4,percent:2,marketCap:20}, AAA:{change:0,percent:3,marketCap:10}, BBB:{change:4,percent:-1,marketCap:30}, DDD:{change:null,percent:null,marketCap:null}}
const symbols = mode => Array.from(order.sorted(rows, quotes, mode), row => row.symbol).join(",")
assert.equal(symbols("custom"), "CCC,AAA,BBB,DDD")
assert.equal(symbols("change"), "BBB,AAA,CCC,DDD")
assert.equal(symbols("percent"), "AAA,CCC,BBB,DDD")
assert.equal(symbols("marketCap"), "BBB,CCC,AAA,DDD")
assert.equal(symbols("symbol"), "AAA,BBB,CCC,DDD")
assert.equal(symbols("name"), "CCC,BBB,DDD,AAA")
assert.equal(symbols("custom"), "CCC,AAA,BBB,DDD", "Derived sorting never mutates Custom order")
quotes.AAA.change = null
assert.equal(symbols("change"), "BBB,CCC,AAA,DDD", "Explicit missing bulk values cannot resurrect an old change")
delete quotes.AAA
assert.equal(symbols("change"), "BBB,AAA,CCC,DDD", "Existing sidebar data works before bulk quotes arrive")
quotes.CCC.marketCap = Infinity
assert.equal(symbols("marketCap"), "BBB,AAA,CCC,DDD")
console.log("PASS: shared sorting, custom-order preservation, numeric/text modes, missing values, zeros and deterministic ties")
