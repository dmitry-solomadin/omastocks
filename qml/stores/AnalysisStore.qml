pragma Singleton
import QtQuick
import ".."

QtObject {
    id: root
    readonly property bool active: MarketStore.companyResearchActive
    readonly property string preference: ["default", "claude", "codex", "opencode"].indexOf(StockStore.barSettings.analysisAgent) >= 0
        ? StockStore.barSettings.analysisAgent : "default"
    readonly property string key: StockStore.selected + ":" + preference
    property var saved: ({})
    readonly property var rawReport: request.data.symbol === StockStore.selected && request.data.preference === preference ? request.data : saved[key] || ({})
    readonly property bool sessionExpired: expiredSession(rawReport, StockStore.quote, now)
    readonly property var report: sessionExpired ? Object.assign({}, rawReport, {summary: "", sources: [], sentences: []}) : rawReport
    readonly property string error: request.data.error || report.error || ""
    readonly property bool working: request.busy || report.pending === true
    signal openRequested()
    signal backgroundRequested()
    readonly property bool notificationBusy: notificationRequest.busy
    property double now: Date.now() / 1000
    readonly property bool stale: !!report.summary && (report.stale === true || now - (report.generated || 0) >= 900 || contextChanged(report, StockStore.quote))

    function expiredSession(result, quote, timestamp) {
        const captured = result.asOf || result.generated || 0
        return !!captured && quote.sessionStart > captured && quote.sessionStart <= timestamp
    }
    function contextChanged(result, quote) {
        const session = result.session || {}
        const extended = StockStore.extendedQuote(quote)
        const kind = extended ? (extended.label === "Pre-market" ? "pre-market" : "after-hours") : "regular"
        const updated = extended ? extended.updated : quote.updated
        const percent = extended ? extended.percent : quote.percent
        return kind !== session.kind || updated - (session.updated || 0) > 21600
            || (Number.isFinite(percent) && Number.isFinite(session.percent) && Math.abs(percent - session.percent) >= 2)
    }
    function show() {
        if (!active) return
        openRequested()
        if (!report.summary && !report.pending) generate(false)
    }
    function generate(force) {
        if (!active || report.pending) return
        request.submit(["start", StockStore.selected, preference], force || sessionExpired)
    }
    function cancel() {
        if (report.pending && report.job) request.submit(["cancel", StockStore.selected, preference, report.job], false)
    }
    function notifyWhenReady() {
        if (report.pending && report.job && !notificationBusy)
            notificationRequest.submit(["notify", StockStore.selected, preference, report.job], false)
    }
    function remember(data) {
        if (data.symbol !== StockStore.selected || data.preference !== preference) return
        saved = Object.assign({}, saved, {[key]: data})
    }
    // Status is a fast local read, never a model call. Generation is deliberately
    // absent from chart, quote, view and Ctrl+R refresh paths.
    property DataRequest request: DataRequest {
        script: "../../bin/move_analysis.py"
        arguments: root.active ? ["status", StockStore.selected, root.preference] : []
        onDataChanged: root.remember(data)
    }
    // Separate from the selected stock's polling, so switching views cannot
    // discard the notification registration. The worker sends it even if Stocks closes.
    property DataRequest notificationRequest: DataRequest {
        script: "../../bin/move_analysis.py"
        onDataChanged: {
            root.remember(data)
            if (data.notifyRequested && data.symbol === StockStore.selected && data.preference === root.preference)
                root.backgroundRequested()
        }
    }
    property Timer poll: Timer {
        interval: 1500; repeat: true
        running: root.active && root.report.pending === true
        onTriggered: if (!root.request.busy) root.request.reload(false)
    }
    property Timer clock: Timer {
        interval: 30000; running: root.active; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.now = Date.now() / 1000
            if (root.report.summary && !root.report.pending && !root.request.busy)
                root.request.reload(false)
        }
    }
}
