import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."
import "MarketAssets.js" as Assets

// Futures, commodities, crypto, rates and currencies at a glance. Quotes come
// from the shared market request, so they refresh in the background and never
// blank while reloading. A row opens the instrument in the Stock view.
GridLayout {
    id: root
    objectName: "crossAssets"
    columns: width >= Style.space(820) ? 4 : 2
    columnSpacing: Style.space(24)
    rowSpacing: Style.space(18)
    readonly property var report: StockStore.marketQuotesRequest.data

    function change(asset, quote) {
        if (asset.format === "yield") {
            if (!Number.isFinite(quote.change)) return "—"
            return (quote.change >= 0 ? "+" : "−") + Math.abs(quote.change * 100).toFixed(1) + " bp"
        }
        return StockStore.percent(quote.percent)
    }

    Repeater {
        model: Assets.groups
        ColumnLayout {
            id: group
            required property var modelData
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 1
            spacing: Style.space(2)
            Label {
                text: group.modelData.title.toUpperCase()
                color: Color.muted
                font.pixelSize: Style.font.bodySmall
                Layout.fillWidth: true
                Layout.bottomMargin: Style.space(4)
                HoverHandler { id: titleHover; enabled: !!group.modelData.note }
                Ui.PanelToolTip { visible: titleHover.hovered; text: group.modelData.note || "" }
            }
            Repeater {
                model: group.modelData.assets
                Rectangle {
                    id: row
                    required property var modelData
                    readonly property var quote: StockStore.marketQuotes[modelData.symbol] || {}
                    Layout.fillWidth: true
                    implicitHeight: lines.implicitHeight + Style.space(12)
                    radius: Style.cornerRadius
                    color: rowMouse.containsMouse ? Util.alpha(Color.foreground, .05) : "transparent"
                    ColumnLayout {
                        id: lines
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.space(6)
                        anchors.rightMargin: Style.space(6)
                        spacing: Style.space(3)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Label { text: row.modelData.name; Layout.fillWidth: true; font.pixelSize: Style.font.bodySmall }
                            Label {
                                text: root.change(row.modelData, row.quote)
                                color: StockStore.direction(row.modelData.format === "yield" ? row.quote.change : row.quote.percent)
                                font.pixelSize: Style.font.bodySmall
                            }
                        }
                        Label { text: Assets.price(row.modelData, row.quote.price); color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: StockStore.select(row.modelData.symbol)
                    }
                    Ui.PanelToolTip {
                        visible: rowMouse.containsMouse
                        text: root.report.error || row.quote.error
                            || "Open " + row.modelData.symbol + (row.quote.updated ? " · " + Qt.formatDateTime(new Date(row.quote.updated * 1000), "d MMM hh:mm") : "")
                    }
                }
            }
        }
    }
}
