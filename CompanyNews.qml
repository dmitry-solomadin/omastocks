import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import "."

ColumnLayout {
    id: root
    spacing: Style.space(8)
    property double now: Date.now() / 1000
    readonly property var articles: MarketStore.news.articles || []
    Timer { interval: 60000; running: StockStore.windowOpen; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() / 1000 }
    function age(timestamp) {
        if (!timestamp) return ""
        const minutes = Math.max(0, Math.floor((now - timestamp) / 60))
        return minutes < 1 ? "Just now" : minutes < 60 ? minutes + "m ago" : minutes < 1440 ? Math.floor(minutes / 60) + "h ago"
            : Qt.formatDate(new Date(timestamp * 1000), "d MMM yyyy")
    }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "LATEST NEWS"; color: Color.muted; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
        ActionButton { text: "↻"; hint: "Refresh company news"; enabled: !MarketStore.newsRequest.busy; onClicked: MarketStore.newsRequest.reload(true) }
    }
    Label {
        Layout.fillWidth: true
        visible: !!MarketStore.news.error || !root.articles.length
        text: MarketStore.news.error ? (root.articles.length ? "Showing saved headlines. " : "") + MarketStore.news.error
            : MarketStore.newsRequest.busy ? "Loading company news…" : "No recent company news found."
        color: Color.muted
        wrapMode: Text.WordWrap
        font.pixelSize: Style.font.bodySmall
    }
    Repeater {
        model: root.articles
        Controls.ItemDelegate {
            id: article
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: Math.max(Style.space(84), contentItem.implicitHeight + padding * 2)
            padding: Style.space(10)
            hoverEnabled: true
            onClicked: Qt.openUrlExternally(modelData.url)
            Accessible.name: modelData.title + " · " + modelData.source
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
                    visible: status === Image.Ready
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
