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
    component ThemedSwitch: Ui.ToggleSwitch {
        rounded: false
        activeFocusOnTab: true
        hasCursor: activeFocus
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: checked
        Accessible.onToggleAction: if (enabled && !busy) toggled()
        Keys.onSpacePressed: if (!busy) toggled()
    }

    width: Math.min(Style.space(380), parent.width - Style.space(32))
    height: Math.min(settingsContent.implicitHeight + topPadding + bottomPadding, parent.height - Style.space(32))
    x: (parent.width - width) / 2
    y: Math.max(Style.space(16), (parent.height - height) / 2)
    padding: Style.space(24)
    modal: true
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    onOpened: { saveError = ""; volumeToggle.forceActiveFocus() }
    Controls.Overlay.modal: Rectangle { color: Util.alpha(Color.background, .55) }
    background: Rectangle {
        color: Color.background
        radius: Style.cornerRadius
        border.width: 1
        border.color: Util.alpha(Color.foreground, .2)
    }
    contentItem: Controls.ScrollView {
        id: settingsScroll
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
        id: settingsContent
        width: settingsScroll.availableWidth
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
        Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, .1) }
        Label { text: "CHART"; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
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
        Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, .1) }
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
        Label { text: "WIDGET"; visible: menu.showStrip; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
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
        Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, .1) }
        Label { text: "WATCHLIST"; color: Tone.muted; font.pixelSize: Style.font.bodySmall }
        Repeater {
            model: [{value:"percent",label:"Display percentage change"}, {value:"change",label:"Display price change"}, {value:"marketCap",label:"Display market cap"}]
            RowLayout {
                id: displayOption
                required property var modelData
                Layout.fillWidth: true
                Label { text: displayOption.modelData.label; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                ThemedSwitch {
                    objectName: "watchlistDisplay_" + displayOption.modelData.value
                    checked: StockStore.watchlistDisplay === displayOption.modelData.value
                    enabled: menu.shell !== null
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: displayOption.modelData.label
                    onToggled: if (!checked) menu.saveSetting("watchlistDisplay", displayOption.modelData.value)
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
}
