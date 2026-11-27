import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Controls.Basic
import "../../core/Units.js" as Units

Item {
    id: root
    objectName: "settings-view"
    property var appState: null
    readonly property bool metric: appState ? appState.metricUnits === true : false

    // Controller EEPROM & Ram opening properties
    readonly property real controllerRamToTableOpening: appState
        && appState.machineControl
        && Number(appState.machineControl.ramToTableOpening) > 0
        ? Number(appState.machineControl.ramToTableOpening) : 0
    readonly property real displayedRamToTableOpening: controllerRamToTableOpening > 0
        ? controllerRamToTableOpening
        : (appState ? Number(appState.desktopRamToTableOpening) : 8.250)
    readonly property string ramToTableOpeningSource: controllerRamToTableOpening > 0
        ? qsTr("CONTROLLER EEPROM") : (appState && appState.offlineSimulationEnabled
            ? qsTr("OFFLINE SETTING") : qsTr("CALIBRATED"))
    readonly property bool controllerSettingsAllowed: appState ? (appState.offlineSimulationEnabled
        || (appState.machineControl && appState.machineControl.pressConnected
            && appState.machineControl.pressReady && appState.machineControl.pressTelemetryFresh
            && ["IDLE", "STARTUP_HOMING_REQUIRED", "HYDRAULIC_SHUTDOWN"]
                .indexOf(String(appState.machineControl.pressMachineState)) >= 0)) : true
    readonly property real editedRamToTableOpening: appState
        && isFinite(Number(appState.editedRamToTableOpening))
        ? Number(appState.editedRamToTableOpening) : displayedRamToTableOpening
    readonly property bool controllerSettingsChanged: appState
        && isFinite(Number(appState.editedRamToTableOpening))
        && Math.abs(Number(appState.editedRamToTableOpening) - displayedRamToTableOpening) > 0.0001

    // Vivid Industrial Palette (Harmonized with Tools, Run, and BackGauge)
    readonly property color canvasBg: "#BFC2C5"
    readonly property color cardBg: "#E0E0E0"
    readonly property color cardSurface: "#F1F5F9"
    readonly property color cardHeaderBg: "#2B2C2B"
    readonly property color cardBorderColor: "#8B95A1"
    readonly property color cardDividerColor: "#CBD5E1"
    readonly property color inputBg: "#FFFFFF"
    readonly property color textPrimary: "#0F172A"
    readonly property color textSecondary: "#334155"
    readonly property color textMuted: "#64748B"

    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color blue: "#2D83B2"
    readonly property color amber: "#D97706"
    readonly property color orange: "#EA580C"
    readonly property color charcoal: "#1E232A"
    readonly property color slate: "#475569"

    // Active Category: 0: DISPLAY, 1: HYDRAULICS, 2: BACK GAUGE, 3: DIAGNOSTICS, 4: MAINTENANCE
    property int activeCategory: {
        // Snapshot/validation aid: --settings-category=N opens a given tab.
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; ++i)
            if (args[i].indexOf("--settings-category=") === 0)
                return parseInt(args[i].substring(20)) || 0
        return 0
    }
    property string directInputId: "0"
    property string directInputValue: "0"
    property var commandHistory: []

    FileDialog {
        id: softwareUpdateDialog
        title: qsTr("Select software update package")
        fileMode: FileDialog.OpenFile
        onAccepted: {
            if (!root.appState) return
            root.appState.selectedUpdatePackage = selectedFile
            root.appState.settingsAction("UPDATE SOFTWARE")
        }
    }

    function toggleSelected(label) {
        if (!appState) return true
        if (label === "Tonnage Protection") return appState.tonnageProtectionEnabled === true
        if (label === "Safety Warnings") return appState.safetyPopupsEnabled === true
        if (label === "Legacy Run UI") return appState.legacyRunUiEnabled === true
        if (label === "Run Preview Debug Logs") return appState.runPreviewDebugLogsEnabled === true
        if (label === "Serial Diagnostic Logs") return appState.serialDiagnosticLogsEnabled !== false
        if (label === "Run Preview Debug Overlays") return appState.runPreviewDebugOverlaysEnabled !== false
        if (label === "Frame Deflection Compensation") {
            const fw = appState.machineControl ? Number(appState.machineControl.deflectionCompensation) : -1
            return fw >= 0 ? fw === 1 : appState.desktopFrameDeflectionCompensationEnabled === true
        }
        if (label === "Measurement Convergence") return appState.manualMeasurementConvergenceEnabled === true
        if (label === "Auto Measure On Clamp") return appState.autoMeasureOnClampEnabled === true
        return true
    }

    function editNumeric(key, label, current, min, max, unit, isApp) {
        if (!appState) return
        var num = isFinite(Number(current)) ? Number(current) : min
        var lenUnit = unit === "in"
        var useMm = lenUnit && metric
        var shown = useMm ? num * 25.4 : num
        var shownMin = useMm ? min * 25.4 : min
        var shownMax = useMm ? max * 25.4 : max
        var shownUnit = useMm ? "mm" : unit
        var keyboardTarget = { text: unit === "%" ? shown.toFixed(1) : (unit === "sec" ? shown.toFixed(1) : (useMm ? shown.toFixed(2) : shown.toFixed(3))) }
        appState.openOnScreenKeyboard(keyboardTarget, true,
            qsTr(label.toUpperCase() + " (" + (useMm ? shownMin.toFixed(1) : shownMin) + " - " + (useMm ? shownMax.toFixed(1) : shownMax) + (shownUnit ? " " + shownUnit : "") + ")"),
            function(value) {
                var v = useMm ? Number(value) / 25.4 : value
                if (isApp) appState.setApplicationNumericSetting(key, v)
                else appState.setBackGaugeUserSetting(key, v)
            })
    }

    // Base industrial canvas
    Rectangle {
        anchors.fill: parent
        color: root.canvasBg
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        // 1. TOP HEADER & CATEGORY NAVIGATION DECK (height: 52)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 7
            color: root.cardHeaderBg
            border.color: "#3F4246"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                // Header Title & Connection Pill
                Row {
                    spacing: 8
                    Layout.alignment: Qt.AlignVCenter
                    Rectangle {
                        width: 28; height: 28; radius: 5
                        color: "#383A3D"
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "⚙"
                            color: "#FFFFFF"
                            font.pixelSize: 15
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("MACHINE & APPLICATION SETTINGS")
                        color: "#FFFFFF"
                        font.bold: true
                        font.pixelSize: 12
                        font.letterSpacing: 0.5
                    }
                }

                Item { Layout.fillWidth: true }

                // Category Tabs Deck
                Row {
                    spacing: 4
                    Layout.alignment: Qt.AlignVCenter

                    CategoryTabButton {
                        index: 0
                        iconText: "🖥"
                        tabLabel: qsTr("DISPLAY")
                        active: root.activeCategory === 0
                        onClicked: root.activeCategory = 0
                    }
                    CategoryTabButton {
                        index: 1
                        iconText: "⚙"
                        tabLabel: qsTr("HYDRAULICS")
                        active: root.activeCategory === 1
                        onClicked: root.activeCategory = 1
                    }
                    CategoryTabButton {
                        index: 2
                        iconText: "📏"
                        tabLabel: qsTr("BACK GAUGE")
                        active: root.activeCategory === 2
                        onClicked: root.activeCategory = 2
                    }
                    CategoryTabButton {
                        index: 3
                        iconText: "⚡"
                        tabLabel: qsTr("DIAGNOSTICS")
                        active: root.activeCategory === 3
                        onClicked: root.activeCategory = 3
                    }
                    CategoryTabButton {
                        index: 4
                        iconText: "💾"
                        tabLabel: qsTr("MAINTENANCE")
                        active: root.activeCategory === 4
                        onClicked: root.activeCategory = 4
                    }
                }
            }
        }

        // 2. MAIN CATEGORY VIEWPORT (Dynamic Swappable Content)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // =================================================================
            // TAB 0: DISPLAY & SYSTEM SETTINGS
            // =================================================================
            RowLayout {
                anchors.fill: parent
                visible: root.activeCategory === 0
                spacing: 8

                // Left Card: Display & Virtual Input
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("INTERFACE & SLEEP PREFERENCES")
                    accentColor: root.blue

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        SettingOptionRow {
                            title: qsTr("On-Screen Virtual Keyboard")
                            desc: qsTr("Behavior of touch input keyboard for data fields")
                            currentValue: root.appState ? String(root.appState.virtualInputMode).toUpperCase() : "ALWAYS"
                            options: ["ALWAYS", "AUTOMATIC", "NEVER"]
                            onOptionSelected: function(opt) {
                                if (root.appState && root.appState.virtualInputMode !== opt)
                                    root.appState.cycleVirtualInputMode()
                            }
                        }

                        SettingOptionRow {
                            title: qsTr("HDMI Display Sleep Timer")
                            desc: qsTr("Automatic screen dimming / sleep timeout on idle")
                            currentValue: root.appState ? root.appState.displaySleepText() : "OFF"
                            options: ["OFF", "5 MIN", "10 MIN", "30 MIN"]
                            onOptionSelected: function(opt) {
                                if (root.appState && root.appState.displaySleepText() !== opt)
                                    root.appState.cycleDisplaySleepMinutes()
                            }
                        }

                        SettingOptionRow {
                            title: qsTr("LIVE Animation FPS Limit")
                            desc: qsTr("Caps LIVE animation frame rate to reduce CPU/GPU load and heat")
                            currentValue: root.appState ? root.appState.liveAnimationFpsText() : "MAX"
                            options: ["5 FPS", "10 FPS", "15 FPS", "20 FPS", "30 FPS", "MAX"]
                            onOptionSelected: function(opt) {
                                if (root.appState)
                                    root.appState.setLiveAnimationFpsText(opt)
                            }
                        }

                        SettingSwitchRow {
                            readonly property var hs: root.appState ? root.appState.hostSystem : null
                            visible: hs !== null && hs.performanceModeAvailable
                            title: qsTr("CPU/GPU Performance Mode")
                            desc: qsTr("Keeps CPU and GPU at full clock for smoother LIVE animation (more heat)")
                            checked: hs ? hs.performanceMode : false
                            onToggled: if (hs) hs.performanceMode = !hs.performanceMode
                        }

                        SettingSwitchRow {
                            title: qsTr("Operator Safety Popups & Alarms")
                            desc: qsTr("Enforces modal confirmations before high-tonnage moves")
                            checked: root.toggleSelected("Safety Warnings")
                            onToggled: if (root.appState) root.appState.settingsAction("Safety Warnings")
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Right Card: 3D Graphics & Render Overlays
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("GRAPHICS & RUN CAD RENDERING")
                    accentColor: root.slate

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        SettingOptionRow {
                            title: qsTr("Tooling CAD Appearance")
                            desc: qsTr("Punch and die opacity in LIVE 3D (same as the Punch view button)")
                            currentValue: root.appState ? root.appState.runToolingAppearance : "SOLID"
                            options: ["SOLID", "TRANSLUCENT"]
                            onOptionSelected: function(opt) {
                                if (root.appState && root.appState.runToolingAppearance !== opt)
                                    root.appState.settingsAction("Tooling Appearance")
                            }
                        }

                        SettingSwitchRow {
                            title: qsTr("CAD Engine Diagnostic Verbose Logs")
                            desc: qsTr("Outputs geometry transform traces to terminal log")
                            checked: root.toggleSelected("Run Preview Debug Logs")
                            onToggled: if (root.appState) root.appState.settingsAction("Run Preview Debug Logs")
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // =================================================================
            // TAB 1: MACHINE & HYDRAULICS SETTINGS
            // =================================================================
            RowLayout {
                anchors.fill: parent
                visible: root.activeCategory === 1
                spacing: 8

                // Left: Calibration & Deflection
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("RAM OPENING & DEFLECTION CALIBRATION")
                    accentColor: root.green

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // Hero Opening Calibration Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            radius: 6
                            color: "#FFFFFF"
                            border.color: root.controllerSettingsChanged ? root.amber : "#CBD5E1"
                            border.width: 1.5

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: qsTr("RAM-TO-TABLE OPENING DISTANCE")
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: root.textPrimary
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        radius: 4
                                        color: root.controllerRamToTableOpening > 0 ? "#DCFCE7" : "#F1F5F9"
                                        border.color: root.controllerRamToTableOpening > 0 ? "#86EFAC" : "#CBD5E1"
                                        Layout.preferredWidth: sourceText.implicitWidth + 12
                                        Layout.preferredHeight: 20
                                        Text {
                                            id: sourceText
                                            anchors.centerIn: parent
                                            text: root.ramToTableOpeningSource
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: root.controllerRamToTableOpening > 0 ? "#15803D" : root.textSecondary
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Column {
                                        Text {
                                            text: Units.len(root.editedRamToTableOpening > 0 ? root.editedRamToTableOpening : 8.25, root.metric, 3)
                                            font.bold: true
                                            font.pixelSize: 24
                                            font.family: "Monospace"
                                            color: root.controllerSettingsChanged ? root.amber : root.textPrimary
                                        }
                                        Text {
                                            text: qsTr("Calibration Range:") + " " + Units.len(7.95, root.metric, 3) + " \u2014 " + Units.len(8.75, root.metric, 3)
                                            font.pixelSize: 11
                                            color: root.textMuted
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Button {
                                        Layout.preferredWidth: 90
                                        Layout.preferredHeight: 34
                                        padding: 0
                                        enabled: root.controllerSettingsAllowed
                                        onClicked: {
                                            if (!root.appState) return
                                            var keyboardTarget = { text: root.editedRamToTableOpening.toFixed(3) }
                                            root.appState.openOnScreenKeyboard(keyboardTarget, true,
                                                qsTr("RAM TO TABLE OPENING (7.950 - 8.750 IN)"),
                                                function(val) {
                                                    var p = Number(val)
                                                    if (isFinite(p)) root.appState.editedRamToTableOpening = Math.max(7.950, Math.min(8.750, p))
                                                })
                                        }
                                        background: Rectangle {
                                            radius: 5
                                            color: root.blue
                                        }
                                        contentItem: Item {
                                            anchors.fill: parent
                                            Text {
                                                anchors.centerIn: parent
                                                text: qsTr("CALIBRATE")
                                                font.bold: true
                                                font.pixelSize: 11
                                                color: "#FFFFFF"
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SettingSwitchRow {
                            title: qsTr("Frame Deflection Compensation")
                            desc: qsTr("Dynamic deflection angle correction based on live tonnage and bed span")
                            checked: root.toggleSelected("Frame Deflection Compensation")
                            onToggled: if (root.appState) root.appState.settingsAction("Frame Deflection Compensation")
                        }

                        SettingSwitchRow {
                            title: qsTr("Tonnage Overload Protection")
                            desc: qsTr("Hardware fail-safe cut-off when calculated tonnage exceeds rating")
                            checked: root.toggleSelected("Tonnage Protection")
                            onToggled: if (root.appState) root.appState.setTonnageProtectionEnabled(!root.toggleSelected("Tonnage Protection"))
                        }

                        SettingSwitchRow {
                            objectName: "settings-measurement-convergence"
                            title: qsTr("Measure Convergence")
                            desc: root.appState
                                ? qsTr("Measure only: accept once stable (≥ %1 frames, Δ ≤ %2 in); Calibrate always %3 frames")
                                    .arg(root.appState.manualMeasurementMinimumSamples)
                                    .arg(root.appState.manualMeasurementConvergenceTolerance.toFixed(4))
                                    .arg(root.appState.manualMeasurementRequiredSamples)
                                : qsTr("Measure only: accept the average once stable; Calibrate keeps the fixed frame count")
                            checked: root.toggleSelected("Measurement Convergence")
                            onToggled: if (root.appState) root.appState.settingsAction("Measurement Convergence")
                        }

                        SettingSwitchRow {
                            objectName: "settings-auto-measure-on-clamp"
                            title: qsTr("Auto Measure On Clamp")
                            desc: qsTr("RUN measures the sheet at 0.50 T before the first clamp; low-tonnage parts use the reference block")
                            checked: root.toggleSelected("Auto Measure On Clamp")
                            onToggled: if (root.appState) root.appState.settingsAction("Auto Measure On Clamp")
                        }

                        SettingNumericRow {
                            title: qsTr("Reference Block Thickness")
                            desc: qsTr("Rigid block under thin sheet; set by each CALIBRATE, editable here")
                            valueText: Units.len(root.appState ? root.appState.autoMeasureReferenceBlockThickness : 0, root.metric, 4)
                            onEditClicked: root.editNumeric("autoMeasureReferenceBlockThickness", "Reference Block Thickness",
                                root.appState ? root.appState.autoMeasureReferenceBlockThickness : 0, 0, 2, "in", true)
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Right: Speed, Pressure & Limits
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("HYDRAULIC PRESS PARAMETERS & LIMITS")
                    accentColor: root.red

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        SettingNumericRow {
                            title: qsTr("Max Tonnage Per Cylinder Ram")
                            desc: qsTr("Upper ceiling limit for Y1/Y2 hydraulic relief valve")
                            valueText: (root.appState ? root.appState.manualModeMaxTonnagePerRam.toFixed(1) : "12.5") + " T"
                            onEditClicked: root.editNumeric("manualModeMaxTonnagePerRam", "Max Tonnage Per Ram",
                                root.appState ? root.appState.manualModeMaxTonnagePerRam : 12.5, 0.5, 12.5, "T", true)
                        }

                        SettingNumericRow {
                            title: qsTr("Air Tonnage Detection Threshold")
                            desc: qsTr("Minimum load before workpiece clamp contact is registered")
                            valueText: (root.appState ? root.appState.airTonnageThreshold.toFixed(1) : "0.0") + " T"
                            onEditClicked: root.editNumeric("airTonnageThreshold", "Air Tonnage Threshold",
                                root.appState ? root.appState.airTonnageThreshold : 0.0, 0.0, 12.5, "T", true)
                        }

                        SettingNumericRow {
                            title: qsTr("Material Clamp Rate")
                            desc: qsTr("Clamp distance as % of material thickness the ram strokes past contact")
                            valueText: (root.appState ? root.appState.materialClampRatePercentage.toFixed(1) : "10.0") + " %"
                            onEditClicked: root.editNumeric("materialClampRate", "Material Clamp Rate",
                                root.appState ? root.appState.materialClampRatePercentage : 10.0, 0, 100, "%", true)
                        }

                        SettingNumericRow {
                            title: qsTr("Auto Clamp-to-Bend Pause Dwell")
                            desc: qsTr("Holding delay between clamping workpiece and bend execution")
                            valueText: (root.appState ? root.appState.autoClampDwellSec.toFixed(1) : "0.5") + " sec"
                            onEditClicked: root.editNumeric("autoClampToBendDwellSec", "Clamp-to-Bend Pause",
                                root.appState ? root.appState.autoClampDwellSec : 0.5, 0, 10, "sec", true)
                        }

                        SettingOptionRow {
                            title: qsTr("RUN Pedal Mode (Jog / Bend)")
                            desc: qsTr("BTN = jog buttons, 1TAP = pedal held, 2TAP = double tap and hold")
                            currentValue: root.appState ? root.appState.runPedalModeChoices[root.appState.runPedalMode] : "BTN / 2TAP"
                            options: root.appState ? root.appState.runPedalModeChoices : []
                            onOptionSelected: function(opt) {
                                if (root.appState)
                                    root.appState.setRunPedalModeText(opt)
                            }
                        }

                        SettingSwitchRow {
                            title: qsTr("Remote RUN Program")
                            desc: qsTr("Allows starting the loaded program from the maintenance socket")
                            checked: root.appState ? root.appState.remoteRunAllowed : false
                            onToggled: if (root.appState) root.appState.setRemoteRunAllowed(!root.appState.remoteRunAllowed)
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // =================================================================
            // TAB 2: BACK GAUGE DEFAULTS
            // =================================================================
            RowLayout {
                anchors.fill: parent
                visible: root.activeCategory === 2
                spacing: 8

                // Left: Positioning Defaults
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("BACK GAUGE AXIS & RETRACT DEFAULTS")
                    accentColor: root.amber

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        SettingOptionRow {
                            title: qsTr("Back Gauge Finger")
                            desc: qsTr("ORIGINAL = stepped finger (face 3.028 in), FLAT = flat-nose finger (face 3.00 in)")
                            currentValue: root.appState ? root.appState.backgaugeFingerStyle : "ORIGINAL"
                            options: root.appState ? root.appState.backgaugeFingerStyleChoices : []
                            onOptionSelected: function(opt) {
                                if (root.appState)
                                    root.appState.setBackgaugeFingerStyle(opt)
                            }
                        }

                        SettingSwitchRow {
                            title: qsTr("Wait Pedal Tap Before Back Gauge Move")
                            desc: qsTr("Step 1 of each next sequence (back gauge move) starts only after a pedal tap")
                            checked: root.appState ? root.appState.runAdvanceOnPedalTap : false
                            onToggled: if (root.appState) root.appState.setRunAdvanceOnPedalTap(!root.appState.runAdvanceOnPedalTap)
                        }

                        SettingSwitchRow {
                            title: qsTr("Retract Between Bends")
                            desc: qsTr("Back gauge backs off after each bend. Off skips the retract move")
                            checked: root.appState ? root.appState.backGaugeRetractBetweenBendsEnabled : true
                            onToggled: if (root.appState) root.appState.setBackGaugeRetractBetweenBendsEnabled(!root.appState.backGaugeRetractBetweenBendsEnabled)
                        }

                        SettingNumericRow {
                            enabled: root.appState ? root.appState.backGaugeRetractBetweenBendsEnabled : true
                            opacity: enabled ? 1 : 0.45
                            title: qsTr("Back Gauge Retract Between Bends")
                            desc: qsTr("Automatic safety back-off distance during part repositioning")
                            valueText: Units.len(root.appState ? root.appState.backGaugeRetractBetweenBendsInch : 0, root.metric, 3)
                            onEditClicked: root.editNumeric("backGaugeRetractBetweenBendsInch", "Retract Between Bends",
                                root.appState ? root.appState.backGaugeRetractBetweenBendsInch : 0.0, 0, 5, "in", false)
                        }

                        SettingNumericRow {
                            title: qsTr("Back Gauge Bump-Off Distance")
                            desc: qsTr("Retraction distance immediately before pinch to prevent pinching")
                            valueText: Units.len(root.appState ? root.appState.backGaugeBumpOffDistanceInch : 0, root.metric, 3)
                            onEditClicked: root.editNumeric("backGaugeBumpOffDistanceInch", "Bump Off Distance",
                                root.appState ? root.appState.backGaugeBumpOffDistanceInch : 0.0, 0, 10, "in", false)
                        }

                        SettingNumericRow {
                            title: qsTr("Default R-Axis Finger Elevation")
                            desc: qsTr("Default resting R-axis height when loading new bend sequences")
                            valueText: Units.len(root.appState ? root.appState.defaultBackGaugeRPositionInch : 0, root.metric, 3)
                            onEditClicked: root.editNumeric("defaultBackGaugeRPositionInch", "Default R Position",
                                root.appState ? root.appState.defaultBackGaugeRPositionInch : 0.0, -10, 10, "in", false)
                        }

                        SettingNumericRow {
                            title: qsTr("Punch Coverage Side Tolerance")
                            desc: qsTr("Allowable overhang tolerance for workpiece edges")
                            valueText: Units.len(root.appState ? root.appState.punchCoverageSideToleranceIn : 0, root.metric, 3)
                            onEditClicked: root.editNumeric("punchCoverageSideToleranceIn", "Punch Side Tolerance",
                                root.appState ? root.appState.punchCoverageSideToleranceIn : 0.0, 0, 2, "in", true)
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Right: Coordinate Reference & Geometry Visual
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("REFERENCE STOPS & SAFETY ZONES")
                    accentColor: root.slate

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                Text {
                                    text: qsTr("CONFIGURED REFERENCE ORIGINS")
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: root.textPrimary
                                }

                                Text {
                                    text: qsTr("The back gauge uses industrial G-code reference systems (G54 - G59) for datum calibration against physical finger stops.")
                                    font.pixelSize: 11
                                    color: root.textSecondary
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: "#E2E8F0"
                                }

                                Repeater {
                                    model: ["G54 · Standard Backstop Finger", "G55 · Deep Flange Offset", "G56 · Acute Flange Stop", "G57 · Side Gauge Reference"]
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        Rectangle {
                                            width: 10; height: 10; radius: 5
                                            color: root.green
                                        }
                                        Text {
                                            text: modelData
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: root.textPrimary
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // TAB 3: DIAGNOSTICS & DIRECT COMMAND TERMINAL
            // =================================================================
            RowLayout {
                anchors.fill: parent
                visible: root.activeCategory === 3
                spacing: 8

                // Left: Direct Command Interactive Console
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("INTERACTIVE DIRECT COMMAND TERMINAL")
                    accentColor: root.orange

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Text {
                            text: qsTr("Send raw register instructions directly to the machine controller firmware.")
                            font.pixelSize: 11
                            color: root.textSecondary
                        }

                        // Terminal Command Box
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            radius: 6
                            color: "#18191C"
                            border.color: "#3F4246"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Column {
                                    spacing: 4
                                    Text { text: qsTr("COMMAND ID"); font.bold: true; font.pixelSize: 11; color: "#94A3B8" }
                                    Rectangle {
                                        width: 70; height: 32; radius: 4; color: "#2B2C2B"
                                        border.color: "#475569"
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.directInputId
                                            color: "#FFFFFF"
                                            font.bold: true
                                            font.pixelSize: 13
                                            font.family: "Monospace"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (!root.appState) return
                                                var t = { text: root.directInputId }
                                                root.appState.openOnScreenKeyboard(t, true, qsTr("COMMAND ID (0-255)"), function(v) { root.directInputId = v })
                                            }
                                        }
                                    }
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: qsTr("PARAMETER VALUE"); font.bold: true; font.pixelSize: 11; color: "#94A3B8" }
                                    Rectangle {
                                        width: parent.width; height: 32; radius: 4; color: "#2B2C2B"
                                        border.color: "#475569"
                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.directInputValue
                                            color: "#FFFFFF"
                                            font.bold: true
                                            font.pixelSize: 13
                                            font.family: "Monospace"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (!root.appState) return
                                                var t = { text: root.directInputValue }
                                                root.appState.openOnScreenKeyboard(t, true, qsTr("PARAMETER VALUE"), function(v) { root.directInputValue = v })
                                            }
                                        }
                                    }
                                }

                                Button {
                                    Layout.preferredWidth: 80
                                    Layout.preferredHeight: 32
                                    Layout.alignment: Qt.AlignBottom
                                    padding: 0
                                    onClicked: {
                                        if (root.appState) {
                                            root.appState.settingsAction("DIRECT INPUT " + root.directInputId + " " + root.directInputValue)
                                            var entry = "[" + new Date().toLocaleTimeString() + "] CMD " + root.directInputId + " := " + root.directInputValue + " (SENT)"
                                            root.commandHistory = [entry].concat(root.commandHistory).slice(0, 8)
                                        }
                                    }
                                    background: Rectangle {
                                        radius: 4
                                        color: root.orange
                                    }
                                    contentItem: Item {
                                        anchors.fill: parent
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("EXECUTE")
                                            font.bold: true
                                            font.pixelSize: 11
                                            color: "#FFFFFF"
                                        }
                                    }
                                }
                            }
                        }

                        // Terminal Log History
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 6
                            color: "#0F1115"
                            border.color: "#2B2C2B"

                            ListView {
                                anchors.fill: parent
                                anchors.margins: 8
                                clip: true
                                model: root.commandHistory.length > 0 ? root.commandHistory : [qsTr("[SYSTEM READY] Terminal awaiting direct commands...")]
                                delegate: Text {
                                    text: modelData
                                    color: index === 0 ? "#86EFAC" : "#94A3B8"
                                    font.family: "Monospace"
                                    font.pixelSize: 11
                                    lineHeight: 1.2
                                }
                            }
                        }
                    }
                }

                // Right: Diagnostic Toggles & Communication Status
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("TELEMETRY LOGGING & SERIAL BUS")
                    accentColor: root.slate

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        SettingSwitchRow {
                            title: qsTr("Serial Diagnostic Logging")
                            desc: qsTr("Logs real-time UART / USB packet transmissions")
                            checked: root.toggleSelected("Serial Diagnostic Logs")
                            onToggled: if (root.appState) root.appState.settingsAction("Serial Diagnostic Logs")
                        }

                        SettingSwitchRow {
                            title: qsTr("Run Preview Debug Overlays")
                            desc: qsTr("Enables raw coordinate overlays in Run View")
                            checked: root.toggleSelected("Run Preview Debug Overlays")
                            onToggled: if (root.appState) root.appState.settingsAction("Run Preview Debug Overlays")
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // =================================================================
            // TAB 4: MAINTENANCE & SYSTEM RECOVERY
            // =================================================================
            RowLayout {
                anchors.fill: parent
                visible: root.activeCategory === 4
                spacing: 8

                // Left: Software & Firmware Management
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("SOFTWARE & FIRMWARE MANAGEMENT")

                    // Scroll instead of overlapping when the boxes exceed the card.
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true
                        contentWidth: width
                        contentHeight: firmwareCardColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ColumnLayout {
                        id: firmwareCardColumn
                        width: parent.width
                        spacing: 10

                        // Software update channel: STABLE (tested) or BETA (fast improvements)
                        Rectangle {
                            id: updateChannelBox
                            readonly property var hs: root.appState ? root.appState.hostSystem : null
                            readonly property string channel: hs ? String(hs.updateChannel || "stable") : "stable"
                            Layout.fillWidth: true
                            Layout.preferredHeight: updateChannelColumn.implicitHeight + 20
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1

                            ColumnLayout {
                                id: updateChannelColumn
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                Text {
                                    text: qsTr("Software Updates")
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: root.textPrimary
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: updateChannelBox.channel === "beta"
                                        ? qsTr("BETA: newest improvements as soon as they are released.")
                                        : qsTr("STABLE: only releases already tested in production.")
                                    font.pixelSize: 11
                                    color: root.textSecondary
                                    wrapMode: Text.WordWrap
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Repeater {
                                        model: [{ value: "stable", label: qsTr("STABLE") }, { value: "beta", label: qsTr("BETA") }]
                                        delegate: Button {
                                            required property var modelData
                                            objectName: "update-channel-" + modelData.value
                                            readonly property bool selected: updateChannelBox.channel === modelData.value
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            Layout.preferredHeight: 28
                                            padding: 0
                                            enabled: updateChannelBox.hs !== null
                                            onClicked: updateChannelBox.hs.updateChannel = modelData.value
                                            background: Rectangle { radius: 4; color: parent.selected ? root.textPrimary : "#F1F5F9"; border.color: "#CBD5E1" }
                                            contentItem: Text {
                                                text: modelData.label
                                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                                font.bold: true; font.pixelSize: 11
                                                color: parent.selected ? "#FFFFFF" : root.textPrimary
                                            }
                                        }
                                    }
                                    Button {
                                        objectName: "update-check-now"
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        padding: 0
                                        enabled: updateChannelBox.hs !== null
                                        onClicked: updateChannelBox.hs.checkForApplicationUpdates()
                                        background: Rectangle { radius: 4; color: parent.pressed ? "#E2E8F0" : "#F1F5F9"; border.color: "#CBD5E1" }
                                        contentItem: Text {
                                            text: "\u21BB"
                                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                            font.bold: true; font.pixelSize: 16
                                            color: root.textPrimary
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    readonly property var hs: updateChannelBox.hs
                                    text: qsTr("Installed: %1").arg(root.appState ? root.appState.applicationVersion : "")
                                        + (hs && hs.applicationUpdateAvailable ? "  \u2192  " + qsTr("Available: %1").arg(hs.applicationUpdateVersion) : "")
                                        + (hs && String(hs.updateCheckError || "").length > 0 ? "\n" + hs.updateCheckError : "")
                                    font.pixelSize: 10
                                    color: root.textSecondary
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // CAD PC pairing (upload-only bendimport account)
                        Rectangle {
                            id: cadPairBox
                            readonly property var hs: root.appState ? root.appState.hostSystem : null
                            property bool revokeArmed: false
                            Layout.fillWidth: true
                            Layout.preferredHeight: cadPairColumn.implicitHeight + 20
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1

                            ColumnLayout {
                                id: cadPairColumn
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                Text {
                                    text: qsTr("Fusion Add-in Pairing")
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: root.textPrimary
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: cadPairBox.hs && cadPairBox.hs.cadPairedDevices.length > 0
                                           ? qsTr("Paired: ") + cadPairBox.hs.cadPairedDevices.join(", ")
                                           : qsTr("No Fusion add-in paired. In Fusion use BendCNC Export > Pair with press and accept the request on this screen. A paired add-in can send parts and read tooling and material preferences.")
                                    font.pixelSize: 11
                                    color: root.textPrimary
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: cadPairBox.hs ? String(cadPairBox.hs.cadPairingMessage || "") : ""
                                    font.pixelSize: 11
                                    color: root.textSecondary
                                    wrapMode: Text.WordWrap
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Button {
                                        objectName: "cad-revoke-button"
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        padding: 0
                                        enabled: cadPairBox.hs !== null && cadPairBox.hs.cadPairedDevices.length > 0
                                        onClicked: {
                                            if (!cadPairBox.revokeArmed) {
                                                cadPairBox.revokeArmed = true
                                                return
                                            }
                                            cadPairBox.revokeArmed = false
                                            cadPairBox.hs.revokeCadAccess(true)
                                        }
                                        background: Rectangle { radius: 4; color: cadPairBox.revokeArmed ? root.red : "#F1F5F9"; border.color: "#CBD5E1" }
                                        contentItem: Text {
                                            readonly property bool many: cadPairBox.hs !== null && cadPairBox.hs.cadPairedDevices.length > 1
                                            text: (cadPairBox.revokeArmed ? qsTr("CONFIRM ") : "") + (many ? qsTr("UNPAIR ALL") : qsTr("UNPAIR"))
                                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                            font.bold: true; font.pixelSize: 11
                                            color: cadPairBox.revokeArmed ? "#FFFFFF" : root.textPrimary
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Embedded Hardware Firmware Flashing Box
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: hwFirmwareColumn.implicitHeight + 20
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1

                            ColumnLayout {
                                id: hwFirmwareColumn
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Text {
                                    text: qsTr("Hardware Controller Firmware")
                                    font.bold: true
                                    font.pixelSize: 12
                                    color: root.textPrimary
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Flash verified firmware images directly to embedded microcontroller boards.")
                                    font.pixelSize: 11
                                    color: root.textSecondary
                                    wrapMode: Text.WordWrap
                                }

                                // Target 1: MACHINE FIRMWARE (Arduino Uno R4 press controller).
                                // Images live on the press; MachineFirmwareBackend verifies SHA-256
                                // and queues the supervised flasher. Two-step confirm required.
                                Rectangle {
                                    id: machineFirmwareBox
                                    objectName: "machine-firmware-section"
                                    readonly property var fw: root.appState ? root.appState.machineFirmware : null
                                    readonly property var mc: root.appState ? root.appState.machineControl : null
                                    readonly property var images: fw ? fw.images : []
                                    // Dropdown order: ORIGINAL first, then newest image first.
                                    readonly property var orderedImages: {
                                        var list = images ? images.slice() : []
                                        list.sort(function(a, b) {
                                            var ao = String(a.kind) === "original" ? 1 : 0
                                            var bo = String(b.kind) === "original" ? 1 : 0
                                            if (ao !== bo) return bo - ao
                                            return Number(b.modifiedMs || 0) - Number(a.modifiedMs || 0)
                                        })
                                        return list
                                    }
                                    readonly property bool useDropdown: images.length > 2
                                    readonly property string reportedVersion: mc && mc.pressFirmwareVersion
                                        ? String(mc.pressFirmwareVersion) : ""
                                    property string selectedId: ""
                                    property bool confirmArmed: false
                                    // "[LS-BEND v1.3]" -> "BEND 1.3"; internal build ids stay hidden.
                                    function friendly(expected, fallback) {
                                        var s = String(expected || "").replace(/[\[\]]/g, "").replace(/LS-/g, "").replace(/\sv(?=\d)/, " ").trim()
                                        return s.length > 0 ? s : String(fallback || "")
                                    }
                                    readonly property var selectedImage: {
                                        for (var i = 0; i < images.length; ++i)
                                            if (images[i].id === selectedId) return images[i]
                                        return null
                                    }
                                    readonly property string blockReason: {
                                        if (!fw) return qsTr("Firmware backend unavailable.")
                                        if (!fw.flashSupported) return fw.flashUnavailableReason
                                        if (fw.busy) return ""
                                        if (root.appState && !root.appState.machineFirmwareUiGateClear)
                                            return qsTr("Stop the run / tool change first.")
                                        var tick = mc ? mc.pressMachineState + mc.ramVelocity + mc.pressTelemetryFresh : 0
                                        return fw.machineBlockReason()
                                    }
                                    function imageInstalled(img) {
                                        if (!img) return false
                                        if (fw && fw.appliedHash.length > 0 && fw.appliedHash === img.sha256) return true
                                        return reportedVersion.length > 0
                                            && (img.expectedVersion === "[BENDCNC v" + reportedVersion + "]"
                                                || img.expectedVersion === "[LS-BEND v" + reportedVersion + "]")
                                    }
                                    Timer { interval: 10000; running: machineFirmwareBox.confirmArmed; onTriggered: machineFirmwareBox.confirmArmed = false }
                                    onSelectedIdChanged: confirmArmed = false

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: machineFirmwareColumn.implicitHeight + 16
                                    radius: 5
                                    color: "#F8FAFC"
                                    border.color: "#E2E8F0"
                                    ColumnLayout {
                                        id: machineFirmwareColumn
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 5
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: qsTr("MACHINE FIRMWARE"); font.bold: true; font.pixelSize: 11; color: root.textPrimary }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: machineFirmwareBox.reportedVersion.length > 0
                                                    ? qsTr("INSTALLED: ") + machineFirmwareBox.friendly("[LS-BEND " + machineFirmwareBox.reportedVersion + "]", machineFirmwareBox.reportedVersion)
                                                    : qsTr("INSTALLED: NOT REPORTED")
                                                font.bold: true; font.pixelSize: 11; color: root.blue
                                            }
                                        }
                                        // Remote CURRENT/BETA firmware: auto-downloaded, never auto-flashed.
                                        ColumnLayout {
                                            objectName: "machine-firmware-remote-row"
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: !!(machineFirmwareBox.fw && machineFirmwareBox.fw.remoteUpdatesEnabled)
                                            Text {
                                                Layout.fillWidth: true
                                                text: machineFirmwareBox.fw && machineFirmwareBox.fw.remoteMessage.length > 0
                                                    ? machineFirmwareBox.fw.remoteMessage
                                                    : qsTr("Firmware updates are checked automatically.")
                                                font.pixelSize: 11; wrapMode: Text.WordWrap
                                                color: machineFirmwareBox.fw && machineFirmwareBox.fw.remoteState === "DOWNLOADED" ? root.green
                                                    : machineFirmwareBox.fw && machineFirmwareBox.fw.remoteState === "REJECTED" ? root.red
                                                    : root.textSecondary
                                            }
                                            RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Rectangle {
                                                objectName: "machine-firmware-check-updates"
                                                Layout.preferredWidth: 110; Layout.preferredHeight: 22; radius: 4
                                                readonly property bool enabledState: !!(machineFirmwareBox.fw && !machineFirmwareBox.fw.remoteBusy)
                                                color: enabledState ? "#FFFFFF" : "#F1F5F9"
                                                border.color: "#CBD5E1"
                                                Text { anchors.centerIn: parent; text: qsTr("CHECK FOR UPDATES"); font.bold: true; font.pixelSize: 11; color: parent.enabledState ? root.blue : root.textMuted }
                                                MouseArea { anchors.fill: parent; enabled: parent.enabledState; onClicked: machineFirmwareBox.fw.checkForUpdate() }
                                            }
                                            }
                                        }
                                        ComboBox {
                                            id: machineFirmwareCombo
                                            objectName: "machine-firmware-dropdown"
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 30
                                            visible: machineFirmwareBox.useDropdown
                                            enabled: !(machineFirmwareBox.fw && machineFirmwareBox.fw.busy)
                                            model: machineFirmwareBox.orderedImages
                                            font.pixelSize: 11
                                            displayText: currentIndex < 0 ? qsTr("Select a firmware image...") : textAt(currentIndex)
                                            textRole: ""
                                            function label(img) {
                                                if (!img) return ""
                                                var t = String(img.title || img.kind || img.id).toUpperCase() + "  " + machineFirmwareBox.friendly(img.expectedVersion, img.version)
                                                if (machineFirmwareBox.imageInstalled(img)) t += "  [INSTALLED]"
                                                if (!img.verified) t += "  [NOT VERIFIED]"
                                                return t
                                            }
                                            function textAt(i) { return label(machineFirmwareBox.orderedImages[i]) }
                                            currentIndex: {
                                                var l = machineFirmwareBox.orderedImages
                                                for (var i = 0; i < l.length; ++i)
                                                    if (l[i].id === machineFirmwareBox.selectedId) return i
                                                return -1
                                            }
                                            delegate: ItemDelegate {
                                                width: machineFirmwareCombo.width
                                                enabled: !!modelData.verified
                                                contentItem: Column {
                                                    Text { text: machineFirmwareCombo.label(modelData); font.bold: true; font.pixelSize: 11; color: root.textPrimary }
                                                    Text {
                                                        text: String(modelData.expectedVersion || "") + "   SHA " + String(modelData.sha256 || "").substring(0, 12)
                                                            + (modelData.modifiedMs ? "   " + Qt.formatDateTime(new Date(Number(modelData.modifiedMs)), "yyyy-MM-dd HH:mm") : "")
                                                        font.pixelSize: 11; font.family: "monospace"; color: root.textMuted
                                                    }
                                                }
                                            }
                                            onActivated: function(index) {
                                                var img = machineFirmwareBox.orderedImages[index]
                                                if (img && img.verified) machineFirmwareBox.selectedId = img.id
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: machineFirmwareBox.useDropdown && machineFirmwareBox.selectedImage !== null
                                            text: machineFirmwareBox.selectedImage
                                                ? String(machineFirmwareBox.selectedImage.expectedVersion || "") + "  SHA "
                                                  + String(machineFirmwareBox.selectedImage.sha256).substring(0, 12)
                                                  + (machineFirmwareBox.selectedImage.description ? "  " + machineFirmwareBox.selectedImage.description : "")
                                                : ""
                                            font.pixelSize: 11; font.family: "monospace"; color: root.textMuted
                                            elide: Text.ElideRight
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            visible: machineFirmwareBox.images.length > 0 && !machineFirmwareBox.useDropdown
                                            Repeater {
                                                model: machineFirmwareBox.orderedImages
                                                delegate: Rectangle {
                                                    id: firmwareCard
                                                    objectName: "machine-firmware-card-" + modelData.id
                                                    readonly property bool selected: machineFirmwareBox.selectedId === modelData.id
                                                    readonly property bool installed: machineFirmwareBox.imageInstalled(modelData)
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 50
                                                    radius: 4
                                                    color: selected ? "#EFF6FF" : "#FFFFFF"
                                                    border.color: selected ? root.blue : "#CBD5E1"
                                                    border.width: selected ? 2 : 1
                                                    opacity: modelData.verified ? 1.0 : 0.6
                                                    ColumnLayout {
                                                        anchors.fill: parent
                                                        anchors.margins: 5
                                                        spacing: 0
                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Text { text: String(modelData.title || modelData.kind || modelData.id).toUpperCase(); font.bold: true; font.pixelSize: 11; color: root.textPrimary }
                                                            Item { Layout.fillWidth: true }
                                                            Rectangle {
                                                                visible: firmwareCard.installed
                                                                width: 56; height: 14; radius: 3; color: root.green
                                                                Text { anchors.centerIn: parent; text: qsTr("INSTALLED"); font.bold: true; font.pixelSize: 11; color: "#FFFFFF" }
                                                            }
                                                        }
                                                        Text { text: machineFirmwareBox.friendly(modelData.expectedVersion, modelData.version); font.pixelSize: 11; color: root.textSecondary; elide: Text.ElideRight; Layout.fillWidth: true }
                                                        Text {
                                                            text: modelData.verified ? qsTr("SHA ") + String(modelData.sha256).substring(0, 12)
                                                                : qsTr("NOT VERIFIED: ") + modelData.verifyError
                                                            font.pixelSize: 11; font.family: "monospace"
                                                            color: modelData.verified ? root.textMuted : root.red
                                                            elide: Text.ElideRight; Layout.fillWidth: true
                                                        }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        enabled: modelData.verified && !(machineFirmwareBox.fw && machineFirmwareBox.fw.busy)
                                                        onClicked: machineFirmwareBox.selectedId = modelData.id
                                                    }
                                                }
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: machineFirmwareBox.images.length === 0
                                            text: machineFirmwareBox.fw ? machineFirmwareBox.fw.catalogError : qsTr("Firmware backend unavailable.")
                                            font.pixelSize: 11; color: root.red; wrapMode: Text.WordWrap
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text {
                                                Layout.fillWidth: true
                                                text: {
                                                    var fw = machineFirmwareBox.fw
                                                    if (machineFirmwareBox.confirmArmed && machineFirmwareBox.selectedImage)
                                                        return qsTr("Install ") + machineFirmwareBox.friendly(machineFirmwareBox.selectedImage.expectedVersion, machineFirmwareBox.selectedImage.title)
                                                            + qsTr("? Hydraulics off. The app closes about 1 min while flashing. Home the press afterwards.")
                                                    if (fw && fw.flashMessage.length > 0) return fw.flashState + " - " + fw.flashMessage
                                                    if (machineFirmwareBox.blockReason.length > 0) return machineFirmwareBox.blockReason
                                                    return machineFirmwareBox.selectedImage ? qsTr("Ready to install.") : qsTr("Select a firmware image.")
                                                }
                                                font.pixelSize: 11
                                                color: machineFirmwareBox.confirmArmed ? root.orange : root.textSecondary
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                            }
                                            Button {
                                                visible: machineFirmwareBox.confirmArmed
                                                Layout.preferredWidth: 64
                                                Layout.preferredHeight: 28
                                                padding: 0
                                                onClicked: machineFirmwareBox.confirmArmed = false
                                                background: Rectangle { radius: 4; color: root.slate }
                                                contentItem: Text { text: qsTr("CANCEL"); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.bold: true; font.pixelSize: 11; color: "#FFFFFF" }
                                            }
                                            Button {
                                                objectName: "machine-firmware-install"
                                                readonly property bool canInstall: machineFirmwareBox.fw !== null
                                                    && machineFirmwareBox.selectedImage !== null
                                                    && machineFirmwareBox.selectedImage.verified
                                                    && !machineFirmwareBox.fw.busy
                                                    && machineFirmwareBox.blockReason.length === 0
                                                Layout.preferredWidth: 110
                                                Layout.preferredHeight: 28
                                                padding: 0
                                                enabled: canInstall
                                                onClicked: {
                                                    if (!machineFirmwareBox.confirmArmed) {
                                                        machineFirmwareBox.confirmArmed = true
                                                        return
                                                    }
                                                    machineFirmwareBox.confirmArmed = false
                                                    if (root.appState) root.appState.log("SETTINGS", "MACHINE FIRMWARE INSTALL " + machineFirmwareBox.selectedId)
                                                    machineFirmwareBox.fw.startFlash(machineFirmwareBox.selectedId, true,
                                                        root.appState ? root.appState.machineFirmwareUiGateClear : false)
                                                }
                                                background: Rectangle { radius: 4; color: parent.enabled ? (machineFirmwareBox.confirmArmed ? root.red : root.charcoal) : "#94A3B8" }
                                                contentItem: Text {
                                                    text: machineFirmwareBox.confirmArmed ? qsTr("CONFIRM INSTALL") : qsTr("INSTALL")
                                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                                    font.bold: true; font.pixelSize: 11; color: "#FFFFFF"
                                                }
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 48
                                            visible: machineFirmwareBox.fw !== null && machineFirmwareBox.fw.flashLogTail.length > 0
                                            text: machineFirmwareBox.fw ? machineFirmwareBox.fw.flashLogTail : ""
                                            font.pixelSize: 11; font.family: "monospace"; color: root.textMuted
                                            clip: true; wrapMode: Text.NoWrap
                                            verticalAlignment: Text.AlignBottom
                                        }
                                    }
                                }

                                // Target 2: Back Gauge Module (Orange Pi). Hidden: no separate
                                // back gauge firmware/flasher exists yet (action only raised an alarm).
                                Rectangle {
                                    visible: false
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    radius: 5
                                    color: "#F8FAFC"
                                    border.color: "#E2E8F0"
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text { text: qsTr("Back Gauge Motion Subsystem"); font.bold: true; font.pixelSize: 11; color: root.textPrimary }
                                            Text { text: qsTr("Orange Pi CM4 (USB-Serial Module)"); font.pixelSize: 11; color: root.textMuted }
                                        }
                                        Button {
                                            Layout.preferredWidth: 125
                                            Layout.preferredHeight: 30
                                            padding: 0
                                            onClicked: if (root.appState) root.appState.settingsAction("FLASH MODULE")
                                            background: Rectangle { radius: 4; color: root.slate }
                                            contentItem: Item {
                                                anchors.fill: parent
                                                Text { anchors.centerIn: parent; text: qsTr("FLASH MODULE"); font.bold: true; font.pixelSize: 11; color: "#FFFFFF" }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 1. USB Software Update Box
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 112
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: qsTr("Application Software Update")
                                        font.bold: true
                                        font.pixelSize: 12
                                        color: root.textPrimary
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 76; height: 20; radius: 4
                                        color: "#EFF6FF"
                                        border.color: "#BFDBFE"
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("USB DISK")
                                            font.bold: true
                                            font.pixelSize: 11
                                            color: root.blue
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Select an update package (.tar.gz / .deb) from a connected USB flash drive to upgrade the BendCNC application.")
                                    font.pixelSize: 11
                                    color: root.textSecondary
                                    wrapMode: Text.WordWrap
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Item { Layout.fillWidth: true }
                                    Button {
                                        Layout.preferredWidth: 150
                                        Layout.preferredHeight: 30
                                        padding: 0
                                        onClicked: softwareUpdateDialog.open()
                                        background: Rectangle {
                                            radius: 4
                                            color: root.blue
                                        }
                                        contentItem: Item {
                                            anchors.fill: parent
                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Text { text: "📁"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                                Text {
                                                    text: qsTr("BROWSE PACKAGE")
                                                    font.bold: true
                                                    font.pixelSize: 11
                                                    color: "#FFFFFF"
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 3. Tooling Library & Program Database Backup Box
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 88
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                Text {
                                    text: qsTr("Tooling & Program Database Backup")
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: root.textPrimary
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Create, export to USB or restore punch/die libraries, material definitions, programs and settings.")
                                    font.pixelSize: 11
                                    color: root.textSecondary
                                    wrapMode: Text.WordWrap
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Button {
                                        objectName: "maintenance-backup-export"
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 28
                                        padding: 0
                                        onClicked: if (root.appState) root.appState.toolbarAction("backup")
                                        background: Rectangle { radius: 4; color: "#F1F5F9"; border.color: "#CBD5E1" }
                                        contentItem: Item {
                                            anchors.fill: parent
                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Text { text: "⤓"; font.pixelSize: 11; font.bold: true; color: root.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                                                Text { text: qsTr("EXPORT BACKUP"); font.bold: true; font.pixelSize: 11; color: root.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                        }
                                    }
                                    Button {
                                        objectName: "maintenance-backup-restore"
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 28
                                        padding: 0
                                        onClicked: if (root.appState) root.appState.toolbarAction("backup")
                                        background: Rectangle { radius: 4; color: "#F1F5F9"; border.color: "#CBD5E1" }
                                        contentItem: Item {
                                            anchors.fill: parent
                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Text { text: "⤒"; font.pixelSize: 11; font.bold: true; color: root.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                                                Text { text: qsTr("RESTORE BACKUP"); font.bold: true; font.pixelSize: 11; color: root.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }
                }

                // Right: System Recovery, Environment & Backup
                SettingCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cardTitle: qsTr("SYSTEM RECOVERY & HARDWARE TELEMETRY")

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        // 1. System Environment Telemetry
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 4

                                Text { text: qsTr("SYSTEM ENVIRONMENT & RUNTIME"); font.bold: true; font.pixelSize: 11; color: root.textPrimary }

                                Rectangle { Layout.fillWidth: true; height: 1; color: "#F1F5F9" }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: qsTr("Application Version:"); font.pixelSize: 11; color: root.textMuted }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "1.0.0 (Qt 6.11 · Precision v8)"; font.bold: true; font.pixelSize: 11; font.family: "Monospace"; color: root.textPrimary }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: qsTr("Hardware Communication:"); font.pixelSize: 11; color: root.textMuted }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "Dual USB Serial (115200 baud)"; font.bold: true; font.pixelSize: 11; font.family: "Monospace"; color: root.textPrimary }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: qsTr("Host Operations:"); font.pixelSize: 11; color: root.textMuted }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: (root.appState && root.appState.hostOperationsAvailable) ? qsTr("AVAILABLE (LINUX KIOSK)") : qsTr("STANDBY (LOCAL)")
                                        font.bold: true; font.pixelSize: 11; font.family: "Monospace"
                                        color: (root.appState && root.appState.hostOperationsAvailable) ? "#15803D" : root.textSecondary
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: qsTr("Storage Architecture:"); font.pixelSize: 11; color: root.textMuted }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "Atomic FileIO Backend (Safe JSON)"; font.bold: true; font.pixelSize: 11; font.family: "Monospace"; color: root.textPrimary }
                                }
                            }
                        }

                        // 2. Factory Reset Card (Clean and comfortable, no overflow!)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 6
                            color: "#FFF5F5"
                            border.color: "#FECACA"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text { text: "⚠"; font.pixelSize: 14; color: root.red }
                                    Text { text: qsTr("Restore Factory Default Settings"); font.bold: true; font.pixelSize: 12; color: root.red }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Resets all machine calibrations, ram-to-table opening distance, back gauge defaults, origin datums, and user display preferences to factory baseline.")
                                    font.pixelSize: 11
                                    color: "#7F1D1D"
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.2
                                }

                                Item { Layout.fillHeight: true }

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    padding: 0
                                    onClicked: if (root.appState) root.appState.settingsAction("RESTORE DEFAULTS")
                                    background: Rectangle {
                                        radius: 4
                                        color: root.red
                                        border.color: "#B91C1C"
                                    }
                                    contentItem: Item {
                                        anchors.fill: parent
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text { text: "↺"; font.pixelSize: 12; font.bold: true; color: "#FFFFFF"; anchors.verticalCenter: parent.verticalCenter }
                                            Text {
                                                text: qsTr("RESTORE FACTORY DEFAULTS"); font.bold: true; font.pixelSize: 11; color: "#FFFFFF"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. FOOTER PERSISTENCE BAR (height: 42)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            radius: 7
            color: root.cardBg
            border.color: root.cardBorderColor
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Row {
                    spacing: 6
                    Rectangle {
                        width: 16; height: 16; radius: 8
                        color: "#DCFCE7"
                        border.color: "#86EFAC"
                        Text { anchors.centerIn: parent; text: "✓"; font.pixelSize: 11; font.bold: true; color: "#15803D" }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Application settings are saved automatically.")
                        font.pixelSize: 11
                        font.bold: true
                        color: root.textSecondary
                    }
                }

                Item { Layout.fillWidth: true }

                // Reset / Discard changes
                Button {
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 32
                    padding: 0
                    onClicked: if (root.appState) root.appState.settingsAction("CANCEL")
                    background: Rectangle {
                        radius: 5
                        color: "#64748B"
                    }
                    contentItem: Item {
                        anchors.fill: parent
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("RESET")
                            font.bold: true
                            font.pixelSize: 11
                            color: "#FFFFFF"
                        }
                    }
                }

                // Save to Controller EEPROM
                Button {
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 32
                    padding: 0
                    enabled: root.controllerSettingsChanged
                    onClicked: if (root.appState) root.appState.settingsAction("SAVE")
                    background: Rectangle {
                        radius: 5
                        color: root.controllerSettingsChanged ? root.green : "#94A3B8"
                    }
                    contentItem: Item {
                        anchors.fill: parent
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "💾"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: qsTr("SAVE EEPROM")
                                font.bold: true
                                font.pixelSize: 11
                                color: "#FFFFFF"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // REUSABLE SETTINGS COMPONENTS
    // =========================================================================

    component CategoryTabButton: Rectangle {
        property int index: 0
        property string iconText: ""
        property string tabLabel: ""
        property bool active: false
        signal clicked()

        width: 100
        height: 34
        radius: 5
        color: active ? root.blue : (catMouse.containsMouse ? "#3F4246" : "#2B2C2B")
        border.color: active ? "#60A5FA" : "#475569"
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 5
            // Drawn icons: the press has no emoji font, so glyphs rendered as boxes.
            Canvas {
                id: tabIcon
                width: 14; height: 14
                anchors.verticalCenter: parent.verticalCenter
                readonly property color ink: active ? "#FFFFFF" : "#CBD5E1"
                onInkChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d")
                    c.reset()
                    c.strokeStyle = ink; c.fillStyle = ink; c.lineWidth = 1.4
                    if (index === 0) {          // display
                        c.strokeRect(1.5, 2.5, 11, 7.5)
                        c.fillRect(5, 11, 4, 1.5)
                    } else if (index === 1) {   // gear
                        c.beginPath(); c.arc(7, 7, 3.6, 0, 2 * Math.PI); c.stroke()
                        for (var k = 0; k < 8; ++k) {
                            var a = k * Math.PI / 4
                            c.beginPath(); c.moveTo(7 + 4.2 * Math.cos(a), 7 + 4.2 * Math.sin(a))
                            c.lineTo(7 + 6.2 * Math.cos(a), 7 + 6.2 * Math.sin(a)); c.stroke()
                        }
                    } else if (index === 2) {   // ruler
                        c.strokeRect(1, 4.5, 12, 5)
                        for (var r = 3; r < 13; r += 2.5) { c.beginPath(); c.moveTo(r, 4.5); c.lineTo(r, 7); c.stroke() }
                    } else if (index === 3) {   // bolt
                        c.beginPath(); c.moveTo(8.5, 0.5); c.lineTo(3, 8); c.lineTo(6.8, 8)
                        c.lineTo(5.5, 13.5); c.lineTo(11, 6); c.lineTo(7.2, 6); c.closePath(); c.fill()
                    } else {                    // disk
                        c.strokeRect(1.5, 1.5, 11, 11)
                        c.fillRect(4, 1.5, 6, 3.5)
                        c.strokeRect(4, 8, 6, 4.5)
                    }
                }
            }
            Text {
                text: tabLabel
                font.bold: true
                font.pixelSize: 11
                color: active ? "#FFFFFF" : "#CBD5E1"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: catMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component SettingCard: Rectangle {
        property string cardTitle: ""
        property color accentColor: root.blue
        default property alias content: cardContentContainer.data

        radius: 7
        color: root.cardBg
        border.color: root.cardBorderColor
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 7
                color: root.cardHeaderBg

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.radius
                    color: parent.color
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: cardTitle
                        font.bold: true
                        font.pixelSize: 11
                        color: "#FFFFFF"
                        font.letterSpacing: 0.5
                    }
                }
            }

            Item {
                id: cardContentContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }

    component SettingSwitchRow: Rectangle {
        property string title: ""
        property string desc: ""
        property bool checked: false
        signal toggled()

        Layout.fillWidth: true
        // Grows with wrapped text so the description never runs under the toggle.
        Layout.preferredHeight: Math.max(52, switchText.implicitHeight + 16)
        radius: 6
        color: "#FFFFFF"
        border.color: "#CBD5E1"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            ColumnLayout {
                id: switchText
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Text { Layout.fillWidth: true; text: title; font.bold: true; font.pixelSize: 11; color: root.textPrimary; wrapMode: Text.WordWrap }
                Text { Layout.fillWidth: true; text: desc; font.pixelSize: 11; color: root.textMuted; wrapMode: Text.WordWrap; visible: text.length > 0 }
            }

            // Modern iOS/Android-style pill toggle
            Rectangle {
                Layout.preferredWidth: 52; Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter
                width: 52; height: 26; radius: 13
                color: checked ? root.green : "#94A3B8"
                border.color: checked ? "#4C8C0A" : "#64748B"
                border.width: 1

                Rectangle {
                    width: 20; height: 20; radius: 10
                    anchors.verticalCenter: parent.verticalCenter
                    x: checked ? (parent.width - 23) : 3
                    color: "#FFFFFF"
                    Behavior on x { NumberAnimation { duration: 150 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toggled()
                }
            }
        }
    }

    component SettingOptionRow: Rectangle {
        property string title: ""
        property string desc: ""
        property string currentValue: ""
        property var options: []
        signal optionSelected(string opt)

        id: optionRow
        // Stack the options under the title when they would cover it.
        readonly property bool stacked: optionButtons.implicitWidth + 190 > width
        Layout.fillWidth: true
        implicitHeight: Math.max(56, optionBody.implicitHeight + 18)
        Layout.preferredHeight: implicitHeight
        Layout.minimumHeight: implicitHeight
        radius: 6
        color: "#FFFFFF"
        border.color: "#CBD5E1"
        border.width: 1

        GridLayout {
            id: optionBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            columns: optionRow.stacked ? 1 : 2
            columnSpacing: 10
            rowSpacing: 6

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { Layout.fillWidth: true; text: title; font.bold: true; font.pixelSize: 11; color: root.textPrimary; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; text: desc; font.pixelSize: 11; color: root.textMuted; wrapMode: Text.WordWrap }
        }

        Row {
            id: optionButtons
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            spacing: 4
                Repeater {
                    model: options
                    delegate: Rectangle {
                        width: optText.implicitWidth + 14
                        height: 26
                        radius: 4
                        color: currentValue === modelData ? root.charcoal : "#F1F5F9"
                        border.color: currentValue === modelData ? root.charcoal : "#CBD5E1"
                        Text {
                            id: optText
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 11
                            font.bold: true
                            color: currentValue === modelData ? "#FFFFFF" : root.textSecondary
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: optionSelected(modelData)
                        }
                    }
                }
        }
        }
    }

    component SettingNumericRow: Rectangle {
        property string title: ""
        property string desc: ""
        property string valueText: ""
        signal editClicked()

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(52, numericText.implicitHeight + 16)
        radius: 6
        color: "#FFFFFF"
        border.color: "#CBD5E1"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            ColumnLayout {
                id: numericText
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Text { Layout.fillWidth: true; text: title; font.bold: true; font.pixelSize: 11; color: root.textPrimary; wrapMode: Text.WordWrap }
                Text { Layout.fillWidth: true; text: desc; font.pixelSize: 11; color: root.textMuted; wrapMode: Text.WordWrap; visible: text.length > 0 }
            }

            Rectangle {
                Layout.preferredWidth: 90; Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                width: 90; height: 32; radius: 5
                color: "#F8FAFC"
                border.color: "#CBD5E1"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: valueText
                    font.bold: true
                    font.pixelSize: 12
                    font.family: "Monospace"
                    color: root.textPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editClicked()
                }
            }
        }
    }
}
