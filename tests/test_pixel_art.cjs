const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")
const load = file => { const context = vm.createContext({}); vm.runInContext(fs.readFileSync(path.join(__dirname, "..", file), "utf8"), context); return context }
const clock = load("qml/market/MarketClock.js")
const sprites = load("qml/art/PixelSprites.js")

// New York wall time → UTC, across both DST regimes.
const et = (y, m, d, h, min, offset) => Date.UTC(y, m - 1, d, h - offset, min)
assert.equal(clock.offsetHours(et(2026, 7, 15, 12, 0, -4)), -4)
assert.equal(clock.offsetHours(et(2026, 1, 15, 12, 0, -5)), -5)
assert.equal(clock.offsetHours(Date.UTC(2026, 2, 8, 6, 59)), -5)
assert.equal(clock.offsetHours(Date.UTC(2026, 2, 8, 7, 0)), -4)
assert.equal(clock.offsetHours(Date.UTC(2026, 10, 1, 5, 59)), -4)
assert.equal(clock.offsetHours(Date.UTC(2026, 10, 1, 6, 0)), -5)

const tuesday = (h, min) => et(2026, 9, 22, h, min, -4)
assert.equal(clock.scheduled(tuesday(3, 59)), "CLOSED")
assert.equal(clock.scheduled(tuesday(4, 0)), "PRE")
assert.equal(clock.scheduled(tuesday(9, 30)), "REGULAR")
assert.equal(clock.scheduled(tuesday(16, 0)), "POST")
assert.equal(clock.scheduled(tuesday(20, 0)), "CLOSED")
assert.equal(clock.scheduled(et(2026, 9, 26, 12, 0, -4)), "CLOSED")

assert.equal(clock.countdown("REGULAR", tuesday(13, 46)), "closes in 2h 14m")
assert.equal(clock.countdown("PRE", tuesday(8, 52)), "opens in 38m")
assert.equal(clock.countdown("POST", tuesday(17, 0)), "opens in 16h 30m")
assert.equal(clock.countdown("CLOSED", et(2026, 9, 25, 20, 30, -4)), "opens Mon 9:30 ET")
// A provider-closed weekday session (holiday) never counts toward a guessed close.
assert.equal(clock.countdown("CLOSED", tuesday(11, 0)), "")
assert.equal(clock.countdown("REGULAR", tuesday(17, 0)), "")
for (const [state, hour] of [["CLOSED", 8], ["PRE", 10], ["POST", 11], ["", 8], ["UNKNOWN", 8]])
    assert.equal(clock.countdown(state, tuesday(hour, 0)), "", state)
assert.equal(clock.position(tuesday(4, 0)), 0)
assert.equal(clock.position(tuesday(12, 0)), .5)
assert.equal(clock.position(tuesday(21, 0)), 1)
assert.equal(clock.position(tuesday(3, 0)), -1)

// Next session change, in ms.
assert.equal(clock.nextBoundary(tuesday(9, 29)), 60000)
assert.equal(clock.nextBoundary(tuesday(9, 30)), 390 * 60000)
assert.equal(clock.nextBoundary(tuesday(20, 0)), 480 * 60000)
assert.equal(clock.nextBoundary(et(2026, 9, 25, 21, 0, -4)), (3 + 48 + 4) * 3600000)
// Weekend countdowns must account for the hour lost/gained on Sunday.
for (const [friday, monday] of [
    [et(2026, 3, 6, 21, 0, -5), et(2026, 3, 9, 4, 0, -4)],
    [et(2026, 10, 30, 21, 0, -4), et(2026, 11, 2, 4, 0, -5)]
]) {
    assert.equal(clock.nextBoundary(friday), monday - friday)
    assert.equal(clock.nextOpen(friday).minutes, (monday + 330 * 60000 - friday) / 60000)
}
assert.equal(clock.normalize("PREPRE"), "PRE")
assert.equal(clock.normalize("POSTPOST"), "POST")
assert.equal(clock.normalize(undefined), "")

const rectangular = rows => rows.every(row => row.length === rows[0].length)
assert.ok(rectangular(sprites.text("+0.84%")))
for (const rising of [true, false]) {
    const walk = sprites.walk(120, 7, rising)
    assert.equal(walk.length, 120)
    assert.equal(walk[0], 0)
    assert.ok(walk.every(value => Math.abs(value) <= 1))
    assert.equal(Math.sign(walk[walk.length - 1]), rising ? 1 : -1)
}
assert.deepEqual(sprites.walk(40, 3, true), sprites.walk(40, 3, true))
console.log("pixel art ok")
