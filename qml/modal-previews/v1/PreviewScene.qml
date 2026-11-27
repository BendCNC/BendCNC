pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent
    property string selectedPreview: "CALIBRATION"
    readonly property var previews: [
        { key: "CALIBRATION", label: qsTr("Calibration"), family: qsTr("950 × 600 · Operational") },
        { key: "MEASUREMENT", label: qsTr("Measurement"), family: qsTr("950 × 600 · Operational") },
        { key: "BLEED", label: qsTr("Bleed"), family: qsTr("950 × 600 · Operational") },
        { key: "ALARM", label: qsTr("Machine alarm"), family: qsTr("850 × 500 · Critical") },
        { key: "ERROR", label: qsTr("Error notification"), family: qsTr("550 × 300 · Notification") }
    ]

    Rectangle {
        anchors.fill: parent
        color: "#D5D7DA"
    }

    Rectangle {
        id: rail
        width: 184
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: "#232323"
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8
            Text {
                text: qsTr("MODAL\nDESIGN LAB")
                color: "white"
                font.pixelSize: 22
                font.bold: true
                lineHeight: 0.95
            }
            Text {
                text: qsTr("Version v1")
                color: "#A8A8A8"
                font.pixelSize: 14
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#555555" }
            Repeater {
                model: root.previews
                Button {
                    id: previewButton
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    text: modelData.label + "\n" + modelData.family
                    onClicked: root.selectedPreview = modelData.key
                    contentItem: Text {
                        text: previewButton.text
                        color: "white"
                        font.pixelSize: 12
                        font.bold: root.selectedPreview === previewButton.modelData.key
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 10
                    }
                    background: Rectangle {
                        radius: 7
                        color: root.selectedPreview === previewButton.modelData.key
                            ? "#2D83B2" : (previewButton.down ? "#444444" : "#2B2C2B")
                        border.color: root.selectedPreview === previewButton.modelData.key
                            ? "white" : "#555555"
                    }
                }
            }
            Item { Layout.fillHeight: true }
            Text {
                text: qsTr("Edit files in\nmodal-previews/v1")
                color: "#A8A8A8"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }

    Rectangle {
        anchors.left: rail.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: "#A6000000"
    }

    OperationalPreview {
        anchors.centerIn: previewArea
        visible: root.selectedPreview === "CALIBRATION"
            || root.selectedPreview === "MEASUREMENT"
            || root.selectedPreview === "BLEED"
        mode: root.selectedPreview
    }

    CriticalPreview {
        anchors.centerIn: previewArea
        visible: root.selectedPreview === "ALARM"
    }

    NotificationPreview {
        anchors.centerIn: previewArea
        visible: root.selectedPreview === "ERROR"
    }

    Item {
        id: previewArea
        anchors.left: rail.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
    }
}