function timeDomain(points, period, sessionStart, sessionEnd, now) {
    if (!points.length) return [0, 1]
    const first = points[0][0], last = points[points.length - 1][0]
    const open = period === "1D" && Number.isFinite(sessionStart) && Number.isFinite(sessionEnd)
        && sessionStart < sessionEnd && now >= sessionStart && now < sessionEnd
        && first >= sessionStart && last <= now
    return open ? [sessionStart, sessionEnd] : [first, last]
}

function pointFraction(points, index, period, domain) {
    if (!points.length || index < 0 || index >= points.length) return 0
    if (period === "1D" && domain[1] > domain[0])
        return (points[index][0] - domain[0]) / (domain[1] - domain[0])
    return index / Math.max(1, points.length - 1)
}

function volumeBarWidth(points, index, period, domain, plotWidth, maximum) {
    if (!points.length || index < 0 || index >= points.length) return 0
    const center = pointFraction(points, index, period, domain)
    let spacing = 1
    // Sparse extended-session samples must not set the width of regular bars.
    if (index > 0) spacing = Math.min(spacing, center - pointFraction(points, index - 1, period, domain))
    if (index + 1 < points.length) spacing = Math.min(spacing, pointFraction(points, index + 1, period, domain) - center)
    return Math.max(0, Math.min(maximum, spacing * plotWidth * .7))
}

function nearestIndex(points, fraction, period, domain) {
    if (!points.length) return -1
    fraction = Math.max(0, Math.min(1, fraction))
    if (period !== "1D" || domain[1] <= domain[0])
        return Math.round(fraction * (points.length - 1))
    const timestamp = domain[0] + fraction * (domain[1] - domain[0])
    let low = 0, high = points.length - 1
    while (low < high) {
        const middle = Math.floor((low + high) / 2)
        if (points[middle][0] < timestamp) low = middle + 1
        else high = middle
    }
    if (low > 0 && timestamp - points[low - 1][0] <= points[low][0] - timestamp) return low - 1
    return low
}

function comparison(points, anchor, cursor) {
    if (anchor < 0 || cursor < 0 || anchor >= points.length || cursor >= points.length || anchor === cursor)
        return null
    const first = Math.min(anchor, cursor), last = Math.max(anchor, cursor)
    const change = points[last][1] - points[first][1]
    return {first: first, last: last, change: change,
        percent: points[first][1] === 0 ? null : change / points[first][1] * 100}
}

// Match trading intervals rather than stretching unrelated sample indices.
function compareSeries(points, dates, other, otherDates, period) {
    const intraday = period === "1D" || period === "1W"
    const bucket = period === "1D" ? 300 : 1800
    function key(point, day) { return intraday ? Math.floor(point[0] / bucket) : day || Math.floor(point[0] / 86400) }
    const lookup = new Map()
    other.forEach((point, index) => lookup.set(key(point, otherDates[index]), point[1]))
    const shared = []
    points.forEach((point, index) => {
        const value = lookup.get(key(point, dates[index]))
        if (value !== undefined) shared.push({index: index, main: point[1], other: value})
    })
    if (shared.length < 2 || shared[0].main === 0 || shared[0].other === 0) return null
    const base = shared[0]
    return {base: base.main, first: base.index, last: shared[shared.length - 1].index,
        main: shared.map(row => [row.index, (row.main / base.main - 1) * 100]),
        other: shared.map(row => [row.index, (row.other / base.other - 1) * 100])}
}

function dailyAveragesSupported(period) {
    return ["1M", "3M", "1Y", "5Y"].indexOf(period) >= 0
}

// All comparison lines share exactly the same observations and baseline date.
function compareMany(series, period) {
    if (!series.length || !series[0].points.length) return null
    const intraday = period === "1D" || period === "1W"
    const bucket = period === "1D" ? 300 : 1800
    function key(point, day) { return intraday ? Math.floor(point[0] / bucket) : day || Math.floor(point[0] / 86400) }
    const lookups = series.map(row => {
        const lookup = new Map()
        row.points.forEach((point, index) => {
            if (Number.isFinite(point[1])) lookup.set(key(point, (row.dates || [])[index]), point[1])
        })
        return lookup
    })
    const shared = []
    series[0].points.forEach((point, index) => {
        const date = key(point, (series[0].dates || [])[index])
        if (lookups.every(lookup => lookup.has(date))) shared.push({index: index, prices: lookups.map(lookup => lookup.get(date))})
    })
    if (shared.length < 2 || shared[0].prices.some(price => price === 0)) return null
    return {first: shared[0].index, last: shared[shared.length - 1].index, base: shared[0].prices[0],
        series: series.map((row, index) => ({symbol: row.symbol, currency: row.currency, color: row.color,
            points: shared.map(point => [point.index, (point.prices[index] / shared[0].prices[index] - 1) * 100, point.prices[index]])}))}
}

function projectAverage(points, dates, series, period) {
    // Daily averages on intraday charts flatten price movement by widening its scale.
    if (!dailyAveragesSupported(period)) return []
    const values = series.points || [], days = series.dates || []
    const result = []
    let cursor = -1
    for (let index = 0; index < points.length; index++) {
        const day = dates[index]
        if (!day) continue
        let cutoff = day
        if (period === "5Y") {
            // Weekly prices represent the last close of the week, not Monday's close.
            const next = dates[index + 1]
            cutoff = next ? new Date(Date.parse(next) - 86400000).toISOString().slice(0, 10) : days[days.length - 1]
        }
        while (cursor + 1 < days.length && days[cursor + 1] <= cutoff) cursor++
        if (cursor >= 0) result.push([index, values[cursor][1]])
    }
    return result
}

function eventPositions(points, dates, events, period) {
    if (!points.length || !dates.length) return []
    let lastDate = dates[dates.length - 1]
    if (period === "5Y") {
        const weekEnd = new Date(Date.parse(lastDate) + 6 * 86400000).toISOString().slice(0, 10)
        lastDate = weekEnd < new Date().toISOString().slice(0, 10) ? weekEnd : new Date().toISOString().slice(0, 10)
    }
    const seen = new Set(), result = []
    for (const event of events) {
        if (!event.date || event.date < dates[0] || event.date > lastDate) continue
        const key = event.type + ":" + event.date
        if (seen.has(key)) continue
        seen.add(key)
        let index = dates.findIndex(day => day >= event.date)
        if (period === "5Y" && (index < 0 || dates[index] > event.date)) index = index < 0 ? dates.length - 1 : Math.max(0, index - 1)
        if (index >= 0) result.push(Object.assign({}, event, {index: index}))
    }
    return result
}
