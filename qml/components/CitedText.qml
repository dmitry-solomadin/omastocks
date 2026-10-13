import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

// Report text followed by its numbered source links. A link opens the source
// in the browser and shows its title on hover.
Label {
    id: root
    property string detail
    property var cited: []
    property var sources: []
    function escapeHtml(value) {
        return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
            .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
    }
    readonly property string links: (cited || []).map(number => {
        const source = (sources || [])[number - 1]
        return source && /^https?:\/\//.test(source.url)
            ? '<a style="color: ' + Color.accent + '; text-decoration: none" href="' + escapeHtml(source.url) + '">[' + number + ']</a>' : ""
    }).filter(link => !!link).join(" ")
    text: escapeHtml(detail) + (links ? " " + links : "")
    textFormat: Text.RichText
    linkColor: Color.accent
    lineHeight: 1.2
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    elide: Text.ElideNone
    onLinkActivated: url => { if (/^https?:\/\//.test(url)) Qt.openUrlExternally(url) }
    HoverHandler { cursorShape: root.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
    Ui.PanelToolTip {
        visible: !!root.hoveredLink
        text: ((root.sources || []).find(source => source.url === root.hoveredLink) || {}).title || root.hoveredLink
    }
}
