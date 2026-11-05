// Pure helpers for the margin debt section's chart and rankings.

var modes = [
    {value: "share", label: "Share of market", hint: "Margin debt as a share of US market value"},
    {value: "debt", label: "Debt", hint: "Margin debt in dollars"},
    {value: "change", label: "1-year change", hint: "Change from a year earlier; shaded while it's negative"}
]

// The months that have a value in this mode, oldest first.
function points(months, mode) {
    return (months || []).filter(row => Number.isFinite(row[mode])).map(row => ({month: row.month, value: row[mode]}))
}

// The axis range: padded, and always including zero for debt and for changes.
function range(values, mode) {
    if (!values.length) return {low: 0, high: 1}
    let low = Math.min(...values), high = Math.max(...values)
    if (mode !== "share") { low = Math.min(0, low); high = Math.max(0, high) }
    const pad = Math.max((high - low) * .06, 1e-9)
    return {low: mode === "debt" ? low : low - pad, high: high + pad}
}

// Up to about `count` round values inside the range.
function guides(bounds, count) {
    const span = bounds.high - bounds.low
    const rough = span / Math.max(1, count || 4), power = Math.pow(10, Math.floor(Math.log10(rough)))
    const step = [1, 2, 2.5, 5, 10].map(factor => factor * power).find(candidate => candidate >= rough)
    const marks = []
    for (let value = Math.ceil(bounds.low / step) * step; value <= bounds.high + step * 1e-9; value += step)
        marks.push(Math.abs(value) < step * 1e-9 ? 0 : value)
    return marks
}

// January of every `every`th year, as an index into the points.
function yearMarks(items, every) {
    const marks = []
    items.forEach((item, index) => {
        const year = Number(item.month.slice(0, 4))
        if (item.month.endsWith("-01") && year % (every || 5) === 0) marks.push({index: index, year: year})
    })
    return marks
}

// The point nearest a position along the plot.
function nearest(count, x, width) {
    if (count < 1 || width <= 0) return -1
    return Math.max(0, Math.min(count - 1, Math.round(x / width * (count - 1))))
}

// A reading's place in its own history, in words. `since` is already formatted.
function ranking(percentile, since) {
    if (!Number.isFinite(percentile)) return ""
    if (percentile <= 0) return "Lowest since " + since
    if (percentile >= 100) return "Highest since " + since
    if (percentile < 5) return "Near the lowest since " + since
    if (percentile > 95) return "Near the highest since " + since
    return "Higher than " + Math.round(percentile) + "% of months since " + since
}

// A guide's label: no more precision than an axis needs.
function axisLabel(value, mode) {
    if (mode === "share") return Number(value).toFixed(1) + "%"
    if (mode === "change") return Math.round(value) + "%"
    if (value === 0) return "$0"
    return Math.abs(value) >= 1e12 ? "$" + Number((value / 1e12).toFixed(2)) + "T" : "$" + Math.round(value / 1e9) + "B"
}
