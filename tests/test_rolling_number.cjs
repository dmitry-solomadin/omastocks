const assert = require("node:assert/strict")
const path = require("node:path")
const {load} = require("./qml_harness.cjs")

// A RollingNumber showing 99.95 for AAA; set() changes what it's given and settles.
function number() {
    const context = load(path.join(__dirname, "../qml/components/RollingNumber.qml"), {
        state: {text: "99.95", value: 99.95, key: "AAA", shown: "99.95", previous: "99.95",
            lastValue: 99.95, lastKey: "AAA", direction: 1, progress: 1, startedAt: 0},
        functions: ["settle"],
        globals: {Date: {now: () => 1000}}
    })
    context.set = (text, value, key = context.key) => {
        Object.assign(context, {text, value, key})
        context.settle()
    }
    return context
}

// A rise rolls up from the old number; a fall rolls down.
let n = number()
n.set("100.05", 100.05)
assert.deepEqual([n.previous, n.shown, n.direction, n.progress, n.startedAt], ["99.95", "100.05", 1, 0, 1000])
n.progress = 1
n.set("99.10", 99.10)
assert.deepEqual([n.previous, n.shown, n.direction, n.progress], ["100.05", "99.10", -1, 0])

// A new stock shows its price at once, even when both change together.
n = number()
n.set("412.30", 412.30, "BBB")
assert.deepEqual([n.previous, n.shown, n.progress, n.lastKey], ["412.30", "412.30", 1, "BBB"])

// A placeholder swaps in and out without rolling.
n = number()
n.set("—", 0)
assert.equal(n.progress, 1)
n.set("101.00", 101)
assert.deepEqual([n.previous, n.shown, n.progress], ["101.00", "101.00", 1])

// Nothing new: nothing moves.
n = number()
n.settle()
assert.equal(n.progress, 1)

console.log("rolling number ok")
