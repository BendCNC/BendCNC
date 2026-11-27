import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Controls.Basic

Item {
    id: root
    objectName: "settings-view"
    property var appState: null

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
    property int activeCategory: 1
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
        if (label === "Frame Deflection Compensation") return appState.desktopFrameDeflectionCompensationEnabled === true
        return true
    }

    function editNumeric(key, label, current, min, max, unit, isApp) {
        if (!appState) return
        var num = isFinite(Number(current)) ? Number(current) : min
        var keyboardTarget = { text: unit === "%" ? num.toFixed(1) : (unit === "sec" ? num.toFixed(1) : num.toFixed(3)) }
        appState.openOnScreenKeyboard(keyboardTarget, true,
            qsTr(label.toUpperCase() + " (" + min + " - " + max + (unit ? " " + unit : "") + ")"),
            function(value) {
                if (isApp) appState.setApplicationNumericSetting(key, value)
                else appState.setBackGaugeUserSetting(key, value)
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

                        SettingSwitchRow {
                            title: qsTr("Operator Safety Popups & Alarms")
                            desc: qsTr("Enforces modal confirmations before high-tonnage moves")
                            checked: root.toggleSelected("Safety Warnings")
                            onToggled: if (root.appState) root.appState.settingsAction("Safety Warnings")
                        }

                        SettingSwitchRow {
                            title: qsTr("Legacy Run Interface Mode")
                            desc: qsTr("Reverts to classic run view layout and step table")
                            checked: root.toggleSelected("Legacy Run UI")
                            onToggled: if (root.appState) root.appState.settingsAction("Legacy Run UI")
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
                            title: qsTr("Flat Pattern Contours Renderer")
                            desc: qsTr("Visual contour rendering engine in bend sequence preview")
                            currentValue: root.appState ? root.appState.runFlatPatternContourRenderer.toUpperCase() : "CLASSIC"
                            options: ["CLASSIC", "CANONICAL", "OVERLAY"]
                            onOptionSelected: function(opt) {
                                if (root.appState && root.appState.runFlatPatternContourRenderer.toUpperCase() !== opt)
                                    root.appState.settingsAction("Flat Pattern Contours")
                            }
                        }

                        SettingOptionRow {
                            title: qsTr("Tooling CAD Appearance")
                            desc: qsTr("Punch and die 3D rendering opacity in Run View")
                            currentValue: root.appState ? root.appState.runToolingAppearance : "SOLID"
                            options: ["SOLID", "TRANSLUCENT"]
                            onOptionSelected: function(opt) {
                                if (root.appState && root.appState.runToolingAppearance !== opt)
                                    root.appState.settingsAction("Tooling Appearance")
                            }
                        }

                        SettingSwitchRow {
                            title: qsTr("Live Preview Debug Overlays")
                            desc: qsTr("Displays flange vectors, sheet normals, and joint origins")
                            checked: root.toggleSelected("Run Preview Debug Overlays")
                            onToggled: if (root.appState) root.appState.settingsAction("Run Preview Debug Overlays")
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
                                            font.pixelSize: 9
                                            font.bold: true
                                            color: root.controllerRamToTableOpening > 0 ? "#15803D" : root.textSecondary
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Column {
                                        Text {
                                            text: (root.editedRamToTableOpening > 0 ? root.editedRamToTableOpening.toFixed(3) : "8.250") + " in"
                                            font.bold: true
                                            font.pixelSize: 24
                                            font.family: "Monospace"
                                            color: root.controllerSettingsChanged ? root.amber : root.textPrimary
                                        }
                                        Text {
                                            text: qsTr("Calibration Range: 7.950 in — 8.750 in")
                                            font.pixelSize: 10
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
                                                font.pixelSize: 10
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

                        SettingNumericRow {
                            title: qsTr("Back Gauge Retract Between Bends")
                            desc: qsTr("Automatic safety back-off distance during part repositioning")
                            valueText: (root.appState ? root.appState.backGaugeRetractBetweenBendsInch.toFixed(3) : "0.000") + " in"
                            onEditClicked: root.editNumeric("backGaugeRetractBetweenBendsInch", "Retract Between Bends",
                                root.appState ? root.appState.backGaugeRetractBetweenBendsInch : 0.0, 0, 5, "in", false)
                        }

                        SettingNumericRow {
                            title: qsTr("Back Gauge Bump-Off Distance")
                            desc: qsTr("Retraction distance immediately before pinch to prevent pinching")
                            valueText: (root.appState ? root.appState.backGaugeBumpOffDistanceInch.toFixed(3) : "0.000") + " in"
                            onEditClicked: root.editNumeric("backGaugeBumpOffDistanceInch", "Bump Off Distance",
                                root.appState ? root.appState.backGaugeBumpOffDistanceInch : 0.0, 0, 10, "in", false)
                        }

                        SettingNumericRow {
                            title: qsTr("Default R-Axis Finger Elevation")
                            desc: qsTr("Default resting R-axis height when loading new bend sequences")
                            valueText: (root.appState ? root.appState.defaultBackGaugeRPositionInch.toFixed(3) : "0.000") + " in"
                            onEditClicked: root.editNumeric("defaultBackGaugeRPositionInch", "Default R Position",
                                root.appState ? root.appState.defaultBackGaugeRPositionInch : 0.0, -10, 10, "in", false)
                        }

                        SettingNumericRow {
                            title: qsTr("Punch Coverage Side Tolerance")
                            desc: qsTr("Allowable overhang tolerance for workpiece edges")
                            valueText: (root.appState ? root.appState.punchCoverageSideToleranceIn.toFixed(3) : "0.000") + " in"
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
                                    font.pixelSize: 10
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
                            font.pixelSize: 10
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
                                    Text { text: qsTr("COMMAND ID"); font.bold: true; font.pixelSize: 9; color: "#94A3B8" }
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
                                    Text { text: qsTr("PARAMETER VALUE"); font.bold: true; font.pixelSize: 9; color: "#94A3B8" }
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
                                    font.pixelSize: 10
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

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

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
                                            font.pixelSize: 9
                                            color: root.blue
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Select an update package (.tar.gz / .deb) from a connected USB flash drive to upgrade the BendCNC application.")
                                    font.pixelSize: 10
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
                                                    font.pixelSize: 10
                                                    color: "#FFFFFF"
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Embedded Hardware Firmware Flashing Box
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1

                            ColumnLayout {
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
                                    font.pixelSize: 10
                                    color: root.textSecondary
                                    wrapMode: Text.WordWrap
                                }

                                // Target 1: Machine Controller (Arduino Uno R4)
                                Rectangle {
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
                                            Text { text: qsTr("Machine Hydraulic Controller"); font.bold: true; font.pixelSize: 10; color: root.textPrimary }
                                            Text { text: qsTr("Arduino Uno R4 Minima (USB-Serial Press)"); font.pixelSize: 9; color: root.textMuted }
                                        }
                                        Button {
                                            Layout.preferredWidth: 125
                                            Layout.preferredHeight: 30
                                            padding: 0
                                            onClicked: if (root.appState) root.appState.settingsAction("FLASH MACHINE")
                                            background: Rectangle { radius: 4; color: root.charcoal }
                                            contentItem: Item {
                                                anchors.fill: parent
                                                Text { anchors.centerIn: parent; text: qsTr("FLASH MACHINE"); font.bold: true; font.pixelSize: 9; color: "#FFFFFF" }
                                            }
                                        }
                                    }
                                }

                                // Target 2: Back Gauge Module (Orange Pi)
                                Rectangle {
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
                                            Text { text: qsTr("Back Gauge Motion Subsystem"); font.bold: true; font.pixelSize: 10; color: root.textPrimary }
                                            Text { text: qsTr("Orange Pi CM4 (USB-Serial Module)"); font.pixelSize: 9; color: root.textMuted }
                                        }
                                        Button {
                                            Layout.preferredWidth: 125
                                            Layout.preferredHeight: 30
                                            padding: 0
                                            onClicked: if (root.appState) root.appState.settingsAction("FLASH MODULE")
                                            background: Rectangle { radius: 4; color: root.slate }
                                            contentItem: Item {
                                                anchors.fill: parent
                                                Text { anchors.centerIn: parent; text: qsTr("FLASH MODULE"); font.bold: true; font.pixelSize: 9; color: "#FFFFFF" }
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
                                    text: qsTr("Export or restore punch/die libraries, material definitions, and bend sequences.")
                                    font.pixelSize: 9
                                    color: root.textSecondary
                                    wrapMode: Text.WordWrap
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        padding: 0
                                        background: Rectangle { radius: 4; color: "#F1F5F9"; border.color: "#CBD5E1" }
                                        contentItem: Item {
                                            anchors.fill: parent
                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Text { text: "⤓"; font.pixelSize: 11; font.bold: true; color: root.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                                                Text { text: qsTr("EXPORT BACKUP"); font.bold: true; font.pixelSize: 9; color: root.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                        }
                                    }
                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        padding: 0
                                        background: Rectangle { radius: 4; color: "#F1F5F9"; border.color: "#CBD5E1" }
                                        contentItem: Item {
                                            anchors.fill: parent
                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Text { text: "⤒"; font.pixelSize: 11; font.bold: true; color: root.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                                                Text { text: qsTr("RESTORE BACKUP"); font.bold: true; font.pixelSize: 9; color: root.textPrimary; anchors.verticalCenter: parent.verticalCenter }
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

                                Text { text: qsTr("SYSTEM ENVIRONMENT & RUNTIME"); font.bold: true; font.pixelSize: 10; color: root.textPrimary }

                                Rectangle { Layout.fillWidth: true; height: 1; color: "#F1F5F9" }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: qsTr("Application Version:"); font.pixelSize: 9; color: root.textMuted }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "1.0.0 (Qt 6.11 · Precision v8)"; font.bold: true; font.pixelSize: 9; font.family: "Monospace"; color: root.textPrimary }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: qsTr("Hardware Communication:"); font.pixelSize: 9; color: root.textMuted }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "Dual USB Serial (115200 baud)"; font.bold: true; font.pixelSize: 9; font.family: "Monospace"; color: root.textPrimary }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: qsTr("Host Operations:"); font.pixelSize: 9; color: root.textMuted }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: (root.appState && root.appState.hostOperationsAvailable) ? qsTr("AVAILABLE (LINUX KIOSK)") : qsTr("STANDBY (LOCAL)")
                                        font.bold: true; font.pixelSize: 9; font.family: "Monospace"
                                        color: (root.appState && root.appState.hostOperationsAvailable) ? "#15803D" : root.textSecondary
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: qsTr("Storage Architecture:"); font.pixelSize: 9; color: root.textMuted }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "Atomic FileIO Backend (Safe JSON)"; font.bold: true; font.pixelSize: 9; font.family: "Monospace"; color: root.textPrimary }
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
                                    font.pixelSize: 10
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
                                                text: qsTr("RESTORE FACTORY DEFAULTS"); font.bold: true; font.pixelSize: 10; color: "#FFFFFF"
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
                        Text { anchors.centerIn: parent; text: "✓"; font.pixelSize: 9; font.bold: true; color: "#15803D" }
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
                            font.pixelSize: 10
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
                                font.pixelSize: 10
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
            Text {
                text: iconText
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: tabLabel
                font.bold: true
                font.pixelSize: 9
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
                        font.pixelSize: 10
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
        Layout.preferredHeight: 52
        radius: 6
        color: "#FFFFFF"
        border.color: "#CBD5E1"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Column {
                Layout.fillWidth: true
                spacing: 2
                Text { text: title; font.bold: true; font.pixelSize: 11; color: root.textPrimary }
                Text { text: desc; font.pixelSize: 9; color: root.textMuted }
            }

            // Modern iOS/Android-style pill toggle
            Rectangle {
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

        Layout.fillWidth: true
        Layout.preferredHeight: 56
        radius: 6
        color: "#FFFFFF"
        border.color: "#CBD5E1"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Column {
                Layout.fillWidth: true
                spacing: 2
                Text { text: title; font.bold: true; font.pixelSize: 11; color: root.textPrimary }
                Text { text: desc; font.pixelSize: 9; color: root.textMuted }
            }

            Row {
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
                            font.pixelSize: 9
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
        Layout.preferredHeight: 52
        radius: 6
        color: "#FFFFFF"
        border.color: "#CBD5E1"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Column {
                Layout.fillWidth: true
                spacing: 2
                Text { text: title; font.bold: true; font.pixelSize: 11; color: root.textPrimary }
                Text { text: desc; font.pixelSize: 9; color: root.textMuted }
            }

            Rectangle {
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
