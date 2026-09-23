import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "."

ColumnLayout {
    id: root
    spacing: Style.space(8)
    property double now: Date.now() / 1000
    property var report: MarketStore.news
    property bool busy: MarketStore.newsRequest.busy
    property string subject: "company"
    readonly property var articles: report.articles || []
    Timer { interval: 60000; running: StockStore.windowOpen && root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() / 1000 }
    function age(timestamp) {
        if (!timestamp) return ""
        const minutes = Math.max(0, Math.floor((now - timestamp) / 60))
        return minutes < 1 ? "Just now" : minutes < 60 ? minutes + "m ago" : minutes < 1440 ? Math.floor(minutes / 60) + "h ago"
            : Qt.formatDate(new Date(timestamp * 1000), "d MMM yyyy")
    }
    MarketLoading {
        Layout.fillWidth: true
        active: root.busy
        text: root.articles.length ? "Updating headlines…" : "Loading " + root.subject + " news…"
    }
    Label {
        Layout.fillWidth: true
        visible: !root.busy && (!!root.report.error || !root.articles.length)
        text: root.report.error ? (root.articles.length ? "Showing saved headlines. " : "") + root.report.error
            : root.busy ? "Loading " + root.subject + " news…" : "No recent " + root.subject + " news found."
        color: Color.muted
        wrapMode: Text.WordWrap
        font.pixelSize: Style.font.bodySmall
    }
    GridLayout {
        id: newsGrid
        Layout.fillWidth: true
        columns: root.width >= Style.space(400) ? 2 : 1
        columnSpacing: Style.space(12)
        rowSpacing: Style.space(8)
        Repeater {
        model: root.articles
        Controls.ItemDelegate {
            id: article
            required property var modelData
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            implicitHeight: Math.max(Style.space(84), contentItem.implicitHeight + padding * 2)
            padding: Style.space(10)
            hoverEnabled: true
            onClicked: Qt.openUrlExternally(modelData.url)
            Accessible.name: modelData.title + " · " + modelData.source
            Ui.PanelToolTip { visible: article.hovered; text: article.modelData.title }
            background: Rectangle {
                radius: Style.cornerRadius
                color: article.hovered ? Util.alpha(Color.foreground, .06) : "transparent"
                border.width: article.activeFocus ? 1 : 0
                border.color: Color.accent
            }
            contentItem: RowLayout {
                spacing: Style.space(14)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)
                    Label {
                        text: article.modelData.title
                        Layout.fillWidth: true
                        font.bold: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                    }
                    Label {
                        text: article.modelData.source + (article.modelData.published ? "  ·  " + root.age(article.modelData.published) : "")
                        color: Color.muted
                        font.pixelSize: Style.font.bodySmall
                        Layout.fillWidth: true
                    }
                }
                Image {
                    source: article.modelData.image
                    asynchronous: true
                    visible: status === Image.Ready && article.width >= Style.space(300)
                    Layout.preferredWidth: Style.space(88)
                    Layout.preferredHeight: Style.space(66)
                    sourceSize.width: 264
                    sourceSize.height: 198
                    fillMode: Image.PreserveAspectCrop
                }
            }
        }
    }
    }
}
