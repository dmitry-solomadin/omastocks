// Squarified treemap: area is proportional to positive, known market cap.
// No minimum weights: small companies are not inflated to fit their labels.
function eligible(row) {
    return typeof row.marketCap === "number" && isFinite(row.marketCap) && row.marketCap > 0
}

function layout(rows, width, height) {
    if (!(width > 0 && height > 0)) return []
    const ordered = rows.filter(eligible).slice().sort((a, b) => b.marketCap - a.marketCap || a.symbol.localeCompare(b.symbol))
    if (!ordered.length) return []
    const maximum = ordered[0].marketCap
    const total = ordered.reduce((sum, row) => sum + row.marketCap / maximum, 0)
    const pending = ordered.map(row => ({entry: row, area: (row.marketCap / maximum) / total * width * height}))
    const result = []
    let x = 0, y = 0, w = width, h = height, index = 0
    function worst(strip, area, side) {
        if (!strip.length || !area || !side) return Infinity
        const largest = strip[0].area, smallest = strip[strip.length - 1].area
        return Math.max(side * side * largest / (area * area), area * area / (side * side * smallest))
    }
    while (index < pending.length && w > 0 && h > 0) {
        const side = Math.min(w, h), strip = [pending[index++]]
        let area = strip[0].area
        while (index < pending.length) {
            const candidate = pending[index]
            if (worst(strip.concat([candidate]), area + candidate.area, side) > worst(strip, area, side)) break
            strip.push(candidate); area += candidate.area; index++
        }
        const vertical = w >= h
        const thickness = index === pending.length ? (vertical ? w : h) : area / side
        let offset = 0
        strip.forEach((cell, position) => {
            const length = position === strip.length - 1 ? side - offset : cell.area / thickness
            result.push({entry: cell.entry, x: x + (vertical ? 0 : offset), y: y + (vertical ? offset : 0),
                width: vertical ? thickness : length, height: vertical ? length : thickness})
            offset += length
        })
        if (vertical) { x += thickness; w = Math.max(0, w - thickness) }
        else { y += thickness; h = Math.max(0, h - thickness) }
    }
    return result
}
