import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

// Compact session chip: pulsing LED, session name and countdown.
RowLayout {
    id: root
    objectName: "marketStatus"
    required property MarketSession session
    readonly property color tone: session.opened ? StockStore.gain : session.state === "PRE" || session.state === "POST" ? Color.foreground : Tone.muted
    spacing: Style.space(8)
    // Caps have no descenders, so centre the dot on the cap height rather than
    // the line box: sit it on the baseline, raised by half the spare cap height.
    FontMetrics { id: metrics; font: statusLabel.font }
    Rectangle {
        id: led
        Layout.alignment: Qt.AlignBaseline
        baselineOffset: height + (metrics.tightBoundingRect("M").height - height) / 2
        implicitWidth: Style.space(6)
        implicitHeight: Style.space(6)
        color: root.tone
        // Pulses from a Timer, not an animation: a looping animation in this window
        // made Qt's animation clock, and so every QML Timer in the shell, run 16%
        // fast (a 10 s Timer fired every 8.6 s).
        readonly property bool pulsing: root.session.opened && root.session.active
        onPulsingChanged: if (!pulsing) opacity = 1
        Timer {
            interval: 33; repeat: true; running: led.pulsing
            onTriggered: led.opacity = .625 + .375 * Math.cos(Date.now() / 1800 * 2 * Math.PI)
        }
    }
    Label {
        id: statusLabel
        Layout.alignment: Qt.AlignBaseline
        text: root.session.status.toUpperCase()
        color: root.tone
        font.bold: true
        font.letterSpacing: Style.space(1)
        font.pixelSize: Style.font.bodySmall
    }
    Label {
        visible: text !== ""
        Layout.alignment: Qt.AlignBaseline
        text: root.session.countdown ? "· " + root.session.countdown : ""
        // Muted text is too faint over the header's sky scene.
        color: Util.alpha(Color.foreground, .7)
        font.pixelSize: Style.font.bodySmall
    }
    HoverHandler { id: hover }
    Ui.PanelToolTip {
        visible: hover.hovered
        text: "US market · New York " + root.session.clock + " ET"
            + "\nPre-market 4:00 · Regular 9:30–16:00 · After hours to 20:00"
            + (root.session.report.fetched ? "\nS&P 500 session checked " + Qt.formatDateTime(new Date(root.session.report.fetched * 1000), "hh:mm") : "")
    }
}
