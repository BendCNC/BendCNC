import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    objectName: "column-right-group-header user-control-view"
    spacing: 4

    Text { text: "CONTROLS"; color: "white"; font.bold: true; font.pixelSize: 16; Layout.alignment: Qt.AlignVCenter }
    Item { Layout.fillWidth: true }
}
