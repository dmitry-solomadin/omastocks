import QtQuick
import qs.Commons
import ".."
import "../market/MarketClock.js" as Clock
import "PixelSprites.js" as Sprites
import "Banner.js" as Banner

// Pixel "Wall Street sky" drawn behind a header. The sun crosses the header on
// the New York clock through the 04:00–20:00 trading day: dawn in pre-market,
// daylight and drifting clouds while open, dusk after hours, and a moon with
// stars when closed. The NYSE facade's interior lights and flag follow the
// session; the flag is raised with a burst of confetti when trading opens.
//
// Two canvases on a 3px cell grid: `still` repaints only when the scene, the
// sun's position or the theme changes; `motion` holds the few moving pixels and
// repaints at 15 Hz while visible.
Item {
    id: root
    objectName: "marketSky"
    required property MarketSession session
    readonly property int cell: 3
    readonly property bool lightTheme: Color.background.hslLightness > .5
    // Kept low so header text stays readable, as in the weather panel.
    property real strength: lightTheme ? .7 : .45
    property real t: 0
    property int tick: 0
    property real flag: 1
    property real burst: -1
    readonly property bool running: session.active && visible
    readonly property string phase: session.state || Clock.scheduled(session.now)
    readonly property string scene: phase === "PRE" ? "dawn" : phase === "REGULAR" ? "day" : phase === "POST" ? "dusk" : "night"
    readonly property real sun: Math.max(0, Math.min(1, session.position))
    clip: true
    Accessible.ignored: true

    onRunningChanged: if (running) { tick = 0; fadeIn.restart() } else { raise.stop(); burst = -1 }
    onSceneChanged: { flag = scene === "night" ? 0 : 1; still.requestPaint() }
    onSunChanged: still.requestPaint()
    Connections {
        target: root.session
        function onOpening() { if (root.running) raise.restart() }
    }
    NumberAnimation { id: fadeIn; target: root; property: "t"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: raise
        ScriptAction { script: { root.flag = 0; root.burst = -1 } }
        NumberAnimation { target: root; property: "flag"; to: 1; duration: 1100; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "burst"; from: 0; to: 1; duration: 2200 }
        ScriptAction { script: root.burst = -1 }
    }
    Timer { interval: 66; repeat: true; running: root.running; onTriggered: { root.tick++; motion.requestPaint() } }

    function blend(base, color, amount) { return Qt.tint(base, Qt.rgba(color.r, color.g, color.b, amount)) }
    readonly property color ink: lightTheme ? Color.foreground : "#ffffff"
    readonly property color stone: blend(Color.background, ink, scene === "night" ? .2 : .32)
    readonly property color stoneLight: blend(Color.background, ink, scene === "night" ? .28 : .46)
    readonly property color stoneDark: blend(Color.background, ink, scene === "night" ? .1 : .16)
    readonly property color warm: blend(Color.accent, ink, .3)
    onInkChanged: still.requestPaint()
    onWarmChanged: still.requestPaint()

    // Geometry shared by both canvases, in cells.
    readonly property int cols: Math.ceil(width / cell)
    readonly property int rows: Math.ceil(height / cell)
    readonly property int facadeWidth: 44
    readonly property int facadeHeight: Math.max(12, Math.min(28, rows - 11))
    readonly property int facadeX: Math.round(cols * .6)
    readonly property int apexY: rows - facadeHeight
    // A listing's banner hangs from the entablature over the hall.
    readonly property var banner: MarketStore.banner
    readonly property int bannerTop: apexY + 9
    readonly property int bannerRows: Math.min(11, rows - 3 - bannerTop)
    property var logo: null
    // Finished pixel grids by logo and banner size, so a rotation reuses them.
    property var logos: ({})
    onBannerChanged: showLogo()
    onBannerRowsChanged: showLogo()
    function showLogo() {
        logo = null
        const url = banner ? banner.logo : ""
        if (url && banners.available) {
            if (banners.isImageLoaded(url)) sampleLogo(url)
            else banners.loadImage(url)
        }
        banners.requestPaint()
    }
    // Qt decodes the logo; its pixels are averaged into half-size cells, fine
    // enough for a wordmark to read. A wordmark spans the banner and stands in
    // for the ticker; an emblem sits beside it.
    function sampleLogo(url) {
        const key = url + " " + bannerRows + " " + facadeWidth
        if (key in logos) {
            logo = logos[key]
            banners.requestPaint()
            return
        }
        try {
            const image = banners.getContext("2d").createImageData(url)
            const box = image && image.width ? Banner.bounds(image.width, image.height, image.data) : null
            const wide = !!box && box.width >= box.height * 2.2
            const across = wide ? facadeWidth - 10 : 14
            logo = box ? Object.assign(Banner.pixelate(image.width, image.height, image.data, across * 2, Math.max(1, bannerRows - 2) * 2, box), {wide: wide}) : null
        } catch (error) {
            logo = null
        }
        if (logo) logos[key] = logo
        banners.requestPaint()
    }

    Canvas {
        id: still
        anchors.fill: parent
        opacity: root.strength * root.t
        renderStrategy: Canvas.Cooperative
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const c = root.cell, cols = root.cols, rows = root.rows, scene = root.scene
            const bg = Color.background, ink = root.ink, accent = Color.accent
            const rect = (i, j, w, h, color) => { ctx.fillStyle = color; ctx.fillRect(i * c, j * c, w * c, h * c) }
            // Sky: flat bands with one dithered row between them.
            const bands = {
                night: [bg, root.blend(bg, accent, .05), root.blend(bg, accent, .1)],
                dawn: [bg, root.blend(bg, accent, .12), root.blend(bg, accent, .26), root.blend(bg, accent, .42)],
                day: [root.blend(bg, ink, .03), root.blend(bg, ink, .06), root.blend(bg, accent, .12)],
                dusk: [bg, root.blend(bg, Color.urgent, .16), root.blend(bg, accent, .3), root.blend(accent, Color.urgent, .45)]
            }[scene]
            const band = rows / bands.length
            bands.forEach((color, b) => rect(0, Math.floor(b * band), cols, Math.ceil(band) + 1, color))
            for (let b = 1; b < bands.length; b++) {
                const j = Math.floor(b * band) - 1
                ctx.fillStyle = bands[b]
                for (let i = j % 2; i < cols; i += 2) ctx.fillRect(i * c, j * c, c, c)
            }
            // Sun on a low arc, or a crescent moon at night.
            if (scene !== "night") {
                const cx = Math.round(cols * (.06 + .88 * root.sun)), cy = Math.round(rows - 4 - Math.sin(Math.PI * root.sun) * (rows - 12))
                const low = scene === "dawn" || scene === "dusk"
                const glow = low ? 16 : 11
                ctx.fillStyle = root.blend(bg, accent, low ? .45 : .3)
                for (let j = cy - glow; j <= cy + glow; j++)
                    for (let i = cx - glow; i <= cx + glow; i++) {
                        const d = Math.hypot(i - cx, j - cy) / glow
                        const threshold = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5][((j & 3) << 2) | (i & 3)] / 16
                        if (d < 1 && 1 - d > threshold + .25) ctx.fillRect(i * c, j * c, c, c)
                    }
                for (let j = -4; j <= 4; j++)
                    for (let i = -4; i <= 4; i++) {
                        const d = Math.hypot(i, j)
                        if (d > 4.3) continue
                        rect(cx + i, cy + j, 1, 1, d < 2.2 ? root.blend(accent, ink, .45) : d < 3.4 ? accent : root.blend(accent, bg, .3))
                    }
            } else {
                const mx = Math.round(cols * .22), my = 8
                for (let j = -4; j <= 4; j++)
                    for (let i = -4; i <= 4; i++)
                        if (Math.hypot(i, j) <= 4.2 && Math.hypot(i - 2, j + 1) > 3.6) rect(mx + i, my + j, 1, 1, root.blend(bg, ink, .7))
            }
            // Skyline with lit windows; denser lights after hours.
            const next = Sprites.random(20260923)
            const lit = {night: .1, dawn: .22, day: .06, dusk: .45}[scene]
            for (let x = 0; x < cols;) {
                const w = 5 + Math.floor(next() * 9), h = 3 + Math.floor(next() * Math.max(4, rows * .4))
                if (x + w > root.facadeX - 3 && x < root.facadeX + root.facadeWidth + 3) { x = root.facadeX + root.facadeWidth + 3; continue }
                rect(x, rows - h, w, h, root.blend(bg, ink, scene === "night" ? .12 : .17))
                for (let j = rows - h + 1; j < rows - 1; j += 2)
                    for (let i = x + 1; i < x + w - 1; i += 2)
                        if (next() < lit) rect(i, j, 1, 1, scene === "day" ? root.blend(bg, ink, .3) : root.warm)
                x += w + (next() < .3 ? 1 : 0)
            }
            // NYSE facade: steps, six columns before a lit hall, entablature, pediment.
            const fx = root.facadeX, fw = root.facadeWidth, bottom = rows
            rect(fx, bottom - 1, fw, 1, root.stoneDark)
            rect(fx + 1, bottom - 2, fw - 2, 1, root.stone)
            rect(fx + 2, bottom - 3, fw - 4, 1, root.stoneLight)
            const pediment = 5, entablature = 4
            const hallTop = root.apexY + pediment + entablature
            rect(fx + 3, hallTop, fw - 6, bottom - 3 - hallTop, root.stoneDark)
            const lights = scene === "night" ? .12 : scene === "day" ? .35 : .6
            for (let k = 0; k < 5; k++)
                rect(fx + 8 + k * 6, hallTop + 2, 3, bottom - hallTop - 6, root.blend(root.stoneDark, root.warm, lights))
            for (let k = 0; k < 6; k++) {
                const x = fx + 4 + k * 6
                rect(x, hallTop, 5, 1, root.stoneLight)
                rect(x + 1, hallTop + 1, 3, bottom - 4 - hallTop, root.stone)
                rect(x + 1, hallTop + 1, 1, bottom - 4 - hallTop, root.stoneLight)
            }
            rect(fx + 1, root.apexY + pediment, fw - 2, entablature, root.stone)
            rect(fx + 1, root.apexY + pediment, fw - 2, 1, root.stoneLight)
            for (let i = fx + 3; i < fx + fw - 3; i += 3) rect(i, root.apexY + pediment + 2, 1, 1, root.stoneDark)
            for (let j = 0; j < pediment; j++) {
                const inset = Math.round((pediment - j) * 3.6)
                rect(fx + inset, root.apexY + j, fw - inset * 2, 1, j ? root.stone : root.stoneLight)
                if (j > 1) rect(fx + inset + 3, root.apexY + j, fw - inset * 2 - 6, 1, root.stoneDark)
            }
            // Flagpole.
            rect(fx + fw / 2, root.apexY - 10, 1, 10, root.stoneLight)
        }
        Connections {
            target: root
            function onStoneChanged() { still.requestPaint() }
        }
    }

    Canvas {
        id: banners
        anchors.fill: parent
        opacity: root.t * (root.scene === "night" ? .6 : .9)
        renderStrategy: Canvas.Cooperative
        onAvailableChanged: root.showLogo()
        onImageLoaded: {
            const url = root.banner ? root.banner.logo : ""
            if (url && isImageLoaded(url)) root.sampleLogo(url)
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const banner = root.banner, rows = root.bannerRows
            if (!banner || rows < 7) return
            const c = root.cell, top = root.bannerTop
            const rect = (i, j, w, h, color) => { ctx.fillStyle = color; ctx.fillRect(i * c, j * c, w * c, h * c) }
            // Logo cells are half size; a logo too thin to read falls back to the ticker.
            const logo = root.logo && root.logo.height >= 4 ? root.logo : null
            const glyphs = logo && logo.wide ? null : Sprites.text(banner.ticker)
            const logoSpan = logo ? Math.ceil(logo.width / 2) : 0
            const span = logoSpan + (logo && glyphs ? 2 : 0) + (glyphs ? glyphs[0].length : 0) + 4
            const left = Math.round(root.facadeX + root.facadeWidth / 2 - span / 2)
            const cloth = Banner.cloth(logo)
            rect(left, top, span, rows, cloth.fill)
            rect(left, top + rows - 1, span, 1, cloth.hem)
            let x = left + 2
            if (logo) {
                const half = c / 2, originY = (top + 1) * c + Math.floor(((rows - 2) * 2 - logo.height) / 2) * half
                logo.cells.forEach((cell, index) => {
                    if (cell[3] < .12) return
                    ctx.fillStyle = Qt.rgba(cell[0] / 255, cell[1] / 255, cell[2] / 255, cell[3])
                    ctx.fillRect(x * c + index % logo.width * half, originY + Math.floor(index / logo.width) * half, half, half)
                })
                x += logoSpan + 2
            }
            if (glyphs) {
                const y = top + 1 + Math.floor((rows - 7) / 2)
                glyphs.forEach((line, j) => { for (let i = 0; i < line.length; i++) if (line[i] === "1") rect(x + i, y + j, 1, 1, cloth.ink) })
            }
        }
    }

    Canvas {
        id: motion
        anchors.fill: parent
        opacity: root.strength * root.t
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const c = root.cell, cols = root.cols, rows = root.rows, scene = root.scene, tick = root.tick, bg = Color.background
            const rect = (i, j, w, h, color, alpha) => { ctx.globalAlpha = alpha === undefined ? 1 : alpha; ctx.fillStyle = color; ctx.fillRect(i * c, j * c, w * c, h * c) }
            // Twinkling stars at night, the last few fading at dawn.
            if (scene === "night" || scene === "dawn") {
                const next = Sprites.random(7)
                const count = scene === "night" ? 60 : 14
                for (let s = 0; s < count; s++) {
                    const x = Math.floor(next() * cols), y = 1 + Math.floor(next() * (rows * .55)), phase = next() * 6.28, speed = .04 + next() * .08
                    if (x > root.facadeX - 2 && x < root.facadeX + root.facadeWidth + 2) continue
                    const alpha = (.25 + .75 * Math.abs(Math.sin(tick * speed + phase))) * (scene === "dawn" ? .5 : 1)
                    rect(x, y, 1, 1, root.ink, alpha)
                    if (s % 11 === 0 && alpha > .8) { rect(x - 1, y, 3, 1, root.ink, alpha * .5); rect(x, y - 1, 1, 3, root.ink, alpha * .5) }
                }
            }
            // Clouds drift west to east.
            if (scene !== "night") {
                const next = Sprites.random(11)
                const color = scene === "day" ? root.blend(bg, root.ink, .32) : root.blend(Color.accent, root.ink, .25)
                for (let k = 0; k < 4; k++) {
                    const w = 10 + Math.floor(next() * 10), y = 3 + Math.floor(next() * Math.max(1, rows * .35))
                    const span = cols + w * 2
                    const x = Math.floor((next() * span + tick * (.04 + next() * .05)) % span) - w
                    rect(x, y, w, 2, color, .8)
                    rect(x + 2, y - 1, w - 5, 1, color, .8)
                    rect(x + Math.floor(w / 3), y - 2, Math.ceil(w / 3), 1, color, .8)
                }
            }
            // US flag, waving; lowered overnight.
            if (root.flag > 0) {
                const pole = root.facadeX + root.facadeWidth / 2 + 1
                const top = root.apexY - 10 + Math.round((1 - root.flag) * 8)
                for (let x = 0; x < 8; x++) {
                    const wave = Math.round(Math.sin(tick * .35 - x * .8) * .6)
                    for (let y = 0; y < 5; y++) {
                        const canton = x < 3 && y < 3
                        rect(pole + x, top + y + wave, 1, 1, canton ? "#3c5a9a" : y % 2 ? "#f2f2f2" : "#c8403a")
                    }
                }
            }
            // Opening-bell confetti from the pediment.
            if (root.burst >= 0) {
                const next = Sprites.random(3)
                const ox = root.facadeX + root.facadeWidth / 2, oy = root.apexY
                const colors = [StockStore.gain, root.ink, Color.accent]
                for (let k = 0; k < 48; k++) {
                    const angle = -Math.PI * (.1 + .8 * next()), speed = 10 + next() * 26
                    const time = root.burst * 2.2
                    const x = ox + Math.cos(angle) * speed * time, y = oy + Math.sin(angle) * speed * time + 9 * time * time
                    rect(Math.round(x), Math.round(y), 1, 1, colors[k % 3], 1 - root.burst)
                }
            }
            ctx.globalAlpha = 1
        }
    }
}
