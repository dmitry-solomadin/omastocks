import QtQuick
import qs.Commons
import ".."

// Explain move, moving averages, extended hours and Compare: occasional tools,
// kept small at the right of the chart's top line rather than on rows of their own.
Row {
    id: root
    objectName: "chartOptions"
    spacing: Style.space(2)
    component SmallButton: ActionButton {
        implicitHeight: Style.space(24)
        padding: Style.space(6)
        implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
        font.pixelSize: Style.font.bodySmall
    }
    AiButton {
        id: explain
        objectName: "explainLatestMove"
        visible: AnalysisStore.enabled && !StockStore.selectedIsNonCompany
        implicitHeight: Style.space(24)
        padding: Style.space(6)
        topPadding: 0
        bottomPadding: 0
        font.pixelSize: Style.font.bodySmall
        text: "Explain move"
        ink: Tone.muted
        ready: !!AnalysisStore.report.summary
        hint: "Research the latest price move with your agent, independently of the chart range"
        onClicked: AnalysisStore.show()
    }
    Label {
        visible: MarketStore.averagesAvailable
        anchors.verticalCenter: parent.verticalCenter
        rightPadding: Style.space(4)
        text: "MA"
        color: Tone.muted
        font.pixelSize: Style.font.bodySmall
    }
    // Daily averages exist from 1M up; shorter ranges leave them out.
    Repeater {
        model: MarketStore.averagesAvailable ? [20, 50, 200] : []
        SmallButton {
            required property int modelData
            objectName: "average_" + modelData
            text: modelData + "D"
            selected: MarketStore.averageWindows.indexOf(modelData) >= 0
            ink: selected ? MarketStore.averageColor(modelData) : Tone.muted
            hint: MarketStore.averages.error || (MarketStore.averagesRequest.busy ? "Loading daily moving averages…"
                : modelData + " trading-day simple moving average")
            onClicked: MarketStore.toggleAverage(modelData)
        }
    }
    Item { visible: MarketStore.averagesAvailable; width: Style.space(10); height: 1 }
    SmallButton {
        objectName: "extendedToggle"
        visible: StockStore.period === "1D"
        text: "Extended"
        // On at once when clicked; the regular chart stays until extended data arrives.
        enabled: !MarketStore.extendedUnavailable(StockStore.selected)
        selected: MarketStore.showExtended && enabled
        ink: selected ? Color.accent : Tone.muted
        // Only a click that found no data explains the greyed-out button.
        hint: MarketStore.extendedRequest.busy ? "Loading extended hours…"
            : MarketStore.noExtended[StockStore.selected] === true && MarketStore.extendedClicked === StockStore.selected
                ? "No extended-hours data for " + StockStore.selected
                : "Include pre-market and after hours in 1D · Shaded regions show extended sessions"
        onClicked: {
            MarketStore.showExtended = !MarketStore.showExtended
            MarketStore.extendedClicked = StockStore.selected
        }
    }
    SmallButton {
        objectName: "compareEnter"
        text: "Compare"
        ink: Tone.muted
        hint: "Compare with up to four other stocks"
        onClicked: MarketStore.compareMode = true
    }
}
