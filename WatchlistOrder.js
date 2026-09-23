// Display ordering only. The persisted membership order is always Custom.
function sorted(entries, quotes, mode) {
    if (mode === "custom") return entries.slice()
    function numeric(entry) {
        const quote = quotes[entry.symbol] || {}
        const value = mode === "marketCap" ? quote.marketCap
            : Object.prototype.hasOwnProperty.call(quote, mode) ? quote[mode] : entry[mode]
        return typeof value === "number" && isFinite(value) ? value : null
    }
    return entries.slice().sort((a, b) => {
        if (mode === "symbol" || mode === "name") {
            const av = String(mode === "name" ? a.name || a.symbol : a.symbol).toLocaleLowerCase()
            const bv = String(mode === "name" ? b.name || b.symbol : b.symbol).toLocaleLowerCase()
            return av.localeCompare(bv) || a.symbol.localeCompare(b.symbol)
        }
        const av = numeric(a), bv = numeric(b)
        if (av === null) return bv === null ? a.symbol.localeCompare(b.symbol) : 1
        if (bv === null) return -1
        return bv - av || a.symbol.localeCompare(b.symbol)
    })
}
