pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../.." as Production
import "../.."

Item {
    id: root
    property var appState: null
    property var dataStore: null
    property bool designerBlankCanvas: false
    property bool sceneInfoActive: false
    property string runDebugLogPath: ""
    property int styleVariant: 0
    property int runCockpitStyle: 2


    // Stage preview override (defaults to 1 = CLAMP for instant active highlighting in lab)
    property int previewStage: 1

    // Theme Color Tokens
    readonly property color canvasBg: "#F0F2F5"
    readonly property color darkPanel: "#181D24"
    readonly property color charcoal: "#2B2C2B"
    readonly property color ink: "#232323"
    readonly property color grey: "#A8A8A8"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color paper: "#F5F5F5"
    readonly property color blue: "#2D83B2"
    readonly property color green: "#59A60C"
    readonly property color runGreen: "#16A34A"
    readonly property color runGreenBorder: "#22C55E"
    readonly property color orange: "#FF9900"
    readonly property color amber: "#F59E0B"
    readonly property color red: "#A82011"
    readonly property color cyan: "#0E7490"
    readonly property color emerald: "#166534"
    readonly property color purple: "#6D28D9"
    readonly property color cardBg: "#1F242D"
    readonly property color cardBorderColor: "#334155"

    readonly property string iconRoot: "../../icons/"

    // Dwell and Auto Clamp state (integer seconds, no decimals)
    property real dwellSeconds: 3
    property bool dwellOverrideActive: true
    property bool localAutoClamp: true
    readonly property real effectiveDwell: dwellOverrideActive ? dwellSeconds : ((appState && typeof appState.autoClampDwellSec !== "undefined") ? appState.autoClampDwellSec : dwellSeconds)

    function stepDwell(delta) {
        dwellOverrideActive = true;
        var cur = Math.round(effectiveDwell);
        var nextVal = Math.max(0, Math.min(15, cur + delta));
        dwellSeconds = nextVal;
        if (appState && typeof appState.setApplicationNumericSetting === "function") {
            appState.setApplicationNumericSetting("autoClampToBendDwellSec", nextVal);
        }
    }

    function toggleAutoClamp() {
        localAutoClamp = !localAutoClamp;
        if (appState && typeof appState.runAction === "function") {
            appState.runAction("auto-clamp");
        }
    }

    // Main Modal Container
    Rectangle {
        anchors.fill: parent
        color: root.darkPanel
        radius: 8
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // =====================================================================
            // SECTION 1: TOP ACTION BAR (Exact Production Layout from RunLeftView)
            // =====================================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 49
                color: root.charcoal
                z: 10

                GridLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 7
                    anchors.rightMargin: 7
                    anchors.topMargin: 7
                    anchors.bottomMargin: 7
                    columns: 7
                    columnSpacing: 7
                    rowSpacing: 0

                    ComboField {
                        id: runProgramCombo
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: appState ? appState.programOptions() : ["DIN Bracket 10in N1", "Panel Flange A", "Bracket 90deg"]
                        currentText: appState ? appState.activeProgram : "DIN Bracket 10in N1"
                        onActivated: function(index) {
                            if (appState) appState.selectProgram(index)
                        }
                    }

                    ProgramNameField {
                        id: programNameEditor
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: "REGENERATE"
                        visible: false
                    }

                    IconButton {
                        id: editButton
                        Layout.fillWidth: false
                        Layout.preferredWidth: 35
                        Layout.fillHeight: true
                        glyph: ""
                        iconSource: root.iconRoot + "fa-pen.svg"
                        base: root.paper
                        glyphColor: root.ink
                        border.color: root.ink
                        border.width: 1
                        onClicked: {
                            if (appState) appState.runAction("edit")
                        }
                    }

                    IconButton {
                        id: trashButton
                        Layout.fillWidth: false
                        Layout.preferredWidth: 35
                        Layout.fillHeight: true
                        glyph: ""
                        iconSource: root.iconRoot + "fa-trash.svg"
                        base: root.red
                        onClicked: {
                            if (appState) appState.runAction("delete")
                        }
                    }

                    TextButton {
                        Layout.preferredWidth: 94
                        Layout.fillHeight: true
                        iconSource: root.iconRoot + "fa-file-white.svg"
                        label: "NEW"
                        base: root.blue
                        onClicked: {
                            if (appState) appState.runAction("new")
                        }
                    }

                    TextButton {
                        Layout.preferredWidth: 82
                        Layout.fillHeight: true
                        iconSource: root.iconRoot + "fa-save.svg"
                        label: "SAVE"
                        base: root.green
                        onClicked: {
                            if (appState) appState.runAction("save")
                        }
                    }

                    TextButton {
                        Layout.preferredWidth: 116
                        Layout.fillHeight: true
                        iconSource: root.iconRoot + "fa-file-white.svg"
                        label: "DUPLICATE"
                        base: root.orange
                        onClicked: {
                            if (appState) appState.runAction("duplicate")
                        }
                    }
                }
            }

            // =====================================================================
            // SECTION 2: 2D/3D CANVAS & SUBHEADER BAR (100% Production Parity)
            // =====================================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 7
                Layout.rightMargin: 7
                Layout.topMargin: 4
                color: "transparent"
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Canvas Sub-Header Bar (Polished UI & Fully Functional SimButtons)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 6
                        color: root.charcoal
                        border.color: root.ink
                        border.width: 1

                        // Square bottom corners for seamless continuity with canvas below
                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: parent.radius
                            height: parent.radius
                            color: root.charcoal
                            Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: root.ink }
                            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: root.ink }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            SimButton {
                                Layout.preferredWidth: 72
                                Layout.preferredHeight: 28
                                label: (appState && appState.runBendListVisible) ? "▼ LIST" : "▲ LIST"
                                base: root.blue
                                onClicked: if (appState) appState.runSimulationAction("toggle-list")
                            }

                            SimButton {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 28
                                label: "\◀"
                                base: "#374151"
                                enabledState: appState ? appState.selectedRunBend > 0 : false
                                onClicked: if (appState) appState.runSimulationAction("previous")
                            }

                            SimButton {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 28
                                label: "\▶"
                                base: "#374151"
                                enabledState: appState ? appState.selectedRunBend < (appState.programBends ? appState.programBends.length - 1 : 0) : false
                                onClicked: if (appState) appState.runSimulationAction("next")
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        var raw = appState ? appState.runSimulationHeader1() : "B1/4 | 90.0\° | GOOSENECK 88\° | DIE";
                                        return String(raw).replace(/\\u00C2\°|°/g, "\°");
                                    }
                                    color: "#F1F5F9"
                                    font.bold: true
                                    font.pixelSize: 11
                                    elide: Text.ElideLeft
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        var raw = appState ? appState.runSimulationHeader2() : 'BG X 0.8634" | R -0.2500" | DIR UP | FACE TOP';
                                        return String(raw).replace(/\\u00C2|Â/g, "");
                                    }
                                    color: "#FBBF24"
                                    font.bold: true
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            SimButton {
                                Layout.preferredWidth: 92
                                Layout.preferredHeight: 28
                                label: "PLACEMENT"
                                base: (appState ? appState.runSceneMode === "PLACEMENT" : true) ? root.blue : "#374151"
                                onClicked: if (appState) appState.runSimulationAction("placement")
                            }

                            SimButton {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 28
                                label: "LIVE"
                                base: (appState && appState.runSceneMode === "LIVE") ? root.blue : "#374151"
                                onClicked: if (appState) appState.runSimulationAction("live")
                            }

                            SimButton {
                                Layout.preferredWidth: 84
                                Layout.preferredHeight: 28
                                label: (appState && appState.runSimulatedRun) ? "STOP DEMO" : "SIM RUN"
                                base: (appState && appState.runSimulatedRun) ? root.runGreen : "#374151"
                                onClicked: if (appState) appState.runSimulationAction("sim-run")
                            }
                        }
                    }

                    // 2D/3D Production Execution Canvas (100% Intact)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 0
                        color: root.lightGrey
                        border.color: root.ink
                        border.width: 1

                        RunExecutionCanvas {
                            id: modernRunCanvas
                            anchors.fill: parent
                            visible: !root.designerBlankCanvas
                            sceneMode: appState ? appState.runSceneMode : "PLACEMENT"
                            liveProjectionMode: appState ? appState.runLiveProjectionMode : "SIDE"
                            liveCameraOrientation: appState ? appState.runLiveCameraOrientation : "ISO_TOP_LEFT"
                            liveStatusCardVisible: !(appState && appState.runSceneMode === "LIVE" && appState.runLiveProjectionMode === "ISOMETRIC")
                            toolingAppearance: appState ? appState.runToolingAppearance : "SOLID"
                            guides: appState ? appState.runShowMachineGuides : false
                            running: appState ? (appState.runSimulatedRun || appState.runActive) : false
                            simulatedPlayback: appState ? appState.runSimulatedRun : false
                            physicalTelemetryFresh: appState && appState.machineControl ? appState.machineControl.pressTelemetryFresh : false
                            physicalExecutionPhase: appState ? appState.executionPhase : ""
                            physicalPressState: appState ? appState.machineStatus : "UNKNOWN"
                            physicalRamPosition: appState ? appState.ramPosition : 0
                            physicalBackGaugeX: appState ? appState.backGaugeX : 0
                            physicalBackGaugeR: appState ? appState.backGaugeR : 0
                            backGaugeEnabled: appState ? appState.runBendUsesBackGauge() : true
                            backGaugeRetractDistanceIn: appState ? appState.backGaugeRetractBetweenBendsInch : 2.0
                            backGaugeBumpOffDistanceIn: appState ? appState.backGaugeBumpOffDistanceInch : 0.25
                            autoClampDwellSeconds: appState && appState.autoClampToBendEnabled ? appState.autoClampDwellSec : 0
                            physicalStartPosition: appState ? appState.runRamTarget("startPosition") : NaN
                            physicalClampPosition: appState ? appState.runRamTarget("clampPosition") : NaN
                            physicalFinalPosition: appState ? appState.runRamTarget("finalPosition") : NaN
                            label: appState && appState.runActive ? appState.runProgressTitle : (appState ? appState.runSimulationHeader1() : "B1/4 | 90.0° | GN88 | DIE")
                            detail: appState && appState.runActive ? appState.runOperatorPrompt() : (appState ? appState.runSimulationHeader2() : "")
                            programName: appState ? appState.activeProgram : ""
                            programPreviewJson: appState ? appState.activeProgramCadPreviewJson : ""
                            selectedBendIndex: appState ? appState.selectedRunBend : 0
                            selectedBend: appState ? appState.selectedBend : ({})
                            punchCatalog: dataStore ? dataStore.punches : []
                            dieCatalog: dataStore ? dataStore.dies : []
                            punchCoverageSideToleranceIn: appState ? appState.punchCoverageSideToleranceIn : 0
                            runDebugLogPath: root.runDebugLogPath
                            runDebugLogsEnabled: appState ? appState.runPreviewDebugLogsEnabled : false
                            runDebugOverlaysEnabled: appState ? appState.runPreviewDebugOverlaysEnabled : false
                            runCadenceDebug: Qt.application.arguments.indexOf("--run-cadence-debug") !== -1
                            flatPatternContourRenderer: appState ? appState.runFlatPatternContourRenderer : "classic"
                        }

                        Rectangle {
                            id: runBendListDropdownOverlay
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.topMargin: 4
                            z: 100
                            visible: appState ? appState.runBendListVisible : false
                            color: "#0F172A"
                            border.color: "#334155"
                            border.width: 1
                            radius: 8
                            clip: true
                            height: 30 + rowsScrollContainer.height + 36

                            // Catch clicks inside the card so they don't fall through to canvas
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { /* consume click */ }
                            }

                            Column {
                                anchors.fill: parent
                                spacing: 0

                                // 1. CNC TABLE COLUMN HEADERS (Height: 30px)
                                Rectangle {
                                    width: parent.width
                                    height: 30
                                    color: "#182234"
                                    border.color: "#334155"
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 0

                                        Text {
                                            Layout.preferredWidth: 58
                                            text: "STEP"
                                            color: "#94A3B8"
                                            font.bold: true
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                        Text {
                                            Layout.preferredWidth: 64
                                            text: "ANGLE"
                                            color: "#94A3B8"
                                            font.bold: true
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                        Item {
                                            Layout.preferredWidth: 205
                                            Layout.fillHeight: true
                                            RowLayout {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                spacing: 4
                                                Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: "#F59E0B" }
                                                Text {
                                                    text: "PUNCH TOOL"
                                                    color: "#94A3B8"
                                                    font.bold: true
                                                    font.pixelSize: 10
                                                }
                                            }
                                        }
                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            RowLayout {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                spacing: 4
                                                Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: "#94A3B8" }
                                                Text {
                                                    text: "DIE & V-OPENING"
                                                    color: "#94A3B8"
                                                    font.bold: true
                                                    font.pixelSize: 10
                                                }
                                            }
                                        }
                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                        Text {
                                            Layout.preferredWidth: 120
                                            text: "BACK GAUGE (X / R)"
                                            color: "#94A3B8"
                                            font.bold: true
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                        Text {
                                            Layout.preferredWidth: 52
                                            text: "DIR"
                                            color: "#94A3B8"
                                            font.bold: true
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                        Text {
                                            Layout.preferredWidth: 68
                                            text: "STATUS"
                                            color: "#94A3B8"
                                            font.bold: true
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }
                                }

                                // 2. SCROLLABLE BEND ROWS (Height: 44px per row, max 264px)
                                Item {
                                    id: rowsScrollContainer
                                    width: parent.width
                                    height: Math.min(bendsCol.height, 264)
                                    clip: true

                                    Flickable {
                                        anchors.fill: parent
                                        contentWidth: width
                                        contentHeight: bendsCol.height
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        Column {
                                            id: bendsCol
                                            width: parent.width
                                            spacing: 0

                                            Repeater {
                                                id: bendsRepeater
                                                model: appState ? appState.programBends : []

                                                Rectangle {
                                                    id: rowDelegate
                                                    width: bendsCol.width
                                                    height: 44

                                                    required property int index
                                                    required property var modelData

                                                    readonly property var currentBend: modelData
                                                    readonly property bool isSelected: appState && appState.selectedRunBend === rowDelegate.index
                                                    readonly property bool isCompleted: appState ? Number(currentBend.seq || rowDelegate.index + 1) < Number(appState.selectedBend.seq || appState.selectedRunBend + 1) : false
                                                    readonly property string angleText: String(currentBend.angle || "90.0").replace(/\u00C2°|°/g, "") + "°"

                                                    // Punch parsing
                                                    readonly property string punchRaw: {
                                                        var p = currentBend.punch || "";
                                                        if ((!p || p === "UNDEFINED" || p === "GN88" || p.length <= 4) && currentBend.notes) {
                                                            var m = /Suggested punch:\s*([^\r\n]+)/.exec(currentBend.notes);
                                                            if (m) p = m[1];
                                                        }
                                                        return String(p || "GOOSENECK 88° PUNCH").replace(/\u00C2°|°/g, "°");
                                                    }
                                                    readonly property string punchCatalog: {
                                                        var m = /\[([^\]]+)\]/.exec(rowDelegate.punchRaw);
                                                        return m ? m[1] : (currentBend.punchId ? String(currentBend.punchId).substring(0, 8) : "");
                                                    }
                                                    readonly property string punchTitle: {
                                                        var cleaned = rowDelegate.punchRaw.replace(/\[[^\]]+\]/g, "").replace(/\bPUNCH\b/ig, "").replace(/\s+/g, " ").trim();
                                                        return (cleaned.length > 0 ? cleaned : "PUNCH").toUpperCase();
                                                    }

                                                    // Die parsing
                                                    readonly property string dieRaw: {
                                                        var d = currentBend.die || "";
                                                        if ((!d || d === "UNDEFINED" || d === "8mm" || d.length <= 4) && currentBend.notes) {
                                                            var m = /Suggested die:\s*([^\r\n]+)/.exec(currentBend.notes);
                                                            if (m) d = m[1];
                                                        }
                                                        return String(d || "ACUTE 8mm 30° DIE").replace(/\u00C2°|°/g, "°");
                                                    }
                                                    readonly property string dieCatalog: {
                                                        var m = /\[([^\]]+)\]/.exec(rowDelegate.dieRaw);
                                                        return m ? m[1] : (currentBend.dieId ? String(currentBend.dieId).substring(0, 8) : "");
                                                    }
                                                    readonly property string dieVOpening: {
                                                        if (currentBend.vdieValue !== undefined && currentBend.vdieValue !== null && String(currentBend.vdieValue).length > 0)
                                                            return "V " + currentBend.vdieValue + "\"";
                                                        if (currentBend.dieOpening !== undefined && currentBend.dieOpening !== null && String(currentBend.dieOpening).length > 0)
                                                            return "V " + currentBend.dieOpening + "\"";
                                                        if (currentBend.vOpening !== undefined && currentBend.vOpening !== null && String(currentBend.vOpening).length > 0)
                                                            return "V " + currentBend.vOpening + "\"";
                                                        if (currentBend.vdie !== undefined && currentBend.vdie !== null && String(currentBend.vdie).length > 0)
                                                            return "V " + currentBend.vdie;
                                                        var vm = /(\d+(?:\.\d+)?\s*(?:mm|in|\"))/i.exec(rowDelegate.dieRaw);
                                                        if (vm) return "V " + vm[1].trim();
                                                        return "V 0.315\"";
                                                    }
                                                    readonly property string dieTitle: {
                                                        var cleaned = rowDelegate.dieRaw.replace(/\[[^\]]+\]/g, "").replace(/\bDIE\b/ig, "").replace(/\s+/g, " ").trim();
                                                        return (cleaned.length > 0 ? cleaned : "DIE").toUpperCase();
                                                    }

                                                    readonly property string xText: (currentBend.x || "0.0000") + '"'
                                                    readonly property string rText: {
                                                        var rawR = (currentBend.r !== undefined && currentBend.r !== null && String(currentBend.r).length > 0)
                                                                   ? currentBend.r
                                                                   : ((currentBend.backGaugeRPosition !== undefined && currentBend.backGaugeRPosition !== null)
                                                                      ? currentBend.backGaugeRPosition
                                                                      : (appState ? appState.defaultBackGaugeRPositionInch : -0.25));
                                                        var num = Number(rawR);
                                                        if (!isNaN(num)) {
                                                            return num.toFixed(4) + '"';
                                                        }
                                                        return String(rawR) + '"';
                                                    }
                                                    readonly property string dirText: appState ? appState.runBendDirection(currentBend) : "UP"

                                                    color: rowDelegate.isSelected ? "#1E293B" : (rowMouse.containsMouse ? "#182234" : (rowDelegate.index % 2 === 1 ? "#0F172A" : "#0B0F17"))

                                                    // Active Indicator Bar on Left
                                                    Rectangle {
                                                        width: 4
                                                        anchors.left: parent.left
                                                        anchors.top: parent.top
                                                        anchors.bottom: parent.bottom
                                                        color: rowDelegate.isSelected ? "#F59E0B" : "transparent"
                                                        visible: rowDelegate.isSelected
                                                    }

                                                    // Divider line at bottom
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        height: 1
                                                        color: rowDelegate.isSelected ? "#334155" : "#1E293B"
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 0

                                                        // Column 1: STEP Badge
                                                        Item {
                                                            Layout.preferredWidth: 58
                                                            Layout.fillHeight: true

                                                            Rectangle {
                                                                anchors.centerIn: parent
                                                                width: 50
                                                                height: 24
                                                                radius: 12
                                                                color: rowDelegate.isSelected ? "#2A2215" : (rowDelegate.isCompleted ? "#064E3B" : "#1E293B")
                                                                border.color: rowDelegate.isSelected ? "#F59E0B" : (rowDelegate.isCompleted ? "#059669" : "#334155")
                                                                border.width: 1

                                                                RowLayout {
                                                                    anchors.centerIn: parent
                                                                    spacing: 3
                                                                    Text {
                                                                        text: rowDelegate.isSelected ? "▶" : (rowDelegate.isCompleted ? "✓" : "")
                                                                        color: rowDelegate.isSelected ? "#F59E0B" : "#34D399"
                                                                        font.bold: true
                                                                        font.pixelSize: 9
                                                                        visible: rowDelegate.isSelected || rowDelegate.isCompleted
                                                                    }
                                                                    Text {
                                                                        text: "B" + String(rowDelegate.index + 1)
                                                                        color: rowDelegate.isSelected ? "#FEF3C7" : (rowDelegate.isCompleted ? "#A7F3D0" : "#94A3B8")
                                                                        font.bold: true
                                                                        font.pixelSize: 11
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: rowDelegate.isSelected ? "#334155" : "#1E293B" }

                                                        // Column 2: ANGLE
                                                        Item {
                                                            Layout.preferredWidth: 64
                                                            Layout.fillHeight: true
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: rowDelegate.angleText
                                                                color: rowDelegate.isSelected ? "#FFFFFF" : (rowDelegate.isCompleted ? "#64748B" : "#F8FAFC")
                                                                font.bold: true
                                                                font.pixelSize: 13
                                                            }
                                                        }

                                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: rowDelegate.isSelected ? "#334155" : "#1E293B" }

                                                        // Column 3: PUNCH TOOL
                                                        Item {
                                                            Layout.preferredWidth: 205
                                                            Layout.fillHeight: true
                                                            RowLayout {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: 8
                                                                anchors.rightMargin: 8
                                                                spacing: 6

                                                                Rectangle {
                                                                    Layout.preferredWidth: 18
                                                                    Layout.preferredHeight: 18
                                                                    radius: 3
                                                                    color: "#78350F"
                                                                    border.color: "#F59E0B"
                                                                    border.width: 1
                                                                    Text {
                                                                        anchors.centerIn: parent
                                                                        text: "P"
                                                                        color: "#FDE68A"
                                                                        font.bold: true
                                                                        font.pixelSize: 9
                                                                    }
                                                                }

                                                                Column {
                                                                    Layout.fillWidth: true
                                                                    spacing: 1
                                                                    Text {
                                                                        width: parent.width
                                                                        text: rowDelegate.punchTitle
                                                                        color: rowDelegate.isSelected ? "#FFFFFF" : (rowDelegate.isCompleted ? "#64748B" : "#F8FAFC")
                                                                        font.bold: true
                                                                        font.pixelSize: 11
                                                                        elide: Text.ElideRight
                                                                    }
                                                                    Text {
                                                                        width: parent.width
                                                                        visible: rowDelegate.punchCatalog.length > 0
                                                                        text: rowDelegate.punchCatalog
                                                                        color: rowDelegate.isSelected ? "#94A3B8" : "#64748B"
                                                                        font.family: "Monospace"
                                                                        font.pixelSize: 9
                                                                        elide: Text.ElideRight
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: rowDelegate.isSelected ? "#334155" : "#1E293B" }

                                                        // Column 4: DIE TOOL & V-OPENING
                                                        Item {
                                                            Layout.fillWidth: true
                                                            Layout.fillHeight: true
                                                            RowLayout {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: 8
                                                                anchors.rightMargin: 8
                                                                spacing: 6

                                                                Rectangle {
                                                                    Layout.preferredWidth: 18
                                                                    Layout.preferredHeight: 18
                                                                    radius: 3
                                                                    color: "#1E293B"
                                                                    border.color: "#475569"
                                                                    border.width: 1
                                                                    Text {
                                                                        anchors.centerIn: parent
                                                                        text: "D"
                                                                        color: "#CBD5E1"
                                                                        font.bold: true
                                                                        font.pixelSize: 9
                                                                    }
                                                                }

                                                                Column {
                                                                    Layout.fillWidth: true
                                                                    spacing: 1
                                                                    RowLayout {
                                                                        width: parent.width
                                                                        spacing: 6
                                                                        Text {
                                                                            Layout.fillWidth: true
                                                                            text: rowDelegate.dieTitle
                                                                            color: rowDelegate.isSelected ? "#FFFFFF" : (rowDelegate.isCompleted ? "#64748B" : "#F8FAFC")
                                                                            font.bold: true
                                                                            font.pixelSize: 11
                                                                            elide: Text.ElideRight
                                                                        }
                                                                        // Prominent High-Contrast V-Opening Badge
                                                                        Rectangle {
                                                                            visible: rowDelegate.dieVOpening.length > 0
                                                                            Layout.preferredHeight: 16
                                                                            Layout.preferredWidth: vText.implicitWidth + 8
                                                                            radius: 3
                                                                            color: "#0F172A"
                                                                            border.color: "#64748B"
                                                                            border.width: 1
                                                                            Text {
                                                                                id: vText
                                                                                anchors.centerIn: parent
                                                                                text: rowDelegate.dieVOpening
                                                                                color: "#E2E8F0"
                                                                                font.bold: true
                                                                                font.pixelSize: 10
                                                                            }
                                                                        }
                                                                    }
                                                                    Text {
                                                                        width: parent.width
                                                                        visible: rowDelegate.dieCatalog.length > 0
                                                                        text: rowDelegate.dieCatalog
                                                                        color: rowDelegate.isSelected ? "#94A3B8" : "#64748B"
                                                                        font.family: "Monospace"
                                                                        font.pixelSize: 9
                                                                        elide: Text.ElideRight
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: rowDelegate.isSelected ? "#334155" : "#1E293B" }

                                                        // Column 5: BACK GAUGE (X / R)
                                                        Item {
                                                            Layout.preferredWidth: 120
                                                            Layout.fillHeight: true

                                                            Rectangle {
                                                                anchors.centerIn: parent
                                                                width: 108
                                                                height: 32
                                                                radius: 4
                                                                color: "#111827"
                                                                border.color: rowDelegate.isSelected ? "#F59E0B" : "#374151"
                                                                border.width: 1

                                                                Column {
                                                                    anchors.centerIn: parent
                                                                    spacing: 1

                                                                    RowLayout {
                                                                        spacing: 4
                                                                        Text { text: "X:"; color: "#94A3B8"; font.bold: true; font.pixelSize: 9 }
                                                                        Text {
                                                                            text: rowDelegate.xText
                                                                            color: rowDelegate.isSelected ? "#FBBF24" : (rowDelegate.isCompleted ? "#64748B" : "#E2E8F0")
                                                                            font.family: "Monospace"
                                                                            font.bold: true
                                                                            font.pixelSize: 10
                                                                        }
                                                                    }

                                                                    RowLayout {
                                                                        spacing: 4
                                                                        Text { text: "R:"; color: "#94A3B8"; font.bold: true; font.pixelSize: 9 }
                                                                        Text {
                                                                            text: rowDelegate.rText
                                                                            color: rowDelegate.isSelected ? "#FBBF24" : (rowDelegate.isCompleted ? "#64748B" : "#CBD5E1")
                                                                            font.family: "Monospace"
                                                                            font.bold: true
                                                                            font.pixelSize: 10
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: rowDelegate.isSelected ? "#334155" : "#1E293B" }

                                                        // Column 6: DIR
                                                        Item {
                                                            Layout.preferredWidth: 52
                                                            Layout.fillHeight: true

                                                            Rectangle {
                                                                anchors.centerIn: parent
                                                                width: 44
                                                                height: 20
                                                                radius: 4
                                                                color: "#1E293B"
                                                                border.color: "#334155"
                                                                border.width: 1

                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: (rowDelegate.dirText === "UP" ? "▲ " : "▼ ") + rowDelegate.dirText
                                                                    color: rowDelegate.isSelected ? "#F59E0B" : (rowDelegate.dirText === "UP" ? "#94A3B8" : "#F59E0B")
                                                                    font.bold: true
                                                                    font.pixelSize: 9
                                                                }
                                                            }
                                                        }

                                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: rowDelegate.isSelected ? "#334155" : "#1E293B" }

                                                        // Column 7: STATUS
                                                        Item {
                                                            Layout.preferredWidth: 68
                                                            Layout.fillHeight: true

                                                            Rectangle {
                                                                anchors.centerIn: parent
                                                                width: 58
                                                                height: 20
                                                                radius: 4
                                                                color: rowDelegate.isSelected ? "#2A2215" : (rowDelegate.isCompleted ? "#064E3B" : "#1E293B")
                                                                border.color: rowDelegate.isSelected ? "#F59E0B" : (rowDelegate.isCompleted ? "#059669" : "#334155")
                                                                border.width: 1

                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: rowDelegate.isSelected ? "ACTIVE" : (rowDelegate.isCompleted ? "DONE" : "PENDING")
                                                                    color: rowDelegate.isSelected ? "#D1FAE5" : (rowDelegate.isCompleted ? "#A7F3D0" : "#64748B")
                                                                    font.bold: true
                                                                    font.pixelSize: 9
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Click to select this bend
                                                    MouseArea {
                                                        id: rowMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (appState) {
                                                                appState.selectedRunBend = rowDelegate.index;
                                                                appState.selectedBend = rowDelegate.currentBend;
                                                                if (typeof appState.runSimulationAction === "function") {
                                                                    appState.runSimulationAction("select-bend-" + rowDelegate.index);
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // 3. TABLE FOOTER (Height: 36px)
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    color: "#0B0F17"
                                    border.color: "#334155"
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12

                                        // Add Bend Button
                                        Rectangle {
                                            Layout.preferredHeight: 26
                                            Layout.preferredWidth: 104
                                            radius: 4
                                            color: addMouse.containsMouse ? "#B45309" : "#78350F"
                                            border.color: "#F59E0B"
                                            border.width: 1

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text { text: "+"; color: "#FDE68A"; font.bold: true; font.pixelSize: 13 }
                                                Text { text: "ADD BEND"; color: "#FDE68A"; font.bold: true; font.pixelSize: 10 }
                                            }

                                            MouseArea {
                                                id: addMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (appState && typeof appState.openAddBendPopup === "function") {
                                                        appState.openAddBendPopup(dataStore ? dataStore.bends : null, dataStore ? dataStore.punches : null, dataStore ? dataStore.dies : null, dataStore ? dataStore.materials : null);
                                                    }
                                                }
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Total steps indicator
                                        Text {
                                            text: (appState && appState.programBends ? appState.programBends.length : 0) + " TOTAL BENDS  |  ALL TOOLS MATCHED"
                                            color: "#64748B"
                                            font.bold: true
                                            font.pixelSize: 10
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Close Button
                                        Rectangle {
                                            Layout.preferredHeight: 26
                                            Layout.preferredWidth: 80
                                            radius: 4
                                            color: closeMouse.containsMouse ? "#334155" : "#1E293B"
                                            border.color: "#475569"
                                            border.width: 1

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text { text: "CLOSE"; color: "#E2E8F0"; font.bold: true; font.pixelSize: 10 }
                                                Text { text: "▲"; color: "#94A3B8"; font.pixelSize: 8 }
                                            }

                                            MouseArea {
                                                id: closeMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (appState) {
                                                        appState.runBendListVisible = false;
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
            }

            // =====================================================================
            // SECTION 3: DYNAMIC STAGE POSITION RIBBON (DRO Highway with Active Highlighting)
            // =====================================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                Layout.maximumHeight: 28
                Layout.fillHeight: false
                Layout.leftMargin: 7
                Layout.rightMargin: 7
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                color: "#0B0F17"
                border.color: "#1E293B"
                border.width: 1
                radius: 4

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // 1: START
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property bool isCurrent: root.previewStage === 0 || (appState && appState.executionPhase === "START")
                        color: isCurrent ? "#D97706" : "transparent"
                        border.color: isCurrent ? "#F59E0B" : "transparent"
                        border.width: isCurrent ? 1 : 0
                        radius: 3
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            Text { text: "START"; color: parent.parent.isCurrent ? "black" : "#64748B"; font.bold: true; font.pixelSize: 10 }
                            Item { Layout.fillWidth: true }
                            Text { text: "-1.2000 in"; color: parent.parent.isCurrent ? "black" : "#F8FAFC"; font.bold: true; font.pixelSize: 11 }
                        }
                    }

                    Rectangle { width: 1; Layout.fillHeight: true; color: "#1E293B" }

                    // 2: CLAMP (Highlighted active stage)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property bool isCurrent: root.previewStage === 1 || (appState && (appState.executionPhase === "CLAMP" || appState.executionPhase === "DWELL_TIMER_WAIT"))
                        color: isCurrent ? "#D97706" : "transparent"
                        border.color: isCurrent ? "#F59E0B" : "transparent"
                        border.width: isCurrent ? 1 : 0
                        radius: 3
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            Text { text: "CLAMP"; color: parent.parent.isCurrent ? "black" : "#64748B"; font.bold: true; font.pixelSize: 10 }
                            Item { Layout.fillWidth: true }
                            Text { text: "-1.2140 in"; color: parent.parent.isCurrent ? "black" : "#F8FAFC"; font.bold: true; font.pixelSize: 11 }
                        }
                    }

                    Rectangle { width: 1; Layout.fillHeight: true; color: "#1E293B" }

                    // 3: FINAL
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property bool isCurrent: root.previewStage === 2 || (appState && appState.executionPhase === "FINAL")
                        color: isCurrent ? "#D97706" : "transparent"
                        border.color: isCurrent ? "#F59E0B" : "transparent"
                        border.width: isCurrent ? 1 : 0
                        radius: 3
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            Text { text: "FINAL"; color: parent.parent.isCurrent ? "black" : "#64748B"; font.bold: true; font.pixelSize: 10 }
                            Item { Layout.fillWidth: true }
                            Text { text: "-1.2500 in"; color: parent.parent.isCurrent ? "black" : "#F8FAFC"; font.bold: true; font.pixelSize: 11 }
                        }
                    }

                    Rectangle { width: 1; Layout.fillHeight: true; color: "#1E293B" }

                    // 4: RETRACT
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property bool isCurrent: root.previewStage === 3 || (appState && appState.executionPhase === "RETRACT")
                        color: isCurrent ? "#D97706" : "transparent"
                        border.color: isCurrent ? "#F59E0B" : "transparent"
                        border.width: isCurrent ? 1 : 0
                        radius: 3
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            Text { text: "RETRACT"; color: parent.parent.isCurrent ? "black" : "#64748B"; font.bold: true; font.pixelSize: 10 }
                            Item { Layout.fillWidth: true }
                            Text { text: "-1.2000 in"; color: parent.parent.isCurrent ? "black" : "#F8FAFC"; font.bold: true; font.pixelSize: 11 }
                        }
                    }
                }
            }

            // =====================================================================
            // SECTION 4: OPERATOR COMMAND DECK (TACTILE POWER STATION - FINAL PRODUCTION)
            // =====================================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 74
                Layout.maximumHeight: 74
                Layout.fillHeight: false
                Layout.leftMargin: 7
                Layout.rightMargin: 7
                Layout.bottomMargin: 7
                Layout.topMargin: 2
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    // Chunky Green Actuator Block (Reduced Width to 165px)
                    Rectangle {
                        Layout.preferredWidth: 165
                        Layout.fillHeight: true
                        radius: 5
                        color: root.runGreen
                        border.color: root.runGreenBorder
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8
                            Rectangle {
                                width: 34; height: 34; radius: 17; color: "#14532D"
                                border.color: "#22C55E"
                                border.width: 1
                                Text { anchors.centerIn: parent; text: "\▶"; color: "white"; font.bold: true; font.pixelSize: 15 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "RUN PROGRAM"; color: "white"; font.bold: true; font.pixelSize: 11; font.letterSpacing: 0.5 }
                                Text { text: "PEDAL ARMED"; color: "#DCFCE7"; font.bold: true; font.pixelSize: 9 }
                            }
                        }
                        MouseArea {
                            id: runActuatorMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (appState) appState.runAction("run") }
                        }
                    }

                    // Middle Power Bay: Auto Clamp + Dwell Stepper (Single Value [-] [VALUE / OFF] [+])
                    Rectangle {
                        Layout.preferredWidth: 245
                        Layout.fillHeight: true
                        radius: 5
                        color: "#080B10"
                        border.color: "#334155"
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4

                            // Auto Clamp Tactile Strip (No "PINCH")
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: 4
                                color: "#111827"
                                border.color: "#374151"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    Text {
                                        text: "AUTO CLAMP TO BEND"
                                        color: "white"
                                        font.bold: true
                                        font.pixelSize: 10
                                        font.letterSpacing: 0.5
                                    }

                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        width: 48
                                        height: 20
                                        radius: 3
                                        readonly property bool isOn: appState ? appState.autoClampEnabled : root.localAutoClamp
                                        color: isOn ? "#16A34A" : "#374151"
                                        border.color: isOn ? "#22C55E" : "#4B5563"
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.isOn ? "ON" : "OFF"
                                            color: "white"
                                            font.bold: true
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleAutoClamp()
                                }
                            }

                            // Dwell Single Value Stepper [-] [VALUE / OFF] [+] (Integer Seconds)
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 4

                                // [-] Button
                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.fillHeight: true
                                    radius: 4
                                    color: minusArea.containsMouse ? "#374151" : "#1E293B"
                                    border.color: "#475569"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\−"
                                        color: "white"
                                        font.bold: true
                                        font.pixelSize: 18
                                    }
                                    MouseArea {
                                        id: minusArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.stepDwell(-1)
                                    }
                                }

                                // Single Value Readout Tile (Integer Seconds or "OFF")
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 4
                                    color: "#030712"
                                    border.color: root.effectiveDwell > 0 ? "#F59E0B" : "#374151"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 0

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: root.effectiveDwell > 0 ? (Math.round(root.effectiveDwell) + " s") : "OFF"
                                            color: root.effectiveDwell > 0 ? "#FBBF24" : "#64748B"
                                            font.bold: true
                                            font.pixelSize: 15
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: root.effectiveDwell > 0 ? "DWELL HOLD" : "DWELL OFF"
                                            color: root.effectiveDwell > 0 ? "#D97706" : "#475569"
                                            font.bold: true
                                            font.pixelSize: 8
                                        }
                                    }
                                }

                                // [+] Button
                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.fillHeight: true
                                    radius: 4
                                    color: plusArea.containsMouse ? "#374151" : "#1E293B"
                                    border.color: "#475569"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "+"
                                        color: "white"
                                        font.bold: true
                                        font.pixelSize: 18
                                    }
                                    MouseArea {
                                        id: plusArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.stepDwell(+1)
                                    }
                                }
                            }
                        }
                    }

                    // 2x2 Chunky Mode Matrix (Expanded Width & Larger Font)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 5
                        color: "#080B10"
                        border.color: "#334155"
                        border.width: 1

                        GridLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            columns: 2
                            rowSpacing: 4
                            columnSpacing: 4

                            Repeater {
                                model: [
                                    { id: "PROGRAM_BEND_MODE", label: "PROGRAM BEND" },
                                    { id: "SINGLE_BEND_MODE", label: "SINGLE BEND" },
                                    { id: "PROGRAM_LOOP_MODE", label: "PROGRAM LOOP" },
                                    { id: "SINGLE_REPEAT_MODE", label: "SINGLE REPEAT" }
                                ]
                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 4
                                    readonly property bool isCurrent: appState ? appState.bendMode === modelData.id : (modelData.id === "SINGLE_BEND_MODE")
                                    color: isCurrent ? "#78350F" : (modeMouse.containsMouse ? "#1F2937" : "#111827")
                                    border.color: isCurrent ? "#F59E0B" : "#374151"
                                    border.width: isCurrent ? 1.5 : 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            color: parent.parent.isCurrent ? "#F59E0B" : "#475569"
                                        }
                                        Text {
                                            text: parent.parent.modelData.label
                                            color: parent.parent.isCurrent ? "white" : "#E2E8F0"
                                            font.bold: true
                                            font.pixelSize: 12
                                            font.letterSpacing: 0.5
                                        }
                                    }

                                    MouseArea {
                                        id: modeMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (appState && typeof appState.setBendMode === "function")
                                                appState.setBendMode(parent.modelData.id)
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

    // =========================================================================
    // INLINE REUSABLE COMPONENTS
    // =========================================================================
    component ComboField: Rectangle {
        id: comboFieldRoot
        signal activated(int index)
        property alias model: comboPopup.model
        property string currentText: ""

        color: root.paper
        border.color: root.ink
        border.width: 1
        radius: 4

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: comboFieldRoot.currentText
                color: root.ink
                font.bold: true
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            Text {
                text: "\▼"
                color: "#666"
                font.pixelSize: 10
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: comboPopup.open()
        }

        Popup {
            id: comboPopup
            y: comboFieldRoot.height + 2
            width: comboFieldRoot.width
            property var model: []
            padding: 2

            background: Rectangle {
                color: root.paper
                border.color: root.ink
                border.width: 1
                radius: 4
            }

            contentItem: ListView {
                implicitHeight: Math.min(200, count * 32)
                model: comboPopup.model
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: comboPopup.width - 4
                    height: 32
                    color: itemMouse.containsMouse ? "#E2E8F0" : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData
                        color: root.ink
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            comboFieldRoot.activated(parent.index)
                            comboPopup.close()
                        }
                    }
                }
            }
        }
    }

    component ProgramNameField: Rectangle {
        property alias text: nameText.text
        color: root.paper
        border.color: root.ink
        border.width: 1
        radius: 4

        Text {
            id: nameText
            anchors.centerIn: parent
            color: root.ink
            font.bold: true
            font.pixelSize: 12
        }
    }

    component IconButton: Rectangle {
        signal clicked()
        property string glyph: ""
        property string iconSource: ""
        property color base: root.charcoal
        property color glyphColor: "white"

        radius: 4
        color: base

        Image {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: parent.iconSource
            fillMode: Image.PreserveAspectFit
            visible: parent.iconSource.length > 0
        }

        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: parent.glyphColor
            font.bold: true
            font.pixelSize: 14
            visible: parent.iconSource.length === 0
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component TextButton: Rectangle {
        signal clicked()
        property string glyph: ""
        property string iconSource: ""
        property string label: ""
        property color base: root.charcoal

        radius: 4
        color: base

        RowLayout {
            anchors.centerIn: parent
            spacing: 6

            Image {
                Layout.preferredWidth: 15
                Layout.preferredHeight: 15
                source: iconSource
                fillMode: Image.PreserveAspectFit
                visible: iconSource.length > 0
            }

            Text {
                text: glyph
                color: "white"
                font.bold: true
                font.pixelSize: 13
                visible: iconSource.length === 0 && glyph.length > 0
            }

            Text {
                text: label
                color: "white"
                font.bold: true
                font.pixelSize: 12
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component SimButton: Rectangle {
        id: simBtnRoot
        signal clicked()
        property string label: ""
        property color base: "#374151"
        property bool enabledState: true

        Layout.preferredHeight: 28
        height: 28
        radius: 4
        color: enabledState ? (mouseArea.containsMouse ? Qt.lighter(base, 1.15) : base) : "#21262D"
        border.color: enabledState ? Qt.lighter(color, 1.25) : "#374151"
        border.width: 1
        opacity: enabledState ? 1.0 : 0.45

        Text {
            anchors.centerIn: parent
            text: simBtnRoot.label
            color: "white"
            font.bold: true
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: simBtnRoot.enabledState ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: simBtnRoot.enabledState
            onClicked: simBtnRoot.clicked()
        }
    }
}
