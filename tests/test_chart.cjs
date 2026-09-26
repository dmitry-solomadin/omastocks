const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")
const chart = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../qml/charts/ChartMath.js"), "utf8"), chart)
const plain = value => JSON.parse(JSON.stringify(value))
const points = [[1000, 100], [1300, 105], [2200, 90]]

const open = chart.timeDomain(points, "1D", 1000, 4600, 2400)
assert.deepEqual(plain(open), [1000, 4600])
assert.equal(chart.pointFraction(points, 2, "1D", open), 1 / 3)
assert.equal(chart.nearestIndex(points, .1, "1D", open), 1)
assert.equal(chart.nearestIndex(points, 1, "1D", open), 2)
assert.equal(chart.nearestIndex(points, -1, "1D", open), 0)
console.log("PASS: open-session time axis and irregular timestamps, with no future samples")

// ELF-like sparse premarket samples followed by five-minute regular bars.
const sparse = [0, 6600, 6900, 8100, 8400, 8700, 8850].map(t => [t, 100])
for (const width of [160, 500, 1400]) {
    const domain = [0, 57600]
    const widths = sparse.map((_, i) => chart.volumeBarWidth(sparse, i, "1D", domain, width, 8))
    for (let i = 1; i < sparse.length; i++) {
        const gap = (chart.pointFraction(sparse, i, "1D", domain) - chart.pointFraction(sparse, i - 1, "1D", domain)) * width
        assert.ok((widths[i - 1] + widths[i]) / 2 < gap, "Volume bars must not overlap")
    }
    assert.ok(Math.abs(widths[4] - Math.min(8, 300 / 57600 * width * .7)) < 1e-10)
}
assert.equal(chart.volumeBarWidth([[0, 100]], 0, "1D", [0, 1], 500, 8), 8)
assert.equal(chart.volumeBarWidth([], 0, "1D", [0, 1], 500, 8), 0)
assert.equal(chart.volumeBarWidth(sparse, 2, "1M", [0, 8850], 500, 8), 8)
console.log("PASS: volume widths follow neighboring intervals across sparse extended hours and dense samples")

const minuteVolumes = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, null]
const volumePrices = minuteVolumes.map((_, index) => [600 + index * 60, index < 5 ? 100 + index : 100 - index])
const originalVolumes = minuteVolumes.slice()
const groupedVolume = chart.volumeSeries(volumePrices, minuteVolumes, "1D")
assert.deepEqual(plain(groupedVolume.volumes), [150, 400, null])
assert.deepEqual(plain(groupedVolume.points), [[720, 104], [1020, 91], [1200, 90]])
assert.deepEqual(plain(groupedVolume.falling), [false, true, true])
assert.deepEqual(minuteVolumes, originalVolumes, "Grouping must not change one-minute hover volume")
assert.equal(volumePrices.length, 11, "Price resolution remains one minute")
const partialVolume = chart.volumeSeries(volumePrices.slice(0, 7), minuteVolumes.slice(0, 7), "1D")
assert.deepEqual(plain(partialVolume.volumes), [150, 130], "The unfinished five-minute bar accumulates only available candles")
assert.deepEqual(plain(chart.volumeSeries([[600, 1], [660, 2]], [10, null], "1D").volumes), [null], "Missing volume is not a zero or partial total")
assert.deepEqual(plain(chart.volumeSeries([[600, 1], [3600, 2]], [0, 20], "1D").volumes), [0, 20], "Sparse timestamps cannot merge across intervals")
assert.equal(chart.volumeSeries(volumePrices, minuteVolumes, "1W").volumes, minuteVolumes, "Other ranges keep native volume bars")
assert.deepEqual(plain(chart.volumeSeries([], [], "1D").points), [])
// A full session has enough samples to make the one-minute width noticeably smaller.
assert.ok(chart.volumeBarWidth(volumePrices, 2, "1D", [600, 24000], 1000, 8)
    < chart.volumeBarWidth(groupedVolume.points, 0, "1D", [600, 24000], 1000, 8))
console.log("PASS: five-minute volume totals, partial bars, missing samples and unchanged one-minute hover data")

for (const [period, start, end, now] of [
    ["1D", 1000, 4600, 999],
    ["1D", 1000, 4600, 4600],
    ["1D", 5000, 8600, 6000],
    ["1D", null, null, 2400],
    ["1M", 1000, 4600, 2400],
]) {
    assert.deepEqual(plain(chart.timeDomain(points, period, start, end, now)), [1000, 2200])
}
assert.deepEqual(plain(chart.timeDomain(points, "1D", 1000, 2800, 2400)), [1000, 2800])
assert.equal(chart.pointFraction(points, 1, "1M", open), .5)
assert.equal(chart.nearestIndex(points, .5, "1M", open), 1)
console.log("PASS: early close, premarket, closed session, previous-day data and historical ranges")

assert.deepEqual(plain(chart.comparison(points, 0, 1)), {first: 0, last: 1, change: 5, percent: 5})
assert.deepEqual(plain(chart.comparison(points, 2, 0)), {first: 0, last: 2, change: -10, percent: -10})
assert.equal(chart.comparison(points, 0, 0), null)
assert.equal(chart.comparison(points, -1, 2), null)
assert.equal(chart.comparison(points, 0, 3), null)
assert.equal(chart.comparison([[1, 0], [2, 5]], 0, 1).percent, null)
assert.equal(chart.nearestIndex([], .5, "1D", [0, 1]), -1)
console.log("PASS: forward/reverse selection, percentage baseline, zero price and empty data")

const primary = [[100, 10], [200, 20], [300, 40]]
const days = ["2026-09-17", "2026-09-18", "2026-09-21"]
const normalized = chart.compareSeries(primary, days, [[200, 100], [300, 110]], days.slice(1), "1M")
assert.equal(normalized.first, 1)
assert.equal(normalized.base, 20)
assert.equal(normalized.main[1][1], 100)
assert.ok(Math.abs(normalized.other[1][1] - 10) < 1e-9)
assert.equal(chart.compareSeries(primary, days, [[500, 12]], ["2026-09-22"], "1M"), null)
assert.equal(chart.compareSeries([[300, 10]], [], [[900, 20]], [], "1D"), null)
console.log("PASS: comparison normalizes at a shared date and rejects non-overlapping data")

const average = {points: [[0, 10], [1, 20], [2, 30]], dates: days}
for (const period of ["1D", "1W"]) {
    assert.equal(chart.dailyAveragesSupported(period), false)
    assert.deepEqual(plain(chart.projectAverage(primary, days, average, period)), [])
}
for (const period of ["1M", "3M", "YTD", "1Y", "2Y", "5Y", "ALL"]) assert.equal(chart.dailyAveragesSupported(period), true)
// ALL bars (monthly or quarterly) run until the next bar: events and averages land in the bar that covers them.
const months = ["2026-03-01", "2026-06-01", "2026-07-01"], monthly = [[1, 10], [2, 11], [3, 12]]
assert.deepEqual(plain(chart.eventPositions(monthly, months, [{type: "split", date: "2026-05-18"}, {type: "split", date: "2026-08-31"}], "ALL")),
    [{type: "split", date: "2026-05-18", index: 0}, {type: "split", date: "2026-08-31", index: 2}])
assert.deepEqual(plain(chart.eventPositions(monthly, months, [{type: "earnings", date: "2026-06-18"}, {type: "dividend", date: "2026-06-19"}], "ALL")), [])
assert.equal(chart.eventPositions(monthly, months, [{type: "earnings", date: "2026-06-18"}], "5Y").length, 1)
const daily = {points: [[0, 5], [1, 6], [2, 7]], dates: ["2026-05-29", "2026-06-30", "2026-08-03"]}
assert.deepEqual(plain(chart.projectAverage(monthly, months, daily, "ALL")), [[0, 5], [1, 6], [2, 7]])
assert.deepEqual(plain(chart.projectAverage(primary, days, average, "1M")), [[0, 10], [1, 20], [2, 30]])
const events = [{type: "earnings", date: "2026-09-18"}, {type: "earnings", date: "2026-09-18"}, {type: "dividend", date: "2026-10-01"}]
assert.deepEqual(plain(chart.eventPositions(primary, days, events, "1M")), [{type: "earnings", date: "2026-09-18", index: 1}])
console.log("PASS: daily averages are excluded from intraday ranges; event markers are deduplicated and range-limited")

const minuteSeries = [0, 60, 120, 180, 240].map((stamp, index) => [stamp, 10 + index])
const minuteComparison = chart.compareMany([{points: minuteSeries}, {points: minuteSeries.map(([t, p]) => [t, p * 2])}], "1D")
assert.equal(minuteComparison.series[0].points.length, 5, "Comparison preserves every one-minute candle")
assert.deepEqual(plain(minuteComparison.series[0].points.map(point => point[2])), [10, 11, 12, 13, 14])
const monthTimes = [36000, 43200, 50400, 122400, 129600, 136800]
const monthDays = ["2026-09-24", "2026-09-24", "2026-09-24", "2026-09-25", "2026-09-25", "2026-09-25"]
const denseMonth = monthTimes.map((stamp, index) => [stamp, 10 + index])
const monthComparison = chart.compareMany([{points: denseMonth, dates: monthDays}, {points: denseMonth, dates: monthDays}], "1M")
assert.deepEqual(plain(monthComparison.series[0].points.map(point => point[2])), [10, 11, 12, 13, 14, 15], "Same-day samples must not collapse to the daily close")
const dailyMA = {points: [[0, 20], [1, 21], [2, 22]], dates: ["2026-09-23", "2026-09-24", "2026-09-25"]}
assert.deepEqual(plain(chart.projectAverage(denseMonth, monthDays, dailyMA, "1M")), [[0, 20], [1, 20], [2, 21], [3, 21], [4, 21], [5, 22]])
console.log("PASS: minute comparisons and intraday monthly samples preserve distinct prices without future daily averages")

const basket = Array.from({length: 5}, (_, index) => ({symbol: "S" + index, currency: "USD", color: "c" + index,
    points: primary.map(([time, price]) => [time, price * (index + 1)]), dates: days}))
basket[4].points = basket[4].points.slice(1)
basket[4].dates = days.slice(1)
const multi = chart.compareMany(basket, "1Y")
assert.equal(multi.series.length, 5)
assert.equal(multi.first, 1)
assert.equal(multi.last, 2)
for (let i = 0; i < 5; i++) {
    assert.deepEqual(plain(multi.series[i].points), [[1, 0, 20 * (i + 1)], [2, 100, 40 * (i + 1)]])
    assert.equal(multi.series[i].color, "c" + i)
}
assert.equal(chart.compareMany([basket[0], {points: [[500, 5], [600, 6]], dates: ["2030-01-01", "2030-01-02"]}], "1Y"), null)
assert.equal(chart.compareMany([{points: [[100, 0], [200, 10]], dates: days.slice(0, 2)}], "1M"), null)
const intraday = chart.compareMany([{points: [[300, 10], [600, 20], [900, 30]]}, {points: [[300, 2], [900, 4]]}], "1D")
assert.deepEqual(plain(intraday.series[1].points), [[0, 0, 2], [2, 100, 4]])
console.log("PASS: five-stock shared baseline, raw hover prices, currencies/colors, missing intervals and non-overlap")
