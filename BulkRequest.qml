import QtQuick
import "."

// One semantic request for the whole selection; old replies are rejected by DataRequest.
Item {
    id: root
    visible: false
    property bool active: false
    property string action: "quotes"
    property var symbols: []
    property alias refreshInterval: request.refreshInterval
    readonly property var rows: request.data.rows || ({})
    readonly property var report: request.data
    readonly property bool busy: request.busy
    function reload(force) { request.reload(force) }
    DataRequest {
        id: request
        arguments: root.active && root.symbols.length ? [root.action, Array.from(new Set(root.symbols)).sort().join(",")] : []
    }
}
