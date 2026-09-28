const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")
const context = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "qml/art/Banner.js"), "utf8"), context)

// A width × height RGBA image filled by paint(x, y) → [r, g, b, a].
const image = (width, height, paint) => {
    const data = new Uint8ClampedArray(width * height * 4)
    for (let y = 0; y < height; y++)
        for (let x = 0; x < width; x++) data.set(paint(x, y), (y * width + x) * 4)
    return data
}

// A red mark on a large transparent canvas is trimmed before fitting.
const logo = image(200, 100, (x, y) => x >= 80 && x < 120 && y >= 40 && y < 60 ? [220, 20, 20, 255] : [0, 0, 0, 0])
const trimmed = context.pixelate(200, 100, logo, 8, 8)
assert.equal(trimmed.width, 8)
assert.equal(trimmed.height, 4)
assert.ok(trimmed.cells.every(cell => cell[0] === 220 && cell[3] === 1))

// Flat white pages around site icons are trimmed too; halves keep their colour.
const icon = image(64, 64, (x, y) => x < 16 || x >= 48 || y < 16 || y >= 48 ? [255, 255, 255, 255] : x < 32 ? [0, 0, 200, 255] : [0, 160, 0, 255])
const fitted = context.pixelate(64, 64, icon, 4, 4)
assert.equal(fitted.width, 4)
assert.equal(JSON.stringify(fitted.cells.slice(0, 4).map(cell => cell.slice(0, 3))), "[[0,0,200],[0,0,200],[0,160,0],[0,160,0]]")

// Partly transparent cells keep their colour and report their coverage.
const edge = image(4, 2, x => x < 2 ? [10, 10, 10, 255] : [10, 10, 10, 64])
const covered = context.pixelate(4, 2, edge, 1, 1)
assert.equal(covered.cells.length, 1)
assert.equal(covered.cells[0][0], 10)
assert.ok(covered.cells[0][3] > .6 && covered.cells[0][3] < .7)

// A white mark on a transparent canvas is ink, not page, and hangs on the dark cloth.
const white = context.pixelate(40, 20, image(40, 20, (x, y) => x >= 10 && x < 30 && y >= 5 && y < 15 ? [255, 255, 255, 255] : [0, 0, 0, 0]), 8, 8)
assert.equal(white.width, 8)
assert.equal(context.cloth(white), context.dark)
// Lime vanishes on the light cloth; navy, red and orange marks keep it.
const solid = rgb => context.pixelate(4, 4, image(4, 4, () => rgb.concat(255)), 2, 2)
assert.equal(context.cloth(solid([204, 255, 0])), context.dark)
assert.equal(context.cloth(solid([29, 58, 110])), context.light)
assert.equal(context.cloth(solid([230, 0, 40])), context.light)
assert.equal(context.cloth(solid([240, 138, 36])), context.light)
assert.equal(context.cloth(null), context.light)

// Nothing visible: no logo.
assert.equal(context.pixelate(10, 10, image(10, 10, () => [255, 255, 255, 0]), 4, 4), null)
assert.equal(context.pixelate(0, 0, new Uint8ClampedArray(0), 4, 4), null)
console.log("banner ok")
