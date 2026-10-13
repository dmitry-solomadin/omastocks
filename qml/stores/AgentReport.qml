import QtQuick
import ".."

// An AI report on one subject (a stock, or the market), researched by the agent
// chosen in Settings and saved as a shareable HTML page. A report stays until
// Refresh, or until `expired` says its day has passed; opening one starts
// research only when there is none to show.
QtObject {
    id: root
    property string script
    property string subject
    property bool active: false
    // Set by reports that belong to a trading day; an expired one is hidden and
    // the next open researches it again.
    property bool expired: false
    readonly property string preference: AnalysisStore.preference
    readonly property string key: subject + ":" + preference
    property var saved: ({})
    readonly property var rawReport: request.data.symbol === subject && request.data.preference === preference ? request.data : saved[key] || ({})
    readonly property var report: expired ? Object.assign({}, rawReport, {summary: ""}) : rawReport
    readonly property bool ready: !!report.summary
    readonly property string error: request.data.error || report.error || ""
    readonly property bool working: request.busy || report.pending === true
    readonly property bool notificationBusy: notificationRequest.busy
    // The copy saved for sharing, for this report only.
    readonly property var exported: exportRequest.data.symbol === subject && exportRequest.data.preference === preference
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
        request.submit(["start", subject, preference], force || expired)
    }
    function cancel() {
        if (report.pending && report.job) request.submit(["cancel", subject, preference, report.job], false)
    }
    function notifyWhenReady() {
        if (report.pending && report.job && !notificationBusy)
            notificationRequest.submit(["notify", subject, preference, report.job], false)
    }
    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/")
    }
    function openInBrowser() {
        if (ready && report.html) Qt.openUrlExternally(fileUrl(report.html))
    }
    function saveCopy() {
        if (ready && !exportRequest.busy) exportRequest.submit(["export", subject, preference], false)
    }
    function remember(data) {
        if (data.symbol !== subject || data.preference !== preference) return
        saved = Object.assign({}, saved, {[key]: data})
    }
    // Status is a fast local read, never a model call.
    property DataRequest request: DataRequest {
        script: root.script
        arguments: root.active ? ["status", root.subject, root.preference] : []
        onDataChanged: root.remember(data)
    }
    property DataRequest notificationRequest: DataRequest {
        script: root.script
        onDataChanged: {
            root.remember(data)
            if (data.notifyRequested && data.symbol === root.subject && data.preference === root.preference)
                root.backgroundRequested()
        }
    }
    property DataRequest exportRequest: DataRequest { script: root.script }
    property Timer poll: Timer {
        interval: 1500; repeat: true
        running: root.active && root.report.pending === true
        onTriggered: if (!root.request.busy) root.request.reload(false)
    }
}
