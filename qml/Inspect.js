// Text-only UI inspection for development: find items by objectName and read
// the visible text beneath them, so a change can be checked without screenshots.

function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (const child of item.children || []) {
        const found = find(child, name)
        if (found) return found
    }
    return null
}

// Size is ignored: an item that just became visible has none until its layout
// next polishes, which would hide it from a dump taken right after `view`.
function shown(item) {
    return item.visible && item.opacity > 0
}

// One line per visual row: texts whose centers share a y (within 4 px) join
// left to right. `[name]` marks items with an objectName so they can be
// activated; `*` marks bold (selected) text.
function text(root) {
    const pieces = []
    function walk(item) {
        if (!item || !shown(item)) return
        const origin = item.mapToItem(root, 0, 0)
        if (item.objectName && item !== root) pieces.push({x: origin.x, y: origin.y + item.height / 2, text: "[" + item.objectName + "]"})
        if (typeof item.text === "string" && item.text !== "" && item.font !== undefined && !(item.contentItem && item.contentItem.text === item.text))
            pieces.push({x: origin.x, y: origin.y + item.height / 2, text: (item.font.bold ? "*" : "") + item.text.replace(/\s+/g, " ")})
        for (const child of item.children || []) walk(child)
    }
    walk(root)
    pieces.sort((a, b) => a.y - b.y || a.x - b.x)
    const lines = []
    let row = null
    for (const piece of pieces) {
        if (!row || piece.y - row.y > 4) lines.push(row = {y: piece.y, parts: []})
        row.parts.push(piece)
    }
    return lines.map(line => line.parts.sort((a, b) => a.x - b.x).map(part => part.text).join("  ")).join("\n")
}

// Runs an item's `activate()` if it defines one, else a button's `clicked()`.
function activate(item) {
    if (typeof item.activate === "function") item.activate()
    else if (typeof item.clicked === "function") item.clicked()
    else return false
    return true
}
