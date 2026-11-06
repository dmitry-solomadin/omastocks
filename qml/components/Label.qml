import QtQuick
import qs.Commons
import qs.Commons as Commons

Text {
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    textFormat: Text.PlainText
    elide: Text.ElideRight
    renderType: Text.NativeRendering
}
