pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

QtObject {
    id: root
    property var entries: []
    property var results: []
    property string searchQuery: ""
    property string completedQuery: ""
    property string searchError: ""
    readonly property bool searching: searchQuery !== "" && completedQuery !== searchQuery
    property string selected: ""
    property string period: "1D"
    property var chart: ({})
    property var previewQuotes: ({})
    property string error: ""
    property var queue: []
    property var active: null
    property bool windowOpen: false
    property var barSettings: ({})
    property bool running: false
    readonly property bool busy: active !== null || queue.length > 0
    readonly property var favorites: entries.filter(entry => entry.favorite)
    readonly property var quote: {
        const entry = entries.find(entry => entry.symbol === selected)
        if (entry) return entry
        return previewQuotes[selected] || {symbol: selected}
    }
    readonly property bool tracked: entries.some(entry => entry.symbol === selected)
    readonly property bool starred: entries.some(entry => entry.symbol === selected && entry.favorite)
    readonly property var visibleChart: chart.symbol === selected && chart.range === period ? chart : ({})
    readonly property bool chartBusy: busy && (!visibleChart.points || !visibleChart.points.length)
    property var chartColors: []
    // Financial direction must retain its meaning across all theme palettes.
    readonly property color gain: "#4caf50"
    readonly property color loss: "#ef5350"
    signal openRequested()

    function start() {
        if (running) return
        running = true
        request(["snapshot"])
        refresh(false)
    }
    function stop() {
        running = false
        windowOpen = false
        queue = []
        search("")
    }

    function direction(value) { return value === null || value === undefined ? Color.muted : value < 0 ? loss : gain }
    function price(value) {
        return value === undefined || value === null || !isFinite(value) ? "—" : Number(value).toLocaleString(Qt.locale(), 'f', 2)
    }
    function percent(value) {
        return value === undefined || value === null ? "—" : (value >= 0 ? "+" : "") + Number(value).toFixed(2) + "%"
    }
    function revenue(value, currency) {
        if (value === undefined || value === null || !isFinite(value)) return "—"
        return (currency === "USD" ? "$" : currency ? currency + " " : "") + compact(value)
    }
    function compact(value) {
        if (value === undefined || value === null) return "—"
        if (Math.abs(value) >= 1e12) return (value / 1e12).toFixed(2) + "T"
        if (Math.abs(value) >= 1e9) return (value / 1e9).toFixed(2) + "B"
        if (Math.abs(value) >= 1e6) return (value / 1e6).toFixed(2) + "M"
        return Number(value).toLocaleString(Qt.locale(), 'f', 0)
    }
    function financial(value, kind, currency) {
        if (value === null || value === undefined || !isFinite(value)) return "—"
        if (kind === "percent") return Number(value).toFixed(2) + "%"
        if (kind === "ratio") return Number(value).toFixed(2) + "×"
        const unit = currency === "USD" ? "$" : currency ? currency + " " : ""
        return unit + (kind === "perShare" ? price(value) : compact(value))
    }
    function select(ticker) {
        selected = ticker
        if (!entries.some(entry => entry.symbol === ticker)) request(["quote", ticker])
        request(["chart", ticker, period])
    }
    function range(value) { period = value; if (selected) request(["chart", selected, value]) }
    function refresh(force) {
        if (force && windowOpen) MarketStore.refresh(true)
        request(force ? ["refresh", "--force"] : ["refresh"])
        if (selected && windowOpen && !tracked) request(["quote", selected])
        if (selected && windowOpen) request(force ? ["chart", selected, period, "--force"] : ["chart", selected, period])
    }
    function search(value) {
        const query = value.trim()
        if (query === searchQuery) return
        searchTimer.stop()
        queue = queue.filter(args => args[0] !== "search")
        searchQuery = query
        completedQuery = ""
        searchError = ""
        results = []
        if (query) searchTimer.restart()
    }
    function adding(ticker) {
        return (active !== null && active[0] === "add" && active[1] === ticker)
            || queue.some(args => args[0] === "add" && args[1] === ticker)
    }
    function add(ticker, name) {
        ticker = ticker || selected
        if (!ticker || entries.some(entry => entry.symbol === ticker) || adding(ticker)) return
        request(["add", ticker, name || (ticker === selected ? quote.name : "") || ticker])
        request(["refresh"])
    }
    function remove() {
        const quotes = Object.assign({}, previewQuotes)
        quotes[selected] = quote
        previewQuotes = quotes
        request(["remove", selected])
    }
    function movedEntries(rows, ticker, before) {
        const entry = rows.find(row => row.symbol === ticker)
        if (!entry || ticker === before || (before && !rows.some(row => row.symbol === before))) return rows
        const ordered = rows.filter(row => row.symbol !== ticker)
        const index = before ? ordered.findIndex(row => row.symbol === before) : ordered.length
        ordered.splice(index, 0, entry)
        return ordered
    }
    function move(ticker, before) {
        const ordered = movedEntries(entries, ticker, before)
        if (ordered.every((entry, index) => entry.symbol === entries[index].symbol)) return
        entries = ordered
        request(["move", ticker, before])
    }
    function request(args) {
        // Supersede reads, but preserve every watchlist mutation in order.
        let pending = queue.slice()
        if (["chart", "quote", "search", "refresh"].indexOf(args[0]) >= 0)
            pending = pending.filter(item => item[0] !== args[0])
        pending.push(args)
        queue = pending
        pump()
    }
    function pump() {
        if (!running || active || !queue.length) return
        active = queue[0]
        queue = queue.slice(1)
        captured = ""
        exited = false
        collected = false
        helper.command = ["python3", Qt.resolvedUrl("bin/stocks.py").toString().replace(/^file:\/\//, "")].concat(active)
        helper.running = true
        watchdog.restart()
    }
    property string captured: ""
    property bool exited: false
    property bool collected: false
    function finish() {
        if (!exited || !collected || !active) return
        watchdog.stop()
        try {
            const data = JSON.parse(captured)
            if (active[0] === "search") {
                // A reply for an older query must never replace the current results.
                if (active[1] === searchQuery) {
                    results = data.results || []
                    searchError = data.error || ""
                    completedQuery = searchQuery
                }
            } else if (data.error) {
                error = data.error
                if (active[0] === "move") request(["snapshot"])
            }
            else {
                if (active[0] !== "snapshot") error = ""
                if (data.entries) {
                    // A reply started before a drop must not undo optimistic moves.
                    entries = queue.filter(args => args[0] === "move").reduce(
                        (rows, args) => movedEntries(rows, args[1], args[2]), data.entries)
                    if (!selected && entries.length) select(entries[0].symbol)
                }
                if (data.chart && data.chart.symbol === selected && data.chart.range === period) chart = data.chart
                if (data.quote) {
                    const quotes = Object.assign({}, previewQuotes)
                    quotes[data.quote.symbol] = data.quote
                    previewQuotes = quotes
                }
            }
        } catch (exception) {
            if (active[0] === "search") {
                if (active[1] === searchQuery) {
                    searchError = "Search did not return a valid response. Try again."
                    completedQuery = searchQuery
                }
            } else {
                error = "The data helper did not return a valid response. Try refreshing."
                if (active[0] === "move") request(["snapshot"])
            }
        }
        active = null
        Qt.callLater(pump)
    }
    property Process helper: Process {
        stdout: StdioCollector { onStreamFinished: { root.captured = text; root.collected = true; root.finish() } }
        onExited: { root.exited = true; root.finish() }
    }
    property Timer watchdog: Timer { interval: 60000; onTriggered: root.helper.running = false }
    property Timer poll: Timer { interval: 300000; running: root.running; repeat: true; onTriggered: root.refresh(false) }
    property Timer searchTimer: Timer { interval: 300; onTriggered: root.request(["search", root.searchQuery]) }
    property FileView palette: FileView {
        path: Color.currentThemePath + "/colors.toml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const values = {}
            // Theme lines: green = '#a6e3a1', or color2 = "#a6e3a1".
            text().split("\n").forEach(line => {
                const match = line.match(/^\s*([\w-]+)\s*=\s*["']?(#[0-9a-fA-F]{6})/)
                if (match) values[match[1]] = match[2]
            })
            root.chartColors = [values.blue || values.color4 || "", values.yellow || values.color3 || "",
                values.magenta || values.color5 || "", values.cyan || values.color6 || ""]
        }
        onLoadFailed: { root.chartColors = [] }
    }
}
