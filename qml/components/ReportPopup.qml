import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

// The frame of an AI report: its title, progress and errors, headline and
// summary, the report's own content, what to watch, sources, and the actions to
// share, refresh or stop it. `name` prefixes the objectNames for IPC inspection.
Controls.Popup {
    id: root
    property AgentReport store: null
    property string name
    property string title
    // Shown in the closing line, after when it was researched.
    property string note
    default property alias content: body.data
    readonly property var report: store.report
    readonly property bool ready: store.ready
    readonly property var sources: report.sources || []
    readonly property string requestKey: store.key
    readonly property bool showSignInHelp: !report.pending && AnalysisStore.needsSignIn(store.error)
    objectName: name + "Popup"
    onRequestKeyChanged: close()

    function escapeHtml(value) {
        return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
            .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
    }
    function host(url) {
        return url.replace(/^https?:\/\/(?:www\.)?/, "").split(/[/?#:]/)[0]
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
        target: root.store
        function onOpenRequested() { root.open() }
        function onBackgroundRequested() { root.close() }
        function onActiveChanged() { if (!root.store.active) root.close() }
    }

    contentItem: ColumnLayout {
        id: layout
        spacing: Style.space(16)
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: root.title
                font.pixelSize: Style.font.heading
                font.bold: true
                Layout.fillWidth: true
            }
            ActionButton {
                id: closeButton
                objectName: root.name + "Close"
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
            objectName: root.name + "Report"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: column.implicitHeight
            contentWidth: availableWidth
            rightPadding: Controls.ScrollBar.vertical.width + Style.space(8)
            clip: true
            FastWheel { flickable: scroll.contentItem }
            ColumnLayout {
                id: column
                width: scroll.availableWidth
                spacing: Style.space(18)
                MarketLoading {
                    Layout.fillWidth: true
                    active: root.visible && root.store.working
                    text: (root.report.stage || "Preparing research") + (root.report.workingAgent ? " · " + root.report.workingAgent : "") + "…"
                }
                Label {
                    objectName: root.name + "Error"
                    visible: !!root.store.error
                    text: root.store.error
                    color: Color.urgent
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                Label {
                    objectName: root.name + "SignInHelp"
                    visible: root.showSignInHelp
                    text: AnalysisStore.signInInstructions(root.report.workingAgent, root.ready ? "Refresh" : "Retry")
                    color: Tone.muted
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                Label {
                    objectName: root.name + "Headline"
                    visible: root.ready && !!root.report.headline
                    text: root.report.headline || ""
                    font.pixelSize: Math.round(Style.font.heading * 1.15)
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                Label {
                    objectName: root.name + "Summary"
                    visible: root.ready
                    text: root.report.summary || ""
                    font.pixelSize: Math.round(Style.font.body * 1.1)
                    lineHeight: 1.25
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                ColumnLayout {
                    id: body
                    visible: root.ready
                    Layout.fillWidth: true
                    spacing: Style.space(18)
                }
                ColumnLayout {
                    objectName: root.name + "Watch"
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
                    objectName: root.name + "Sources"
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
                            text: (index + 1) + ".  " + (/^https?:\/\//.test(modelData.url)
                                ? '<a style="color: ' + Color.accent + '; text-decoration: none" href="' + root.escapeHtml(modelData.url) + '">'
                                    + root.escapeHtml(modelData.title) + '</a>' : root.escapeHtml(modelData.title))
                                + " · " + root.escapeHtml(root.host(modelData.url))
                            textFormat: Text.RichText
                            color: Tone.muted
                            font.pixelSize: Style.font.bodySmall
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                            onLinkActivated: url => { if (/^https?:\/\//.test(url)) Qt.openUrlExternally(url) }
                            HoverHandler { cursorShape: source.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        }
                    }
                }
                Label {
                    visible: root.ready
                    text: "AI · " + (root.report.agent || "") + " · Researched " + Qt.formatDateTime(new Date((root.report.generated || 0) * 1000), "d MMM yyyy hh:mm")
                        + (root.note ? " · " + root.note : "") + " · Not investment advice"
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
                objectName: root.name + "Open"
                visible: root.ready && !!root.report.html
                text: "Open in browser"
                hint: "Open the shareable HTML report in your browser"
                onClicked: root.store.openInBrowser()
            }
            ActionButton {
                objectName: root.name + "Save"
                visible: root.ready
                text: "Save to Downloads"
                hint: "Save a copy of the HTML report to share"
                enabled: !root.store.exportRequest.busy
                onClicked: root.store.saveCopy()
            }
            Label {
                objectName: root.name + "Saved"
                text: root.store.exported.error || (root.store.exported.shown ? "Saved to " + root.store.exported.shown : "")
                color: root.store.exported.error ? Color.urgent : Tone.muted
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
            ActionButton {
                objectName: root.name + "Notify"
                visible: root.report.pending === true
                text: "Notify when ready"
                hint: "Close this popup and send a desktop notification when the report is ready"
                enabled: !root.store.notificationBusy
                onClicked: root.store.notifyWhenReady()
            }
            ActionButton {
                objectName: root.name + "Refresh"
                visible: !root.report.pending
                text: root.ready ? "Refresh" : "Retry"
                hint: "Research it again using your selected agent"
                enabled: !root.store.working
                onClicked: root.store.generate(true)
            }
            ActionButton {
                objectName: root.name + "Cancel"
                visible: root.report.pending === true
                text: "Cancel research"
                onClicked: root.store.cancel()
            }
        }
    }
}
