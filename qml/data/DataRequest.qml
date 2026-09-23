import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property var arguments: []
    property string script: "../../bin/research.py"
    property int refreshInterval: 0
    readonly property string requestKey: JSON.stringify([root.script, root.arguments])
    property var data: ({})
    readonly property bool busy: pending !== null || activeRevision >= 0
    property var pending: null
    property int revision: 0
    property int activeRevision: -1
    property string captured: ""
    property bool exited: false
    property bool collected: false
    // QML can create a new array for the same request when an MA is toggled.
    // Only a different request should discard the already loaded data.
    onRequestKeyChanged: {
        data = ({})
        revision++
        pending = null
        debounce.stop()
        reload(false)
    }
    function reload(force) {
        if (!root.arguments.length) return
        submit(root.arguments, force)
    }
    function submit(args, force) {
        if (!args.length) return
        const forced = force === true || (pending && pending.force && pending.script === root.script
            && JSON.stringify(pending.args) === JSON.stringify(args))
        pending = {args: args.slice(), script: root.script, revision: ++revision, force: !!forced}
        debounce.restart()
    }
    function pump() {
        // Process exit and stdout completion are separate signals. Keep the
        // task active until both arrive, even if the debounce timer fires first.
        if (activeRevision >= 0 || !pending) return
        const task = pending
        pending = null
        activeRevision = task.revision
        captured = ""
        exited = collected = false
        helper.command = ["python3", decodeURIComponent(Qt.resolvedUrl(task.script).toString().replace(/^file:\/\//, ""))]
            .concat(task.args).concat(task.force ? ["--force"] : [])
        helper.running = true
        watchdog.restart()
    }
    function finish() {
        if (!exited || !collected) return
        watchdog.stop()
        if (activeRevision === revision) {
            try { data = JSON.parse(captured) }
            catch (_) { data = {error: "This request could not be completed. Try refreshing.", stale: true} }
        }
        activeRevision = -1
        Qt.callLater(pump)
    }
    property Timer debounce: Timer { interval: 150; onTriggered: root.pump() }
    property Timer poll: Timer {
        interval: root.refreshInterval
        running: root.refreshInterval > 0 && root.arguments.length > 0
        repeat: true
        onTriggered: if (!root.busy) root.reload(false)
    }
    property Timer watchdog: Timer { interval: 45000; onTriggered: helper.running = false }
    property Process helper: Process {
        stdout: StdioCollector { onStreamFinished: { root.captured = text; root.collected = true; root.finish() } }
        onExited: { root.exited = true; root.finish() }
    }
}
