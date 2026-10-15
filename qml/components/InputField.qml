import QtQuick
import QtQuick.Controls as Controls
import Quickshell.Io
import qs.Commons
import ".."
import "InputEdit.js" as Edit

// The app's text input: stock search, watchlist names, the comparison ticker. A
// trailing button (such as clear) goes inside and widens `rightPadding`.
//
// The field stays read-only to Qt. On released Qt (6.11, 6.12) an editable
// TextInput reads the whole clipboard text whenever another app changes it, and
// again when the field turns editable (QQuickTextInput::q_canPasteChanged), with
// no size limit or overall deadline, which could stall or swell the shared shell.
// Typing is applied here from key events instead, and paste reads at most
// `pasteLimit` bytes through wl-paste in its own process, stopped after 2 s. Qt
// keeps navigation, selection, copy and Enter, which work read-only. Input methods
// and dead keys need an editable field, so they don't reach this one. Qt draws no
// caret in a read-only field, so the field draws its own.
Controls.TextField {
    id: root
    readOnly: true
    cursorVisible: activeFocus
    property int pasteLimit: 1024
    implicitHeight: Style.space(38)
    color: Color.foreground
    placeholderTextColor: Tone.muted
    selectionColor: Util.alpha(Color.accent, .3)
    selectedTextColor: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    leftPadding: Style.space(12)
    rightPadding: Style.space(12)
    background: Rectangle {
        color: Util.alpha(Color.foreground, .04)
        radius: Style.cornerRadius
        border.width: 1
        border.color: root.activeFocus ? Color.accent : Tone.border
    }
    // Own edits announce themselves as Qt's would, for `onTextEdited` handlers.
    function apply(edit) {
        if (!edit) return
        text = edit.text
        cursorPosition = edit.cursor
        textEdited()
    }
    Keys.onPressed: event => {
        if (event.matches(StandardKey.Paste)) {
            clipboardRead.running = true
        } else if (event.matches(StandardKey.Cut)) {
            if (selectedText) {
                copy()
                apply(Edit.replace(text, selectionStart, selectionEnd, "", maximumLength))
            }
        } else {
            const edit = Edit.keyEdit(text, selectionStart, selectionEnd, event.key, event.modifiers, event.text, maximumLength)
            if (edit === undefined) return
            apply(edit)
        }
        event.accepted = true
    }
    Process {
        id: clipboardRead
        command: ["timeout", "2", "sh", "-c", "wl-paste --no-newline --type text 2>/dev/null | head -c \"$1\"",
            "sh", String(root.pasteLimit + 1)]
        stdout: StdioCollector {
            // A longer clipboard is left out rather than pasted cut short.
            onStreamFinished: if (root.activeFocus && Edit.utf8Length(text) <= root.pasteLimit)
                root.apply(Edit.replace(root.text, root.selectionStart, root.selectionEnd, Edit.pasteText(text), root.maximumLength))
        }
    }
    cursorDelegate: Rectangle {
        id: caret
        property bool blinkOn: true
        width: 1
        color: root.color
        visible: root.activeFocus && blinkOn
        Timer {
            id: blink
            interval: Math.max(100, Qt.styleHints.cursorFlashTime / 2)
            running: root.activeFocus && Qt.styleHints.cursorFlashTime >= 2
            repeat: true
            onTriggered: caret.blinkOn = !caret.blinkOn
        }
        // Moving or typing shows the caret at once, as an editable field does.
        Connections {
            target: root
            function onCursorPositionChanged() { caret.blinkOn = true; blink.restart() }
            function onActiveFocusChanged() { caret.blinkOn = true; blink.restart() }
        }
    }
}
