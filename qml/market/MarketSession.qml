import QtQuick
import qs.Commons
import ".."
import "MarketClock.js" as Clock

// US session state shared by MarketStatus and MarketSky. The provider's
// marketState decides the session; the clock only positions and counts down.
QtObject {
    id: root
    property bool active: false
    property double now: Date.now()
    readonly property var report: StockStore.marketQuotesRequest.data
    readonly property var quote: StockStore.marketQuotes["^SPX"] || {}
    readonly property bool fresh: !!report.fetched && !report.stale && !report.error && now / 1000 - report.fetched < 1200
    readonly property string raw: fresh ? (quote.marketState || "") : ""
    readonly property string reported: Clock.normalize(raw)
    // Background checks never blank the chip: while a reload is in flight the
    // last reported session stays up. Loading shows only before the first result.
    property string held: ""
    onReportedChanged: if (reported) held = reported
    readonly property string state: reported || (StockStore.marketQuotesRequest.busy ? held : "")
    readonly property bool opened: state === "REGULAR"
    readonly property string status: opened ? "Market open" : state === "PRE" ? "Pre-market" : state === "POST" ? "After hours"
        : state === "CLOSED" ? "Market closed" : StockStore.marketQuotesRequest.busy ? "Checking market…" : "Status unavailable"
    readonly property string countdown: state ? Clock.countdown(state, now) : ""
    // 0..1 through the 04:00–20:00 ET day, -1 before it or at weekends.
    readonly property real position: Clock.position(now)
    readonly property string clock: {
        const minutes = Math.floor(Clock.eastern(now).minutes)
        return Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0")
    }
    property string previousState: ""
    // Emitted when a known non-regular session turns regular.
    signal opening()
    onStateChanged: {
        if (!state) return
        if (previousState && previousState !== "REGULAR" && opened) opening()
        previousState = state
    }
    property Timer clockTimer: Timer { interval: 30000; running: root.active; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() }
}
