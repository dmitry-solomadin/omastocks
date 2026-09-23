// Benchmarks and cross-asset quotes for the Market tab. `format` picks how a
// price reads: yields as a percentage, FX to four decimals, the rest as prices.
var benchmarks = [
    {symbol: "^SPX", name: "S&P 500"}, {symbol: "^IXIC", name: "Nasdaq"},
    {symbol: "^DJI", name: "Dow Jones"}, {symbol: "^VIX", name: "VIX"}
]
var groups = [
    {title: "Index futures", note: "Trade nearly around the clock; a read on the next open.", assets: [
        {symbol: "ES=F", name: "S&P 500"}, {symbol: "NQ=F", name: "Nasdaq 100"}, {symbol: "YM=F", name: "Dow"}]},
    {title: "Commodities", assets: [
        {symbol: "GC=F", name: "Gold"}, {symbol: "SI=F", name: "Silver"}, {symbol: "CL=F", name: "Crude oil"},
        {symbol: "NG=F", name: "Natural gas"}, {symbol: "HG=F", name: "Copper"}]},
    {title: "Crypto", assets: [
        {symbol: "BTC-USD", name: "Bitcoin"}, {symbol: "ETH-USD", name: "Ethereum"}, {symbol: "SOL-USD", name: "Solana"}]},
    {title: "Rates & currencies", assets: [
        {symbol: "^TNX", name: "US 10Y yield", format: "yield"}, {symbol: "^TYX", name: "US 30Y yield", format: "yield"},
        {symbol: "DX-Y.NYB", name: "US dollar index"}, {symbol: "EURUSD=X", name: "EUR/USD", format: "fx"},
        {symbol: "JPY=X", name: "USD/JPY", format: "fx"}]}
]
// VIX term structure, shortest to longest horizon.
var volatility = [
    {symbol: "^VIX9D", name: "9D"}, {symbol: "^VIX", name: "30D"},
    {symbol: "^VIX3M", name: "3M"}, {symbol: "^VIX6M", name: "6M"}
]
// SPDR sector ETFs, keyed to the heatmap's sector values.
var sectors = [
    {symbol: "XLK", name: "Technology", sector: "technology"},
    {symbol: "XLF", name: "Financials", sector: "financial-services"},
    {symbol: "XLY", name: "Consumer cyclical", sector: "consumer-cyclical"},
    {symbol: "XLC", name: "Communication", sector: "communication-services"},
    {symbol: "XLV", name: "Healthcare", sector: "healthcare"},
    {symbol: "XLI", name: "Industrials", sector: "industrials"},
    {symbol: "XLP", name: "Consumer defensive", sector: "consumer-defensive"},
    {symbol: "XLE", name: "Energy", sector: "energy"},
    {symbol: "XLB", name: "Materials", sector: "basic-materials"},
    {symbol: "XLRE", name: "Real estate", sector: "real-estate"},
    {symbol: "XLU", name: "Utilities", sector: "utilities"}
]

function symbols() {
    return Array.from(new Set(benchmarks.concat(...groups.map(group => group.assets), volatility, sectors).map(asset => asset.symbol))).sort()
}

// Sectors that have a daily change, best first.
function rankedSectors(quotes) {
    return sectors.map(sector => Object.assign({}, sector, {percent: (quotes[sector.symbol] || {}).percent}))
        .filter(sector => Number.isFinite(sector.percent)).sort((a, b) => b.percent - a.percent)
}

function price(asset, value) {
    if (value === null || value === undefined || !isFinite(value)) return "—"
    if (asset.format === "yield") return Number(value).toFixed(3) + "%"
    if (asset.format === "fx") return Number(value).toFixed(4)
    return Number(value).toLocaleString(Qt.locale(), "f", 2)
}
