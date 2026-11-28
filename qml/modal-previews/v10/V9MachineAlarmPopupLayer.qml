pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "../.." as Production

Item {
    id: alarmLayer
    Production.ModalMetrics { id: modalMetrics }
    objectName: "alarm-popup MachineAlarmPopupView panePopup container body footer right-spacer label-title label-content buttonClear"
    property var appState: null
    visible: alarmLayer.appState ? alarmLayer.appState.alarmVisible : false
    anchors.fill: parent
    focus: visible
    z: 9100

    readonly property string currentTitle: alarmLayer.appState && alarmLayer.appState.alarmTitle ? String(alarmLayer.appState.alarmTitle) : qsTr("MACHINE ALARM")
    readonly property string currentBody: alarmLayer.appState && alarmLayer.appState.alarmBody ? String(alarmLayer.appState.alarmBody) : qsTr("Clear the condition before continuing.")
    readonly property bool isSerialDisconnect: {
        const t = currentTitle.toUpperCase()
        return t.indexOf("DISCONNECT") >= 0 || t.indexOf("SERIAL") >= 0
            || t.indexOf("NOT CONNECTED") >= 0 || t.indexOf("COMMUNICATION") >= 0
    }

    Keys.onEscapePressed: function(event) { event.accepted = true }

    // Scrim overlay
    Rectangle {
        anchors.fill: parent
        color: "#A6000000"
    }
    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

    // Modal Container (Subtle, familiar industrial alarm card, perfectly proportioned)
    Rectangle {
        id: container
        objectName: "container"
        width: 820
        height: 480
        anchors.centerIn: parent
        radius: 10
        color: "#A82011"
        border.color: "#3F0B05"
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // -----------------------------------------------------------------
            // Alarm Body (Safety Crimson Red, high contrast, clean centering)
            // -----------------------------------------------------------------
            Rectangle {
                id: bodyRect
                objectName: "body"
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#A82011"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 28
                    spacing: 12

                    Item { Layout.fillHeight: true }

                    // Safety Warning Badge / Icon
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 72
                        radius: 36
                        color: "#26FFFFFF"
                        border.color: "#4DFFFFFF"
                        border.width: 2

                        Text {
                            anchors.centerIn: parent
                            text: "⚠"
                            color: "white"
                            font.pixelSize: 42
                            Accessible.ignored: true
                        }
                    }

                    // Status pill tag (Context aware, subtle)
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: tagText.implicitWidth + 24
                        radius: 11
                        color: "#33000000"

                        Text {
                            id: tagText
                            anchors.centerIn: parent
                            text: alarmLayer.isSerialDisconnect ? qsTr("COMMUNICATION FAULT") : qsTr("HARDWARE SAFETY INTERLOCK")
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                    }

                    // Alarm Title (Centered, bold, clear)
                    Text {
                        id: titleLabel
                        objectName: "label-title"
                        text: alarmLayer.currentTitle
                        color: "white"
                        font.bold: true
                        font.pixelSize: 30
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                    }

                    // Alarm Body Content (Centered, readable line height, comfortable margins)
                    Text {
                        id: contentLabel
                        objectName: "label-content"
                        text: alarmLayer.currentBody
                        color: "#FDE8E8"
                        font.pixelSize: 17
                        lineHeight: 1.3
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillWidth: true
                        Layout.maximumWidth: 700
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Divider line between body and footer
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#85170B"
            }

            // -----------------------------------------------------------------
            // Footer (Clean off-white industrial base, tactile centered clear button)
            // -----------------------------------------------------------------
            Rectangle {
                id: footerRect
                objectName: "footer"
                Layout.fillWidth: true
                Layout.preferredHeight: 74
                color: "#F8FAFC"

                Button {
                    id: btnClear
                    objectName: "buttonClear"
                    anchors.centerIn: parent
                    width: 200
                    height: 48
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0
                    activeFocusOnTab: true
                    Accessible.name: qsTr("Clear alarm")

                    contentItem: Text {
                        text: qsTr("CLEAR ALARM")
                        color: "white"
                        font.bold: true
                        font.pixelSize: 15
                        font.letterSpacing: 0.5
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: 6
                        color: btnClear.down ? "#7B140B" : "#A82011"
                        border.color: btnClear.activeFocus ? "#232323" : "#6E130A"
                        border.width: btnClear.activeFocus ? 2 : 1
                    }

                    onClicked: {
                        if (alarmLayer.appState && typeof alarmLayer.appState.clearAlarm === "function")
                            alarmLayer.appState.clearAlarm()
                    }
                }
            }
        }
    }
}
