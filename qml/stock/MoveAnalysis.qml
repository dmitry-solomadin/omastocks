import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

Controls.Popup {
    id: root
    objectName: "moveAnalysisPopup"
    readonly property var report: AnalysisStore.report
    readonly property string requestKey: AnalysisStore.key
    readonly property bool showSignInHelp: !report.pending && /sign.?in|log(?:ged)?.?in|logged.?out|authenticat|credentials?|needs setup|not installed/i.test(AnalysisStore.error)
    readonly property string signInInstructions: {
        const agent = report.workingAgent || ({claude: "Claude Code", codex: "Codex", opencode: "OpenCode"})[AnalysisStore.preference] || ""
        const retry = "Then return here and click " + (report.summary ? "Refresh" : "Retry") + "."
        if (agent === "Claude Code")
            return "To sign in to Claude Code, run this in a terminal:\n\nclaude auth login\n\nComplete the browser sign-in with your Claude account. " + retry
        if (agent === "Codex")
            return "To sign in to Codex, run this in a terminal:\n\ncodex login\n\nComplete the browser sign-in with your ChatGPT account. " + retry
        if (agent === "OpenCode")
            return "To sign in, open OpenCode and enter /connect. Choose your provider and complete its sign-in flow. " + retry
        return "Choose an agent in Settings → AI, then open that agent in a terminal and sign in. " + retry
    }
    onRequestKeyChanged: close()

    function escapeHtml(value) {
        return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
            .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
    }
    readonly property string paragraph: {
        const links = (report.sources || []).filter(source => /^https?:\/\//.test(source.url || "")).map((source, index) => {
            const host = source.url.replace(/^https?:\/\/(?:www\.)?/, "").split(/[/?#]/)[0]
            return '<a style="color: ' + Color.accent + '" href="' + escapeHtml(source.url) + '">[' + (index + 1) + '] ' + escapeHtml(host) + '</a>'
        })
        return escapeHtml(report.summary) + (links.length ? "<br><br>" + links.join(" &nbsp;·&nbsp; ") : "")
    }
    width: Math.min(Style.space(720), parent.width - Style.space(32))
    height: Math.min(analysisContent.implicitHeight + topPadding + bottomPadding, parent.height - Style.space(32))
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
        target: AnalysisStore
        function onOpenRequested() { root.open() }
        function onBackgroundRequested() { root.close() }
        function onActiveChanged() { if (!AnalysisStore.active) root.close() }
    }
    contentItem: Controls.ScrollView {
        id: scroll
        objectName: "moveAnalysis"
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: analysisContent
            width: scroll.availableWidth
            spacing: Style.space(16)
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "Latest move · " + StockStore.selected
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    Layout.fillWidth: true
                }
                ActionButton {
                    id: closeButton
                    objectName: "hideMoveAnalysis"
                    text: "×"
                    hint: "Close analysis"
                    font.pixelSize: Style.font.body * 2
                    Layout.preferredWidth: Style.space(36)
                    Layout.preferredHeight: Style.space(34)
                    padding: 0
                    onClicked: root.close()
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Util.alpha(Color.foreground, .1) }
            MarketLoading {
                Layout.fillWidth: true
                active: root.visible && AnalysisStore.working
                text: (root.report.stage || "Preparing analysis") + (root.report.workingAgent ? " · " + root.report.workingAgent : "") + "…"
            }
            Label {
                objectName: "moveAnalysisError"
                visible: !!AnalysisStore.error
                text: AnalysisStore.error
                color: Color.urgent
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
            Label {
                objectName: "moveAnalysisSignInHelp"
                visible: root.showSignInHelp
                text: root.signInInstructions
                color: Tone.muted
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
            Label {
                id: summary
                objectName: "moveAnalysisSummary"
                visible: !!root.report.summary
                text: root.paragraph
                textFormat: Text.RichText
                linkColor: Color.accent
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                lineHeight: 1.25
                onLinkActivated: link => { if (/^https?:\/\//.test(link)) Qt.openUrlExternally(link) }
                HoverHandler { cursorShape: summary.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                Ui.PanelToolTip {
                    visible: !!summary.hoveredLink
                    text: ((root.report.sources || []).find(source => source.url === summary.hoveredLink) || {}).title || summary.hoveredLink
                }
            }
            Label {
                visible: !!root.report.summary
                text: "AI · " + (root.report.agent || "") + " · " + ((root.report.session || {}).kind || "regular")
                    + " · " + ((root.report.session || {}).date || "")
                    + " · Updated " + Qt.formatDateTime(new Date((root.report.generated || 0) * 1000), "d MMM hh:mm")
                    + (AnalysisStore.stale ? " · Earlier snapshot — refresh for latest context" : "")
                color: Tone.muted
                font.pixelSize: Style.font.bodySmall
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ActionButton {
                    objectName: "backgroundMoveAnalysis"
                    visible: root.report.pending === true
                    text: "Notify when ready"
                    hint: "Close this popup and send a desktop notification when the analysis finishes"
                    enabled: !AnalysisStore.notificationBusy
                    onClicked: AnalysisStore.notifyWhenReady()
                }
                ActionButton {
                    objectName: "refreshMoveAnalysis"
                    visible: !root.report.pending
                    text: root.report.summary ? "Refresh" : "Retry"
                    hint: "Research the latest move again using your selected agent"
                    enabled: !AnalysisStore.working
                    onClicked: AnalysisStore.generate(true)
                }
                ActionButton {
                    objectName: "cancelMoveAnalysis"
                    visible: root.report.pending === true
                    text: "Cancel research"
                    onClicked: AnalysisStore.cancel()
                }
            }
        }
    }
}
