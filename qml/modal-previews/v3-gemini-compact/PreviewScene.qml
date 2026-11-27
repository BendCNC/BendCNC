pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../.." as Production

Item {
    id: root
    anchors.fill: parent
    property string selectedPreview: "CALIBRATION"

    readonly property var previews: [
        { key: "CALIBRATION", label: qsTr("Calibration (v3)"), family: qsTr("950 × 600 · Harmonized") },
        { key: "MEASUREMENT", label: qsTr("Measurement"), family: qsTr("950 × 600 · Production") },
        { key: "BLEED", label: qsTr("Bleed"), family: qsTr("950 × 600 · Production") },
        { key: "ALARM", label: qsTr("Machine alarm"), family: qsTr("850 × 500 · Production") },
        { key: "ERROR", label: qsTr("Error notification"), family: qsTr("550 × 300 · Production") }
    ]

    Production.AppState {
        id: productionPreviewState
        offlineSimulationEnabled: true
        manualModeArmed: true
        ramPosition: 1.375
        tonnageHoldTarget: 1.0

        manualMeasurementVisible: root.selectedPreview === "MEASUREMENT"
        manualMeasurementMode: "MEASUREMENT"
        manualMeasurementStatus: "READY FOR PIECE"

        alarmVisible: root.selectedPreview === "ALARM"
        alarmTitle: "MACHINE ALARM"
        alarmBody: "Release the active safety condition before continuing."

        popupVisible: root.selectedPreview === "BLEED"
            || root.selectedPreview === "ERROR"
        popupKind: root.selectedPreview === "BLEED" ? "bleed-procedure" : "message"
        popupTitle: "OPERATION ERROR"
        popupBody: "The requested operation could not be completed. Review the machine state and try again."
        popupButtonText: "CLOSE"
    }

    // -------------------------------------------------------------------------
    // Interactive Simulation State
    // -------------------------------------------------------------------------
    property int simPhase: 0 // 0: Ready, 1: Sampling (4/10), 2: Calibrated (10/10)
    property bool simTelemetryReady: true
    property bool simDieTopCalibrated: true
    property string simHeaderTheme: "RED" // "RED" | "BLUE"
    property string simUnit: "INCH"
    property real simThicknessInches: 0.1250
    property real simThicknessMm: 3.1750
    property bool simPedalActive: false
    property bool simAutoActive: false
    property string toastMessage: ""

    Timer {
        id: toastTimer
        interval: 2200
        repeat: false
        onTriggered: root.toastMessage = ""
    }

    function showToast(msg: string) {
        root.toastMessage = msg
        toastTimer.restart()
    }

    function cycleSimPhase() {
        root.simPhase = (root.simPhase + 1) % 3
        if (root.simPhase === 0) {
            root.simPedalActive = false
            root.simAutoActive = false
            root.showToast(qsTr("Reset to READY TO CALIBRATE"))
        } else if (root.simPhase === 1) {
            root.simAutoActive = true
            root.showToast(qsTr("Simulating: Active Contact (4 / 10 samples)"))
        } else {
            root.simAutoActive = false
            root.simDieTopCalibrated = true
            root.showToast(qsTr("Simulating: Calibrated & Datum Stored (10 / 10)"))
        }
    }

    function cycleThickness() {
        if (root.simThicknessInches === 0.1250) {
            root.simThicknessInches = 0.0600
            root.simThicknessMm = 1.5240
            root.showToast(qsTr("Shim: 0.0600 in (16 ga)"))
        } else if (root.simThicknessInches === 0.0600) {
            root.simThicknessInches = 0.2500
            root.simThicknessMm = 6.3500
            root.showToast(qsTr("Shim: 0.2500 in (1/4\")"))
        } else {
            root.simThicknessInches = 0.1250
            root.simThicknessMm = 3.1750
            root.showToast(qsTr("Shim: 0.1250 in (1/8\")"))
        }
    }

    // Standard application canvas background
    Rectangle {
        anchors.fill: parent
        color: "#D5D7DA"
    }

    // =========================================================================
    // LEFT NAVIGATION & SIMULATOR RAIL (Width: 194px)
    // =========================================================================
    Rectangle {
        id: rail
        width: 194
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: "#232323"
        z: 20000

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            Text {
                text: qsTr("MODAL\nDESIGN LAB")
                color: "white"
                font.pixelSize: 20
                font.bold: true
                lineHeight: 0.95
            }

            Text {
                text: qsTr("Version v3-gemini-compact")
                color: "#59A60C"
                font.pixelSize: 11
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#555555" }

            Repeater {
                model: root.previews
                Button {
                    id: previewButton
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: previewButton.modelData.label + "\n" + previewButton.modelData.family
                    onClicked: root.selectedPreview = previewButton.modelData.key

                    contentItem: Text {
                        text: previewButton.text
                        color: "white"
                        font.pixelSize: 11
                        font.bold: root.selectedPreview === previewButton.modelData.key
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 8
                    }

                    background: Rectangle {
                        radius: 6
                        color: root.selectedPreview === previewButton.modelData.key
                            ? "#2D83B2" : (previewButton.down ? "#444444" : "#2B2C2B")
                        border.color: root.selectedPreview === previewButton.modelData.key
                            ? "white" : "#555555"
                    }
                }
            }

            // Interactive simulation controls for Calibration
            Item { Layout.fillHeight: true }

            Rectangle {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#555555"
            }

            Text {
                visible: root.selectedPreview === "CALIBRATION"
                text: qsTr("SIMULATION CONTROLS")
                color: "#A8A8A8"
                font.pixelSize: 9
                font.bold: true
            }

            // Cycle calibration phase
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                onClicked: root.cycleSimPhase()
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simPhase === 0 ? qsTr("Phase: 1. READY")
                        : (root.simPhase === 1 ? qsTr("Phase: 2. SAMPLING") : qsTr("Phase: 3. CALIBRATED"))
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#2D83B2"
                }
            }

            // Toggle Header Theme (Red vs Blue)
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                onClicked: {
                    root.simHeaderTheme = root.simHeaderTheme === "RED" ? "BLUE" : "RED"
                    root.showToast(qsTr("Header theme: %1").arg(root.simHeaderTheme))
                }
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simHeaderTheme === "RED" ? qsTr("Header: RED (#A82011)") : qsTr("Header: BLUE (#2D83B2)")
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: root.simHeaderTheme === "RED" ? "#A82011" : "#2D83B2"
                }
            }

            // Toggle Die Top State
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                onClicked: {
                    root.simDieTopCalibrated = !root.simDieTopCalibrated
                    root.showToast(root.simDieTopCalibrated ? qsTr("Die Top: Calibrated") : qsTr("Die Top: NOT Calibrated"))
                }
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simDieTopCalibrated ? qsTr("Die Top: STORED (1.2500)") : qsTr("Die Top: NOT CALIBRATED")
                    color: root.simDieTopCalibrated ? "#59A60C" : "#FFA500"
                    font.pixelSize: 10
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#383838"
                    border.color: "#555555"
                }
            }

            // Toggle Sensors Online/Offline
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                onClicked: {
                    root.simTelemetryReady = !root.simTelemetryReady
                    root.showToast(root.simTelemetryReady ? qsTr("Sensors Online") : qsTr("Sensors Offline"))
                }
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simTelemetryReady ? qsTr("Sensors: LIVE (1.3750)") : qsTr("Sensors: OFFLINE (----)")
                    color: root.simTelemetryReady ? "#59A60C" : "#A82011"
                    font.pixelSize: 10
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#383838"
                    border.color: "#555555"
                }
            }

            // Cycle Shim Thickness
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                onClicked: root.cycleThickness()
                contentItem: Text {
                    anchors.centerIn: parent
                    text: qsTr("Shim: %1 in").arg(root.simThicknessInches.toFixed(4))
                    color: "#2D83B2"
                    font.pixelSize: 10
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#383838"
                    border.color: "#555555"
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#555555" }

            Text {
                text: qsTr("Canvas: 1366 × 768\nModal: 950 × 600")
                color: "#A8A8A8"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }
    }

    // =========================================================================
    // PREVIEW CANVAS AREA (the exact 1366 × 768 production coordinate space)
    // =========================================================================
    Item {
        id: previewArea
        anchors.fill: parent

        // Standard production dark modal backdrop (scrim: #A6000000)
        Rectangle {
            anchors.fill: parent
            color: "#A6000000"
        }

        // ---------------------------------------------------------------------
        // CALIBRATION (V3 HARMONIZED REDESIGN CANDIDATE)
        // ---------------------------------------------------------------------
        CalibrationModal {
            id: calibrationModal
            anchors.centerIn: parent
            visible: root.selectedPreview === "CALIBRATION"

            headerColorTheme: root.simHeaderTheme
            telemetryReady: root.simTelemetryReady
            ramPositionY1: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? 1.2510 : 1.2500)) : 0
            ramPositionY2: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? 1.2512 : 1.2500)) : 0
            ramPositionMean: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? 1.2511 : 1.2500)) : 0

            ramLoadY1: root.simTelemetryReady ? (root.simPhase === 0 ? 0.000 : (root.simPhase === 1 ? 0.501 : 0.500)) : 0
            ramLoadY2: root.simTelemetryReady ? (root.simPhase === 0 ? 0.000 : (root.simPhase === 1 ? 0.501 : 0.500)) : 0
            tonnageHoldTarget: 1.000

            knownPieceUnit: root.simUnit
            knownPieceThicknessInches: root.simThicknessInches
            knownPieceThicknessMm: root.simThicknessMm

            dieTopCalibrationValid: root.simDieTopCalibrated
            calibratedDieTop: 1.2500

            measurementStatus: root.simPhase === 0 ? qsTr("READY TO CALIBRATE")
                : (root.simPhase === 1 ? qsTr("QUALIFYING CONTACT") : qsTr("CALIBRATION COMPLETE"))

            measurementResult: root.simPhase === 2 ? root.simThicknessInches : Number.NaN
            requiredSamples: 10
            qualifiedSamples: root.simPhase === 0 ? 0 : (root.simPhase === 1 ? 4 : 10)
            processActive: root.simPhase === 1
            appliedLoadMean: root.simPhase > 0 ? 1.002 : Number.NaN
            appliedLoadPeak: root.simPhase > 0 ? 1.015 : Number.NaN
            acceptedSamples: root.simPhase === 2 ? 10 : (root.simPhase === 1 ? 4 : 0)
            acceptedDurationMs: root.simPhase === 2 ? 2800 : (root.simPhase === 1 ? 1100 : 0)

            tonnageHoldActive: root.simPedalActive
            contactProfileActive: root.simAutoActive

            onPedalRequested: {
                root.simPedalActive = !root.simPedalActive
                if (root.simPedalActive) {
                    root.simAutoActive = false
                    root.simPhase = 1
                    root.showToast(qsTr("PEDAL pressed: Contact holding active"))
                } else {
                    root.showToast(qsTr("PEDAL released / stopped"))
                }
            }

            onAutoRequested: {
                root.simAutoActive = !root.simAutoActive
                if (root.simAutoActive) {
                    root.simPedalActive = false
                    root.simPhase = 1
                    root.showToast(qsTr("AUTO started: Qualifying contact..."))
                } else {
                    root.showToast(qsTr("AUTO cancelled"))
                }
            }

            onCloseRequested: {
                root.showToast(qsTr("CLOSE requested (in production will dismiss modal)"))
            }

            onEditKnownPieceRequested: {
                root.cycleThickness()
            }

            onUnitChanged: function(unit) {
                root.simUnit = unit
                root.showToast(qsTr("Unit changed to %1").arg(unit))
            }
        }

        // ---------------------------------------------------------------------
        // REAL PRODUCTION MODALS. Only Calibration is replaced by this candidate.
        // ---------------------------------------------------------------------
        Production.ManualMeasurementPopup {
            anchors.fill: parent
            appState: productionPreviewState
        }

        Production.MachinePopupLayer {
            anchors.fill: parent
            appState: productionPreviewState
        }

        Production.MachineAlarmPopupLayer {
            anchors.fill: parent
            appState: productionPreviewState
        }

        // Live interaction feedback toast banner
        Rectangle {
            visible: root.toastMessage.length > 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            height: 38
            width: toastLabel.implicitWidth + 36
            radius: 19
            color: "#2B2C2B"
            border.color: "#2D83B2"
            border.width: 1.5
            z: 99999

            Text {
                id: toastLabel
                anchors.centerIn: parent
                text: root.toastMessage
                color: "white"
                font.pixelSize: 12
                font.bold: true
            }
        }
    }
}