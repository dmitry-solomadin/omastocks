import QtQuick
import qs.Commons

// A number whose changed characters roll to the new value: up when it rises,
// down when it falls. Characters line up from the right, so the decimals stay
// put when the number gains or loses a digit.
//
// Driven by a Timer against the wall clock, not by an animation: a running
// animation hands Qt's animation clock to the renderer, which once made every
// QML Timer in the shell run 16% fast (see MarketStatus's dot).
Item {
    id: root
    property string text
    // The number itself, for the roll's direction.
    property real value
    // Rolls only while this stays the same; a new stock just shows its price.
    property string key
    property alias font: metrics.font
    property color color: Color.foreground
    property int duration: 400

    // What's on screen: set by settle(), not bound, so a change can be seen
    // against what came before.
    property string shown
    property string previous
    property int direction: 1
    property real progress: 1
    property double startedAt: 0
    property real lastValue
    property string lastKey
    Component.onCompleted: { shown = previous = text; lastValue = value; lastKey = key }

    implicitWidth: row.width
    implicitHeight: metrics.height
    baselineOffset: metrics.ascent

    // Settles once per change, after both the key and the text have moved on.
    onTextChanged: Qt.callLater(settle)
    onKeyChanged: Qt.callLater(settle)
    function settle() {
        if (text === shown && key === lastKey) return
        // Only a number rolls into a number: a placeholder like "—" just swaps.
        const rolls = key === lastKey && /\d/.test(shown) && /\d/.test(text) && value !== lastValue
        previous = rolls ? shown : text
        direction = value < lastValue ? -1 : 1
        shown = text
        lastValue = value
        lastKey = key
        startedAt = Date.now()
        progress = rolls ? 0 : 1
    }

    FontMetrics { id: metrics; font.family: Style.font.family; font.pixelSize: Style.font.body }

    Timer {
        interval: 16; repeat: true; running: root.progress < 1
        onTriggered: {
            const t = Math.min(1, (Date.now() - root.startedAt) / root.duration)
            root.progress = 1 - Math.pow(1 - t, 3)
        }
    }

    Row {
        id: row
        Repeater {
            model: Math.max(root.previous.length, root.shown.length)
            Item {
                id: slot
                // Counted from the right so decimals match up across lengths.
                readonly property int fromRight: Math.max(root.previous.length, root.shown.length) - 1 - index
                readonly property string before: root.previous.charAt(root.previous.length - 1 - fromRight)
                readonly property string after: root.shown.charAt(root.shown.length - 1 - fromRight)
                readonly property bool rolling: before !== after && root.progress < 1
                readonly property real offset: root.direction * height
                width: rolling ? metrics.advanceWidth(before) + (metrics.advanceWidth(after) - metrics.advanceWidth(before)) * root.progress
                               : metrics.advanceWidth(after)
                height: metrics.height
                clip: rolling
                Text {
                    visible: slot.rolling
                    text: slot.before
                    y: -slot.offset * root.progress
                    opacity: 1 - root.progress
                    font: metrics.font; color: root.color; renderType: Text.NativeRendering
                }
                Text {
                    text: slot.after
                    y: slot.rolling ? slot.offset * (1 - root.progress) : 0
                    opacity: slot.rolling ? root.progress : 1
                    font: metrics.font; color: root.color; renderType: Text.NativeRendering
                }
            }
        }
    }
}
