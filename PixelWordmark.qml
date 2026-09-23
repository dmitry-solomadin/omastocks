import QtQuick
import qs.Commons
import "."
import "PixelSprites.js" as Sprites

PixelArt {
    id: root
    objectName: "pixelWordmark"
    pixels: Sprites.wordmark()
    Accessible.ignored: false
    Accessible.role: Accessible.StaticText
    Accessible.name: "Stocks"
    function boot() { build.restart() }
    NumberAnimation { id: build; target: root; property: "reveal"; from: 0; to: 1; duration: 440; easing.type: Easing.OutCubic }
    Component.onCompleted: if (StockStore.windowOpen) boot()
    Connections { target: StockStore; function onWindowOpenChanged() { if (StockStore.windowOpen) root.boot(); else build.stop() } }
}
