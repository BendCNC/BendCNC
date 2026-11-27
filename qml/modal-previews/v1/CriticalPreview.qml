import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    width: 850
    height: 500
    radius: 12
    color: "transparent"
    clip: true
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#A82011"
            Column {
                anchors.centerIn: parent
                width: parent.width - 60
                spacing: 16
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "⚠"; color: "white"; font.pixelSize: 80 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("MACHINE ALARM"); color: "white"; font.pixelSize: 34; font.bold: true }
                Text { width: parent.width; text: qsTr("Release the active safety condition before continuing."); color: "white"; font.pixelSize: 21; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 90
            color: "white"
            Button { anchors.centerIn: parent; width: 190; height: 58; text: qsTr("CLEAR") }
        }
    }
}