import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property string mode
    width: 950
    height: 600
    radius: 12
    color: "#F5F5F5"
    clip: true

    readonly property bool bleedMode: mode === "BLEED"
    readonly property string heading: bleedMode ? qsTr("BLEED HYDRAULICS")
        : mode === "CALIBRATION" ? qsTr("DIE TOP CALIBRATION") : qsTr("PIECE MEASUREMENT")

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "#A82011"
            Column {
                anchors.centerIn: parent
                spacing: 3
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.heading; color: "white"; font.pixelSize: 27; font.bold: true }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.bleedMode ? qsTr("Supervised service procedure") : qsTr("Realtime Y1/Y2 contact measurement"); color: "white"; font.pixelSize: 16 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 10

            GridLayout {
                visible: !root.bleedMode
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 8
                columnSpacing: 8
                Repeater {
                    model: ["Y1 POSITION", "Y2 POSITION", "Y1 / Y2 MEAN", "Y1 - Y2", "Y1 TONNAGE", "Y2 TONNAGE", "TOTAL APPLIED", "TARGET"]
                    Rectangle {
                        id: fieldCard
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 66
                        radius: 7
                        color: "#E0E0E0"
                        border.color: modelData.indexOf("TONNAGE") >= 0 || modelData === "TOTAL APPLIED" ? "#59A60C" : "#2D83B2"
                        border.width: 2
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: fieldCard.modelData; color: "#2B2C2B"; font.pixelSize: 12; font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: fieldCard.modelData.indexOf("POSITION") >= 0 ? "1.3750 in" : "0.500 T"; color: "#2D83B2"; font.pixelSize: 18; font.bold: true }
                        }
                    }
                }
            }

            RowLayout {
                visible: root.bleedMode
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                spacing: 12
                Repeater {
                    model: [qsTr("LEFT PALM SWITCH\nLOGICAL Y1 OUTPUT"), qsTr("RIGHT PALM SWITCH\nLOGICAL Y2 OUTPUT")]
                    Rectangle {
                        id: bleedCard
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: "#E0E0E0"
                        border.color: "#2D83B2"
                        border.width: 2
                        Text { anchors.centerIn: parent; text: bleedCard.modelData; color: "#232323"; font.pixelSize: 18; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: root.bleedMode ? "#ECECEC" : "#2B2C2B"
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    text: root.bleedMode
                        ? qsTr("BLEED PROCEDURE\n1  Remove tooling and keep clear.\n2  Open the selected cylinder bleeder.\n3  Hold the corresponding palm switch.\n4  Tighten before releasing the switch.")
                        : root.mode === "CALIBRATION" ? qsTr("KNOWN PIECE SIZE    0.1250 in\n\nREADY TO CALIBRATE") : qsTr("CALIBRATED DIE TOP REFERENCE\n\nREADY FOR PIECE")
                    color: root.bleedMode ? "#232323" : "white"
                    font.pixelSize: root.bleedMode ? 17 : 20
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "white"
            Row {
                anchors.centerIn: parent
                spacing: 14
                Repeater {
                    model: root.bleedMode ? [qsTr("COMPLETE"), qsTr("CANCEL / DISABLE")] : [qsTr("PEDAL"), qsTr("AUTO"), qsTr("CLOSE")]
                    Button { required property string modelData; width: 190; height: 52; text: modelData }
                }
            }
        }
    }
}