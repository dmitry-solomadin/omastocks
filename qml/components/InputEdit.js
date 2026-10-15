.pragma library
// Single-line edits for InputField, which stays read-only to Qt (see there).
// An edit is {text, cursor}, or null when it changes nothing.

// Replaces start..end with `insert`, cut to the field's maximum length.
function replace(text, start, end, insert, maximumLength) {
    insert = insert.slice(0, Math.max(0, maximumLength - (text.length - (end - start))))
    if (start === end && insert === "") return null
    return {text: text.slice(0, start) + insert + text.slice(end), cursor: start + insert.length}
}

// Ctrl+Backspace and Ctrl+Delete reach past spaces, then one word.
function wordEdge(text, position, forward) {
    const inside = () => forward ? position < text.length : position > 0
    const next = () => text.charAt(forward ? position : position - 1)
    while (inside() && /\s/.test(next())) position += forward ? 1 : -1
    while (inside() && /\S/.test(next())) position += forward ? 1 : -1
    return position
}

// A key's edit; undefined when the key is not an edit and Qt or the field's own
// handlers take it: navigation, selection, copy, Enter, Escape and shortcuts.
function keyEdit(text, start, end, key, modifiers, typed, maximumLength) {
    const word = (modifiers & Qt.ControlModifier) !== 0
    if (key === Qt.Key_Backspace || key === Qt.Key_Delete) {
        // Surrogate pairs (emoji) go as one character.
        if (start === end && key === Qt.Key_Backspace)
            start = word ? wordEdge(text, start, false) : start - (/[\uDC00-\uDFFF]/.test(text.charAt(start - 1)) ? 2 : 1)
        else if (start === end)
            end = word ? wordEdge(text, end, true) : end + (/[\uD800-\uDBFF]/.test(text.charAt(end)) ? 2 : 1)
        return replace(text, Math.max(0, start), Math.min(text.length, end), "", maximumLength)
    }
    // Qt's rule for text input (QInputControl::isAcceptableInput): Ctrl and
    // Ctrl+Shift make shortcuts, while AltGr may arrive as Ctrl+Alt.
    const held = modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
    if (!typed || /[\x00-\x1f\x7f]/.test(typed) || held === Qt.ControlModifier || held === (Qt.ControlModifier | Qt.ShiftModifier))
        return undefined
    return replace(text, start, end, typed, maximumLength)
}

// Clipboard text as one line: line breaks and tabs become spaces, other control
// characters go.
function pasteText(value) {
    return value.replace(/\s*[\r\n\t]+\s*/g, " ").replace(/[\x00-\x1f\x7f]/g, "").trim()
}

function utf8Length(value) {
    let bytes = 0
    for (let i = 0; i < value.length; i++) {
        const unit = value.charCodeAt(i)
        // A surrogate pair is four bytes: three for the first unit, one for the second.
        bytes += unit < 0x80 ? 1 : unit < 0x800 ? 2 : unit >= 0xDC00 && unit <= 0xDFFF ? 1 : 3
    }
    return bytes
}
