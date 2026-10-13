pragma Singleton
import QtQuick
import ".."

// Bull and bear case reports, one per stock and agent. A report stays until
// Refresh replaces it; opening one never starts research when it exists.
QtObject {
    id: root
    readonly property bool active: AnalysisStore.enabled && MarketStore.companyResearchActive
    readonly property string preference: AnalysisStore.preference
    readonly property string key: StockStore.selected + ":" + preference
    property var saved: ({})
    readonly property var report: request.data.symbol === StockStore.selected && request.data.preference === preference ? request.data : saved[key] || ({})
    readonly property bool ready: (report.bull || []).length > 0
    readonly property string error: request.data.error || report.error || ""
    readonly property bool working: request.busy || report.pending === true
    readonly property bool notificationBusy: notificationRequest.busy
    // The copy saved for sharing, for this report only.
    readonly property var exported: exportRequest.data.symbol === StockStore.selected && exportRequest.data.preference === preference
        && (exportRequest.data.error || exportRequest.data.generated === report.generated) ? exportRequest.data : ({})
    signal openRequested()
    signal backgroundRequested()

    function show() {
        if (!active) return
        openRequested()
        if (!ready && !report.pending) generate(false)
    }
    function generate(force) {
        if (!active || report.pending) return
        request.submit(["start", StockStore.selected, preference], force)
    }
    function cancel() {
        if (report.pending && report.job) request.submit(["cancel", StockStore.selected, preference, report.job], false)
    }
    function notifyWhenReady() {
        if (report.pending && report.job && !notificationBusy)
            notificationRequest.submit(["notify", StockStore.selected, preference, report.job], false)
    }
    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/")
    }
    function openInBrowser() {
        if (ready && report.html) Qt.openUrlExternally(fileUrl(report.html))
    }
    function saveCopy() {
        if (ready && !exportRequest.busy) exportRequest.submit(["export", StockStore.selected, preference], false)
    }
    function remember(data) {
        if (data.symbol !== StockStore.selected || data.preference !== preference) return
        saved = Object.assign({}, saved, {[key]: data})
    }
    // Status is a fast local read, never a model call.
    property DataRequest request: DataRequest {
        script: "../../bin/bull_bear.py"
        arguments: root.active ? ["status", StockStore.selected, root.preference] : []
        onDataChanged: root.remember(data)
    }
    property DataRequest notificationRequest: DataRequest {
        script: "../../bin/bull_bear.py"
        onDataChanged: {
            root.remember(data)
            if (data.notifyRequested && data.symbol === StockStore.selected && data.preference === root.preference)
                root.backgroundRequested()
        }
    }
    property DataRequest exportRequest: DataRequest { script: "../../bin/bull_bear.py" }
    property Timer poll: Timer {
        interval: 1500; repeat: true
        running: root.active && root.report.pending === true
        onTriggered: if (!root.request.busy) root.request.reload(false)
    }
}
