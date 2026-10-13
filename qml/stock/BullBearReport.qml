import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

// The bull and bear case, drawn from the same result as its HTML report. The
// report itself opens in the browser or is saved to Downloads for sharing.
Controls.Popup {
    id: root
    objectName: "bullBearPopup"
    readonly property var report: BullBearStore.report
    readonly property bool ready: BullBearStore.ready
    readonly property var sources: report.sources || []
    readonly property string requestKey: BullBearStore.key
    readonly property bool showSignInHelp: !report.pending && AnalysisStore.needsSignIn(BullBearStore.error)
    onRequestKeyChanged: close()

    function escapeHtml(value) {
        return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
            .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
    }
    function host(url) {
        return url.replace(/^https?:\/\/(?:www\.)?/, "").split(/[/?#:]/)[0]
    }
    function link(number, text) {
        const source = sources[number - 1]
        return source && /^https?:\/\//.test(source.url)
            ? '<a style="color: ' + Color.accent + '; text-decoration: none" href="' + escapeHtml(source.url) + '">' + text + '</a>' : ""
    }
    // A point's explanation, then the numbered sources behind it.
    function cited(point) {
        const links = (point.sources || []).map(number => link(number, "[" + number + "]")).filter(text => !!text)
        return escapeHtml(point.detail) + (links.length ? " " + links.join(" ") : "")
    }
    function sourceTitle(url) {
        return (sources.find(source => source.url === url) || {}).title || url
    }
    function openLink(url) {
        if (/^https?:\/\//.test(url)) Qt.openUrlExternally(url)
    }

    width: Math.min(Style.space(1000), parent.width - Style.space(32))
    height: Math.min(layout.implicitHeight + topPadding + bottomPadding, parent.height - Style.space(32))
    x: (parent.width - width) / 2
    y: Math.max(Style.space(16), (parent.height - height) / 2)
    padding: Style.space(24)
    modal: true
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    onOpened: closeButton.forceActiveFocus()
    Controls.Overlay.modal: Rectangle { color: Util.alpha(Color.background, .55) }
    background: Rectangle {
        color: Color.background
        radius: Style.cornerRadius
        border.width: 1
        border.color: Util.alpha(Color.foreground, .2)
    }
    Connections {
        target: BullBearStore
        function onOpenRequested() { root.open() }
        function onBackgroundRequested() { root.close() }
        function onActiveChanged() { if (!BullBearStore.active) root.close() }
    }

    // One side of the case: a tinted card of headed, sourced points.
    component Case: Rectangle {
        id: card
        property string title
        property color tone
        property var points: []
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: cardContent.implicitHeight + Style.space(36)
        radius: Style.cornerRadius
        color: Util.alpha(tone, .05)
        border.width: 1
        border.color: Util.alpha(tone, .3)
        ColumnLayout {
            id: cardContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(18)
            spacing: Style.space(16)
            Label {
                text: card.title
                color: card.tone
                font.bold: true
                font.letterSpacing: Style.space(1)
                font.pixelSize: Style.font.bodySmall
            }
            Repeater {
                model: card.points
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Style.space(4)
                    Label {
                        text: modelData.title
                        font.bold: true
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                    Label {
                        id: detail
                        text: root.cited(modelData)
                        textFormat: Text.RichText
                        linkColor: Color.accent
                        lineHeight: 1.2
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        onLinkActivated: url => root.openLink(url)
                        HoverHandler { cursorShape: detail.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        Ui.PanelToolTip { visible: !!detail.hoveredLink; text: root.sourceTitle(detail.hoveredLink) }
                    }
                }
            }
        }
    }

    contentItem: ColumnLayout {
        id: layout
        spacing: Style.space(16)
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "Bull & bear · " + StockStore.selected
                font.pixelSize: Style.font.heading
                font.bold: true
                Layout.fillWidth: true
            }
            ActionButton {
                id: closeButton
                objectName: "hideBullBear"
                text: "×"
                hint: "Close report"
                font.pixelSize: Style.font.body * 2
                Layout.preferredWidth: Style.space(36)
                Layout.preferredHeight: Style.space(34)
                padding: 0
                onClicked: root.close()
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Util.alpha(Color.foreground, .1) }
        Controls.ScrollView {
            id: scroll
            objectName: "bullBearReport"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: body.implicitHeight
            contentWidth: availableWidth
            rightPadding: Controls.ScrollBar.vertical.width + Style.space(8)
            clip: true
            FastWheel { flickable: scroll.contentItem }
            ColumnLayout {
                id: body
                width: scroll.availableWidth
                spacing: Style.space(18)
                MarketLoading {
                    Layout.fillWidth: true
                    active: root.visible && BullBearStore.working
                    text: (root.report.stage || "Preparing research") + (root.report.workingAgent ? " · " + root.report.workingAgent : "") + "…"
                }
                Label {
                    objectName: "bullBearError"
                    visible: !!BullBearStore.error
                    text: BullBearStore.error
                    color: Color.urgent
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                Label {
                    objectName: "bullBearSignInHelp"
                    visible: root.showSignInHelp
                    text: AnalysisStore.signInInstructions(root.report.workingAgent, root.ready ? "Refresh" : "Retry")
                    color: Tone.muted
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                Label {
                    objectName: "bullBearSummary"
                    visible: root.ready
                    text: root.report.summary || ""
                    font.pixelSize: Math.round(Style.font.body * 1.1)
                    lineHeight: 1.25
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                GridLayout {
                    objectName: "bullBearCases"
                    visible: root.ready
                    Layout.fillWidth: true
                    columns: root.width > Style.space(720) ? 2 : 1
                    uniformCellWidths: true
                    columnSpacing: Style.space(16)
                    rowSpacing: Style.space(16)
                    Case { objectName: "bullCase"; title: "▲  BULL CASE"; tone: "#4caf50"; points: root.report.bull || [] }
                    Case { objectName: "bearCase"; title: "▼  BEAR CASE"; tone: "#ef5350"; points: root.report.bear || [] }
                }
                ColumnLayout {
                    objectName: "bullBearWatch"
                    visible: root.ready && (root.report.watch || []).length > 0
                    Layout.fillWidth: true
                    spacing: Style.space(6)
                    SectionHeading { text: "WHAT TO WATCH" }
                    Repeater {
                        model: root.report.watch || []
                        Label {
                            required property string modelData
                            text: "•  " + modelData
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                        }
                    }
                }
                ColumnLayout {
                    objectName: "bullBearSources"
                    visible: root.ready
                    Layout.fillWidth: true
                    spacing: Style.space(6)
                    SectionHeading { text: "SOURCES" }
                    Repeater {
                        model: root.sources
                        Label {
                            id: source
                            required property var modelData
                            required property int index
                            text: (index + 1) + ".  " + root.link(index + 1, root.escapeHtml(modelData.title)) + " · " + root.escapeHtml(root.host(modelData.url))
                            textFormat: Text.RichText
                            color: Tone.muted
                            font.pixelSize: Style.font.bodySmall
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                            onLinkActivated: url => root.openLink(url)
                            HoverHandler { cursorShape: source.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        }
                    }
                }
                Label {
                    visible: root.ready
                    text: "AI · " + (root.report.agent || "") + " · Researched " + Qt.formatDateTime(new Date((root.report.generated || 0) * 1000), "d MMM yyyy hh:mm")
                        + (Date.now() / 1000 - (root.report.generated || 0) > 7 * 86400 ? " · Over a week old — refresh for the latest" : "")
                        + " · Not investment advice"
                    color: Tone.muted
                    font.pixelSize: Style.font.bodySmall
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            ActionButton {
                objectName: "openBullBearReport"
                visible: root.ready && !!root.report.html
                text: "Open in browser"
                hint: "Open the shareable HTML report in your browser"
                onClicked: BullBearStore.openInBrowser()
            }
            ActionButton {
                objectName: "saveBullBearReport"
                visible: root.ready
                text: "Save to Downloads"
                hint: "Save a copy of the HTML report to share"
                enabled: !BullBearStore.exportRequest.busy
                onClicked: BullBearStore.saveCopy()
            }
            Label {
                objectName: "bullBearSaved"
                text: BullBearStore.exported.error || (BullBearStore.exported.shown ? "Saved to " + BullBearStore.exported.shown : "")
                color: BullBearStore.exported.error ? Color.urgent : Tone.muted
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
            ActionButton {
                objectName: "backgroundBullBear"
                visible: root.report.pending === true
                text: "Notify when ready"
                hint: "Close this popup and send a desktop notification when the report is ready"
                enabled: !BullBearStore.notificationBusy
                onClicked: BullBearStore.notifyWhenReady()
            }
            ActionButton {
                objectName: "refreshBullBear"
                visible: !root.report.pending
                text: root.ready ? "Refresh" : "Retry"
                hint: "Research the bull and bear case again using your selected agent"
                enabled: !BullBearStore.working
                onClicked: BullBearStore.generate(true)
            }
            ActionButton {
                objectName: "cancelBullBear"
                visible: root.report.pending === true
                text: "Cancel research"
                onClicked: BullBearStore.cancel()
            }
        }
    }
}
