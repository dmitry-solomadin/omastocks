import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."

ColumnLayout {
    id: root
    objectName: "stockBrief"
    readonly property bool active: StockStore.windowOpen && root.visible && !!StockStore.selected
    readonly property bool expanded: MarketStore.sectionOpen("brief")
    readonly property var report: request.data
    readonly property bool working: request.busy || report.pending === true
    spacing: Style.space(10)
    function source(identity) { return (report.sources || []).find(row => row.id === identity) || ({}) }
    DataRequest {
        id: request
        script: "bin/brief.py"
        arguments: root.active ? ["status", StockStore.selected] : []
    }
    Timer { interval: 1500; running: root.active && root.report.pending === true; repeat: true; onTriggered: if (!request.busy) request.reload(false) }
    RowLayout {
        Layout.fillWidth: true
        ActionButton {
            objectName: "briefMe"
            text: (root.expanded ? "▾ " : "▸ ") + "Brief me"
            hint: "Create a brief from loaded stock data using your default Omarchy agent"
            onClicked: {
                MarketStore.toggleSection("brief")
                if (root.expanded && !(root.report.sections || []).length && !root.report.pending)
                    request.submit(["start", StockStore.selected], false)
            }
        }
        Item { Layout.fillWidth: true }
        ActionButton {
            visible: root.expanded && (root.report.sections || []).length > 0
            text: "↻"
            enabled: !root.working
            hint: "Generate a new brief with your Omarchy agent using the currently loaded data"
            onClicked: request.submit(["start", StockStore.selected], true)
        }
        ActionButton {
            visible: root.expanded && !!root.report.error
            text: "Retry"
            enabled: !root.working
            onClicked: request.submit(["start", StockStore.selected], true)
        }
    }
    ColumnLayout {
        visible: root.expanded
        Layout.fillWidth: true
        spacing: Style.space(12)
        MarketLoading { Layout.fillWidth: true; active: root.working; text: root.report.pending ? "Your " + root.report.agent + " agent is preparing the brief…" : "Preparing brief…" }
        Label {
            visible: !!root.report.error
            text: root.report.error || ""
            color: Color.muted
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        Label {
            visible: !!root.report.generated
            text: "AI brief · " + (root.report.agent || "") + " · Snapshot " + Qt.formatDateTime(new Date((root.report.asOf || 0) * 1000), "d MMM hh:mm")
            font.pixelSize: Style.font.bodySmall
            color: Color.muted
            Layout.fillWidth: true
        }
        Repeater {
            model: root.report.sections || []
            ColumnLayout {
                id: section
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(6)
                Label { text: section.modelData.heading; font.bold: true; Layout.fillWidth: true }
                Repeater {
                    model: section.modelData.points
                    ColumnLayout {
                        id: point
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Style.space(2)
                        Label { text: point.modelData.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Style.space(4)
                            Repeater {
                                model: point.modelData.sources
                                ActionButton {
                                    required property string modelData
                                    readonly property var citation: root.source(modelData)
                                    text: citation.label || modelData
                                    font.pixelSize: Style.font.bodySmall
                                    hint: (citation.stale ? "Saved data · " : "") + (citation.retrieved ? "Retrieved " + Qt.formatDateTime(new Date(citation.retrieved * 1000), "d MMM hh:mm") + "\n" : "") + (citation.url || "")
                                    onClicked: if (/^https?:\/\//.test(citation.url || "")) Qt.openUrlExternally(citation.url)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
