pragma Singleton
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Readable secondary text. Themes define `muted` for subtle accents; on some
// light themes it sits almost on the background (Rosé Pine Dawn: 1.5:1). Keep
// the theme's muted colour when it still reads (3:1, which typical dark themes
// meet), otherwise blend the foreground into the background just enough to
// reach WCAG AA contrast (4.5:1).
QtObject {
    id: root
    readonly property real keep: 3
    readonly property real target: 4.5

    function luminance(color) {
        const channel = value => value <= .03928 ? value / 12.92 : Math.pow((value + .055) / 1.055, 2.4)
        return .2126 * channel(color.r) + .7152 * channel(color.g) + .0722 * channel(color.b)
    }
    function contrast(a, b) {
        const one = luminance(a), two = luminance(b)
        return (Math.max(one, two) + .05) / (Math.min(one, two) + .05)
    }
    function readable(background) {
        if (contrast(Commons.Color.muted, background) >= keep) return Commons.Color.muted
        for (let amount = .45; amount < 1; amount += .05) {
            const blended = Qt.tint(background, Util.alpha(Commons.Color.foreground, amount))
            if (contrast(blended, background) >= target) return blended
        }
        return Commons.Color.foreground
    }

    readonly property bool light: Commons.Color.background.hslLightness > .5
    readonly property color muted: readable(Commons.Color.background)
    // Input and control outlines, which the theme's faint borders leave nearly
    // invisible on light backgrounds.
    readonly property color border: Util.alpha(Commons.Color.foreground, light ? .3 : .12)
    // A soft backdrop that lifts controls off the sky scene behind page headers.
    readonly property color backdrop: Util.alpha(Commons.Color.background, .55)
    readonly property color backdropHovered: Qt.tint(Util.alpha(Commons.Color.background, .7), Util.alpha(Commons.Color.foreground, .07))
}
