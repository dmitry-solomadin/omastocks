import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."

// Minimal terminal prompt for empty sidebar states. An empty list types and
// erases example tickers, searching echoes the query with ticking dots, and a
// miss leaves the query at a blinking cursor.
ColumnLayout {
    id: root
    objectName: "watchlistEmpty"
    property string mode: "empty"  // empty | searching | nomatch
    property string query: ""
    property string error: ""
    property int frame: 0
    readonly property bool animating: visible && StockStore.windowOpen
    readonly property var demos: ["NVDA", "AAPL", "MSFT", "TSLA", "AMD"]
    // Per example, in frames: type, hold, erase.
    readonly property int demoLength: 5 + 14 + 5
    readonly property string demoText: {
        const word = demos[Math.floor(frame / demoLength) % demos.length], at = frame % demoLength
        return word.slice(0, at < 19 ? Math.min(at, word.length) : Math.max(0, word.length - (at - 19)))
    }
    readonly property bool cursorOn: frame % 8 < 5
    spacing: Style.space(10)
    onModeChanged: frame = 0

    Row {
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.space(6)
        Label { text: ">"; color: Color.accent; font.bold: true }
        Label {
            text: root.mode === "empty" ? root.demoText : root.query.toUpperCase()
            color: root.mode === "nomatch" ? Color.muted : Color.foreground
        }
        Label { visible: root.mode === "searching"; text: ".".repeat(root.frame % 4); color: Color.muted; width: Style.space(18) }
        Rectangle {
            visible: root.mode !== "searching"
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(8)
            height: Style.font.body + Style.space(2)
            color: Color.accent
            opacity: root.cursorOn ? 1 : 0
        }
    }
    Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
        text: root.mode === "empty" ? "No tickers yet · Ctrl K to search"
            : root.mode === "searching" ? "Searching markets"
            : root.error || "No matches · try a company name"
    }
    Timer { interval: root.mode === "searching" ? 220 : 110; running: root.animating; repeat: true; onTriggered: root.frame++ }
}
