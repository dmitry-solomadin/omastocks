import QtQuick
import QtQuick.Layouts
import qs.Commons
import ".."

// The day's market brief: what moved markets, then notable movers, each of
// which opens its stock.
ReportPopup {
    id: root
    name: "marketBrief"
    title: "Market brief"
    store: MarketBriefStore
    note: (report.session || {}).phase ? "Written " + report.session.phase : ""

    ColumnLayout {
        objectName: "marketBriefDrivers"
        Layout.fillWidth: true
        spacing: Style.space(14)
        SectionHeading { text: "WHAT MOVED MARKETS" }
        Repeater {
            model: root.report.drivers || []
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(4)
                Label {
                    text: modelData.title
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                CitedText { detail: modelData.detail; cited: modelData.sources; sources: root.sources }
            }
        }
    }
    ColumnLayout {
        objectName: "marketBriefMovers"
        visible: (root.report.movers || []).length > 0
        Layout.fillWidth: true
        spacing: Style.space(10)
        SectionHeading { text: "NOTABLE MOVERS" }
        Repeater {
            model: root.report.movers || []
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(12)
                ActionButton {
                    objectName: "marketBriefMover_" + modelData.symbol
                    text: modelData.symbol
                    hint: "Open " + modelData.symbol
                    ink: Color.accent
                    Layout.alignment: Qt.AlignTop
                    Layout.minimumWidth: Style.space(72)
                    onClicked: {
                        root.close()
                        StockStore.select(modelData.symbol)
                    }
                }
                CitedText {
                    detail: modelData.detail
                    cited: modelData.sources
                    sources: root.sources
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }
}
