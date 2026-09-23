import QtQuick
import qs.Commons

WheelHandler {
    property var flickable
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
        if (!flickable || (!event.angleDelta.y && !event.pixelDelta.y)) { event.accepted = false; return }
        const delta = event.pixelDelta.y || event.angleDelta.y / 120 * Style.space(96)
        const start = flickable.originY || 0
        const end = start + Math.max(0, flickable.contentHeight - flickable.height)
        flickable.cancelFlick()
        flickable.contentY = Math.max(start, Math.min(end, flickable.contentY - delta))
        event.accepted = true
    }
}
