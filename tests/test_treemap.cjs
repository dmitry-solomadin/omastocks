const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")
const tree = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../Treemap.js"), "utf8"), tree)
const rows = Array.from({length: 50}, (_, i) => ({symbol: `S${i}`, marketCap: 1e12 / (i + 1) ** 2}))
for (const [width, height] of [[534, 450], [1000, 720], [200, 900], [900, 200]]) {
    const cells = tree.layout(rows, width, height)
    assert.equal(cells.length, rows.length)
    const total = rows.reduce((sum, row) => sum + row.marketCap, 0)
    let area = 0
    cells.forEach((cell, index) => {
        assert.ok(cell.width > 0 && cell.height > 0)
        assert.ok(cell.x >= -1e-8 && cell.y >= -1e-8)
        assert.ok(cell.x + cell.width <= width + 1e-8 && cell.y + cell.height <= height + 1e-8)
        assert.ok(Math.abs(cell.width * cell.height / (width * height) - cell.entry.marketCap / total) < 1e-10)
        area += cell.width * cell.height
        cells.slice(index + 1).forEach(other => {
            const overlapW = Math.min(cell.x + cell.width, other.x + other.width) - Math.max(cell.x, other.x)
            const overlapH = Math.min(cell.y + cell.height, other.y + other.height) - Math.max(cell.y, other.y)
            assert.ok(overlapW < 1e-8 || overlapH < 1e-8, "Tiles must not overlap")
        })
    })
    assert.ok(Math.abs(area - width * height) < 1e-6)
    assert.equal(JSON.stringify(cells), JSON.stringify(tree.layout(rows.slice().reverse(), width, height)))
}
assert.equal(tree.layout([{symbol:"A", marketCap:0}, {symbol:"B", marketCap:null}, {symbol:"C", marketCap:NaN}], 100, 100).length, 0)
assert.equal(tree.layout(rows, 0, 100).length, 0)
const single = tree.layout([{symbol:"A", marketCap:1}], 300, 200)[0]
assert.equal(single.width * single.height, 60000)
const large = tree.layout([{symbol:"A", marketCap:1e308}, {symbol:"B", marketCap:1e308}], 100, 100)
assert.equal(large.length, 2)
assert.equal(large[0].width * large[0].height, 5000)
const indexRows = Array.from({length: 2000}, (_, i) => ({symbol: `R${i}`, marketCap: 1e9 / (i + 1)}))
const dense = tree.layout(indexRows, 534, 450)
assert.equal(dense.length, 2000)
const indexTotal = indexRows.reduce((sum, row) => sum + row.marketCap, 0)
dense.forEach(cell => {
    assert.ok(cell.width > 0 && cell.height > 0)
    assert.ok(cell.x + cell.width <= 534 + 1e-8 && cell.y + cell.height <= 450 + 1e-8)
    assert.ok(Math.abs(cell.width * cell.height / (534 * 450) - cell.entry.marketCap / indexTotal) < 1e-10)
})
console.log("PASS: market-cap areas, complete coverage, no overlap, responsive geometry, stable order and missing caps")
