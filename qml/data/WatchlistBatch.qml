import QtQuick
import ".."

// Four independent, bounded requests. Switching views rejects obsolete replies.
Item {
    id: root
    visible: false
    property bool active: false
    property string action: ""
    property string parameter: ""
    property var symbols: []
    property var rows: ({})
    property var jobs: []
    property bool force: false
    property int completed: 0
    property string loadedKey: ""
    readonly property string requestKey: JSON.stringify([active, action, parameter, symbols])
    readonly property bool busy: active && completed < symbols.length
    onRequestKeyChanged: resetTimer.restart()
    Timer { id: resetTimer; interval: 0; onTriggered: root.reload(false) }
    Timer {
        id: dispatchTimer
        interval: 0
        onTriggered: { for (let i = 0; i < workers.count; i++) root.assign(workers.itemAt(i)) }
    }
    function reload(forced) {
        dispatchTimer.stop()
        force = forced === true
        if (loadedKey !== requestKey) rows = ({})
        loadedKey = requestKey
        completed = 0
        jobs = active ? symbols.slice() : []
        for (let i = 0; i < workers.count; i++) {
            const worker = workers.itemAt(i)
            worker.ticker = ""
            worker.request.arguments = []
        }
        for (let i = 0; i < workers.count; i++) assign(workers.itemAt(i))
    }
    function assign(worker) {
        if (!active || worker.ticker || !jobs.length) return
        worker.ticker = jobs[0]
        jobs = jobs.slice(1)
        worker.request.arguments = [action, worker.ticker].concat(parameter ? [parameter] : [])
        if (force) worker.request.reload(true)
    }
    Repeater {
        id: workers
        model: 4
        Item {
            id: worker
            property string ticker: ""
            property DataRequest request: DataRequest {
                onDataChanged: {
                    if (!worker.ticker || !Object.keys(data).length) return
                    root.rows = Object.assign({}, root.rows, {[worker.ticker]: data})
                    root.completed++
                    worker.ticker = ""
                    dispatchTimer.restart()
                }
            }
        }
    }
}
