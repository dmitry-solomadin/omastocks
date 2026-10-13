pragma Singleton
import QtQuick
import ".."

// Bull and bear case reports, one per stock and agent, kept until Refresh.
AgentReport {
    script: "../../bin/bull_bear.py"
    subject: StockStore.selected
    active: AnalysisStore.enabled && MarketStore.companyResearchActive
}
