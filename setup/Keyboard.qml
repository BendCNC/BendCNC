import QtQuick
import QtQuick.Layouts

// On-screen keyboard for the touch-only press. Keys are MouseAreas so they
// never take focus away from the target field.
Rectangle {
    id: kb
    property Item target: null
    readonly property bool numeric: target !== null && (target.inputMethodHints & Qt.ImhDigitsOnly)
    property bool shift: false
    property bool symbols: false
    signal done()

    color: "#0b0f13"
    implicitHeight: 250

    function press(k) {
        if (!target) return
        if (k === "\u232B") {
            if (target.selectedText.length > 0) target.remove(target.selectionStart, target.selectionEnd)
            else if (target.cursorPosition > 0) target.remove(target.cursorPosition - 1, target.cursorPosition)
        } else {
            if (target.selectedText.length > 0) target.remove(target.selectionStart, target.selectionEnd)
            target.insert(target.cursorPosition, k)
            if (shift && k.length === 1) shift = false
        }
    }

    readonly property var letterRows: [
        "1234567890".split(""),
        "qwertyuiop".split(""),
        "asdfghjkl".split(""),
        ["\u21E7"].concat("zxcvbnm".split("")).concat(["\u232B"]),
        ["#+=", "@", ".", "-", "_", " ", ".com", "Done"]
    ]
    readonly property var symbolRows: [
        "1234567890".split(""),
        "!#$%&*+=?^".split(""),
        "~()[]{}/\\|".split(""),
        ["\u21E7"].concat(":;,'\"<>".split("")).concat(["\u232B"]),
        ["abc", "@", ".", "-", "_", " ", "`", "Done"]
    ]
    readonly property var numRows: [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["Done", "0", "\u232B"]]

    component Key: Rectangle {
        id: key
        property string k
        property real units: k === " " ? 4 : (k === "Done" || k === ".com" || k === "\u232B" || k === "\u21E7" || k === "#+=" || k === "abc") ? 1.6 : 1
        readonly property bool special: k === "Done" || k === "\u21E7" || k === "#+=" || k === "abc" || k === "\u232B"
        Layout.fillWidth: true; Layout.fillHeight: true
        Layout.preferredWidth: units * 100
        radius: 8
        color: ma.pressed ? "#ff8a1f" : k === "Done" ? "#3a2a16" : special ? "#222b35" : "#1a2129"
        border.color: (k === "\u21E7" && kb.shift) ? "#ff8a1f" : "#2a333d"
        Text {
            anchors.centerIn: parent
            text: key.k === " " ? "space" : (kb.shift && key.k.length === 1 ? key.k.toUpperCase() : key.k)
            color: ma.pressed ? "#1a1004" : key.k === "Done" ? "#ff8a1f" : "#e8edf2"
            font.pixelSize: key.k.length === 1 ? 24 : 17; font.bold: key.k === "Done"
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            onClicked: {
                if (key.k === "Done") kb.done()
                else if (key.k === "\u21E7") kb.shift = !kb.shift
                else if (key.k === "#+=") kb.symbols = true
                else if (key.k === "abc") kb.symbols = false
                else kb.press(kb.shift && key.k.length === 1 ? key.k.toUpperCase() : key.k)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 8; spacing: 6
        Repeater {
            model: kb.numeric ? kb.numRows : kb.symbols ? kb.symbolRows : kb.letterRows
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.maximumWidth: kb.numeric ? 480 : kb.width
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                Repeater {
                    model: parent.modelData
                    delegate: Key { required property string modelData; k: modelData }
                }
            }
        }
    }
}
