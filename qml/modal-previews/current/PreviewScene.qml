pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../.." as Production

Item {
    id: root
    anchors.fill: parent
    property string selectedPreview: {
        for (var arg of Qt.application.arguments) {
            if (arg.indexOf("--modal-preview-selection=") === 0)
                return arg.substring("--modal-preview-selection=".length)
        }
        return "RIGHT_PANEL"
    }
    // Set by ModalPreviewer's LIVE CANVAS toggle.
    property bool designerLiveCanvas: false
    readonly property bool surfaceSelected: selectedPreview.indexOf("LEFT_") === 0
        || selectedPreview === "ACTION_BAR" || selectedPreview === "TOOL_BAR"
    readonly property var previews: [
        { key: "RIGHT_PANEL", label: qsTr("Right panel"), family: qsTr("462 × 668 · Production") },
        { key: "ACTION_BAR", label: qsTr("Upper action bar"), family: qsTr("1366 × 40 · Production") },
        { key: "TOOL_BAR", label: qsTr("Connection bar"), family: qsTr("1366 × 50 · Production") },
        { key: "LEFT_0", label: qsTr("RUN left panel"), family: qsTr("Controls · LIVE CANVAS toggle") },
        { key: "LEFT_1", label: qsTr("CREATE BEND left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_2", label: qsTr("TOOLS left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_3", label: qsTr("BACK GAUGE left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_4", label: qsTr("MANUAL left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_5", label: qsTr("CAD left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_6", label: qsTr("SETTINGS left"), family: qsTr("864 × 668 · Production") },
        { key: "CALIBRATION", label: qsTr("Calibration"), family: qsTr("950 × 600 · Operational") },
        { key: "MEASUREMENT", label: qsTr("Measurement"), family: qsTr("950 × 600 · Operational") },
        { key: "BLEED", label: qsTr("Bleed"), family: qsTr("950 × 600 · Operational") },
        { key: "CAD_RESULT", label: qsTr("CAD result"), family: qsTr("950 × 600 · Operational") },
        { key: "ALARM", label: qsTr("Machine alarm"), family: qsTr("850 × 500 · Critical") },
        { key: "ERROR", label: qsTr("Error notification"), family: qsTr("550 × 300 · Notification") },
        { key: "CONFIRMATION", label: qsTr("Confirmation"), family: qsTr("550 × 300 · Notification") },
        { key: "PROGRESS", label: qsTr("Progress"), family: qsTr("550 × 300 · Notification") }
    ]

    Production.AppState {
        id: previewState
        offlineSimulationEnabled: true
        manualModeArmed: true
        ramPosition: 1.375
        tonnageHoldTarget: 1.0

        manualMeasurementVisible: root.selectedPreview === "CALIBRATION"
            || root.selectedPreview === "MEASUREMENT"
        manualMeasurementMode: root.selectedPreview
        manualMeasurementStatus: root.selectedPreview === "CALIBRATION"
            ? "READY TO CALIBRATE" : "READY FOR PIECE"

        alarmVisible: root.selectedPreview === "ALARM"
        alarmTitle: "MACHINE ALARM"
        alarmBody: "Release the active safety condition before continuing."

        popupVisible: root.selectedPreview === "BLEED"
            || root.selectedPreview === "CAD_RESULT"
            || root.selectedPreview === "ERROR"
            || root.selectedPreview === "CONFIRMATION"
            || root.selectedPreview === "PROGRESS"
        popupKind: root.selectedPreview === "BLEED" ? "bleed-procedure"
            : root.selectedPreview === "CAD_RESULT" ? "cad-result"
            : root.selectedPreview === "CONFIRMATION" ? "caution"
            : root.selectedPreview === "PROGRESS" ? "blur" : "message"
        popupTitle: root.selectedPreview === "CAD_RESULT" ? "BEND PROGRAM READY"
            : root.selectedPreview === "CONFIRMATION" ? "DELETE PROGRAM"
            : root.selectedPreview === "PROGRESS" ? "UPDATING MACHINE" : "OPERATION ERROR"
        popupBody: root.selectedPreview === "CONFIRMATION"
            ? "Delete this program? This action cannot be undone."
            : root.selectedPreview === "PROGRESS"
                ? "Waiting for the machine to complete the requested operation."
                : "The requested operation could not be completed. Review the machine state and try again."
        popupProgress: 0.45
        popupButtonText: root.selectedPreview === "CONFIRMATION" ? "DELETE" : "CLOSE"
        popupCancelButtonText: "CANCEL"
        popupAction: root.selectedPreview === "CONFIRMATION" ? "confirmation" : ""
        popupResultData: ({
            programName: "Battery Plate N1",
            partName: "Battery Plate N1",
            material: "Steel",
            thickness: "0.0600 in",
            bendCount: 4,
            saved: true,
            storageLabel: "SAVED · backup protected",
            rows: [
                { seq: 1, angle: "90.0", setup: "STD", tooling: "GN88 / 8mm", bg: "0.9494", reference: "EDGE", status: "OK" },
                { seq: 2, angle: "90.0", setup: "STD", tooling: "GN88 / 8mm", bg: "0.9494", reference: "EDGE", status: "OK" },
                { seq: 3, angle: "45.0", setup: "STD", tooling: "GN88 / 8mm", bg: "1.2500", reference: "EDGE", status: "OK" },
                { seq: 4, angle: "90.0", setup: "STD", tooling: "GN88 / 8mm", bg: "2.1250", reference: "EDGE", status: "OK" }
            ]
        })
    }

    Production.ModalDesignerCanvasSource {
        id: canvasSource
        appState: previewState
        active: root.designerLiveCanvas
    }

    Production.ModalDesignerSurface {
        x: 204; y: 58
        selection: root.selectedPreview
        appState: previewState
        liveCanvas: root.designerLiveCanvas
        dataStore: canvasSource.dataStore
        visible: root.surfaceSelected
        onPageRequested: function(index) { root.selectedPreview = "LEFT_" + index }
    }

    Rectangle {
        anchors.fill: parent
        color: "#D5D7DA"
        visible: root.selectedPreview === "RIGHT_PANEL"

        Rectangle {
            anchors.centerIn: parent
            width: 490
            height: 696
            radius: 11
            color: "#BFC2C5"
            border.color: "#8B8E91"
            border.width: 1

            Production.ColumnRightView {
                anchors.centerIn: parent
                width: 462
                height: 668
                appState: previewState
            }
        }
    }

    Production.ManualMeasurementPopup {
        x: 204; y: 58; width: 1366; height: 768
        appState: previewState
    }
    Production.MachinePopupLayer {
        x: 204; y: 58; width: 1366; height: 768
        appState: previewState
    }
    Production.MachineAlarmPopupLayer {
        x: 204; y: 58; width: 1366; height: 768
        appState: previewState
    }

    Rectangle {
        id: rail
        z: 20000
        width: 192
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: "#232323"
        Flickable {
            anchors.fill: parent
            anchors.margins: 14
            contentHeight: railContents.implicitHeight
            contentWidth: width
            clip: true
            ColumnLayout {
            id: railContents
            width: rail.width - 28
            spacing: 8
            Text {
                text: qsTr("CURRENT QT\nMODALS")
                color: "white"
                font.pixelSize: 21
                font.bold: true
                lineHeight: 0.95
            }
            Text { text: qsTr("Live production QML"); color: "#59A60C"; font.pixelSize: 13; font.bold: true }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#555555" }
            Repeater {
                model: root.previews
                Button {
                    id: previewButton
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    text: modelData.label + "\n" + modelData.family
                    onClicked: root.selectedPreview = modelData.key
                    contentItem: Text {
                        text: previewButton.text
                        color: "white"
                        font.pixelSize: 11
                        font.bold: root.selectedPreview === previewButton.modelData.key
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 9
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
            Item { Layout.preferredHeight: 8 }
            Text {
                text: qsTr("Reference only\nUse v1+ for proposals")
                color: "#A8A8A8"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            }
        }
    }
}