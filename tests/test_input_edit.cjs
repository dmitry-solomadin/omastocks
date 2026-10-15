const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")

const qml = path.join(__dirname, "../qml")
const Qt = {Key_Backspace: 0x01000003, Key_Delete: 0x01000007, Key_A: 0x41,
    ShiftModifier: 0x02000000, ControlModifier: 0x04000000, AltModifier: 0x08000000, MetaModifier: 0x10000000}
const edit = vm.createContext({Qt})
vm.runInContext(fs.readFileSync(path.join(qml, "components/InputEdit.js"), "utf8").replace(".pragma library", ""), edit)
const plain = value => value && {text: value.text, cursor: value.cursor}
const key = (text, start, end, code, modifiers, typed, maximum = 32767) =>
    plain(edit.keyEdit(text, start, end, code, modifiers, typed, maximum))

// Typing replaces the selection and respects the field's maximum length.
assert.deepEqual(key("AM", 2, 2, Qt.Key_A, 0, "D"), {text: "AMD", cursor: 3})
assert.deepEqual(key("AMD", 0, 3, Qt.Key_A, Qt.ShiftModifier, "N"), {text: "N", cursor: 1})
assert.deepEqual(key("abc", 1, 1, Qt.Key_A, 0, "xyz", 4), {text: "axbc", cursor: 2})
assert.equal(key("abcd", 4, 4, Qt.Key_A, 0, "e", 4), null, "A full field takes the key without changing")
// AltGr can arrive as Ctrl+Alt and still types; Ctrl and Ctrl+Shift are shortcuts.
assert.deepEqual(key("", 0, 0, 0x40, Qt.ControlModifier | Qt.AltModifier, "@"), {text: "@", cursor: 1})
assert.equal(key("a", 1, 1, Qt.Key_A, Qt.ControlModifier, "a"), undefined)
assert.equal(key("a", 1, 1, Qt.Key_A, Qt.ControlModifier | Qt.ShiftModifier, "A"), undefined)
// Enter, Escape, Tab and keys without text stay with Qt and the field's handlers.
for (const typed of ["\r", "\x1b", "\t", ""]) assert.equal(key("a", 1, 1, 0, 0, typed), undefined, JSON.stringify(typed))

// Backspace and Delete, by character, by word, and over a selection.
assert.deepEqual(key("AMD", 3, 3, Qt.Key_Backspace, 0, "\b"), {text: "AM", cursor: 2})
assert.equal(key("AMD", 0, 0, Qt.Key_Backspace, 0, "\b"), null, "Backspace at the start changes nothing")
assert.deepEqual(key("AMD", 0, 0, Qt.Key_Delete, 0, ""), {text: "MD", cursor: 0})
assert.equal(key("AMD", 3, 3, Qt.Key_Delete, 0, ""), null)
assert.deepEqual(key("Tech stocks  ", 13, 13, Qt.Key_Backspace, Qt.ControlModifier, ""), {text: "Tech ", cursor: 5})
assert.deepEqual(key("Tech stocks", 0, 0, Qt.Key_Delete, Qt.ControlModifier, ""), {text: " stocks", cursor: 0})
assert.deepEqual(key("Tech stocks", 1, 4, Qt.Key_Backspace, 0, "\b"), {text: "T stocks", cursor: 1})
assert.deepEqual(key("a😀", 3, 3, Qt.Key_Backspace, 0, "\b"), {text: "a", cursor: 1}, "An emoji is one character")
assert.deepEqual(key("😀a", 0, 0, Qt.Key_Delete, 0, ""), {text: "a", cursor: 0})

// Pasted text becomes one line, and length is counted in UTF-8 bytes.
assert.equal(edit.pasteText("  MSFT\r\n"), "MSFT")
assert.equal(edit.pasteText("Big\ntech\tnames\x07"), "Big tech names")
assert.equal(edit.utf8Length("aé€😀"), 1 + 2 + 3 + 4)

// No text input in the plugin may be editable to Qt: InputField is the only one,
// and it stays read-only.
const files = []
const walk = folder => fs.readdirSync(folder, {withFileTypes: true}).forEach(entry =>
    entry.isDirectory() ? walk(path.join(folder, entry.name)) : entry.name.endsWith(".qml") && files.push(path.join(folder, entry.name)))
walk(qml)
const field = path.join(qml, "components/InputField.qml")
for (const file of files) {
    const source = fs.readFileSync(file, "utf8")
    const inputs = source.match(/\b(TextField|TextInput|TextEdit|TextArea)\s*\{/g) || []
    assert.equal(inputs.length, file === field ? 1 : 0, path.relative(qml, file) + " declares a Qt text input")
    assert.doesNotMatch(source, /\breadOnly\s*:(?!\s*true\s*$)/m, path.relative(qml, file) + " changes readOnly")
}
assert.match(fs.readFileSync(field, "utf8"), /^    readOnly: true$/m)
console.log("PASS: input edits, bounded paste text, and no editable Qt text input")
