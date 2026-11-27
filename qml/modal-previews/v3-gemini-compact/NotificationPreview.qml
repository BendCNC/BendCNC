import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    width: 550
    height: 300
    radius: 12
    color: "#F5F5F5"
    clip: true
    border.color: "#A8A8A8"
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: "#A82011"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                Text { text: "⚠"; color: "white"; font.pixelSize: 25 }
                Text { text: qsTr("OPERATION ERROR"); color: "white"; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 24
            text: qsTr("The requested operation could not be completed. Review the machine state and try again.")
            color: "#232323"
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 70
            color: "white"
            Button { anchors.centerIn: parent; width: 150; height: 44; text: qsTr("CLOSE") }
        }
    }
}