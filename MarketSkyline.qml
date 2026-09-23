import QtQuick
import qs.Commons
import "."
import "PixelSprites.js" as Sprites

PixelArt {
    pixels: Sprites.skyline()
    ink: Color.muted
    shade: Color.foreground
    opacity: .3
}
