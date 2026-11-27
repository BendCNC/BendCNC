import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    property var appState: null

    readonly property bool numeric: appState && appState.onScreenKeyboardKind === "numeric"
    readonly property bool keyboardVisible: appState && appState.onScreenKeyboardVisible
    readonly property color panelColor: "#333433"
    readonly property color headerColor: "#2B2C2B"
    readonly property color keyColor: "#555655"
    readonly property color numberKeyColor: "#686968"
    readonly property color functionColor: "#FFA500"
    readonly property color white: "#FFFFFF"

    readonly property var textRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]
    readonly property var symbolRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["+", "=", "/", "_", "<", ">", "[", "]", "`", "~"],
        ["!", "@", "#", "$", "%", "^", "&", "(", ")"],
        ["*", "-", "'", "\"", ":", ";", "?"]
    ]

    visible: keyboardVisible
    enabled: visible
    focus: visible
    Keys.onEscapePressed: if (appState) appState.cancelOnScreenKeyboard()

    Rectangle {
        anchors.fill: parent
        color: "#72000000"
        MouseArea { anchors.fill: parent }
    }

    Loader {
        anchors.centerIn: parent
        active: root.keyboardVisible
        sourceComponent: root.numeric ? numericKeyboard : qwertyKeyboard
    }

    Component {
        id: keyboardHeader

        Rectangle {
            objectName: "osk-header"
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            color: root.headerColor
            radius: 7

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 7
                color: parent.color
            }

            Item {
                objectName: "osk-header-content"
                anchors.fill: parent
                anchors.bottomMargin: 4

                Item {
                    id: headerIcon
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 8
                    width: 52
                    Text { anchors.centerIn: parent; text: "⌨"; color: root.white; font.pixelSize: 24 }
                }
                Text {
                    objectName: "osk-header-title"
                    anchors.left: headerIcon.right
                    anchors.right: closeButton.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    text: qsTr("Enter Value")
                    color: root.white
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                }
                KeyboardKey {
                    id: closeButton
                    objectName: "osk-close-button"
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    label: "×"
                    baseColor: "transparent"
                    labelSize: 30
                    width: 52
                    height: 46
                    onTriggered: if (root.appState) root.appState.cancelOnScreenKeyboard()
                }
            }
        }
    }

    Component {
        id: numericKeyboard

        Rectangle {
            objectName: "numeric-osk-panel"
            width: 397
            height: 537
            radius: 7
            color: root.panelColor

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Loader { Layout.fillWidth: true; Layout.preferredHeight: 54; sourceComponent: keyboardHeader }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 7
                    columns: 4
                    rowSpacing: 7
                    columnSpacing: 7

                    Rectangle {
                        objectName: "numeric-value-display"
                        Layout.columnSpan: 4
                        Layout.fillWidth: true
                        Layout.preferredHeight: 85
                        Layout.minimumHeight: 85
                        Layout.maximumHeight: 85
                        color: "transparent"

                        Text {
                            objectName: "numeric-value-text"
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            text: root.appState && !root.appState.onScreenKeyboardOriginalValue
                                ? root.appState.onScreenKeyboardValue : ""
                            color: root.white
                            font.pixelSize: 42
                            font.bold: true
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideLeft
                        }
                    }

                    Repeater {
                        model: ["1", "2", "3"]
                        KeyboardKey { required property string modelData; objectName: "numeric-key-" + modelData; label: modelData; Layout.preferredWidth: 89; onTriggered: root.appState.insertOnScreenKeyboardText(label) }
                    }
                    KeyboardKey { objectName: "numeric-delete-key"; label: "⌫"; helper: qsTr("DEL"); baseColor: root.functionColor; labelSize: 31; Layout.preferredWidth: 89; onTriggered: root.appState.backspaceOnScreenKeyboard() }
                    Repeater {
                        model: ["4", "5", "6"]
                        KeyboardKey { required property string modelData; objectName: "numeric-key-" + modelData; label: modelData; Layout.preferredWidth: 89; onTriggered: root.appState.insertOnScreenKeyboardText(label) }
                    }
                    KeyboardKey { objectName: "numeric-clear-key"; label: "C"; helper: qsTr("CLR"); baseColor: root.functionColor; labelSize: 27; Layout.preferredWidth: 89; onTriggered: root.appState.clearOnScreenKeyboard() }
                    Repeater {
                        model: ["7", "8", "9"]
                        KeyboardKey { required property string modelData; objectName: "numeric-key-" + modelData; label: modelData; Layout.preferredWidth: 89; onTriggered: root.appState.insertOnScreenKeyboardText(label) }
                    }
                    KeyboardKey { objectName: "numeric-ok-key"; label: "→"; helper: qsTr("OK"); baseColor: root.functionColor; labelSize: 43; Layout.preferredWidth: 89; Layout.preferredHeight: 185; Layout.minimumHeight: 185; Layout.maximumHeight: 185; Layout.rowSpan: 2; onTriggered: root.appState.commitOnScreenKeyboard() }
                    KeyboardKey { objectName: "numeric-negative-key"; label: "−"; helper: qsTr("NEG"); Layout.preferredWidth: 89; onTriggered: root.appState.toggleOnScreenKeyboardNegative() }
                    KeyboardKey { objectName: "numeric-key-0"; label: "0"; Layout.preferredWidth: 89; onTriggered: root.appState.insertOnScreenKeyboardText("0") }
                    KeyboardKey { objectName: "numeric-decimal-key"; label: "."; helper: qsTr("DEC"); Layout.preferredWidth: 89; onTriggered: root.appState.insertOnScreenKeyboardText(".") }
                }
            }
        }
    }

    Component {
        id: qwertyKeyboard

        Rectangle {
            objectName: "qwerty-osk-panel"
            width: Math.min(985, root.width - 20)
            height: Math.min(648, root.height - 20)
            radius: 7
            color: root.panelColor

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Loader { Layout.fillWidth: true; Layout.preferredHeight: 54; sourceComponent: keyboardHeader }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 7
                    columns: 10
                    rowSpacing: 7
                    columnSpacing: 7

                    Rectangle {
                        objectName: "qwerty-value-display"
                        Layout.columnSpan: 9
                        Layout.fillWidth: true
                        Layout.preferredHeight: 85
                        Layout.minimumHeight: 85
                        color: root.keyColor
                        border.color: "#707170"
                        border.width: 3

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 10
                            contentWidth: valueText.implicitWidth
                            contentHeight: height
                            contentX: Math.max(0, Math.min(contentWidth - width, cursorMarker.x - width + 28))
                            clip: true

                            Text {
                                id: valueText
                                height: parent.height
                                text: root.appState ? root.appState.onScreenKeyboardValue : ""
                                color: root.white
                                font.pixelSize: 36
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }
                            Rectangle {
                                id: cursorMarker
                                x: cursorMeasure.advanceWidth
                                y: 11
                                width: 4
                                height: parent.height - 22
                                color: "#C5C6C5"
                            }
                            TextMetrics {
                                id: cursorMeasure
                                font: valueText.font
                                text: root.appState
                                    ? valueText.text.substring(0, root.appState.onScreenKeyboardCursor) : ""
                            }
                        }
                    }
                    KeyboardKey { objectName: "qwerty-clear-key"; label: "C"; helper: qsTr("CLR"); baseColor: root.functionColor; labelSize: 27; Layout.preferredHeight: 85; Layout.minimumHeight: 85; Layout.maximumHeight: 85; onTriggered: root.appState.clearOnScreenKeyboard() }

                    Repeater {
                        model: 10
                        KeyboardKey { required property int index; objectName: "qwerty-number-key-" + index; label: root.textRows[0][index]; baseColor: root.numberKeyColor; Layout.preferredWidth: 90; onTriggered: root.appState.insertOnScreenKeyboardText(label) }
                    }
                    Repeater {
                        model: 10
                        KeyboardKey { required property int index; objectName: "qwerty-row1-key-" + index; readonly property string baseText: root.appState && root.appState.onScreenKeyboardSymbols ? root.symbolRows[1][index] : root.textRows[1][index]; label: root.appState && root.appState.onScreenKeyboardShiftState !== "NONE" && !root.appState.onScreenKeyboardSymbols ? baseText.toUpperCase() : baseText.toLowerCase(); Layout.preferredWidth: 90; onTriggered: root.typeQwerty(label) }
                    }
                    Repeater {
                        model: 9
                        KeyboardKey { required property int index; objectName: "qwerty-row2-key-" + index; readonly property string baseText: root.appState && root.appState.onScreenKeyboardSymbols ? root.symbolRows[2][index] : root.textRows[2][index]; label: root.appState && root.appState.onScreenKeyboardShiftState !== "NONE" && !root.appState.onScreenKeyboardSymbols ? baseText.toUpperCase() : baseText.toLowerCase(); Layout.preferredWidth: 90; onTriggered: root.typeQwerty(label) }
                    }
                    KeyboardKey { objectName: "qwerty-delete-key"; label: "⌫"; helper: qsTr("DEL"); baseColor: root.functionColor; labelSize: 30; Layout.preferredWidth: 90; onTriggered: root.appState.backspaceOnScreenKeyboard() }
                    KeyboardKey { objectName: "qwerty-shift-key"; label: root.appState && root.appState.onScreenKeyboardSymbols ? "|" : "⇧"; baseColor: root.appState && root.appState.onScreenKeyboardShiftState === "SHIFT" ? "#2D83B2" : root.functionColor; labelSize: 35; Layout.preferredWidth: 90; onTriggered: if (root.appState.onScreenKeyboardSymbols) root.typeQwerty("|"); else root.appState.cycleOnScreenKeyboardShift() }
                    Repeater {
                        model: 7
                        KeyboardKey { required property int index; objectName: "qwerty-row3-key-" + index; readonly property string baseText: root.appState && root.appState.onScreenKeyboardSymbols ? root.symbolRows[3][index] : root.textRows[3][index]; label: root.appState && root.appState.onScreenKeyboardShiftState !== "NONE" && !root.appState.onScreenKeyboardSymbols ? baseText.toUpperCase() : baseText.toLowerCase(); Layout.preferredWidth: 90; onTriggered: root.typeQwerty(label) }
                    }
                    KeyboardKey { objectName: "qwerty-left-key"; label: "◀"; baseColor: root.functionColor; Layout.preferredWidth: 90; onTriggered: root.appState.moveOnScreenKeyboardCursor(-1) }
                    KeyboardKey { objectName: "qwerty-right-key"; label: "▶"; baseColor: root.functionColor; Layout.preferredWidth: 90; onTriggered: root.appState.moveOnScreenKeyboardCursor(1) }
                    KeyboardKey { objectName: "qwerty-symbol-key"; label: root.appState && root.appState.onScreenKeyboardSymbols ? qsTr("ABC") : "!@#"; baseColor: root.functionColor; labelSize: 19; Layout.preferredWidth: 90; onTriggered: root.appState.onScreenKeyboardSymbols = !root.appState.onScreenKeyboardSymbols }
                    KeyboardKey { objectName: "qwerty-comma-key"; label: ","; Layout.preferredWidth: 90; onTriggered: root.typeQwerty(",") }
                    KeyboardKey { objectName: "qwerty-space-key"; label: "▔"; labelSize: 42; Layout.columnSpan: 4; onTriggered: root.typeQwerty(" ") }
                    KeyboardKey { objectName: "qwerty-period-key"; label: "."; onTriggered: root.typeQwerty(".") }
                    KeyboardKey { objectName: "qwerty-ok-key"; label: "→"; helper: qsTr("OK"); baseColor: root.functionColor; labelSize: 39; Layout.columnSpan: 3; onTriggered: root.appState.commitOnScreenKeyboard() }
                }
            }
        }
    }

    function typeQwerty(text) {
        if (!appState)
            return
        appState.insertOnScreenKeyboardText(text)
        if (appState.onScreenKeyboardShiftState === "SHIFT")
            appState.onScreenKeyboardShiftState = "NONE"
    }

    component KeyboardKey: Button {
        id: key
        property string label: ""
        property string helper: ""
        property color baseColor: root.keyColor
        property int labelSize: 26
        signal triggered()

        Layout.fillWidth: !root.numeric
        Layout.fillHeight: false
        Layout.preferredWidth: root.numeric ? 89 : -1
        Layout.minimumWidth: root.numeric ? 89 : 58
        Layout.maximumWidth: root.numeric ? 89 : Number.POSITIVE_INFINITY
        Layout.preferredHeight: root.numeric ? 89 : 81
        Layout.minimumHeight: root.numeric ? 89 : 81
        Layout.maximumHeight: root.numeric ? 89 : 81
        activeFocusOnTab: true
        Accessible.name: helper.length > 0 ? label + " " + helper : label

        contentItem: Item {
            objectName: "osk-key-content"

            Text {
                objectName: "osk-key-label"
                visible: key.helper.length === 0
                anchors.fill: parent
                text: key.label
                color: root.white
                font.pixelSize: key.labelSize
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Column {
                visible: key.helper.length > 0
                width: parent.width
                height: implicitHeight
                anchors.centerIn: parent
                spacing: 1

                Text {
                    objectName: "osk-key-compound-label"
                    width: parent.width
                    text: key.label
                    color: root.white
                    font.pixelSize: key.labelSize
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    objectName: "osk-key-helper"
                    width: parent.width
                    text: key.helper
                    color: root.white
                    font.pixelSize: 15
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
        background: Rectangle { radius: 5; color: key.down ? Qt.darker(key.baseColor, 1.12) : key.baseColor }
        onClicked: triggered()
    }
}
