pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import ".."
import "../watchlist/WatchlistOrder.js" as Order
import "../market/MarketAssets.js" as Assets
import "../market/MarketClock.js" as Clock

QtObject {
    id: root
    property var entries: []
    property var watchlists: []
    property string activeWatchlist: "default"
    property var favoriteEntries: []
    property string view: "stock"
    readonly property var activeList: watchlists.find(row => row.id === activeWatchlist) || ({})
    readonly property string watchlistName: activeList.name || "Watchlist"
    readonly property string sortMode: activeList.sort || "custom"
    readonly property var watchlistQuotes: entries.reduce((rows, entry) => { rows[entry.symbol] = entry; return rows }, {})
    readonly property var sortedEntries: Order.sorted(entries, watchlistQuotes, sortMode)
    readonly property string watchlistDisplay: ["percent", "change", "marketCap"].indexOf(barSettings.watchlistDisplay) >= 0 ? barSettings.watchlistDisplay : "percent"
    function watchlistMetric(entry) {
        const bulk = watchlistQuotes[entry.symbol] || {}
        return bulk[watchlistDisplay] !== undefined ? bulk[watchlistDisplay] : entry[watchlistDisplay]
    }
    function watchlistMetricText(entry) {
        const value = watchlistMetric(entry)
        if (watchlistDisplay === "marketCap") return compact(value)
        if (watchlistDisplay === "percent") return percent(value)
        return value === null || value === undefined ? "—" : (value >= 0 ? "+" : "−") + financial(Math.abs(value), "perShare", entry.currency || "")
    }
    function setSortMode(mode) {
        if (mode !== sortMode) request(["watchlist", "sort", activeWatchlist, mode])
    }
    // The sidebar, Overview and ticker share the same bulk quote refresh.
    property QtObject watchlistQuotesRequest: QtObject {
        readonly property bool busy: root.busy
        readonly property var data: ({rows: root.watchlistQuotes,
            stale: root.entries.some(row => row.stale),
            error: root.error || (root.entries.find(row => row.error) || {}).error || ""})
        function reload(force) { root.refresh(force) }
    }
    // Next reports for the active list, shared by the sidebar badges and the
    // Watchlist earnings calendar.
    property DataRequest watchlistEarningsRequest: DataRequest {
        arguments: root.windowOpen && root.entries.length
            ? ["calendar-bulk", Array.from(new Set(root.entries.map(row => row.symbol))).sort().join(",")] : []
        refreshInterval: 21600000
    }
    property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property string easternToday: Clock.easternDate(Date.now())
    property Timer todayTimer: Timer {
        interval: 60000; running: root.windowOpen; repeat: true; triggeredOnStart: true
        onTriggered: { root.today = Qt.formatDate(new Date(), "yyyy-MM-dd"); root.easternToday = Clock.easternDate(Date.now()) }
    }
    // A report within the next two weeks, with its distance in calendar days.
    function upcomingEarnings(ticker) {
        const next = ((watchlistEarningsRequest.data.rows || {})[ticker] || {}).next
        if (!next || !next.date || next.date < today) return null
        const days = Math.round((new Date(next.date + "T12:00:00") - new Date(today + "T12:00:00")) / 86400000)
        return days <= 14 ? Object.assign({ days: days }, next) : null
    }
    // Benchmarks, the US session and cross-asset quotes. Its arguments never
    // change once started, so switching watchlists cannot reset it, and a
    // reload keeps showing the previous result until the new one arrives.
    property bool marketStarted: false
    property DataRequest marketQuotesRequest: DataRequest {
        arguments: root.marketStarted ? ["quotes", Assets.symbols().join(",")] : []
        refreshInterval: root.windowOpen ? 300000 : 0
    }
    readonly property var marketQuotes: marketQuotesRequest.data.rows || ({})
    onWindowOpenChanged: {
        if (windowOpen) {
            if (marketStarted) marketQuotesRequest.reload(false)
            marketStarted = true
        } else {
            marketRetries = 0
            marketRetryTimer.stop()
        }
    }
    // Force a reload 5 s after each scheduled session change. If the provider
    // still reports the old session, retry every 15 s up to four times; the cap
    // also covers holidays, when the schedule and the provider disagree.
    property int marketRetries: 0
    property Timer marketBoundaryTimer: Timer {
        running: root.windowOpen && root.marketStarted
        onRunningChanged: if (running) interval = Clock.nextBoundary(Date.now()) + 5000
        onTriggered: {
            root.marketRetries = 4
            root.marketQuotesRequest.reload(true)
            interval = Clock.nextBoundary(Date.now()) + 5000
            restart()
        }
    }
    property Timer marketRetryTimer: Timer { interval: 15000; onTriggered: if (root.windowOpen) root.marketQuotesRequest.reload(true) }
    property Connections marketBoundaryCheck: Connections {
        target: root.marketQuotesRequest
        function onDataChanged() {
            if (!root.windowOpen || root.marketRetries <= 0) return
            root.marketRetries--
            const reported = Clock.normalize((root.marketQuotes["^SPX"] || {}).marketState)
            if (reported === Clock.scheduled(Date.now())) root.marketRetries = 0
            else if (root.marketRetries > 0) root.marketRetryTimer.restart()
        }
    }
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
    readonly property var favorites: favoriteEntries
    readonly property var quote: {
        const entry = entries.find(entry => entry.symbol === selected)
        if (entry) return entry
        return previewQuotes[selected] || {symbol: selected}
    }
    readonly property bool tracked: entries.some(entry => entry.symbol === selected)
    function isNonCompany(ticker) {
        const entry = entries.find(row => row.symbol === ticker) || previewQuotes[ticker] || {}
        const detail = chart.symbol === ticker ? chart : {}
        const result = results.find(row => row.symbol === ticker) || {}
        const type = detail.instrumentType || entry.instrumentType || result.type || ""
        // Indexes, futures, crypto and currencies have no company research.
        return type ? ["INDEX", "FUTURE", "CRYPTOCURRENCY", "CURRENCY"].indexOf(type.toUpperCase()) >= 0
            : /^\^|=[FX]$|-USD$/.test(ticker)
    }
    readonly property bool selectedIsNonCompany: isNonCompany(selected)
    readonly property bool starred: entries.some(entry => entry.symbol === selected && entry.favorite)
    readonly property var visibleChart: chart.symbol === selected && chart.range === period ? chart : ({})
    readonly property bool chartBusy: busy && (!visibleChart.points || !visibleChart.points.length)
    property var chartColors: []
    // Financial direction must retain its meaning across all theme palettes.
    readonly property color gain: "#4caf50"
    readonly property color loss: "#ef5350"
    signal openRequested()
    signal stockAdded(string ticker)

    function start() {
        if (running) return
        running = true
        request(["snapshot"])
        refresh(false)
    }
    function stop() {
        running = false
        quoteRetry.stop()
        windowOpen = false
        queue = []
        search("")
    }

    function direction(value) { return value === null || value === undefined ? Tone.muted : value < 0 ? loss : gain }
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
        view = "stock"
        selected = ticker
        if (!entries.some(entry => entry.symbol === ticker)) request(["quote", ticker])
        if (windowOpen) request(["chart", ticker, period])
    }
    // Opens the window on a stock, e.g. from the bar's favorites ticker.
    function show(ticker) {
        openRequested()
        select(ticker)
    }
    function range(value) { period = value; if (selected) request(["chart", selected, value]) }
    function refresh(force) {
        if (force && windowOpen) MarketStore.refresh(true)
        request(force ? ["refresh", "--force"] : ["refresh"])
        if (selected && windowOpen && view === "stock" && !tracked) request(["quote", selected])
        if (selected && windowOpen && view === "stock") request(force ? ["chart", selected, period, "--force"] : ["chart", selected, period])
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
    // Leaving the list keeps the selected stock's page showing its last quote.
    function keepPreview(ticker) {
        if (ticker !== selected) return
        const quotes = Object.assign({}, previewQuotes)
        quotes[selected] = quote
        previewQuotes = quotes
    }
    function remove(ticker) {
        ticker = ticker || selected
        const index = entries.findIndex(entry => entry.symbol === ticker)
        if (index < 0) return
        const entry = entries[index]
        keepPreview(ticker)
        // Undo restores the stock, its star and its place in the custom order.
        lastRemoved = { symbol: ticker, name: entry.name || ticker, favorite: entry.favorite === true,
            before: index + 1 < entries.length ? entries[index + 1].symbol : "", list: activeWatchlist }
        undoTimer.restart()
        request(["remove", ticker])
    }
    property var lastRemoved: null
    property Timer undoTimer: Timer { interval: 8000; onTriggered: root.lastRemoved = null }
    function undoRemove() {
        const removed = lastRemoved
        if (!removed) return
        lastRemoved = null
        undoTimer.stop()
        request(["add", removed.symbol, removed.name, removed.favorite ? "true" : "", "--list", removed.list])
        // Put it back before its old neighbour, when that stock is still listed.
        if (removed.before && (removed.list !== activeWatchlist || entries.some(entry => entry.symbol === removed.before)))
            request(["move", removed.symbol, removed.before, "--list", removed.list])
        request(["refresh"])
    }
    function transfer(ticker, target) {
        if (!entries.some(entry => entry.symbol === ticker) || target === activeWatchlist) return
        keepPreview(ticker)
        request(["transfer", ticker, target])
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
        if (sortMode !== "custom") return
        const ordered = movedEntries(entries, ticker, before)
        if (ordered.every((entry, index) => entry.symbol === entries[index].symbol)) return
        entries = ordered
        request(["move", ticker, before])
    }
    function request(args) {
        if (["add", "remove", "favorite", "move", "transfer"].indexOf(args[0]) >= 0 && args.indexOf("--list") < 0)
            args = args.concat(["--list", activeWatchlist])
        // Supersede reads, but preserve every watchlist mutation in order.
        let pending = queue.slice()
        if (["chart", "quote", "search", "refresh", "retry-quotes"].indexOf(args[0]) >= 0)
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
        helper.command = ["python3", decodeURIComponent(Qt.resolvedUrl("../../bin/stocks.py").toString().replace(/^file:\/\//, ""))].concat(active)
        helper.running = true
        watchdog.restart()
    }
    property string captured: ""
    property bool exited: false
    property bool collected: false
    property int quoteTransportFailures: 0
    function scheduleQuoteRetry(deadline) {
        quoteRetry.stop()
        if (deadline && running) {
            quoteRetry.interval = Math.max(1000, Math.min(2147483647, deadline * 1000 - Date.now()))
            quoteRetry.restart()
        }
    }
    function finish() {
        if (!exited || !collected || !active) return
        watchdog.stop()
        let quoteReply = false
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
                    quoteReply = true
                    quoteTransportFailures = 0
                    scheduleQuoteRetry(data.quoteRetryAfter)
                    const changedList = data.activeWatchlist && data.activeWatchlist !== activeWatchlist
                    if (data.watchlists) watchlists = data.watchlists
                    if (data.activeWatchlist) activeWatchlist = data.activeWatchlist
                    if (data.favoriteEntries) favoriteEntries = data.favoriteEntries
                    // A reply started before a drop must not undo optimistic moves.
                    entries = queue.filter(args => args[0] === "move").reduce(
                        (rows, args) => args[args.length - 1] === activeWatchlist ? movedEntries(rows, args[1], args[2]) : rows, data.entries)
                    if (changedList) {
                        selected = entries.length ? entries[0].symbol : ""
                        search("")
                        if (selected && windowOpen) request(["chart", selected, period])
                        request(["refresh"])
                    } else if (!selected && entries.length) select(entries[0].symbol)
                }
                if (data.chart && data.chart.symbol === selected && data.chart.range === period) chart = data.chart
                if (data.quote) {
                    const quotes = Object.assign({}, previewQuotes)
                    quotes[data.quote.symbol] = data.quote
                    previewQuotes = quotes
                }
                if (active[0] === "add" && active[active.length - 1] === activeWatchlist && entries.some(entry => entry.symbol === active[1])) {
                    search("")
                    select(active[1])
                    stockAdded(active[1])
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
        // A killed/timed-out helper has no backend deadline. Keep recovery
        // alive even when it could not serialize its saved quote results.
        if (!quoteReply && ["snapshot", "refresh", "retry-quotes"].indexOf(active[0]) >= 0) {
            quoteTransportFailures = Math.min(quoteTransportFailures + 1, 10)
            scheduleQuoteRetry(Date.now() / 1000 + Math.min(300, Math.pow(2, quoteTransportFailures - 1)))
        }
        active = null
        Qt.callLater(pump)
    }
    property Process helper: Process {
        stdout: StdioCollector { onStreamFinished: { root.captured = text; root.collected = true; root.finish() } }
        onExited: { root.exited = true; root.finish() }
    }
    property Timer watchdog: Timer { interval: 60000; onTriggered: root.helper.running = false }
    property Timer quoteRetry: Timer { onTriggered: root.request(["retry-quotes"]) }
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
