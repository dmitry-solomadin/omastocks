import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "."

Controls.Popup {
    id: menu
    objectName: "stockSettings"
    property var shell: null
    property string saveError: ""
    property string section: "general"
    // Widget settings stay live even while the strip is hidden.
    readonly property var barSettings: StockStore.barSettings
    readonly property bool showStrip: barSettings.showStrip !== false
    readonly property int stripWidth: Math.max(40, Math.min(800, Number(barSettings.maxWidth) || 360))
    function saveSetting(key, value) {
        saveError = ""
        const settings = Object.assign({}, barSettings)
        settings[key] = value
        if (!shell || !shell.updateEntryInline("io.github.dmitry-solomadin.omastocks", settings))
            saveError = "Could not save this setting. Please try again."
        else
            StockStore.barSettings = settings
    }
    // Keyboard shortcuts, listed at the bottom of General.
    readonly property var shortcuts: [
        {keys: ["A–Z"], action: "Start a search by typing"},
        {keys: ["Ctrl", "S"], action: "Focus search"},
        {keys: ["↑", "↓"], action: "Previous or next stock"},
        {keys: ["←", "→"], action: "Previous or next chart range"},
        {keys: ["Enter"], action: "Open the selected result"},
        {keys: ["Del"], action: "Remove the selected stock"},
        {keys: ["Ctrl", "Z"], action: "Undo the last removal"},
        {keys: ["Ctrl", "R"], action: "Refresh"}
    ]
    component ThemedSwitch: Ui.ToggleSwitch {
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        rounded: false
        cursorPad: Style.space(4)
        activeFocusOnTab: true
        hasCursor: activeFocus
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: checked
        Accessible.onToggleAction: if (enabled && !busy) toggled()
        Keys.onSpacePressed: if (!busy) toggled()
    }

    width: Math.min(Style.space(540), parent.width - Style.space(32))
    height: Math.min(Style.space(700), parent.height - Style.space(32))
    x: (parent.width - width) / 2
    y: Math.max(Style.space(16), (parent.height - height) / 2)
    padding: Style.space(24)
    modal: true
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    onOpened: {
        saveError = ""
        if (section === "ai") aiTab.forceActiveFocus()
        else generalTab.forceActiveFocus()
    }
    Controls.Overlay.modal: Rectangle { color: Util.alpha(Color.background, .55) }
    background: Rectangle {
        color: Color.background
        radius: Style.cornerRadius
        border.width: 1
        border.color: Util.alpha(Color.foreground, .2)
    }
    contentItem: ColumnLayout {
        id: settingsContent
        objectName: "settingsContent"
        spacing: Style.space(12)
        RowLayout {
            Layout.fillWidth: true
            Label { text: "Settings"; font.pixelSize: Style.font.heading; font.bold: true; Layout.fillWidth: true }
            ActionButton {
                objectName: "closeSettings"
                text: "×"
                font.pixelSize: Style.font.body * 2
                Layout.preferredWidth: Style.space(36)
                Layout.preferredHeight: Style.space(34)
                padding: 0
                hint: "Close settings"
                onClicked: menu.close()
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Util.alpha(Color.foreground, .1) }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(20)
            Rectangle {
                objectName: "settingsSidebar"
                Layout.preferredWidth: Style.space(130)
                Layout.fillHeight: true
                color: Util.alpha(Color.foreground, .025)
                radius: Style.cornerRadius
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.space(8)
                    spacing: Style.space(4)
                    ActionButton {
                        id: generalTab
                        objectName: "settingsTab_general"
                        Layout.fillWidth: true
                        text: "General"
                        selected: menu.section === "general"
                        onClicked: menu.section = "general"
                        Keys.onDownPressed: { menu.section = "ai"; aiTab.forceActiveFocus() }
                        contentItem: Label {
                            text: generalTab.text
                            color: generalTab.ink
                            font.bold: generalTab.selected
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    ActionButton {
                        id: aiTab
                        objectName: "settingsTab_ai"
                        Layout.fillWidth: true
                        text: "AI"
                        selected: menu.section === "ai"
                        onClicked: menu.section = "ai"
                        Keys.onUpPressed: { menu.section = "general"; generalTab.forceActiveFocus() }
                        contentItem: Label {
                            text: aiTab.text
                            color: aiTab.ink
                            font.bold: aiTab.selected
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: menu.section === "ai" ? 1 : 0
                Controls.ScrollView {
                    id: generalScroll
                    objectName: "settingsGeneral"
                    contentWidth: availableWidth
                    rightPadding: Controls.ScrollBar.vertical.width + Style.space(8)
                    clip: true
                    ColumnLayout {
                        width: generalScroll.availableWidth
                        spacing: Style.space(8)
                        SectionHeading { text: "CHART" }
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Volume bars"; Layout.fillWidth: true }
                            ThemedSwitch {
                                id: volumeToggle
                                objectName: "showVolume"
                                checked: MarketStore.showVolume
                                enabled: menu.shell !== null
                                Accessible.name: "Show chart volume bars"
                                onToggled: menu.saveSetting("showVolume", !checked)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Event markers"; Layout.fillWidth: true }
                            ThemedSwitch {
                                objectName: "showEvents"
                                checked: MarketStore.showEvents
                                enabled: menu.shell !== null
                                Accessible.name: "Show earnings, dividend and split markers"
                                onToggled: menu.saveSetting("showEvents", !checked)
                            }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Util.alpha(Color.foreground, .1) }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(16)
                            Label { text: "Enable topbar widget"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            ThemedSwitch {
                                id: barToggle
                                objectName: "barToggle"
                                checked: menu.showStrip
                                enabled: menu.shell !== null
                                onToggled: menu.saveSetting("showStrip", !checked)
                                Accessible.name: "Enable topbar widget"
                            }
                        }
                        SectionHeading { text: "WIDGET"; visible: menu.showStrip }
                        Repeater {
                            model: [
                                {key: "showPrice", label: "Price", defaultValue: false},
                                {key: "showPercent", label: "Percentage change", defaultValue: true},
                                {key: "showChange", label: "Price change ($)", defaultValue: false}
                            ]
                            RowLayout {
                                id: fieldRow
                                required property var modelData
                                visible: menu.showStrip
                                Layout.fillWidth: true
                                Label { text: fieldRow.modelData.label; Layout.fillWidth: true }
                                ThemedSwitch {
                                    objectName: fieldRow.modelData.key
                                    readonly property bool savedValue: menu.barSettings[fieldRow.modelData.key] === undefined
                                        ? fieldRow.modelData.defaultValue : menu.barSettings[fieldRow.modelData.key] === true
                                    checked: savedValue
                                    enabled: menu.shell !== null
                                    Accessible.name: fieldRow.modelData.label
                                    onToggled: menu.saveSetting(fieldRow.modelData.key, !checked)
                                }
                            }
                        }
                        RowLayout {
                            visible: menu.showStrip
                            Layout.fillWidth: true
                            Label { text: "Maximum width"; Layout.fillWidth: true }
                            ActionButton {
                                text: "−"; hint: "Narrower strip"
                                enabled: menu.shell !== null && menu.stripWidth > 40
                                onClicked: menu.saveSetting("maxWidth", Math.max(40, menu.stripWidth - 40))
                            }
                            Label { text: menu.stripWidth + " px" }
                            ActionButton {
                                text: "+"; hint: "Wider strip"
                                enabled: menu.shell !== null && menu.stripWidth < 800
                                onClicked: menu.saveSetting("maxWidth", Math.min(800, menu.stripWidth + 40))
                            }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Util.alpha(Color.foreground, .1) }
                        SectionHeading { text: "WATCHLIST" }
                        Label { text: "Beside each price"; Layout.fillWidth: true }
                        SegmentedControl {
                            objectName: "watchlistDisplay"
                            objectNamePrefix: "watchlistDisplay_"
                            Layout.fillWidth: true
                            enabled: menu.shell !== null
                            value: StockStore.watchlistDisplay
                            options: [
                                {value: "percent", label: "% change", hint: "Percentage change today"},
                                {value: "change", label: "$ change", hint: "Price change today"},
                                {value: "marketCap", label: "Market cap", hint: "Market capitalization"}
                            ]
                            onActivated: value => menu.saveSetting("watchlistDisplay", value)
                            Accessible.name: "Watchlist value beside each price"
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Util.alpha(Color.foreground, .1) }
                        SectionHeading { text: "SHORTCUTS" }
                        GridLayout {
                            objectName: "shortcutList"
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: Style.space(14)
                            rowSpacing: Style.space(8)
                            Repeater {
                                model: menu.shortcuts
                                delegate: RowLayout {
                                    id: shortcut
                                    required property var modelData
                                    required property int index
                                    // Each shortcut takes a grid row: key caps, then the action.
                                    Layout.row: index
                                    Layout.column: 0
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Style.space(4)
                                    Repeater {
                                        model: shortcut.modelData.keys
                                        Rectangle {
                                            required property string modelData
                                            implicitWidth: Math.max(implicitHeight, cap.implicitWidth + Style.space(10))
                                            implicitHeight: cap.implicitHeight + Style.space(4)
                                            radius: Style.space(3)
                                            color: Util.alpha(Color.foreground, .05)
                                            border.width: 1
                                            border.color: Tone.border
                                            Label { id: cap; anchors.centerIn: parent; text: parent.modelData; font.pixelSize: Style.font.bodySmall }
                                        }
                                    }
                                }
                            }
                            Repeater {
                                model: menu.shortcuts.length
                                delegate: Label {
                                    required property int index
                                    Layout.row: index
                                    Layout.column: 1
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: menu.shortcuts[index].action
                                    color: Tone.muted
                                    font.pixelSize: Style.font.bodySmall
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideNone
                                }
                            }
                        }
                    }
                }
                Controls.ScrollView {
                    id: aiScroll
                    objectName: "settingsAI"
                    contentWidth: availableWidth
                    rightPadding: Controls.ScrollBar.vertical.width + Style.space(8)
                    clip: true
                    ColumnLayout {
                        width: aiScroll.availableWidth
                        spacing: Style.space(12)
                        SectionHeading { text: "AI ANALYSIS" }
                        Label {
                            text: "AI features use your agent’s existing account and model. Sign in to the agent first. Some features also require web research."
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                            color: Tone.muted
                            font.pixelSize: Style.font.bodySmall
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(4)
                            Repeater {
                                model: [{value: "default", label: "Use Omarchy default"}, {value: "claude", label: "Claude Code"},
                                    {value: "codex", label: "Codex"}, {value: "opencode", label: "OpenCode"}]
                                ActionButton {
                                    required property var modelData
                                    objectName: "analysisAgent_" + modelData.value
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    selected: AnalysisStore.preference === modelData.value
                                    enabled: menu.shell !== null
                                    onClicked: menu.saveSetting("analysisAgent", modelData.value)
                                }
                            }
                        }
                    }
                }
            }
        }
        Label {
            visible: menu.saveError !== ""
            text: menu.saveError
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Color.urgent
        }
    }
}
