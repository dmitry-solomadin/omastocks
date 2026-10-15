import QtQuick
import QtQuick.Layouts
import qs.Commons
import ".."

// The comparison's ticker input, shown only in Compare mode.
RowLayout {
    id: root
    objectName: "chartTools"
    property var chart: null
    spacing: Style.space(8)
    onVisibleChanged: if (visible) compareInput.forceActiveFocus()
    InputField {
        id: compareInput
        objectName: "compareInput"
        Layout.fillWidth: true
        implicitHeight: Style.space(34)
        enabled: MarketStore.compareSymbols.length < 4
        placeholderText: enabled ? "Add ticker, e.g. MSFT or SPY" : "Five stocks selected"
        leftPadding: Style.space(10)
        onAccepted: if (MarketStore.compare(text)) clear()
        onTextEdited: MarketStore.compareValidation = ""
        Accessible.name: "Comparison ticker symbol"
    }
    ActionButton {
        objectName: "compareAdd"
        text: "Add"
        enabled: compareInput.enabled && !!compareInput.text.trim()
        hint: MarketStore.compareValidation || "Add stock to comparison (five stocks maximum)"
        onClicked: if (MarketStore.compare(compareInput.text)) compareInput.clear()
    }
    ActionButton {
        objectName: "compareExit"
        text: "×"; font.pixelSize: Style.font.body * 2; hint: "Exit comparison"
        onClicked: { compareInput.clear(); MarketStore.closeComparison() }
    }
}
