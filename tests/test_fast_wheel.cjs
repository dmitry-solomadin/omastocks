const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")

const source = fs.readFileSync(path.join(__dirname, "../qml/components/FastWheel.qml"), "utf8")
const handler = source.match(/onWheel: (event => \{[\s\S]*?\n    \})/)[1]
const Qt = {NoScrollPhase: 0, ScrollBegin: 1, ScrollUpdate: 2, ScrollEnd: 3}

function scroll(phase, pixels, angle, contentY = 500) {
    const flickable = {contentY, originY: 0, contentHeight: 5000, height: 400, cancelFlick() {}}
    const event = {phase, pixelDelta: {y: pixels}, angleDelta: {y: angle}, accepted: false}
    vm.runInNewContext(`(${handler})`, {flickable, Qt, Style: {space: px => px}})(event)
    return {moved: flickable.contentY - contentY, accepted: event.accepted}
}

// A wheel notch takes the full step, whether or not Qt also reports pixels (it does since 6.12).
assert.deepEqual(scroll(Qt.NoScrollPhase, -15, -120), {moved: 96, accepted: true})
assert.deepEqual(scroll(Qt.NoScrollPhase, 0, -120), {moved: 96, accepted: true})
assert.deepEqual(scroll(Qt.NoScrollPhase, 15, 120), {moved: -96, accepted: true})
// High-resolution wheels report part of a notch and move that part of the step.
assert.deepEqual(scroll(Qt.NoScrollPhase, -8, -60), {moved: 48, accepted: true})

// A touchpad follows the fingers exactly.
assert.deepEqual(scroll(Qt.ScrollUpdate, -40, -480), {moved: 40, accepted: true})

// Phase markers carry no movement and stay with Qt.
assert.deepEqual(scroll(Qt.ScrollBegin, 0, 0), {moved: 0, accepted: false})
assert.deepEqual(scroll(Qt.ScrollEnd, 0, 0), {moved: 0, accepted: false})

// A step stops at either end of the content.
assert.deepEqual(scroll(Qt.NoScrollPhase, 15, 120, 50), {moved: -50, accepted: true})
assert.deepEqual(scroll(Qt.NoScrollPhase, -15, -120, 4550), {moved: 50, accepted: true})

console.log("FastWheel tests passed")
