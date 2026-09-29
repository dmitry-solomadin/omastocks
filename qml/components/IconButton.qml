import QtQuick
import qs.Commons

// A square toolbar button holding one Nerd Font glyph. Every icon button is the
// same size whatever its glyph's width, and takes its glyphs from one icon set
// (Material Design, U+F0000 and up) so they share a design grid.
ActionButton {
    implicitWidth: Style.space(34)
    implicitHeight: Style.space(34)
    padding: 0
    font.pixelSize: Style.space(18)
}
