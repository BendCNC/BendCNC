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
        { key: "CALIBRATION", label: qsTr("Calibration (v2)"), family: qsTr("950 × 600 · Redesigned") },
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
    // Interactive Simulation State for Calibration Review
    // -------------------------------------------------------------------------
    property int simPhase: 0 // 0: Ready, 1: Sampling (4/10), 2: Calibrated (10/10)
    property bool simTelemetryReady: true
    property bool simDieTopCalibrated: true
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

    // Background Canvas representing the 1366 × 768 kiosk host
    Rectangle {
        anchors.fill: parent
        color: "#0F1216"

        // Subtle industrial grid texture
        Grid {
            anchors.fill: parent
            rows: 24
            columns: 42
            spacing: 32
            opacity: 0.08
            Repeater {
                model: 100
                Rectangle {
                    required property int index
                    width: 2
                    height: 2
                    color: "white"
                }
            }
        }
    }

    // =========================================================================
    // LEFT NAVIGATION & SIMULATOR RAIL (Width: 200px)
    // =========================================================================
    Rectangle {
        id: rail
        width: 200
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: "#16191E"
        border.color: "#252B35"
        border.width: 1
        z: 20000

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            // Header badge
            RowLayout {
                spacing: 6
                Rectangle {
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 18
                    radius: 3
                    color: "#0EA5E9"
                }
                Text {
                    text: qsTr("MODAL LAB")
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    font.letterSpacing: 0.8
                }
            }

            Text {
                text: qsTr("v2-gemini-calibration")
                color: "#38BDF8"
                font.pixelSize: 11
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2A313C" }

            Text {
                text: qsTr("SELECT PREVIEW")
                color: "#64748B"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.5
            }

            Repeater {
                model: root.previews
                Button {
                    id: previewButton
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    text: previewButton.modelData.label
                    onClicked: root.selectedPreview = previewButton.modelData.key

                    contentItem: RowLayout {
                        spacing: 8
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        Rectangle {
                            Layout.preferredWidth: 6
                            Layout.preferredHeight: 6
                            radius: 3
                            color: root.selectedPreview === previewButton.modelData.key ? "#38BDF8" : "#475569"
                        }
                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: previewButton.modelData.label
                                color: root.selectedPreview === previewButton.modelData.key ? "white" : "#94A3B8"
                                font.pixelSize: 11
                                font.bold: root.selectedPreview === previewButton.modelData.key
                            }
                            Text {
                                text: previewButton.modelData.family
                                color: root.selectedPreview === previewButton.modelData.key ? "#7DD3FC" : "#64748B"
                                font.pixelSize: 9
                            }
                        }
                    }

                    background: Rectangle {
                        radius: 6
                        color: root.selectedPreview === previewButton.modelData.key
                            ? "#0F2942" : (previewButton.down ? "#222730" : "#1B1F26")
                        border.color: root.selectedPreview === previewButton.modelData.key
                            ? "#0284C7" : "#28303C"
                        border.width: root.selectedPreview === previewButton.modelData.key ? 1.5 : 1
                    }
                }
            }

            // Interactive Simulator Controls for Calibration
            Item { Layout.fillHeight: true }

            Rectangle {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#2A313C"
            }

            Text {
                visible: root.selectedPreview === "CALIBRATION"
                text: qsTr("INTERACTIVE SIMULATOR")
                color: "#64748B"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.5
            }

            // Sim control 1: Phase cycle
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                onClicked: root.cycleSimPhase()
                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "⚡"; color: "#38BDF8"; font.pixelSize: 12 }
                    Text {
                        text: root.simPhase === 0 ? qsTr("Phase: 1. READY")
                            : (root.simPhase === 1 ? qsTr("Phase: 2. SAMPLING") : qsTr("Phase: 3. CALIBRATED"))
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
                background: Rectangle {
                    radius: 5
                    color: "#1E293B"
                    border.color: "#38BDF8"
                    border.width: 1
                }
            }

            // Sim control 2: Die top status
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                onClicked: {
                    root.simDieTopCalibrated = !root.simDieTopCalibrated
                    root.showToast(root.simDieTopCalibrated ? qsTr("Die Top: Calibrated") : qsTr("Die Top: NOT Calibrated"))
                }
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simDieTopCalibrated ? qsTr("Die Top: Calibrated") : qsTr("Die Top: NOT Calibrated")
                    color: root.simDieTopCalibrated ? "#4ADE80" : "#F59E0B"
                    font.pixelSize: 10
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#1C2128"
                    border.color: "#2C3440"
                }
            }

            // Sim control 3: Telemetry Online / Offline
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                onClicked: {
                    root.simTelemetryReady = !root.simTelemetryReady
                    root.showToast(root.simTelemetryReady ? qsTr("Sensors Online") : qsTr("Sensors Offline"))
                }
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simTelemetryReady ? qsTr("Sensors: LIVE (ON)") : qsTr("Sensors: OFFLINE")
                    color: root.simTelemetryReady ? "#4ADE80" : "#EF4444"
                    font.pixelSize: 10
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#1C2128"
                    border.color: "#2C3440"
                }
            }

            // Sim control 4: Cycle shim size
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                onClicked: root.cycleThickness()
                contentItem: Text {
                    anchors.centerIn: parent
                    text: qsTr("Shim: %1 in").arg(root.simThicknessInches.toFixed(4))
                    color: "#38BDF8"
                    font.pixelSize: 10
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#1C2128"
                    border.color: "#2C3440"
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2A313C" }

            Text {
                text: qsTr("Canvas: 1366 × 768\nModal: 950 × 600")
                color: "#64748B"
                font.pixelSize: 9
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

        // Dark modal backdrop overlay
        Rectangle {
            anchors.fill: parent
            color: "#B3000000" // 70% black backdrop for rich contrast
        }

        // ---------------------------------------------------------------------
        // CALIBRATION (V2 REDESIGN CANDIDATE)
        // ---------------------------------------------------------------------
        CalibrationModal {
            id: calibrationModal
            anchors.centerIn: parent
            visible: root.selectedPreview === "CALIBRATION"

            // Wire simulation properties
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
            color: "#0F2942"
            border.color: "#0284C7"
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