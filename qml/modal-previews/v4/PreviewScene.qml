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
    readonly property bool surfaceSelected: selectedPreview.indexOf("LEFT_") === 0
        || selectedPreview === "ACTION_BAR" || selectedPreview === "TOOL_BAR"

    readonly property var previews: [
        { key: "RIGHT_PANEL", label: qsTr("Right panel"), family: qsTr("462 × 668 · Production") },
        { key: "ACTION_BAR", label: qsTr("Upper action bar"), family: qsTr("1366 × 40 · Separate") },
        { key: "TOOL_BAR", label: qsTr("Connection bar"), family: qsTr("1366 × 50 · Separate") },
        { key: "ACTIVATOR_PROPOSALS", label: qsTr("Activator proposals"), family: qsTr("5 iterations · Gris/Verde/Rojo") },
        { key: "BEND_MODE_PROPOSALS", label: qsTr("Bend mode menu proposals"), family: qsTr("4 iterations · Expansion menu") },
        { key: "LEFT_0", label: qsTr("RUN left panel"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_1", label: qsTr("CREATE BEND left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_2", label: qsTr("TOOLS left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_3", label: qsTr("BACK GAUGE left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_4", label: qsTr("MANUAL left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_5", label: qsTr("CAD left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_6", label: qsTr("SETTINGS left"), family: qsTr("864 × 668 · Production") },
        { key: "CALIBRATION", label: qsTr("Calibration (v4)"), family: qsTr("950 × 600 · Precision") },
        { key: "MEASUREMENT", label: qsTr("Measurement (v4)"), family: qsTr("950 × 600 · Precision") },
        { key: "BLEED", label: qsTr("Bleed (v4)"), family: qsTr("950 × 600 · Precision") },
        { key: "CAD_RESULT", label: qsTr("CAD result (v4)"), family: qsTr("950 × 600 · Precision") },
        { key: "ALARM", label: qsTr("Machine alarm"), family: qsTr("850 × 500 · Production") },
        { key: "ERROR", label: qsTr("Error notification"), family: qsTr("550 × 300 · Production") },
        { key: "CONFIRMATION", label: qsTr("Confirmation"), family: qsTr("550 × 300 · Production") },
        { key: "PROGRESS", label: qsTr("Progress"), family: qsTr("550 × 300 · Production") }
    ]

    // -------------------------------------------------------------------------
    // Interactive Simulation State for Custom Calibration Proposal
    // -------------------------------------------------------------------------
    property int simPhase: 0 // 0: Ready, 1: Sampling (4/10), 2: Calibrated (10/10)
    property bool simTelemetryReady: true
    property bool simDieTopCalibrated: true
    property string simHeaderTheme: "BLUE" // "BLUE" | "RED"
    property string simUnit: "INCH"
    property real simThicknessInches: 0.1250
    property real simThicknessMm: 3.1750
    property bool simPedalActive: false
    property bool simAutoActive: false
    property bool simCadSaved: true
    property string toastMessage: ""
    property real liveWobble: 0.0

    Timer {
        id: wobbleTimer
        interval: 400
        running: (root.simAutoActive || root.simPedalActive || root.simPhase === 1) && root.simTelemetryReady
        repeat: true
        onTriggered: {
            root.liveWobble = (Math.random() - 0.5) * 0.0008
        }
    }

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

    // -------------------------------------------------------------------------
    // Production Simulated State for all other modal views
    // -------------------------------------------------------------------------
    Production.AppState {
        id: previewState
        offlineSimulationEnabled: true
        manualModeArmed: true
        ramPosition: 1.375
        tonnageHoldTarget: 1.0

        manualMeasurementVisible: false
        manualMeasurementMode: root.selectedPreview
        manualMeasurementStatus: "READY FOR PIECE"

        alarmVisible: root.selectedPreview === "ALARM"
        alarmTitle: "MACHINE ALARM"
        alarmBody: "Release the active safety condition before continuing."

        popupVisible: root.selectedPreview === "ERROR"
            || root.selectedPreview === "CONFIRMATION"
            || root.selectedPreview === "PROGRESS"
        popupKind: root.selectedPreview === "CONFIRMATION" ? "caution"
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

    Production.ModalDesignerSurface {
        x: 204
        y: 58
        width: root.width - 204
        height: root.height - 58
        selection: root.selectedPreview
        appState: previewState
        visible: root.surfaceSelected
        onPageRequested: function(index) { root.selectedPreview = "LEFT_" + index }
    }

    Rectangle {
        x: 204
        y: 58
        width: root.width - 204
        height: root.height - 58
        color: "#0F1115"
        visible: root.selectedPreview === "BEND_MODE_PROPOSALS"

        Production.BendModeProposalsView {
            anchors.fill: parent
        }
    }

    Rectangle {
        x: 204
        y: 58
        width: root.width - 204
        height: root.height - 58
        color: "#18191C"
        visible: root.selectedPreview === "ACTIVATOR_PROPOSALS"

        Production.ActivatorProposalsView {
            anchors.fill: parent
        }
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

    // -------------------------------------------------------------------------
    // Real Production Components for all non-Calibration views
    // -------------------------------------------------------------------------
    Production.ManualMeasurementPopup {
        anchors.fill: parent
        appState: previewState
    }

    Production.MachinePopupLayer {
        anchors.fill: parent
        appState: previewState
    }

    Production.MachineAlarmPopupLayer {
        anchors.fill: parent
        appState: previewState
    }

    // -------------------------------------------------------------------------
    // Custom Redesigned Calibration Modal (Centered in full 1366 × 768 canvas)
    // -------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#A6000000"
        visible: root.selectedPreview === "CALIBRATION"
        z: 1000

        MouseArea { anchors.fill: parent }

        CalibrationModal {
            id: customCalibration
            anchors.centerIn: parent

            headerTheme: root.simHeaderTheme
            telemetryReady: root.simTelemetryReady
            ramPositionY1: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? (1.2514 + root.liveWobble) : 1.2500)) : 0
            ramPositionY2: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? (1.2508 - root.liveWobble) : 1.2500)) : 0
            ramPositionMean: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? 1.2511 : 1.2500)) : 0

            ramLoadY1: root.simTelemetryReady ? (root.simPhase === 0 ? 0.000 : (root.simPhase === 1 ? (0.535 + root.liveWobble * 30) : 0.500)) : 0
            ramLoadY2: root.simTelemetryReady ? (root.simPhase === 0 ? 0.000 : (root.simPhase === 1 ? (0.465 - root.liveWobble * 30) : 0.500)) : 0
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

        // Live interaction toast
        Rectangle {
            visible: root.toastMessage.length > 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            height: 36
            width: toastText.implicitWidth + 32
            radius: 18
            color: "#2B2C2B"
            border.color: "#2D83B2"
            border.width: 1.5

            Text {
                id: toastText
                anchors.centerIn: parent
                text: root.toastMessage
                color: "white"
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

    // -------------------------------------------------------------------------
    // Custom Redesigned Piece Measurement Modal (Centered in 1366 × 768 canvas)
    // -------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#A6000000"
        visible: root.selectedPreview === "MEASUREMENT"
        z: 1000

        MouseArea { anchors.fill: parent }

        MeasurementModal {
            id: customMeasurement
            anchors.centerIn: parent

            headerTheme: root.simHeaderTheme
            telemetryReady: root.simTelemetryReady
            ramPositionY1: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? (1.2514 + root.liveWobble) : 1.2500)) : 0
            ramPositionY2: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? (1.2508 - root.liveWobble) : 1.2500)) : 0
            ramPositionMean: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? 1.2511 : 1.2500)) : 0

            ramLoadY1: root.simTelemetryReady ? (root.simPhase === 0 ? 0.000 : (root.simPhase === 1 ? (0.535 + root.liveWobble * 30) : 0.500)) : 0
            ramLoadY2: root.simTelemetryReady ? (root.simPhase === 0 ? 0.000 : (root.simPhase === 1 ? (0.465 - root.liveWobble * 30) : 0.500)) : 0
            tonnageHoldTarget: 1.000

            measurementUnit: root.simUnit
            calibratedDieTop: 1.2500
            dieTopCalibrationValid: root.simDieTopCalibrated

            measurementStatus: root.simPhase === 0 ? qsTr("READY TO MEASURE")
                : (root.simPhase === 1 ? qsTr("ACQUIRING CONTACT") : qsTr("MEASUREMENT COMPLETE"))

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
                    root.showToast(qsTr("PEDAL pressed: Measuring piece contact..."))
                } else {
                    root.showToast(qsTr("PEDAL released / stopped"))
                }
            }

            onAutoRequested: {
                root.simAutoActive = !root.simAutoActive
                if (root.simAutoActive) {
                    root.simPedalActive = false
                    root.simPhase = 1
                    root.showToast(qsTr("AUTO started: Qualifying piece thickness..."))
                } else {
                    root.showToast(qsTr("AUTO cancelled"))
                }
            }

            onCloseRequested: {
                root.showToast(qsTr("CLOSE requested"))
            }

            onUnitChanged: function(unit) {
                root.simUnit = unit
                root.showToast(qsTr("Unit changed to %1").arg(unit))
            }
        }
    }

    // -------------------------------------------------------------------------
    // Custom Redesigned Bleed Hydraulics Modal (Centered in 1366 × 768 canvas)
    // -------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#A6000000"
        visible: root.selectedPreview === "BLEED"
        z: 1000

        MouseArea { anchors.fill: parent }

        BleedModal {
            id: customBleed
            anchors.centerIn: parent

            headerTheme: root.simHeaderTheme === "BLUE" ? "BLUE" : "RED"
            leftHeld: root.simPedalActive
            rightHeld: root.simAutoActive

            onLeftToggleRequested: {
                root.simPedalActive = !root.simPedalActive
                root.showToast(root.simPedalActive ? qsTr("Y1 Left Palm Switch HELD") : qsTr("Y1 Left Palm Switch RELEASED"))
            }

            onRightToggleRequested: {
                root.simAutoActive = !root.simAutoActive
                root.showToast(root.simAutoActive ? qsTr("Y2 Right Palm Switch HELD") : qsTr("Y2 Right Palm Switch RELEASED"))
            }

            onCompleteRequested: {
                root.showToast(qsTr("BLEED COMPLETE · Procedure finished successfully"))
            }

            onCancelRequested: {
                root.showToast(qsTr("BLEED CANCELLED / DISABLED"))
            }
        }
    }

    // -------------------------------------------------------------------------
    // Custom Redesigned CAD Result Modal (Centered in 1366 × 768 canvas)
    // -------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#A6000000"
        visible: root.selectedPreview === "CAD_RESULT"
        z: 1000

        MouseArea { anchors.fill: parent }

        CadResultModal {
            id: customCadResult
            anchors.centerIn: parent

            resultData: ({
                programName: previewState.popupResultData.programName || "Battery Plate N1",
                partName: previewState.popupResultData.partName || "Battery Plate N1",
                material: previewState.popupResultData.material || "Steel",
                thickness: previewState.popupResultData.thickness || "0.0600 in",
                bendCount: previewState.popupResultData.bendCount || 4,
                saved: root.simCadSaved,
                storageLabel: root.simCadSaved ? qsTr("SAVED · backup protected") : qsTr("UNSAVED DRAFT"),
                rows: previewState.popupResultData.rows || []
            })

            onCloseRequested: {
                root.showToast(qsTr("CLOSE requested (dismiss CAD result)"))
            }

            onViewInRunRequested: {
                root.showToast(qsTr("VIEW IN RUN requested (navigate to Run)"))
            }
        }
    }

    // =========================================================================
    // DESIGN LAB OVERLAY RAIL (z: 20000 - does not shift modal centering)
    // =========================================================================
    Rectangle {
        id: rail
        z: 20000
        width: 184
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
                spacing: 6

                Text {
                    text: qsTr("MODAL\nDESIGN LAB")
                    color: "white"
                    font.pixelSize: 20
                    font.bold: true
                    lineHeight: 0.95
                }

                Text {
                    text: qsTr("v4")
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
                            font.pixelSize: 10
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

                // Interactive simulation controls when in Calibration or Measurement view
                Item { Layout.preferredHeight: 8 }

            Rectangle {
                visible: root.selectedPreview === "CALIBRATION" || root.selectedPreview === "MEASUREMENT"
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#555555"
            }

            Text {
                visible: root.selectedPreview === "CALIBRATION" || root.selectedPreview === "MEASUREMENT"
                text: qsTr("SIMULATION CONTROLS")
                color: "#A8A8A8"
                font.pixelSize: 9
                font.bold: true
            }

            // Phase cycle
            Button {
                visible: root.selectedPreview === "CALIBRATION" || root.selectedPreview === "MEASUREMENT"
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                onClicked: root.cycleSimPhase()
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simPhase === 0 ? qsTr("Phase: 1. READY")
                        : (root.simPhase === 1 ? qsTr("Phase: 2. SAMPLING") : qsTr("Phase: 3. COMPLETE"))
                    color: "white"
                    font.pixelSize: 9
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#2D83B2"
                }
            }

            // Header color toggle (Blue vs Red)
            Button {
                visible: root.selectedPreview === "CALIBRATION" || root.selectedPreview === "MEASUREMENT"
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                onClicked: {
                    root.simHeaderTheme = root.simHeaderTheme === "BLUE" ? "RED" : "BLUE"
                    root.showToast(qsTr("Header theme: %1").arg(root.simHeaderTheme))
                }
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simHeaderTheme === "BLUE" ? qsTr("Header: BLUE (#2D83B2)") : qsTr("Header: RED (#A82011)")
                    color: "white"
                    font.pixelSize: 9
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: root.simHeaderTheme === "BLUE" ? "#2D83B2" : "#A82011"
                }
            }

            // Die Top state toggle
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                onClicked: {
                    root.simDieTopCalibrated = !root.simDieTopCalibrated
                    root.showToast(root.simDieTopCalibrated ? qsTr("Die Top: STORED (1.2500)") : qsTr("Die Top: NOT CALIBRATED"))
                }
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simDieTopCalibrated ? qsTr("Die Top: STORED") : qsTr("Die Top: NOT CALIBRATED")
                    color: root.simDieTopCalibrated ? "#59A60C" : "#FFA500"
                    font.pixelSize: 9
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#383838"
                    border.color: "#555555"
                }
            }

            // Sensors toggle
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                onClicked: {
                    root.simTelemetryReady = !root.simTelemetryReady
                    root.showToast(root.simTelemetryReady ? qsTr("Sensors Online") : qsTr("Sensors Offline"))
                }
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simTelemetryReady ? qsTr("Sensors: LIVE (1.3750)") : qsTr("Sensors: OFFLINE")
                    color: root.simTelemetryReady ? "#59A60C" : "#A82011"
                    font.pixelSize: 9
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#383838"
                    border.color: "#555555"
                }
            }

            // Shim cycle
            Button {
                visible: root.selectedPreview === "CALIBRATION"
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                onClicked: root.cycleThickness()
                contentItem: Text {
                    anchors.centerIn: parent
                    text: qsTr("Shim: %1 in").arg(root.simThicknessInches.toFixed(4))
                    color: "#2D83B2"
                    font.pixelSize: 9
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: "#383838"
                    border.color: "#555555"
                }
            }

            // CAD Result Status Toggle (Saved vs Draft)
            Button {
                visible: root.selectedPreview === "CAD_RESULT"
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                onClicked: {
                    root.simCadSaved = !root.simCadSaved
                    root.showToast(root.simCadSaved ? qsTr("CAD: SAVED (#1B7A5A)") : qsTr("CAD: DRAFT (#D97706)"))
                }
                contentItem: Text {
                    anchors.centerIn: parent
                    text: root.simCadSaved ? qsTr("Status: SAVED (Green)") : qsTr("Status: DRAFT (Orange)")
                    color: "white"
                    font.pixelSize: 9
                    font.bold: true
                }
                background: Rectangle {
                    radius: 5
                    color: root.simCadSaved ? "#1B7A5A" : "#D97706"
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#555555" }

            Text {
                text: qsTr("F5 / RELOAD to refresh\nModal: 950 × 600")
                color: "#A8A8A8"
                font.pixelSize: 9
                wrapMode: Text.WordWrap
            }
        }
        }
    }
}
