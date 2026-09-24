// Benchmarks and cross-asset quotes for the Market tab. `format` picks how a
// price reads: yields as a percentage, FX to four decimals, the rest as prices.
// Outside the regular session a benchmark with `futures` shows that contract
// instead, since the cash index is frozen at its last close.
var benchmarks = [
    {symbol: "^SPX", name: "S&P 500", futures: {symbol: "ES=F", name: "S&P 500"}},
    {symbol: "^IXIC", name: "Nasdaq", futures: {symbol: "NQ=F", name: "Nasdaq 100"}},
    {symbol: "^DJI", name: "Dow Jones", futures: {symbol: "YM=F", name: "Dow Jones"}},
    {symbol: "^VIX", name: "VIX"}
]
var groups = [
    {title: "Global", note: "Overseas benchmarks; Asia has usually closed by the US open.", assets: [
        {symbol: "^FTSE", name: "FTSE 100"}, {symbol: "^GDAXI", name: "DAX"}, {symbol: "^STOXX50E", name: "Euro Stoxx 50"},
        {symbol: "^N225", name: "Nikkei 225"}, {symbol: "^HSI", name: "Hang Seng"}]},
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

// The instrument a benchmark tile shows: its futures contract when the session
// is known and not regular, else the index itself.
function benchmark(asset, offHours) {
    return offHours && asset.futures ? Object.assign({futures: true}, asset.futures) : asset
}

function symbols() {
    const futures = benchmarks.filter(asset => asset.futures).map(asset => asset.futures)
    return Array.from(new Set(benchmarks.concat(futures, ...groups.map(group => group.assets), volatility, sectors).map(asset => asset.symbol))).sort()
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
