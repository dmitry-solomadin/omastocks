import QtQuick
import Quickshell.Io

// One long-lived bin/data_server.py: a JSON line each way, one request at a
// time, over its own kept Yahoo connection. StockStore keeps a few and gives
// each request to a free one. It starts with its first request and reports a
// reply, a death with a request running, or a request stopped after 45 s.
QtObject {
    id: root
    property var active: null
    readonly property bool free: active === null
    signal replied(var args, var reply)
    signal lost(var args)
    signal hung(var args)
    function send(id, args) {
        active = {id: id, args: args}
        watchdog.restart()
        if (process.running) write()
        else process.running = true
    }
    function write() {
        if (!active) return
        const args = active.args
        const request = args[0] === "chart" ? {action: "chart", symbol: args[1], range: args[2]}
            : args[0] === "quote" ? {action: "quote", symbol: args[1]}
            : args[0] === "quotes" ? {action: "quotes", symbols: args.slice(1)} : {action: "search", query: args[1]}
        process.write(JSON.stringify(Object.assign({id: active.id}, request)) + "\n")
    }
    // Only the reply to the running request counts.
    function read(line) {
        let reply
        try { reply = JSON.parse(line) } catch (_) { return }
        if (!active || !reply || reply.id !== active.id) return
        const args = active.args
        watchdog.stop()
        active = null
        replied(args, reply)
    }
    function exited() {
        const args = active && active.args
        active = null
        watchdog.stop()
        if (args) lost(args)
    }
    function timedOut() {
        const args = active.args
        active = null
        process.running = false
        hung(args)
    }
    // Drops its request without a report.
    function stop() {
        active = null
        watchdog.stop()
        process.running = false
    }
    property Process process: Process {
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("../../bin/data_server.py").toString().replace(/^file:\/\//, ""))]
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root.read(data) }
        onStarted: root.write()
        onExited: root.exited()
    }
    property Timer watchdog: Timer { interval: 45000; onTriggered: root.timedOut() }
}
