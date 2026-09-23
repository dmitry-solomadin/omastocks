import QtQuick
import qs.Commons
import qs.Ui as Ui
import ".."

Item {
    id: root
    property var metric: null
    property var dates: []
    readonly property var samples: dates.map((day, index) => ({date: day, value: metric ? metric.values[index] : null,
        currency: metric ? metric.currencies[index] : ""})).reverse()
    readonly property var values: samples.filter(sample => sample.value !== null).map(sample => sample.value)
    readonly property real low: Math.min(0, ...values)
    readonly property real high: Math.max(0, ...values)
    readonly property real span: Math.max(.000001, high - low)
    readonly property real plotTop: Style.space(24)
    readonly property real plotHeight: height - plotTop - Style.space(30)
    function valueY(value) { return plotTop + (high - value) / span * plotHeight }
    implicitHeight: Style.space(150)
    Rectangle { x: 0; width: parent.width; y: root.valueY(0); height: 1; color: Util.alpha(Color.foreground, .15) }
    Row {
        anchors.fill: parent
        Repeater {
            model: root.samples
            Item {
                id: bar
                required property var modelData
                width: root.width / Math.max(1, root.samples.length)
                height: root.height
                Rectangle {
                    width: Math.min(Style.space(48), parent.width * .55)
                    x: (parent.width - width) / 2
                    y: bar.modelData.value !== null ? Math.min(root.valueY(0), root.valueY(bar.modelData.value)) : root.valueY(0)
                    height: bar.modelData.value !== null ? Math.max(1, Math.abs(root.valueY(bar.modelData.value) - root.valueY(0))) : 0
                    color: bar.modelData.value < 0 ? StockStore.loss : StockStore.gain
                }
                Label {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    y: 0; font.pixelSize: Style.font.bodySmall
                    text: StockStore.financial(bar.modelData.value, root.metric ? root.metric.kind : "money", bar.modelData.currency)
                }
                Label {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    y: root.height - height; font.pixelSize: Style.font.bodySmall; color: Color.muted
                    text: Qt.formatDate(new Date(bar.modelData.date + "T12:00:00"), "MMM yy")
                }
                HoverHandler { id: hover }
                Ui.PanelToolTip {
                    visible: hover.hovered
                    text: bar.modelData.date + "\n" + StockStore.financial(bar.modelData.value, root.metric ? root.metric.kind : "money", bar.modelData.currency)
                }
            }
        }
    }
}
