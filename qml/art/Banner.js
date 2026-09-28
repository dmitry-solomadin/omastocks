// Pixelated listing logos for the exchange banner. A logo is trimmed to its
// visible pixels (ceremony logos sit on a large transparent canvas), fitted
// into the banner's cell box, and each cell averages the pixels beneath it.

// Banner cloths. A logo whose ink mostly vanishes on the light cloth (a lime
// or white mark) hangs on the dark one instead.
var light = {fill: "#f1ece2", hem: "#d6cdbb", ink: "#1d3a6e", rgb: [241, 236, 226]}
var dark = {fill: "#1c2230", hem: "#10141c", ink: "#f1ece2", rgb: [28, 34, 48]}

// Transparent, or on an opaque image the flat white page some site icons are
// drawn on. A white mark on a transparent canvas is ink.
function empty(data, index, opaque) {
    return data[index + 3] < 32 || (opaque && data[index] > 240 && data[index + 1] > 240 && data[index + 2] > 240)
}

// Visible bounds, sampled on a coarse grid so a 1920px logo stays cheap.
function bounds(width, height, data) {
    const step = Math.max(1, Math.floor(Math.max(width, height) / 480))
    let opaque = true
    for (let y = 0; y < height && opaque; y += step)
        for (let x = 0; x < width; x += step)
            if (data[(y * width + x) * 4 + 3] < 32) { opaque = false; break }
    let left = width, top = height, right = -1, bottom = -1
    for (let y = 0; y < height; y += step)
        for (let x = 0; x < width; x += step) {
            if (empty(data, (y * width + x) * 4, opaque)) continue
            left = Math.min(left, x); right = Math.max(right, x)
            top = Math.min(top, y); bottom = Math.max(bottom, y)
        }
    if (right < 0) return null
    return {x: left, y: top, width: Math.min(width, right + step) - left, height: Math.min(height, bottom + step) - top}
}

// {width, height, cells: [[r, g, b, alpha 0-1] row-major]} or null for a blank
// image. `box` reuses bounds() already measured by the caller.
function pixelate(width, height, data, maxWidth, maxHeight, box) {
    box = box || (width > 0 && height > 0 ? bounds(width, height, data) : null)
    if (!box) return null
    const scale = Math.min(maxWidth / box.width, maxHeight / box.height)
    const columns = Math.max(1, Math.min(maxWidth, Math.round(box.width * scale)))
    const rows = Math.max(1, Math.min(maxHeight, Math.round(box.height * scale)))
    const cells = []
    for (let row = 0; row < rows; row++)
        for (let column = 0; column < columns; column++) {
            const x0 = box.x + Math.floor(column * box.width / columns), x1 = box.x + Math.floor((column + 1) * box.width / columns)
            const y0 = box.y + Math.floor(row * box.height / rows), y1 = box.y + Math.floor((row + 1) * box.height / rows)
            // Up to 8 × 8 samples per cell, weighted by opacity.
            const stepX = Math.max(1, Math.floor((x1 - x0) / 8)), stepY = Math.max(1, Math.floor((y1 - y0) / 8))
            let red = 0, green = 0, blue = 0, weight = 0, count = 0
            for (let y = y0; y < Math.max(y1, y0 + 1); y += stepY)
                for (let x = x0; x < Math.max(x1, x0 + 1); x += stepX) {
                    const index = (y * width + x) * 4, alpha = data[index + 3] / 255
                    red += data[index] * alpha; green += data[index + 1] * alpha; blue += data[index + 2] * alpha
                    weight += alpha; count++
                }
            cells.push(weight ? [Math.round(red / weight), Math.round(green / weight), Math.round(blue / weight), weight / count] : [0, 0, 0, 0])
        }
    return {width: columns, height: rows, cells: cells}
}

// WCAG relative luminance and contrast ratio of [r, g, b] colours.
function luminance(rgb) {
    const channel = value => (value /= 255) <= .03928 ? value / 12.92 : Math.pow((value + .055) / 1.055, 2.4)
    return .2126 * channel(rgb[0]) + .7152 * channel(rgb[1]) + .0722 * channel(rgb[2])
}
function contrast(a, b) {
    const one = luminance(a), two = luminance(b)
    return (Math.max(one, two) + .05) / (Math.min(one, two) + .05)
}

// Share of a logo's ink, by opacity, under 2:1 contrast against a cloth.
function faint(logo, rgb) {
    let hidden = 0, total = 0
    for (const cell of logo.cells) {
        if (cell[3] < .12) continue
        if (contrast(cell, rgb) < 2) hidden += cell[3]
        total += cell[3]
    }
    return total ? hidden / total : 0
}

function cloth(logo) {
    if (!logo) return light
    const onLight = faint(logo, light.rgb)
    return onLight > .5 && faint(logo, dark.rgb) < onLight ? dark : light
}
