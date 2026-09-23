import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import ".."

ColumnLayout {
    id: root
    objectName: "socialPanel"
    spacing: Style.space(8)
    property double now: Date.now() / 1000
    readonly property var posts: MarketStore.social.posts || []
    readonly property string socialSymbol: StockStore.selected.replace(/^\^/, "")
    readonly property var buzz: (MarketStore.buzz.rows || []).find(row => row.symbol === root.socialSymbol) || null
    readonly property var mentionChange: buzz && buzz.mentions !== null && buzz.previousMentions > 0
        ? (buzz.mentions - buzz.previousMentions) / buzz.previousMentions * 100 : null
    function age(timestamp) {
        const minutes = Math.max(0, Math.floor((now - timestamp) / 60))
        return minutes < 1 ? "Just now" : minutes < 60 ? minutes + "m ago" : minutes < 1440 ? Math.floor(minutes / 60) + "h ago"
            : Qt.formatDate(new Date(timestamp * 1000), "d MMM yyyy")
    }
    Timer { interval: 60000; running: root.visible && MarketStore.stockResearchActive && MarketStore.socialOpen; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() / 1000 }
    ColumnLayout {
        objectName: "socialContent"
        visible: MarketStore.socialOpen
        Layout.fillWidth: true
        spacing: Style.space(8)
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "REDDIT BUZZ · 24H"
                Layout.fillWidth: true
                color: Tone.muted
                font.pixelSize: Style.font.bodySmall
                HoverHandler { id: buzzHover }
                Ui.PanelToolTip {
                    visible: buzzHover.hovered
                    text: "Mentions measure attention, not sentiment"
                }
            }
            ActionButton {
                text: "ApeWisdom ↗"
                hint: "Open Reddit mention activity on ApeWisdom"
                onClicked: Qt.openUrlExternally("https://apewisdom.io/stocks/" + encodeURIComponent(root.socialSymbol) + "/")
            }
        }
        Label {
            Layout.fillWidth: true
            visible: !!MarketStore.buzz.error || !root.buzz
            text: MarketStore.buzz.error ? (root.buzz ? "Showing saved activity. " : "") + MarketStore.buzz.error
                : MarketStore.buzzRequest.busy ? "Loading Reddit activity…" : "Not listed in the current tracked rankings."
            color: Tone.muted
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
        }
        Flow {
            visible: !!root.buzz
            Layout.fillWidth: true
            spacing: Style.space(16)
            Label { text: "Mentions " + StockStore.compact(root.buzz ? root.buzz.mentions : null) }
            Label {
                visible: root.mentionChange !== null
                text: StockStore.percent(root.mentionChange) + " vs prior 24h"
                color: Tone.muted
            }
            Label { text: "Upvotes " + StockStore.compact(root.buzz ? root.buzz.upvotes : null) }
            Label { text: "Rank " + (root.buzz && root.buzz.rank !== null ? "#" + root.buzz.rank : "—") }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(8)
            Label { text: "STOCKTWITS"; Layout.fillWidth: true; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
            ActionButton {
                text: "Stocktwits ↗"
                hint: "Open this symbol's discussion on Stocktwits"
                onClicked: Qt.openUrlExternally("https://stocktwits.com/symbol/" + encodeURIComponent(root.socialSymbol))
            }
        }
        Label {
            Layout.fillWidth: true
            visible: !!MarketStore.social.error || !root.posts.length
            text: MarketStore.social.error ? (root.posts.length ? "Showing saved posts. " : "") + MarketStore.social.error
                : MarketStore.socialRequest.busy ? "Loading Stocktwits posts…" : "No recent posts available."
            color: Tone.muted
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: root.posts
            Controls.ItemDelegate {
                id: post
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: contentItem.implicitHeight + padding * 2
                padding: Style.space(10)
                hoverEnabled: true
                onClicked: Qt.openUrlExternally(modelData.url)
                Accessible.role: Accessible.Link
                Accessible.name: modelData.author + ": " + modelData.text
                background: Rectangle {
                    radius: Style.cornerRadius
                    color: post.hovered || post.activeFocus ? Util.alpha(Color.foreground, .06) : "transparent"
                }
                contentItem: ColumnLayout {
                    spacing: Style.space(6)
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "@" + post.modelData.author; Layout.fillWidth: true; font.bold: true; font.pixelSize: Style.font.bodySmall }
                        Label { text: root.age(post.modelData.published); color: Tone.muted; font.pixelSize: Style.font.bodySmall }
                        Label { text: "↗"; color: Tone.muted }
                    }
                    Label {
                        text: post.modelData.text
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        maximumLineCount: 5
                    }
                    Flow {
                        visible: !!post.modelData.sentiment || post.modelData.likes !== null
                        Layout.fillWidth: true
                        spacing: Style.space(12)
                        Label {
                            visible: !!post.modelData.sentiment
                            text: post.modelData.sentiment || ""
                            font.pixelSize: Style.font.bodySmall
                            color: post.modelData.sentiment === "Bullish" ? StockStore.gain : StockStore.loss
                        }
                        Label { visible: post.modelData.likes !== null; text: "♡ " + StockStore.compact(post.modelData.likes); color: Tone.muted; font.pixelSize: Style.font.bodySmall }
                    }
                }
            }
        }
    }
}
