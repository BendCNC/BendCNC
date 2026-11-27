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
    readonly property bool surfaceSelected: (selectedPreview.indexOf("LEFT_") === 0 && selectedPreview !== "LEFT_0" && selectedPreview !== "LEFT_1" && selectedPreview !== "LEFT_2" && selectedPreview !== "LEFT_3" && selectedPreview !== "LEFT_4")
        || selectedPreview === "ACTION_BAR" || selectedPreview === "TOOL_BAR"

    readonly property var previews: [
        { key: "RIGHT_PANEL", label: qsTr("Right panel (v6)"), family: qsTr("462 × 668 · Precision DRO") },
        { key: "RUN_LEFT_V5", label: qsTr("RUN left panel (v6)"), family: qsTr("864 × 668 · Bottom controls") },
        { key: "THC_LIVE_TUNING", label: qsTr("V46 Fine Tune · V53"), family: qsTr("950 × 600 · Precision") },
        { key: "ACTION_BAR", label: qsTr("Upper action bar"), family: qsTr("1366 × 40 · Separate") },
        { key: "TOOL_BAR", label: qsTr("Connection bar"), family: qsTr("1366 × 50 · Separate") },
        { key: "ACTIVATOR_PROPOSALS", label: qsTr("Activator proposals"), family: qsTr("5 iterations · Gris/Verde/Rojo") },
        { key: "BEND_MODE_PROPOSALS", label: qsTr("Bend mode menu proposals"), family: qsTr("4 iterations · Expansion menu") },
        { key: "LEFT_0", label: qsTr("RUN left panel"), family: qsTr("864 × 668 · (v6 candidate)") },
        { key: "LEFT_1", label: qsTr("CREATE BEND left (v6)"), family: qsTr("864 × 668 · Precision") },
        { key: "LEFT_2", label: qsTr("TOOLS left (v6)"), family: qsTr("864 × 668 · Precision DXF") },
        { key: "LEFT_3", label: qsTr("BACK GAUGE left (v6)"), family: qsTr("864 × 668 · Precision") },
        { key: "LEFT_4", label: qsTr("MANUAL left (v6)"), family: qsTr("864 × 668 · Precision") },
        { key: "LEFT_5", label: qsTr("CAD left"), family: qsTr("864 × 668 · Production") },
        { key: "LEFT_6", label: qsTr("SETTINGS left"), family: qsTr("864 × 668 · Production") },
        { key: "BLEED", label: qsTr("Bleed (v6)"), family: qsTr("950 × 600 · Precision") },
        { key: "CAD_RESULT", label: qsTr("CAD result (v6)"), family: qsTr("950 × 600 · Precision") },
        { key: "CALIBRATION", label: qsTr("Calibration (v6)"), family: qsTr("950 × 600 · Precision") },
        { key: "MEASUREMENT", label: qsTr("Measurement (v6)"), family: qsTr("950 × 600 · Precision") },
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
        manualModeState: "IDLE"
        ramPosition: 1.3750
        tonnageHoldTarget: 1.0
        manualModeMaxTonnagePerRam: 12.5
        manualJogStep: 0.1000
        liveTonnage: 0.00

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

        // Program state for RUN_LEFT_V5
        programs: [
            ({
                name: "Battery Plate N1",
                source: "cad",
                bends: [
                    { id: 1, seq: 1, angle: 90.0, setup: "STD", punch: "GN88", die: "8mm", x: "0.9494", r: "-0.2500", reference: "EDGE", startPosition: "-1.2000", clampPosition: "-1.2140", finalPosition: "-1.2500", retractPosition: "-1.1500", status: "OK" },
                    { id: 2, seq: 2, angle: 90.0, setup: "STD", punch: "GN88", die: "8mm", x: "0.9494", r: "-0.2500", reference: "EDGE", startPosition: "-1.2000", clampPosition: "-1.2140", finalPosition: "-1.2500", retractPosition: "-1.1500", status: "OK" },
                    { id: 3, seq: 3, angle: 45.0, setup: "STD", punch: "GN88", die: "8mm", x: "1.2500", r: "-0.2500", reference: "EDGE", startPosition: "-1.2000", clampPosition: "-1.2140", finalPosition: "-1.2500", retractPosition: "-1.1500", status: "OK" },
                    { id: 4, seq: 4, angle: 90.0, setup: "STD", punch: "GN88", die: "8mm", x: "2.1250", r: "-0.2500", reference: "EDGE", startPosition: "-1.2000", clampPosition: "-1.2140", finalPosition: "-1.2500", retractPosition: "-1.1500", status: "OK" }
                ],
                cadPreviewJson: ""
            })
        ]
        selectedProgramIndex: 0
        selectedRunBend: 0
        activeProgram: "Battery Plate N1"
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

    Production.ModalDesignerSurface {
        x: 204
        y: 58
        width: root.width - 204
        height: root.height - 58
        selection: root.selectedPreview
        appState: previewState
        visible: root.surfaceSelected
        onPageRequested: function(index) { root.selectedPreview = (index === 0 ? "RUN_LEFT_V5" : "LEFT_" + index) }
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
        visible: root.selectedPreview === "RUN_LEFT_V5" || root.selectedPreview === "LEFT_0"

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
                            designerBlankCanvas: true
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
                                            if (index === 0) root.selectedPreview = "RUN_LEFT_V5"
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

                        V6CreateBendLeftView {
                            id: createBendViewV6
                            objectName: "createBendLeftPanelV6"
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
                                            if (index === 0) root.selectedPreview = "RUN_LEFT_V5"
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
                                            if (index === 0) root.selectedPreview = "RUN_LEFT_V5"
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
                                            if (index === 0) root.selectedPreview = "RUN_LEFT_V5"
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

    Production.MachinePopupLayer {
        x: 204; y: 58; width: 1366; height: 768
        appState: previewState
    }

    Production.MachineAlarmPopupLayer {
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
                text: qsTr("v6-gemini-precision")
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
                    readonly property bool isSelected: root.selectedPreview === previewButton.modelData.key
                        || (root.selectedPreview === "RUN_LEFT_V5" && previewButton.modelData.key === "LEFT_0")
                    onClicked: root.selectedPreview = (previewButton.modelData.key === "LEFT_0" ? "RUN_LEFT_V5" : previewButton.modelData.key)

                    contentItem: Text {
                        text: previewButton.text
                        color: "white"
                        font.pixelSize: 10
                        font.bold: previewButton.isSelected
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 8
                    }

                    background: Rectangle {
                        radius: 6
                        color: previewButton.isSelected
                            ? "#2D83B2" : (previewButton.down ? "#444444" : "#2B2C2B")
                        border.color: previewButton.isSelected
                            ? "white" : "#555555"
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
}
