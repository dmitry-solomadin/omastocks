const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")

const chart = vm.createContext({})
// Qt's JavaScript engine lacks flatMap; fail here rather than in the shell.
vm.runInContext("delete Array.prototype.flatMap; delete Array.prototype.flat", chart)
vm.runInContext(fs.readFileSync(path.join(__dirname, "../qml/market/MarginChart.js"), "utf8"), chart)
const plain = value => JSON.parse(JSON.stringify(value))

const months = [{month: "2019-12", debt: 5, share: 1.5, change: null}, {month: "2020-01", debt: 6, share: null, change: -10},
    {month: "2020-02", debt: 7, share: 2.5, change: 0}]
assert.deepEqual(plain(chart.points(months, "share")), [{month: "2019-12", value: 1.5}, {month: "2020-02", value: 2.5}], "A month without a value is left out")
assert.deepEqual(plain(chart.points(months, "change")), [{month: "2020-01", value: -10}, {month: "2020-02", value: 0}], "Zero is a real change")
assert.deepEqual(plain(chart.points(undefined, "debt")), [])

// Debt and changes keep zero in view; the share zooms to its own range.
const share = chart.range([1.5, 2.5], "share")
assert.ok(share.low > 1 && share.low < 1.5 && share.high > 2.5)
assert.equal(chart.range([5, 10], "debt").low, 0)
assert.ok(chart.range([5, 10], "change").low < 0)
assert.ok(chart.range([-40, -10], "change").high > 0)
assert.deepEqual(plain(chart.range([], "share")), {low: 0, high: 1})
assert.ok(chart.range([3, 3], "share").high > chart.range([3, 3], "share").low, "A flat line still has a range")

// Round guides stay inside the range, and zero is exactly zero.
assert.deepEqual(plain(chart.guides({low: 0, high: 1.6e12}, 4)), [0, 5e11, 1e12, 1.5e12])
const changes = chart.guides({low: -50, high: 90}, 4)
assert.ok(changes.includes(0))
assert.ok(changes.every(value => value >= -50 && value <= 90))
assert.ok(chart.guides({low: 1.2, high: 3}, 4).every(value => value >= 1.2 && value <= 3))

const years = [{month: "2019-12"}, {month: "2020-01"}, {month: "2020-02"}, {month: "2021-01"}, {month: "2025-01"}]
assert.deepEqual(plain(chart.yearMarks(years, 5)), [{index: 1, year: 2020}, {index: 4, year: 2025}])

assert.equal(chart.nearest(11, 0, 100), 0)
assert.equal(chart.nearest(11, 54, 100), 5)
assert.equal(chart.nearest(11, 100, 100), 10)
assert.equal(chart.nearest(11, 400, 100), 10, "Past the plot, over the axis labels, stays on the last month")
assert.equal(chart.nearest(11, -5, 100), 0)
assert.equal(chart.nearest(0, 5, 100), -1)

assert.equal(chart.ranking(48.9, "1997"), "Higher than 49% of months since 1997")
assert.equal(chart.ranking(0, "Feb 2010"), "Lowest since Feb 2010")
assert.equal(chart.ranking(100, "1997"), "Highest since 1997")
assert.equal(chart.ranking(0.5, "Feb 2010"), "Near the lowest since Feb 2010", "Second lowest isn't the lowest")
assert.equal(chart.ranking(99.8, "1997"), "Near the highest since 1997", "Second highest isn't the highest")
assert.equal(chart.ranking(5, "1997"), "Higher than 5% of months since 1997")
assert.equal(chart.ranking(95, "1997"), "Higher than 95% of months since 1997")
assert.equal(chart.ranking(null, "1997"), "")
assert.equal(chart.ranking(undefined, "1997"), "")

assert.equal(chart.axisLabel(5e11, "debt"), "$500B")
assert.equal(chart.axisLabel(1e12, "debt"), "$1T")
assert.equal(chart.axisLabel(1.5e12, "debt"), "$1.5T")
assert.equal(chart.axisLabel(0, "debt"), "$0")
assert.equal(chart.axisLabel(2.5, "share"), "2.5%")
assert.equal(chart.axisLabel(-50, "change"), "-50%")

assert.deepEqual(Array.from(chart.modes, mode => mode.value), ["share", "debt", "change"])
