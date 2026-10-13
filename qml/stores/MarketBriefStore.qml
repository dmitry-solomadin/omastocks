pragma Singleton
import QtQuick
import ".."
import "../market/MarketClock.js" as Clock

// The day's market brief, one per agent. It belongs to the New York trading day
// it was written on: once the S&P 500 trades on a later date, it expires and
// the next open researches a new one. Closed days keep the last brief.
AgentReport {
    id: root
    script: "../../bin/market_brief.py"
    subject: "MARKET"
    active: AnalysisStore.enabled && StockStore.windowOpen && StockStore.view === "market"
    expired: staleBrief(rawReport, StockStore.marketQuotes["^SPX"] || ({}))

    function staleBrief(brief, quote) {
        return !!brief.asOf && !!quote.updated && Clock.easternDate(quote.updated * 1000) > Clock.easternDate(brief.asOf * 1000)
    }
}
