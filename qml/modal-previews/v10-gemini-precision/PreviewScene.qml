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

    readonly property bool surfaceSelected: (selectedPreview.indexOf("LEFT_") === 0 && selectedPreview !== "LEFT_0" && selectedPreview !== "LEFT_1" && selectedPreview !== "LEFT_2" && selectedPreview !== "LEFT_3" && selectedPreview !== "LEFT_4" && selectedPreview !== "LEFT_6")

        || selectedPreview === "ACTION_BAR" || selectedPreview === "TOOL_BAR"



    readonly property var previews: [

        // Category 1: Main Modals

        { category: qsTr("MAIN MODALS"), key: "RUN_FINAL", label: qsTr("RUN (v10 Final)"), family: qsTr("864 \u00D7 668 \u00B7 Tactile Power Cockpit") },

        { category: qsTr("MAIN MODALS"), key: "LEFT_0", label: qsTr("RUN (Legacy)"), family: qsTr("864 \u00D7 668 \u00B7 Baseline Comparison") },

        { category: qsTr("MAIN MODALS"), key: "LEFT_1", label: qsTr("CREATE BEND"), family: qsTr("864 \u00D7 668 \u00B7 Live CAD Studio") },

        { category: qsTr("MAIN MODALS"), key: "LEFT_2", label: qsTr("TOOLS"), family: qsTr("864 \u00D7 668 \u00B7 Precision DXF") },

        { category: qsTr("MAIN MODALS"), key: "LEFT_3", label: qsTr("BACK GAUGE"), family: qsTr("864 \u00D7 668 \u00B7 Axis Motion") },

        { category: qsTr("MAIN MODALS"), key: "LEFT_4", label: qsTr("MANUAL"), family: qsTr("864 \u00D7 668 \u00B7 Jog & Fine Tune") },

        { category: qsTr("MAIN MODALS"), key: "LEFT_6", label: qsTr("SETTINGS"), family: qsTr("864 \u00D7 668 \u00B7 Cockpit & Calibration") },

        { category: qsTr("MAIN MODALS"), key: "LEFT_5", label: qsTr("CAD"), family: qsTr("864 \u00D7 668 \u00B7 Part Profile") },



        { category: qsTr("TELEMETRY"), key: "RIGHT_PANEL", label: qsTr("Right Panel"), family: qsTr("462 × 668 · Precision DRO") },



        // Category 3: Precision Dialogs

        { category: qsTr("PRECISION DIALOGS"), key: "MEASUREMENT", label: qsTr("Measurement"), family: qsTr("950 × 600 · Live Convergence") },

        { category: qsTr("PRECISION DIALOGS"), key: "CALIBRATION", label: qsTr("Calibration"), family: qsTr("950 × 600 · Die Top Datum") },

        { category: qsTr("PRECISION DIALOGS"), key: "BLEED", label: qsTr("Bleed"), family: qsTr("950 × 600 · Dual Ram Purge") },

        { category: qsTr("PRECISION DIALOGS"), key: "CAD_RESULT", label: qsTr("CAD Result"), family: qsTr("950 × 600 · Part Verification") },

        { category: qsTr("PRECISION DIALOGS"), key: "THC_LIVE_TUNING", label: qsTr("Fine Tune"), family: qsTr("950 × 600 · Precision THC") },



        // Category 4: System Alerts & Notifications (v10 Precision)
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "START_RUNNING", label: qsTr("Start Run Confirmation"), family: qsTr("650 × 380 · Program Execution Admission") },
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "STOP_RUNNING", label: qsTr("Stop Running"), family: qsTr("550 × 300 · Safety Abort Confirmation") },
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "STOPPED_NOTIFICATION", label: qsTr("Program Stopped"), family: qsTr("550 × 300 · State Notification") },
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "PAUSED_NOTIFICATION", label: qsTr("Program Paused"), family: qsTr("550 × 300 · State Notification") },
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "HOMING", label: qsTr("Homing in Progress"), family: qsTr("550 × 300 · Dual Axis Datum Seeking") },
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "SERIAL_DISCONNECT", label: qsTr("Serial Disconnect"), family: qsTr("850 × 500 · Communication Lost") },
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "ALARM", label: qsTr("Machine Alarm"), family: qsTr("850 × 500 · Critical E-Stop Tripped") },
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "ERROR", label: qsTr("Error Notification"), family: qsTr("550 × 300 · Parameter Validation") },
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "CONFIRMATION", label: qsTr("Confirmation"), family: qsTr("550 × 300 · Action Modal") },
        { category: qsTr("NOTIFICATIONS & ALERTS"), key: "PROGRESS", label: qsTr("Progress"), family: qsTr("550 × 300 · Task Progress") },



        // Category 5: Lab Proposals

        { category: qsTr("LAB PROPOSALS"), key: "ACTIVATOR_PROPOSALS", label: qsTr("Activator Proposals"), family: qsTr("5 State Proposals") },

        { category: qsTr("LAB PROPOSALS"), key: "BEND_MODE_PROPOSALS", label: qsTr("Bend Mode Proposals"), family: qsTr("Expansion Menu") },

        { category: qsTr("LAB PROPOSALS"), key: "ACTION_BAR", label: qsTr("Upper Action Bar"), family: qsTr("1366 × 40 · Separate") },

        { category: qsTr("LAB PROPOSALS"), key: "TOOL_BAR", label: qsTr("Connection Bar"), family: qsTr("1366 × 50 · Separate") }

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

        manualModeState: "IDLE"

        ramPosition: 1.3750

        tonnageHoldTarget: 1.0

        manualModeMaxTonnagePerRam: 12.5

        manualJogStep: 0.1000

        liveTonnage: 0.00

        runBendListVisible: root.selectedPreview === "RUN_BEND_LIST" || root.selectedPreview === "RUN_PROPOSAL_LIST"



        manualMeasurementVisible: false

        manualMeasurementMode: root.selectedPreview

        manualMeasurementStatus: "READY FOR PART"



        alarmVisible: root.selectedPreview === "ALARM" || root.selectedPreview === "SERIAL_DISCONNECT"

        alarmTitle: root.selectedPreview === "SERIAL_DISCONNECT"
            ? "SERIAL DISCONNECTED"
            : "MACHINE ALARM"

        alarmBody: root.selectedPreview === "SERIAL_DISCONNECT"
            ? "Serial communication with controller was lost on COM3 (/dev/ttyACM0). Check physical USB cable connection and verify controller board is responding."
            : "Emergency Stop circuit opened or safety limit switch tripped. Ram motion halted immediately. Clear workpiece obstacle, reset physical switch, and clear alarm."



        popupVisible: root.selectedPreview === "ERROR"
            || root.selectedPreview === "CONFIRMATION"
            || root.selectedPreview === "PROGRESS"
            || root.selectedPreview === "HOMING"
            || root.selectedPreview === "STOP_RUNNING"
            || root.selectedPreview === "STOPPED_NOTIFICATION"
            || root.selectedPreview === "PAUSED_NOTIFICATION"

        popupKind: (root.selectedPreview === "CONFIRMATION" || root.selectedPreview === "STOP_RUNNING") ? "caution"
            : (root.selectedPreview === "PROGRESS" || root.selectedPreview === "HOMING") ? "blur" : "message"

        popupTitle: root.selectedPreview === "HOMING" ? "HOMING IN PROGRESS"
            : root.selectedPreview === "STOP_RUNNING" ? "STOP PROGRAM RUN"
            : root.selectedPreview === "STOPPED_NOTIFICATION" ? "PROGRAM STOPPED"
            : root.selectedPreview === "PAUSED_NOTIFICATION" ? "PROGRAM PAUSED"
            : root.selectedPreview === "CAD_RESULT" ? "BEND PROGRAM READY"
            : root.selectedPreview === "CONFIRMATION" ? "DELETE PROGRAM"
            : root.selectedPreview === "PROGRESS" ? "UPDATING MACHINE" : "OPERATION ERROR"

        popupBody: root.selectedPreview === "HOMING"
            ? "Ram and backgauge axes moving to mechanical datum zero. Keep physical emergency stop within reach."
            : root.selectedPreview === "STOP_RUNNING"
                ? "Abort active bend program? Ram motion will halt immediately and backgauge will freeze. Hydraulic pressure will be vented."
                : root.selectedPreview === "STOPPED_NOTIFICATION"
                    ? "Active program halted by operator request.\nRam position safe · Backgauge stationary."
                    : root.selectedPreview === "PAUSED_NOTIFICATION"
                        ? "Active program paused between steps.\nResume execution when workspace is clear."
                        : root.selectedPreview === "CONFIRMATION"
                            ? "Delete this program? This action cannot be undone."
                            : root.selectedPreview === "PROGRESS"
                                ? "Waiting for the machine to complete the requested operation."
                                : "The requested operation could not be completed. Review the machine state and try again."

        popupProgress: root.selectedPreview === "HOMING" ? 0.65 : 0.45

        popupButtonText: root.selectedPreview === "HOMING" ? "CANCEL HOMING"
            : root.selectedPreview === "STOP_RUNNING" ? "ABORT RUN"
            : root.selectedPreview === "CONFIRMATION" ? "DELETE" : "CLOSE"

        popupCancelButtonText: root.selectedPreview === "STOP_RUNNING" ? "RESUME" : "CANCEL"

        popupAction: (root.selectedPreview === "CONFIRMATION" || root.selectedPreview === "STOP_RUNNING") ? "confirmation" : ""

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



        // Program state for RUN_LEFT_V5

        programs: [

            ({

                name: "DIN Bracket 10in N1",

                source: "cad",

                bends: [

                    { id: 1, seq: 1, angle: 90.0, setup: "STD", punch: "Gooseneck 88° Punch [BC-8392]", die: "Acute 8mm Die 30° Die [BC-5623]", vdieValue: 0.315, vdie: "8mm", x: "0.8634", r: "-0.2500", reference: "EDGE", startPosition: "-1.2000", clampPosition: "-1.2140", finalPosition: "-1.2500", retractPosition: "-1.1500", status: "OK" },

                    { id: 2, seq: 2, angle: 90.0, setup: "STD", punch: "Gooseneck 88° Punch [BC-8392]", die: "Acute 8mm Die 30° Die [BC-5623]", vdieValue: 0.315, vdie: "8mm", x: "0.8634", r: "-0.2500", reference: "EDGE", startPosition: "-1.2000", clampPosition: "-1.2140", finalPosition: "-1.2500", retractPosition: "-1.1500", status: "OK" },

                    { id: 3, seq: 3, angle: 90.0, setup: "STD", punch: "Gooseneck 88° Punch [BC-8392]", die: "Acute 8mm Die 30° Die [BC-5623]", vdieValue: 0.315, vdie: "8mm", x: "1.7627", r: "-0.2500", reference: "EDGE", startPosition: "-1.2000", clampPosition: "-1.2140", finalPosition: "-1.2500", retractPosition: "-1.1500", status: "OK" },

                    { id: 4, seq: 4, angle: 90.0, setup: "STD", punch: "Gooseneck 88° Punch [BC-8392]", die: "Acute 8mm Die 30° Die [BC-5623]", vdieValue: 0.315, vdie: "8mm", x: "1.7627", r: "-0.2500", reference: "EDGE", startPosition: "-1.2000", clampPosition: "-1.2140", finalPosition: "-1.2500", retractPosition: "-1.1500", status: "OK" }

                ],

                cadPreviewJson: ""

            })

        ]

        selectedProgramIndex: 0

        selectedRunBend: 0

        activeProgram: "DIN Bracket 10in N1"

        bendMode: "PROGRAM_BEND_MODE"

        autoClampEnabled: true

        autoClampDwellSec: 3.0

    }



    Loader {

        id: thcLoader

        objectName: "designer-thc-loader"

        x: 204

        y: 58

        width: root.width - 204

        height: root.height - 58

        z: 1000

        active: root.visible && root.selectedPreview === "THC_LIVE_TUNING"

        sourceComponent: Component {

            Rectangle {

                id: tuningStage

                anchors.fill: parent

                color: "#A6000000"

                MouseArea { anchors.fill: parent }



                ThcLiveTuningPreview {

                    anchors.centerIn: parent

                    scale: Math.min(1, tuningStage.width / width, tuningStage.height / height)

                    onCloseRequested: root.selectedPreview = "LEFT_4"

                }

            }

        }

    }



    Production.ModalDesignerCanvasSource {

        id: canvasSource

        appState: previewState

        active: root.designerLiveCanvas

    }



    Production.ModalDesignerSurface {

        x: 204

        y: 58

        width: root.width - 204

        height: root.height - 58

        selection: root.selectedPreview

        appState: previewState

        liveCanvas: root.designerLiveCanvas

        dataStore: canvasSource.dataStore

        visible: root.surfaceSelected

        onPageRequested: function(index) { root.selectedPreview = (index === 0 ? "RUN_FINAL" : "LEFT_" + index) }

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



            ColumnRightView {

                anchors.centerIn: parent

                width: 462

                height: 668

                appState: previewState

            }

        }

    }



    // -------------------------------------------------------------------------

    // RUN Left Panel (v5) Interactive View

    // -------------------------------------------------------------------------

    Rectangle {

        anchors.fill: parent

        color: "#D5D7DA"

        visible: root.selectedPreview === "RUN_FINAL" || root.selectedPreview === "LEFT_0" || root.selectedPreview === "RUN_LEFT_V5" || root.selectedPreview === "RUN_BEND_LIST"



        Rectangle {

            anchors.centerIn: parent

            width: 864 + 24

            height: 668 + 24

            radius: 11

            color: "#BFC2C5"

            border.color: "#8B8E91"

            border.width: 1



            Rectangle {

                anchors.centerIn: parent

                width: 864

                height: 668

                color: "transparent"



                ColumnLayout {

                    anchors.fill: parent

                    spacing: 0



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.preferredHeight: 30

                        radius: 7

                        antialiasing: true

                        color: "#2B2C2B"

                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 7; color: "#2B2C2B" }



                        Row {

                            anchors.fill: parent

                            Repeater {

                                model: ["RUN", "CREATE BEND", "TOOLS", "BACK GAUGE", "MANUAL", "CAD", "SETTINGS"]

                                delegate: Rectangle {

                                    required property int index

                                    required property string modelData

                                    readonly property var widths: [52, 118, 70, 113, 82, 50, 91]

                                    width: widths[index]

                                    height: 30

                                    color: index === 0 ? "#A82011" : "transparent"

                                    radius: index === 0 ? 7 : 0

                                    antialiasing: index === 0



                                    Rectangle {

                                        anchors.right: parent.right

                                        anchors.top: parent.top

                                        anchors.bottom: parent.bottom

                                        width: parent.radius

                                        color: parent.color

                                        visible: index === 0

                                    }

                                    Rectangle {

                                        anchors.left: parent.left

                                        anchors.right: parent.right

                                        anchors.bottom: parent.bottom

                                        height: parent.radius

                                        color: parent.color

                                        visible: index === 0

                                    }



                                    Text {

                                        anchors.centerIn: parent

                                        text: modelData

                                        color: "white"

                                        font.bold: true

                                        font.pixelSize: 14

                                    }



                                    MouseArea {

                                        anchors.fill: parent

                                        onClicked: if (index !== 0) root.selectedPreview = "LEFT_" + index

                                    }

                                }

                            }

                        }

                    }



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.fillHeight: true

                        color: "#E0E0E0"

                        radius: 7

                        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 7; color: "#E0E0E0" }



                        RunLeftView {

                            id: runViewV5

                            objectName: "runLeftPanelV5"

                            anchors.fill: parent

                            appState: previewState

                            dataStore: canvasSource.dataStore

                            designerBlankCanvas: !root.designerLiveCanvas

                        }

                    }

                }

            }

        }

    }



    // -------------------------------------------------------------------------

        // -------------------------------------------------------------------------

    // RUN Left Panel Proposal B (Cockpit Pro) Interactive View

    // -------------------------------------------------------------------------

    Rectangle {

        anchors.fill: parent

        color: "#D5D7DA"

        visible: root.selectedPreview === "RUN_PROPOSAL_B"

            || root.selectedPreview === "RUN_PROPOSAL_1"

            || root.selectedPreview === "RUN_PROPOSAL_2"

            || root.selectedPreview === "RUN_PROPOSAL_3"

            || root.selectedPreview === "RUN_PROPOSAL_4"

            || root.selectedPreview === "RUN_PROPOSAL_5"

            || root.selectedPreview === "RUN_PROPOSAL_6"

            || root.selectedPreview === "RUN_PROPOSAL_LIST"



        Rectangle {

            anchors.centerIn: parent

            width: 864 + 24

            height: 668 + 24

            radius: 11

            color: "#BFC2C5"

            border.color: "#8B8E91"

            border.width: 1



            Rectangle {

                anchors.centerIn: parent

                width: 864

                height: 668

                color: "transparent"



                ColumnLayout {

                    anchors.fill: parent

                    spacing: 0



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.preferredHeight: 30

                        radius: 7

                        antialiasing: true

                        color: "#2B2C2B"

                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 7; color: "#2B2C2B" }



                        Row {

                            anchors.fill: parent

                            Repeater {

                                model: ["RUN", "CREATE BEND", "TOOLS", "BACK GAUGE", "MANUAL", "CAD", "SETTINGS"]

                                delegate: Rectangle {

                                    required property int index

                                    required property string modelData

                                    readonly property var widths: [52, 118, 70, 113, 82, 50, 91]

                                    width: widths[index]

                                    height: 30

                                    color: index === 0 ? "#A82011" : "transparent"

                                    radius: 7

                                    Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 7; color: index === 0 ? "#A82011" : "transparent"; visible: index === 0 }

                                    Text {

                                        anchors.centerIn: parent

                                        text: parent.modelData

                                        color: "white"

                                        font.bold: true

                                        font.pixelSize: 14

                                    }

                                    MouseArea {

                                        anchors.fill: parent

                                        onClicked: if (index !== 0) root.selectedPreview = "LEFT_" + index

                                    }

                                }

                            }

                        }

                    }



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.fillHeight: true

                        color: "#15181E"

                        radius: 7

                        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 7; color: "#15181E" }



                        V9RunCockpitView {

                            id: runCockpitViewV9

                            objectName: "runCockpitLeftPanelV9"

                            anchors.fill: parent

                            appState: previewState

                            dataStore: canvasSource.dataStore

                            designerBlankCanvas: !root.designerLiveCanvas

                            styleVariant: {

                                if (root.selectedPreview === "RUN_PROPOSAL_2") return 2;

                                if (root.selectedPreview === "RUN_PROPOSAL_3") return 3;

                                if (root.selectedPreview === "RUN_PROPOSAL_4") return 4;

                                if (root.selectedPreview === "RUN_PROPOSAL_5") return 5;

                                if (root.selectedPreview === "RUN_PROPOSAL_6") return 6;

                                return 1;

                            }

                            previewStage: 1

                        }

                    }

                }

            }

        }

    }



    // -------------------------------------------------------------------------

    // CREATE BEND Left Panel (v6) Interactive Precision Studio

    // -------------------------------------------------------------------------

    Rectangle {

        anchors.fill: parent

        color: "#D5D7DA"

        visible: root.selectedPreview === "LEFT_1" || root.selectedPreview === "CREATE_BEND_LEFT_V6"



        Rectangle {

            anchors.centerIn: parent

            width: 864 + 24

            height: 668 + 24

            radius: 11

            color: "#BFC2C5"

            border.color: "#8B8E91"

            border.width: 1



            Rectangle {

                anchors.centerIn: parent

                width: 864

                height: 668

                color: "transparent"



                ColumnLayout {

                    anchors.fill: parent

                    spacing: 0



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.preferredHeight: 30

                        radius: 7

                        antialiasing: true

                        color: "#2B2C2B"

                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 7; color: "#2B2C2B" }



                        Row {

                            anchors.fill: parent

                            Repeater {

                                model: ["RUN", "CREATE BEND", "TOOLS", "BACK GAUGE", "MANUAL", "CAD", "SETTINGS"]

                                delegate: Rectangle {

                                    required property int index

                                    required property string modelData

                                    readonly property var widths: [52, 118, 70, 113, 82, 50, 91]

                                    width: widths[index]

                                    height: 30

                                    color: index === 1 ? "#A82011" : "transparent"

                                    radius: index === 1 ? 7 : 0

                                    antialiasing: index === 1



                                    Text {

                                        anchors.centerIn: parent

                                        text: modelData

                                        color: "white"

                                        font.bold: true

                                        font.pixelSize: 14

                                    }



                                    MouseArea {

                                        anchors.fill: parent

                                        onClicked: {

                                            if (index === 0) root.selectedPreview = "RUN_FINAL"

                                            else root.selectedPreview = "LEFT_" + index

                                        }

                                    }

                                }

                            }

                        }

                    }



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.fillHeight: true

                        color: "#E5E7EB"

                        radius: 0



                        V9CreateBendLeftView {

                            id: createBendViewV9

                            objectName: "createBendLeftPanelV9"

                            anchors.fill: parent

                            appState: previewState

                        }

                    }

                }

            }

        }

    }



    // -------------------------------------------------------------------------

    // TOOLS Left Panel (v5) Interactive Precision Studio

    // -------------------------------------------------------------------------

    Rectangle {

        anchors.fill: parent

        color: "#D5D7DA"

        visible: root.selectedPreview === "LEFT_2" || root.selectedPreview === "TOOLS_LEFT_V5"



        Rectangle {

            anchors.centerIn: parent

            width: 864 + 24

            height: 668 + 24

            radius: 11

            color: "#BFC2C5"

            border.color: "#8B8E91"

            border.width: 1



            Rectangle {

                anchors.centerIn: parent

                width: 864

                height: 668

                color: "transparent"



                ColumnLayout {

                    anchors.fill: parent

                    spacing: 0



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.preferredHeight: 30

                        radius: 7

                        antialiasing: true

                        color: "#2B2C2B"

                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 7; color: "#2B2C2B" }



                        Row {

                            anchors.fill: parent

                            Repeater {

                                model: ["RUN", "CREATE BEND", "TOOLS", "BACK GAUGE", "MANUAL", "CAD", "SETTINGS"]

                                delegate: Rectangle {

                                    required property int index

                                    required property string modelData

                                    readonly property var widths: [52, 118, 70, 113, 82, 50, 91]

                                    width: widths[index]

                                    height: 30

                                    color: index === 2 ? "#A82011" : "transparent"

                                    radius: index === 2 ? 7 : 0

                                    antialiasing: index === 2



                                    Text {

                                        anchors.centerIn: parent

                                        text: modelData

                                        color: "white"

                                        font.bold: true

                                        font.pixelSize: 14

                                    }



                                    MouseArea {

                                        anchors.fill: parent

                                        onClicked: {

                                            if (index === 0) root.selectedPreview = "RUN_FINAL"

                                            else root.selectedPreview = "LEFT_" + index

                                        }

                                    }

                                }

                            }

                        }

                    }



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.fillHeight: true

                        color: "#E5E7EB"

                        radius: 0



                        V6ToolsLeftView {

                            id: toolsViewV6

                            objectName: "toolsLeftPanelV6"

                            anchors.fill: parent

                            appState: previewState

                            designerInteractive: true

                        }

                    }

                }

            }

        }

    }



    // -------------------------------------------------------------------------

    // BACK GAUGE Left Panel (v5) Interactive Precision View

    // -------------------------------------------------------------------------

    Rectangle {

        anchors.fill: parent

        color: "#D5D7DA"

        visible: root.selectedPreview === "LEFT_3" || root.selectedPreview === "BACK_GAUGE_LEFT_V5"



        Rectangle {

            anchors.centerIn: parent

            width: 864 + 24

            height: 668 + 24

            radius: 11

            color: "#BFC2C5"

            border.color: "#8B8E91"

            border.width: 1



            Rectangle {

                anchors.centerIn: parent

                width: 864

                height: 668

                color: "transparent"



                ColumnLayout {

                    anchors.fill: parent

                    spacing: 0



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.preferredHeight: 30

                        radius: 7

                        antialiasing: true

                        color: "#2B2C2B"

                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 7; color: "#2B2C2B" }



                        Row {

                            anchors.fill: parent

                            Repeater {

                                model: ["RUN", "CREATE BEND", "TOOLS", "BACK GAUGE", "MANUAL", "CAD", "SETTINGS"]

                                delegate: Rectangle {

                                    required property int index

                                    required property string modelData

                                    readonly property var widths: [52, 118, 70, 113, 82, 50, 91]

                                    width: widths[index]

                                    height: 30

                                    color: index === 3 ? "#A82011" : "transparent"

                                    radius: index === 3 ? 7 : 0

                                    antialiasing: index === 3



                                    Text {

                                        anchors.centerIn: parent

                                        text: modelData

                                        color: "white"

                                        font.bold: true

                                        font.pixelSize: 14

                                    }



                                    MouseArea {

                                        anchors.fill: parent

                                        onClicked: {

                                            if (index === 0) root.selectedPreview = "RUN_FINAL"

                                            else root.selectedPreview = "LEFT_" + index

                                        }

                                    }

                                }

                            }

                        }

                    }



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.fillHeight: true

                        color: "#E5E7EB"

                        radius: 0



                        V6BackGaugeLeftView {

                            id: backGaugeViewV6

                            objectName: "backGaugeLeftPanelV6"

                            anchors.fill: parent

                            appState: previewState

                            designerInteractive: true

                        }

                    }

                }

            }

        }

    }



    // -------------------------------------------------------------------------

    // MANUAL Left Panel (v5) Interactive View

    // -------------------------------------------------------------------------

    Rectangle {

        anchors.fill: parent

        color: "#D5D7DA"

        visible: root.selectedPreview === "LEFT_4" || root.selectedPreview === "MANUAL_LEFT_V5"



        Rectangle {

            anchors.centerIn: parent

            width: 864 + 24

            height: 668 + 24

            radius: 11

            color: "#BFC2C5"

            border.color: "#8B8E91"

            border.width: 1



            Rectangle {

                anchors.centerIn: parent

                width: 864

                height: 668

                color: "transparent"



                ColumnLayout {

                    anchors.fill: parent

                    spacing: 0



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.preferredHeight: 30

                        radius: 7

                        antialiasing: true

                        color: "#2B2C2B"

                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 7; color: "#2B2C2B" }



                        Row {

                            anchors.fill: parent

                            Repeater {

                                model: ["RUN", "CREATE BEND", "TOOLS", "BACK GAUGE", "MANUAL", "CAD", "SETTINGS"]

                                delegate: Rectangle {

                                    required property int index

                                    required property string modelData

                                    readonly property var widths: [52, 118, 70, 113, 82, 50, 91]

                                    width: widths[index]

                                    height: 30

                                    color: index === 4 ? "#A82011" : "transparent"

                                    radius: index === 4 ? 7 : 0

                                    antialiasing: index === 4



                                    Text {

                                        anchors.centerIn: parent

                                        text: modelData

                                        color: "white"

                                        font.bold: true

                                        font.pixelSize: 14

                                    }



                                    MouseArea {

                                        anchors.fill: parent

                                        onClicked: {

                                            if (index === 0) root.selectedPreview = "RUN_FINAL"

                                            else root.selectedPreview = "LEFT_" + index

                                        }

                                    }

                                }

                            }

                        }

                    }



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.fillHeight: true

                        color: "#E0E0E0"

                        radius: 7

                        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 7; color: "#E0E0E0" }



                        ManualLeftView {

                            id: manualViewV5

                            objectName: "manualLeftPanelV5"

                            anchors.fill: parent

                            appState: previewState

                            designerInteractive: true

                            onCalibrationRequested: root.selectedPreview = "CALIBRATION"

                            onBleedRequested: root.selectedPreview = "BLEED"

                            onFineTuneRequested: root.selectedPreview = "THC_LIVE_TUNING"

                        }

                    }

                }

            }

        }

    }



    // -------------------------------------------------------------------------

    // SETTINGS Left Panel (v9) Interactive Modern Cockpit

    // -------------------------------------------------------------------------

    Rectangle {

        anchors.fill: parent

        color: "#D5D7DA"

        visible: root.selectedPreview === "LEFT_6" || root.selectedPreview === "SETTINGS_LEFT_V9"



        Rectangle {

            anchors.centerIn: parent

            width: 864 + 24

            height: 668 + 24

            radius: 11

            color: "#BFC2C5"

            border.color: "#8B8E91"

            border.width: 1



            Rectangle {

                anchors.centerIn: parent

                width: 864

                height: 668

                color: "transparent"



                ColumnLayout {

                    anchors.fill: parent

                    spacing: 0



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.preferredHeight: 30

                        radius: 7

                        antialiasing: true

                        color: "#2B2C2B"

                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 7; color: "#2B2C2B" }



                        Row {

                            anchors.fill: parent

                            Repeater {

                                model: ["RUN", "CREATE BEND", "TOOLS", "BACK GAUGE", "MANUAL", "CAD", "SETTINGS"]

                                delegate: Rectangle {

                                    required property int index

                                    required property string modelData

                                    readonly property var widths: [52, 118, 70, 113, 82, 50, 91]

                                    width: widths[index]

                                    height: 30

                                    color: index === 6 ? "#A82011" : "transparent"

                                    radius: index === 6 ? 7 : 0

                                    antialiasing: index === 6



                                    Text {

                                        anchors.centerIn: parent

                                        text: modelData

                                        color: "white"

                                        font.bold: true

                                        font.pixelSize: 14

                                    }



                                    MouseArea {

                                        anchors.fill: parent

                                        onClicked: {

                                            if (index === 0) root.selectedPreview = "RUN_FINAL"

                                            else root.selectedPreview = "LEFT_" + index

                                        }

                                    }

                                }

                            }

                        }

                    }



                    Rectangle {

                        Layout.fillWidth: true

                        Layout.fillHeight: true

                        color: "#E5E7EB"

                        radius: 0



                        V9SettingsLeftView {

                            id: settingsViewV9

                            objectName: "settingsLeftPanelV9"

                            anchors.fill: parent

                            appState: previewState

                        }

                    }

                }

            }

        }

    }



    // -------------------------------------------------------------------------

    // Real Production Components for all non-Calibration views

    // -------------------------------------------------------------------------

    Production.ManualMeasurementPopup {

        x: 204; y: 58; width: 1366; height: 768

        appState: previewState

    }



    V9MachinePopupLayer {

        x: 204; y: 58; width: 1366; height: 768

        appState: previewState

    }



    V9MachineAlarmPopupLayer {

        x: 204; y: 58; width: 1366; height: 768

        appState: previewState

    }



    // -------------------------------------------------------------------------

    // Custom Redesigned Calibration Modal (Centered in full 1366 × 768 canvas)

    // -------------------------------------------------------------------------

    Rectangle {

        x: 204; y: 58; width: 1366; height: 768

        color: "#A6000000"

        visible: root.selectedPreview === "CALIBRATION"

        z: 1000



        MouseArea { anchors.fill: parent }



        MeasurementModal {
            id: customCalibration
            anchors.centerIn: parent
            operationalMode: "CALIBRATE"
            headerTheme: root.simHeaderTheme
            telemetryReady: root.simTelemetryReady
            ramPositionY1: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? (1.2514 + root.liveWobble) : 1.2500)) : 0
            ramPositionY2: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? (1.2508 - root.liveWobble) : 1.2500)) : 0
            ramPositionMean: root.simTelemetryReady ? (root.simPhase === 0 ? 1.3750 : (root.simPhase === 1 ? 1.2511 : 1.2500)) : 0
            ramLoadY1: root.simTelemetryReady ? (root.simPhase === 0 ? 0.000 : (root.simPhase === 1 ? (0.535 + root.liveWobble * 30) : 0.500)) : 0
            ramLoadY2: root.simTelemetryReady ? (root.simPhase === 0 ? 0.000 : (root.simPhase === 1 ? (0.465 - root.liveWobble * 30) : 0.500)) : 0
            tonnageHoldTarget: 1.000
            measurementTonnageEditable: true

            shimUnit: root.simUnit
            shimThicknessInches: root.simThicknessInches
            shimThicknessMm: root.simThicknessMm
            dieTopCalibrationValid: root.simDieTopCalibrated
            calibratedDieTop: -0.1250
            toolingText: "P 4.610 in · D 1.862 in"
            toolingValid: true

            measurementStatus: root.simPhase === 0 ? qsTr("ENTER SHIM THICKNESS")
                : (root.simPhase === 1 ? qsTr("QUALIFYING CONTACT") : qsTr("CALIBRATION COMPLETE"))
            measurementResult: root.simPhase === 2 ? -0.1250 : Number.NaN
            requiredSamples: 10
            qualifiedSamples: root.simPhase === 0 ? 0 : (root.simPhase === 1 ? 4 : 10)
            processActive: root.simPhase === 1
            appliedLoadMean: root.simPhase > 0 ? 1.002 : Number.NaN
            appliedLoadPeak: root.simPhase > 0 ? 1.015 : Number.NaN
            acceptedSamples: root.simPhase === 2 ? 10 : (root.simPhase === 1 ? 4 : 0)
            acceptedDurationMs: root.simPhase === 2 ? 2800 : (root.simPhase === 1 ? 1100 : 0)

            tonnageHoldActive: root.simPedalActive
            contactProfileActive: root.simAutoActive
            openingState: "LOCKED"
            openingCurrent: 8.2200
            openingCandidate: 8.2013
            openingCanApply: true

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
                root.showToast(qsTr("CLOSE requested"))
            }

            onEditShimRequested: {
                root.cycleThickness()
                root.showToast(qsTr("Shim thickness adjusted: %1 %2").arg(root.simUnit === "MILLIMETER" ? root.simThicknessMm.toFixed(3) : root.simThicknessInches.toFixed(4)).arg(root.simUnit === "MILLIMETER" ? "mm" : "in"))
            }

            onToolingRequested: {
                root.showToast(qsTr("TOOLING: Punch 4.610 in · Die 1.862 in"))
            }

            onMeasurementTonnageRequested: {
                root.showToast(qsTr("TARGET FORCE: 0.5–1.0 T"))
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

        x: 204; y: 58; width: 1366; height: 768

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
            measurementTonnageEditable: true

            measurementUnit: root.simUnit
            calibratedDieTop: -0.1250
            dieTopCalibrationValid: root.simDieTopCalibrated
            referenceThickness: 0.1250
            toolingText: "P 4.610 in · D 1.862 in"
            toolingValid: true

            measurementStatus: root.simPhase === 0 ? qsTr("READY FOR PART")
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
                    root.showToast(qsTr("PEDAL pressed: Measuring part contact..."))
                } else {
                    root.showToast(qsTr("PEDAL released / stopped"))
                }
            }

            onAutoRequested: {
                root.simAutoActive = !root.simAutoActive
                if (root.simAutoActive) {
                    root.simPedalActive = false
                    root.simPhase = 1
                    root.showToast(qsTr("AUTO started: Qualifying part thickness..."))
                } else {
                    root.showToast(qsTr("AUTO cancelled"))
                }
            }

            onCloseRequested: {
                root.showToast(qsTr("CLOSE requested"))
            }

            onEditShimRequested: {
                root.cycleThickness()
                root.showToast(qsTr("Shim thickness adjusted"))
            }

            onToolingRequested: {
                root.showToast(qsTr("TOOLING: Punch 4.610 in · Die 1.862 in"))
            }

            onMeasurementTonnageRequested: {
                root.showToast(qsTr("TARGET FORCE: 0.5–1.0 T"))
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

        x: 204; y: 58; width: 1366; height: 768

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



            onKillHydraulicPowerRequested: {

                root.simPedalActive = false

                root.simAutoActive = false

                root.showToast(qsTr("KILL HYDRAULIC POWER · Emergency power cut"))

            }



            onExitProcedureRequested: {

                root.simPedalActive = false

                root.simAutoActive = false

                root.showToast(qsTr("EXIT BLEED PROCEDURE · Prompting Home Machine"))

            }



            onContinueToBleedRequested: {

                root.showToast(qsTr("PROCEEDING TO BLEED PROCEDURE · Mode Enabled"))

            }



            onCancelRequested: {

                root.simPedalActive = false

                root.simAutoActive = false

                root.showToast(qsTr("BLEED CANCELLED / DISABLED"))

            }

        }

    }



    // -------------------------------------------------------------------------

    // Custom Redesigned CAD Result Modal (Centered in 1366 × 768 canvas)

    // -------------------------------------------------------------------------

    Rectangle {

        x: 204; y: 58; width: 1366; height: 768

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

    // -------------------------------------------------------------------------
    // Start Run Confirmation Modal (Centered in full 1366 × 768 canvas)
    // -------------------------------------------------------------------------
    Rectangle {
        x: 204; y: 58; width: 1366; height: 768
        color: "#A6000000"
        visible: root.selectedPreview === "START_RUNNING"
        z: 1000

        MouseArea { anchors.fill: parent }

        Rectangle {
            width: 650
            height: 380
            anchors.centerIn: parent
            radius: 8
            color: "#FFFFFF"
            border.color: "#CBD5E1"
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Header Bar (Mode-aware theme color with centered title & mode badge)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    color: !previewState ? "#B91C1C"
                        : previewState.bendMode === "SINGLE_BEND_MODE" ? "#16A34A"
                        : previewState.bendMode === "SINGLE_BEND_REPEAT" ? "#0284C7"
                        : previewState.bendMode === "PROGRAM_BEND_LOOP" ? "#7C3AED"
                        : "#B91C1C"
                    radius: 8

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 8
                        color: parent.color
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 14
                            color: "#26FFFFFF"
                            Text {
                                anchors.centerIn: parent
                                text: "▶"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 13
                            }
                        }

                        Text {
                            text: qsTr("RUN PROGRAM")
                            color: "white"
                            font.bold: true
                            font.pixelSize: 17
                            font.letterSpacing: 0.5
                            verticalAlignment: Text.AlignVCenter
                        }

                        Rectangle {
                            visible: !!previewState && !!previewState.bendMode
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: previewModeLabel.implicitWidth + 14
                            radius: 4
                            color: "#33000000"
                            Text {
                                id: previewModeLabel
                                anchors.centerIn: parent
                                text: previewState ? previewState.bendMode.replace(/_/g, " ") : ""
                                color: "white"
                                font.bold: true
                                font.pixelSize: 10
                                font.letterSpacing: 0.5
                            }
                        }
                    }
                }

                // Body Container
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#FFFFFF"

                    GridLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        columns: 2
                        columnSpacing: 18
                        rowSpacing: 0

                        // Left Column: Program info and starting bend sequence
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    text: qsTr("PROGRAM TITLE")
                                    color: "#64748B"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.letterSpacing: 0.5
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: previewState ? previewState.activeProgram : "Battery Plate N1"
                                    color: "#0F172A"
                                    font.bold: true
                                    font.pixelSize: 20
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: "#E2E8F0"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    Layout.fillWidth: true
                                    text: previewState && previewState.bendModeIsProgramMode()
                                        ? qsTr("EXECUTION SEQUENCE (STARTING BEND)")
                                        : qsTr("TARGET BEND")
                                    color: "#64748B"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.letterSpacing: 0.5
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    radius: 6
                                    color: "#F8FAFC"
                                    border.color: "#CBD5E1"
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text {
                                            text: "●"
                                            color: !previewState ? "#B91C1C"
                                                : previewState.bendMode === "SINGLE_BEND_MODE" ? "#16A34A"
                                                : previewState.bendMode === "SINGLE_BEND_REPEAT" ? "#0284C7"
                                                : previewState.bendMode === "PROGRAM_BEND_LOOP" ? "#7C3AED"
                                                : "#B91C1C"
                                            font.pixelSize: 10
                                        }
                                        Text {
                                            text: previewState ? "#" + String(previewState.selectedRunBend + 1) + "  ·  " + (previewState.selectedBend.name || "Bend 1") : "#1  ·  Bend 1"
                                            color: "#0F172A"
                                            font.bold: true
                                            font.pixelSize: 14
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: previewState ? previewState.bendModeIsProgramMode() : false
                                Layout.fillWidth: true
                                text: qsTr("Ram will execute sequentially through all programmed bends.")
                                color: "#64748B"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            Item { Layout.fillHeight: true }
                        }

                        // Right Column: Safety pre-checks & warning panels
                        ColumnLayout {
                            Layout.preferredWidth: 240
                            Layout.fillHeight: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 6
                                color: "#F8FAFC"
                                border.color: "#E2E8F0"
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8

                                    Text {
                                        text: qsTr("SAFETY & PRE-CHECKS")
                                        color: "#64748B"
                                        font.bold: true
                                        font.pixelSize: 10
                                        font.letterSpacing: 0.5
                                    }

                                    // Repeat Badge
                                    Rectangle {
                                        visible: previewState ? previewState.bendModeIsRepeatable() : false
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 38
                                        radius: 5
                                        color: "#FEF3C7"
                                        border.color: "#FCD34D"
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text { text: "↻"; color: "#B45309"; font.bold: true; font.pixelSize: 14 }
                                            Text { text: qsTr("PROGRAM WILL BE REPEATED"); color: "#92400E"; font.bold: true; font.pixelSize: 11 }
                                        }
                                    }

                                    // Not Top Most Badge
                                    Rectangle {
                                        visible: previewState ? previewState.selectedBendNotTopMostWarning : false
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 38
                                        radius: 5
                                        color: "#FEF3C7"
                                        border.color: "#FCD34D"
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text { text: "!"; color: "#B45309"; font.bold: true; font.pixelSize: 14 }
                                            Text { text: qsTr("STARTING BEND IS NOT #1"); color: "#92400E"; font.bold: true; font.pixelSize: 11 }
                                        }
                                    }

                                    // All Clear Badge
                                    Rectangle {
                                        visible: previewState ? (!previewState.bendModeIsRepeatable() && !previewState.selectedBendNotTopMostWarning) : true
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 38
                                        radius: 5
                                        color: "#F0FDF4"
                                        border.color: "#BBF7D0"
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                text: "✓"
                                                color: "#16A34A"
                                                font.bold: true
                                                font.pixelSize: 13
                                            }
                                            Text {
                                                text: qsTr("ALL CHECKS CLEAR · READY")
                                                color: "#15803D"
                                                font.bold: true
                                                font.pixelSize: 11
                                                font.letterSpacing: 0.3
                                            }
                                        }
                                    }

                                    Item { Layout.fillHeight: true }
                                }
                            }
                        }
                    }
                }

                // Dedicated Footer Bar (Centered buttons, clear hierarchy, no glyph offsets)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: "#F8FAFC"

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: "#E2E8F0"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 12

                        Text {
                            text: qsTr("Do you want to proceed with execution?")
                            color: "#334155"
                            font.bold: true
                            font.pixelSize: 13
                            Layout.fillWidth: true
                        }

                        // Primary Confirmation Button (YES / START)
                        Rectangle {
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 40
                            radius: 6
                            color: "#16A34A"
                            border.color: "#22C55E"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("START RUN")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showToast(qsTr("START RUN confirmed · Initiating execution sequence"))
                            }
                        }

                        // Dismiss / Cancel Button (NO / CANCEL)
                        Rectangle {
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: 40
                            radius: 6
                            color: "#334155"
                            border.color: "#475569"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("CANCEL")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showToast(qsTr("CANCEL requested · Execution aborted"))
                            }
                        }
                    }
                }
            }
        }
    }



    // =========================================================================

    // DESIGN LAB OVERLAY RAIL (z: 20000 - does not shift modal centering)

    // =========================================================================

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

            spacing: 6



            Text {

                text: qsTr("MODAL\nDESIGN LAB")

                color: "white"

                font.pixelSize: 20

                font.bold: true

                lineHeight: 0.95

            }



            Text {

                text: qsTr("v10-gemini-precision")

                color: "#59A60C"

                font.pixelSize: 11

                font.bold: true

            }



            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#555555" }



            Repeater {

                model: root.previews

                delegate: ColumnLayout {

                    id: previewItemCol

                    required property var modelData

                    required property int index

                    Layout.fillWidth: true

                    spacing: 3



                    // Section Category Header

                    Item {

                        Layout.fillWidth: true

                        Layout.preferredHeight: 20

                        visible: previewItemCol.index === 0 || root.previews[previewItemCol.index - 1].category !== previewItemCol.modelData.category



                        RowLayout {

                            anchors.fill: parent

                            spacing: 6



                            Rectangle {

                                Layout.preferredWidth: 3

                                Layout.preferredHeight: 11

                                radius: 1.5

                                color: previewItemCol.modelData.category === qsTr("MAIN MODALS") ? "#38BDF8"

                                     : previewItemCol.modelData.category === qsTr("TELEMETRY") ? "#34D399"

                                     : previewItemCol.modelData.category === qsTr("PRECISION DIALOGS") ? "#FBBF24"

                                     : previewItemCol.modelData.category === qsTr("SYSTEM ALERTS") ? "#F87171"

                                     : "#A78BFA"

                            }



                            Text {

                                text: previewItemCol.modelData.category

                                color: "#94A3B8"

                                font.pixelSize: 9

                                font.bold: true

                                Layout.fillWidth: true

                                elide: Text.ElideRight

                            }

                        }

                    }



                    // Button Card

                    Rectangle {

                        id: cardButton

                        Layout.fillWidth: true

                        Layout.preferredHeight: 38

                        radius: 6

                        readonly property bool isSelected: root.selectedPreview === previewItemCol.modelData.key

                            || ((root.selectedPreview === "RUN_LEFT_V5" || root.selectedPreview === "LEFT_0") && previewItemCol.modelData.key === "LEFT_0")

                        color: isSelected ? "#2D83B2" : (btnMouse.containsMouse ? "#32353B" : "#26282E")

                        border.color: isSelected ? "#60A5FA" : (btnMouse.containsMouse ? "#475569" : "#373A42")

                        border.width: 1



                        RowLayout {

                            anchors.fill: parent

                            anchors.leftMargin: 8

                            anchors.rightMargin: 8

                            spacing: 8



                            Rectangle {

                                Layout.preferredWidth: 5

                                Layout.preferredHeight: 5

                                radius: 2.5

                                color: cardButton.isSelected ? "#FFFFFF" : (btnMouse.containsMouse ? "#94A3B8" : "#4B5563")

                            }



                            ColumnLayout {

                                Layout.fillWidth: true

                                spacing: 1



                                Text {

                                    Layout.fillWidth: true

                                    text: previewItemCol.modelData.label

                                    color: "white"

                                    font.pixelSize: 10

                                    font.bold: cardButton.isSelected

                                    elide: Text.ElideRight

                                }



                                Text {

                                    Layout.fillWidth: true

                                    text: previewItemCol.modelData.family

                                    color: cardButton.isSelected ? "#E0F2FE" : "#94A3B8"

                                    font.pixelSize: 8

                                    elide: Text.ElideRight

                                }

                            }

                        }



                        MouseArea {

                            id: btnMouse

                            anchors.fill: parent

                            hoverEnabled: true

                            cursorShape: Qt.PointingHandCursor

                            onClicked: {

                                root.selectedPreview = (previewItemCol.modelData.key === "LEFT_0" ? "RUN_LEFT_V5" : previewItemCol.modelData.key)

                            }

                        }

                    }

                }

            }



            // Interactive simulation controls when in Calibration or Measurement view

            Item { Layout.preferredHeight: 8 }



            Rectangle {

                visible: root.selectedPreview === "CALIBRATION" || root.selectedPreview === "MEASUREMENT" || root.selectedPreview === "BLEED" || root.selectedPreview === "CAD_RESULT" || root.selectedPreview === "RUN_LEFT_V5"

                Layout.fillWidth: true

                Layout.preferredHeight: 1

                color: "#555555"

            }



            Text {

                visible: root.selectedPreview === "CALIBRATION" || root.selectedPreview === "MEASUREMENT" || root.selectedPreview === "BLEED" || root.selectedPreview === "CAD_RESULT" || root.selectedPreview === "RUN_LEFT_V5"

                text: root.selectedPreview === "RUN_LEFT_V5" ? qsTr("RUN CONTROLS SIMULATION") : qsTr("SIMULATION CONTROLS")

                color: "#A8A8A8"

                font.pixelSize: 9

                font.bold: true

            }



            // Visual-only cycle preview: never dispatch a machine RUN action.

            Button {

                visible: root.selectedPreview === "RUN_LEFT_V5"

                Layout.fillWidth: true

                Layout.preferredHeight: 32

                onClicked: {

                    previewState.runActive = !previewState.runActive

                    root.showToast(previewState.runActive ? qsTr("Preview only · executing appearance") : qsTr("Preview only · ready appearance"))

                }

                contentItem: Text {

                    anchors.centerIn: parent

                    text: previewState.runActive ? qsTr("Preview: EXECUTING (Red)") : qsTr("Preview: READY (Green)")

                    color: "white"

                    font.pixelSize: 9

                    font.bold: true

                }

                background: Rectangle {

                    radius: 5

                    color: previewState.runActive ? "#A82011" : "#59A60C"

                }

            }



            // Auto Clamp toggle

            Button {

                visible: root.selectedPreview === "RUN_LEFT_V5"

                Layout.fillWidth: true

                Layout.preferredHeight: 30

                onClicked: {

                    previewState.runAction("auto-clamp")

                    root.showToast(previewState.autoClampEnabled ? qsTr("Auto Clamp ON") : qsTr("Auto Clamp OFF"))

                }

                contentItem: Text {

                    anchors.centerIn: parent

                    text: previewState.autoClampEnabled ? qsTr("Auto Clamp: ON") : qsTr("Auto Clamp: OFF")

                    color: previewState.autoClampEnabled ? "#59A60C" : "white"

                    font.pixelSize: 9

                    font.bold: true

                }

                background: Rectangle {

                    radius: 5

                    color: "#383838"

                    border.color: previewState.autoClampEnabled ? "#59A60C" : "#555555"

                }

            }



            // Dwell toggle

            Button {

                visible: root.selectedPreview === "RUN_LEFT_V5"

                Layout.fillWidth: true

                Layout.preferredHeight: 30

                onClicked: {

                    if (previewState.autoClampEnabled)

                        previewState.runAction("auto-dwell")

                    root.showToast(previewState.autoClampDwellEnabled ? qsTr("Dwell ON (3.0s)") : qsTr("Dwell OFF"))

                }

                contentItem: Text {

                    anchors.centerIn: parent

                    text: previewState.autoClampDwellEnabled ? qsTr("Dwell: ON (3.0s)") : qsTr("Dwell: OFF")

                    color: previewState.autoClampDwellEnabled ? "#F59E0B" : "white"

                    font.pixelSize: 9

                    font.bold: true

                }

                background: Rectangle {

                    radius: 5

                    color: "#383838"

                    border.color: previewState.autoClampDwellEnabled ? "#F59E0B" : "#555555"

                }

            }



            // Cycle Bend Mode

            Button {

                visible: root.selectedPreview === "RUN_LEFT_V5"

                Layout.fillWidth: true

                Layout.preferredHeight: 32

                onClicked: {

                    var modes = previewState.multipleBendsProgram

                        ? ["PROGRAM_BEND_MODE", "PROGRAM_BEND_LOOP"]

                        : ["SINGLE_BEND_MODE", "SINGLE_BEND_REPEAT"]

                    var curIdx = modes.indexOf(previewState.bendMode)

                    var nextIdx = (curIdx + 1) % modes.length

                    previewState.setBendMode(modes[nextIdx])

                    root.showToast(qsTr("Bend Mode: %1").arg(previewState.bendMode))

                }

                contentItem: Text {

                    anchors.centerIn: parent

                    text: previewState.bendMode.replace(/_/g, " ")

                    color: "white"

                    font.pixelSize: 8

                    font.bold: true

                    elide: Text.ElideRight

                }

                background: Rectangle {

                    radius: 5

                    color: previewState.bendMode === "SINGLE_BEND_MODE" ? "#59A60C"

                        : previewState.bendMode === "SINGLE_BEND_REPEAT" ? "#2D83B2"

                        : previewState.bendMode === "PROGRAM_BEND_LOOP" ? "#8B5CF6" : "#A82011"

                }

            }



            // Toggle Popup Upward

            Button {

                visible: root.selectedPreview === "RUN_LEFT_V5"

                Layout.fillWidth: true

                Layout.preferredHeight: 30

                onClicked: {

                    previewState.toggleBendModePopup()

                    root.showToast(previewState.bendModePopupVisible ? qsTr("Selector Upward OPEN") : qsTr("Selector CLOSED"))

                }

                contentItem: Text {

                    anchors.centerIn: parent

                    text: previewState.bendModePopupVisible ? qsTr("Selector: ▲ OPEN") : qsTr("Selector: ▼ CLOSED")

                    color: "white"

                    font.pixelSize: 9

                    font.bold: true

                }

                background: Rectangle {

                    radius: 5

                    color: previewState.bendModePopupVisible ? "#2D83B2" : "#383838"

                    border.color: "#555555"

                }

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

                visible: root.selectedPreview === "CALIBRATION" || root.selectedPreview === "MEASUREMENT" || root.selectedPreview === "BLEED"

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



            // BLEED Simulation Controls

            Button {

                visible: root.selectedPreview === "BLEED"

                Layout.fillWidth: true

                Layout.preferredHeight: 32

                onClicked: {

                    customBleed.wizardStep = customBleed.wizardStep === 1 ? 2 : 1

                    root.showToast(customBleed.wizardStep === 1 ? qsTr("Bleed: Step 1 PREPARATION") : qsTr("Bleed: Step 2 ACTIVE PURGE"))

                }

                contentItem: Text {

                    anchors.centerIn: parent

                    text: customBleed.wizardStep === 1 ? qsTr("Phase: 1. PREP") : qsTr("Phase: 2. PURGE")

                    color: "white"

                    font.pixelSize: 9

                    font.bold: true

                }

                background: Rectangle {

                    radius: 5

                    color: customBleed.wizardStep === 1 ? "#D97706" : "#A82011"

                }

            }



            Button {

                visible: root.selectedPreview === "BLEED"

                Layout.fillWidth: true

                Layout.preferredHeight: 30

                onClicked: {

                    root.simAutoActive = !root.simAutoActive

                    root.showToast(root.simAutoActive ? qsTr("Right Ram (Y2) Held") : qsTr("Right Ram (Y2) Released"))

                }

                contentItem: Text {

                    anchors.centerIn: parent

                    text: root.simAutoActive ? qsTr("Right Ram (Y2): HELD") : qsTr("Right Ram (Y2): OFF")

                    color: root.simAutoActive ? "#59A60C" : "white"

                    font.pixelSize: 9

                    font.bold: true

                }

                background: Rectangle {

                    radius: 5

                    color: "#383838"

                    border.color: root.simAutoActive ? "#59A60C" : "#555555"

                }

            }



            Button {

                visible: root.selectedPreview === "BLEED"

                Layout.fillWidth: true

                Layout.preferredHeight: 30

                onClicked: {

                    root.simPedalActive = !root.simPedalActive

                    root.showToast(root.simPedalActive ? qsTr("Left Ram (Y1) Held") : qsTr("Left Ram (Y1) Released"))

                }

                contentItem: Text {

                    anchors.centerIn: parent

                    text: root.simPedalActive ? qsTr("Left Ram (Y1): HELD") : qsTr("Left Ram (Y1): OFF")

                    color: root.simPedalActive ? "#59A60C" : "white"

                    font.pixelSize: 9

                    font.bold: true

                }

                background: Rectangle {

                    radius: 5

                    color: "#383838"

                    border.color: root.simPedalActive ? "#59A60C" : "#555555"

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



    Production.OnScreenKeyboard {

        id: previewKeyboard

        anchors.fill: parent

        appState: previewState

        z: 35000

    }

}

