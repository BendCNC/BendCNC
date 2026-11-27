import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "core/Units.js" as Units

Item {
    id: root
    property var appState: null
    property var dataStore: null
    // SIM RUN plays the whole program (advances bend each cycle) when true.
    property bool simFullSequence: Qt.application.arguments.indexOf("--run-sim-full-sequence") !== -1
    function advanceSimulatedBend() {
        if (!appState || !simFullSequence || !appState.runSimulatedRun || appState.runActive)
            return
        var count = appState.programBends ? appState.programBends.length : 0
        if (count > 1)
            appState.selectRunBend((appState.selectedRunBend + 1) % count)
    }
    // The design lab previews RUN controls without drawing placement/live geometry.
    property bool designerBlankCanvas: false
    property bool sceneInfoActive: false
    readonly property var programNameField: programNameEditor
    function beginProgramNameEdit() {
        if (!appState)
            return
        appState.runAction("edit")
        Qt.callLater(programNameEditor.openKeyboard)
    }
    // Normal operation must never arm sweep capture or file logging. A path is
    // supplied only when the launch command explicitly requests one.
    property string runDebugLogPath: argumentValue("--run-debug-log=", "")
    readonly property bool runPreviewFrameReady: modernRunCanvas.previewFrameReady
    readonly property string renderedPreviewProgramName: modernRunCanvas.renderedPreviewProgramName
    readonly property string renderedCadPartName: modernRunCanvas.renderedCadPartName
    readonly property int renderedPreviewBendIndex: modernRunCanvas.renderedPreviewBendIndex
    readonly property string renderedPreviewSceneMode: modernRunCanvas.renderedPreviewSceneMode
    readonly property bool legacyRunVisible: appState ? appState.legacyRunUiEnabled : false
    readonly property bool activeRunPresentationVisible: activeRunHeader.visible
    readonly property bool autoClampControlVisible: autoClampControl.visible
    readonly property bool autoClampControlEnabled: autoClampControl.enabledState
    readonly property string autoClampControlLabel: autoClampControl.labelText
    readonly property color red: "#a82011"
    readonly property color green: "#59a60c"
    readonly property color blue: "#2d83b2"
    readonly property color charcoal: "#2b2c2b"
    readonly property color grey: "#a8a8a8"
    readonly property color lightGrey: "#e0e0e0"
    readonly property color paper: "#f5f5f5"
    readonly property color ink: "#232323"
    readonly property string iconRoot: "icons/"
    readonly property bool runNativePunchProfileRequested:
        Qt.application.arguments.indexOf("--run-native-retained-punch-profile") !== -1

    function argumentValue(prefix, fallback) {
        for (var i = 0; i < Qt.application.arguments.length; i++) {
            if (Qt.application.arguments[i].indexOf(prefix) === 0)
                return Qt.application.arguments[i].substring(prefix.length)
        }
        return fallback
    }

    onAppStateChanged: {
        if (runNativePunchProfileRequested && appState)
            appState.runSimulationAction("sim-run")
    }

    // Offline simulation may advance on a timer. Production phases advance only from
    // native controller completion signals; this timer is used solely for real dwell ticks.
    Timer {
        id: runExecutionTimer
        interval: 100
        repeat: true
        running: appState ? appState.runActive
            && (appState.offlineSimulationEnabled
                || appState.executionPhase === "DWELL_TIMER_WAIT"
                || appState.physicalRunWaitAction !== "") : false
        onTriggered: if (appState && appState.runActive) {
            if (appState.offlineSimulationEnabled)
                appState.advanceExecutionPhase()
            else if (appState.executionPhase === "DWELL_TIMER_WAIT")
                appState.tickPhysicalRunDwell()
            else if (appState.physicalRunWaitAction !== "")
                appState.processPhysicalRunOperatorGate()
        }
    }

    Timer {
        id: sceneInfoGuideTimer
        interval: 5000
        repeat: false
        onTriggered: root.setSceneInfoActive(false)
    }

    function setSceneInfoActive(active) {
        sceneInfoActive = active
        if (appState)
            appState.runShowMachineGuides = active
        if (appState && appState.runSceneMode === "PLACEMENT") {
            if (active)
                modernRunCanvas.focusAllPlacementPunchBadges()
            else
                modernRunCanvas.clearPlacementPunchBadgeFocus()
        }
        if (active) {
            sceneInfoPopup.open()
            sceneInfoGuideTimer.restart()
        } else {
            sceneInfoGuideTimer.stop()
            sceneInfoPopup.close()
        }
    }

    function toggleSceneInfo() {
        setSceneInfoActive(!sceneInfoActive)
    }

    // v9 DRO ribbon: highlights the stage the native run sequence is in.
    // Phase names come from AppState.runPhaseSequence(); idle shows none.
    readonly property int activeRunStage: {
        if (!appState || !appState.runActive)
            return -1
        switch (appState.executionPhase) {
        case "STARTING":
        case "BACK_GAUGE_MOVE":
        case "SAFETY_CLEARANCE_POSITION_MOVE":
            return 0
        case "CLAMP_MATERIAL_MOVE":
        case "BACK_GAUGE_BUMP_MOVE":
        case "DWELL_TIMER_WAIT":
            return 1
        case "BEND_MOVE":
            return 2
        case "BACK_GAUGE_AND_RAM_RETRACT_MOVE":
            return 3
        default:
            return -1
        }
    }

    // Catalog text decoded as Latin-1 shows "°"; drop the stray lead byte.
    function cleanHeaderText(raw) {
        return String(raw).replace(/\u00C2(?=[\u0080-\u00BF])/g, "")
    }

    // Bend-list tool cells: program bend name split into title + [catalog].
    function runToolText(name) {
        var text = cleanHeaderText(name === undefined || name === null ? "" : name).trim()
        return text.length > 0 ? text : "UNDEFINED"
    }

    function runToolCatalog(text) {
        var match = /\[([^\]]+)\]/.exec(text)
        return match ? match[1] : ""
    }

    function runToolTitle(text, kindPattern) {
        var cleaned = String(text).replace(/\[[^\]]+\]/g, "").replace(kindPattern, "").replace(/\s+/g, " ").trim()
        return (cleaned.length > 0 ? cleaned : String(text)).toUpperCase()
    }

    // Whole-second dwell stepper; AppState clamps the setting to 0..10 s.
    function stepAutoClampDwell(delta) {
        if (!appState)
            return
        var current = Number(appState.autoClampDwellSec)
        var next = delta > 0 ? Math.floor(current) + 1 : Math.ceil(current) - 1
        appState.setApplicationNumericSetting("autoClampToBendDwellSec", Math.max(0, Math.min(10, next)))
    }

    // Designer v9 cockpit background: darkPanel body under a charcoal action strip.
    // The legacy RUN UI keeps the light tab surface it was designed for.
    Rectangle {
        objectName: "run-dark-panel"
        anchors.fill: parent
        visible: !root.legacyRunVisible
        radius: 7
        color: "#181D24"
        Rectangle {
            objectName: "run-top-action-strip"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 56
            color: charcoal
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        GridLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 49
            Layout.leftMargin: 7
            Layout.rightMargin: 7
            Layout.topMargin: 7
            columns: 7
            columnSpacing: 7

            ComboField { objectName: "run-program-combo"; Layout.fillWidth: true; Layout.columnSpan: 2; visible: appState ? !appState.runProgramEditing : true; text: appState ? appState.activeProgram : "Enclosure Box - Electronics Module"; programs: appState ? appState.programs : []; selectedIndex: appState ? appState.selectedProgramIndex : 0; onProgramSelected: function(index) { if (appState) appState.requestProgramSelection(index) } }
            ProgramNameField { id: programNameEditor; objectName: "run-program-name-field"; Layout.fillWidth: true; Layout.columnSpan: 2; visible: appState ? appState.runProgramEditing : false; text: appState ? appState.runProgramNameDraft : "UNTITLED PROGRAM"; onTextEdited: function(value) { if (appState) appState.runProgramNameDraft = value } }
            IconButton { Layout.preferredWidth: 35; iconSource: root.iconRoot + "fa-pen.svg"; base: "white"; glyphColor: ink; borderColor: ink; visible: appState ? !appState.runProgramEditing : true; onClicked: root.beginProgramNameEdit() }
            IconButton { Layout.preferredWidth: 35; iconSource: root.iconRoot + "fa-trash.svg"; base: red; glyphColor: "white"; visible: appState ? !appState.runProgramEditing : true; onClicked: if (appState) appState.runAction("delete") }
            IconButton { Layout.preferredWidth: 35; iconSource: root.iconRoot + "fa-times.svg"; base: red; glyphColor: "white"; visible: appState ? appState.runProgramEditing : false; onClicked: if (appState) appState.runAction("cancel") }
            TextButton { Layout.preferredWidth: 94; iconSource: root.iconRoot + "fa-file-white.svg"; label: "NEW"; base: blue; onClicked: if (appState) appState.runAction("new") }
            TextButton { Layout.preferredWidth: 82; iconSource: root.iconRoot + "fa-save.svg"; label: "SAVE"; base: green; onClicked: if (appState) appState.runAction("save") }
            TextButton { Layout.preferredWidth: 116; iconSource: root.iconRoot + "fa-file-white.svg"; label: "DUPLICATE"; base: "orange"; onClicked: if (appState) appState.runAction("duplicate") }
        }

        Rectangle {
            id: runCanvasArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"
            clip: true

            ColumnLayout {
                visible: appState ? !appState.legacyRunUiEnabled : true
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 7
                anchors.leftMargin: 7
                anchors.rightMargin: 7
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                spacing: 0

                // Compact active-run strip: phase chip | program + bend progress | operator prompt.
                // Dwell countdown is folded into the same strip (no extra block) so the canvas
                // keeps its height.
                Rectangle {
                    id: activeRunHeader
                    objectName: "active-run-header"
                    readonly property bool dwelling: appState ? appState.executionPhase === "DWELL_TIMER_WAIT" : false
                    readonly property string prompt: appState ? appState.runOperatorPrompt() : qsTr("STARTING")
                    // amber = operator action/dwell, cyan = machine moving, violet = tool change.
                    readonly property color accent: !appState ? "#22d3ee"
                        : appState.runToolChangeActive ? "#a78bfa"
                        : (dwelling || /HOLD|PRESS|RELEASE|TAP/.test(prompt)) ? "#fbbf24"
                        : "#22d3ee"
                    readonly property int step: appState ? appState.runSequenceStep(appState.executionPhase) : 0
                    readonly property string chipText: !appState ? qsTr("RUN")
                        : appState.runToolChangeActive ? qsTr("TOOL")
                        : step > 0 ? qsTr("STEP %1/6  %2").arg(step).arg(appState.runSequenceStepNames[step - 1])
                        : qsTr("START")
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 46 : 0
                    Layout.bottomMargin: visible ? 3 : 0
                    visible: appState ? appState.runActive : false
                    color: "#16191d"
                    border.color: accent
                    border.width: 1
                    radius: 5
                    clip: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 10
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: chipLabel.implicitWidth + 18
                            Layout.preferredHeight: 32
                            radius: 4
                            color: activeRunHeader.accent
                            Text {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: activeRunHeader.dwelling && appState
                                    ? qsTr("STEP 5/6  DWELL %1 s").arg(Number(appState.dwellRemainingSec).toFixed(1))
                                    : activeRunHeader.chipText
                                color: "#111418"
                                font.bold: true
                                font.pixelSize: 16
                            }
                        }

                        ColumnLayout {
                            Layout.preferredWidth: Math.min(260, activeRunHeader.width * 0.32)
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: appState ? appState.activeProgram : ""
                                color: "white"
                                font.bold: true
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    text: appState ? qsTr("B%1/%2").arg(appState.selectedRunBend + 1).arg(appState.programBends.length) : ""
                                    color: "#9ca3af"
                                    font.bold: true
                                    font.pixelSize: 11
                                }
                                Row {
                                    spacing: 2
                                    Repeater {
                                        model: appState ? Math.min(appState.programBends.length, 24) : 0
                                        delegate: Rectangle {
                                            width: 8; height: 4; radius: 1
                                            color: index < appState.selectedRunBend ? "#59a60c"
                                                : index === appState.selectedRunBend ? activeRunHeader.accent : "#374151"
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            objectName: "run-operator-prompt"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: activeRunHeader.dwelling && appState && !appState.dwellPausedForPedal
                                ? qsTr("KEEP FOOT PEDAL DOWN")
                                : (appState && activeRunHeader.prompt === appState.executionPhaseDisplayName(appState.executionPhase)
                                    ? "" : activeRunHeader.prompt)
                            color: activeRunHeader.accent
                            font.bold: true
                            font.pixelSize: 17
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 11
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }

                    // Dwell countdown bar along the bottom edge.
                    Rectangle {
                        id: dwellNotice
                        objectName: "physical-run-dwell-notice"
                        visible: activeRunHeader.dwelling
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        height: 3
                        readonly property real total: appState ? Math.max(0.1, appState.autoClampDwellSec) : 1
                        width: appState ? parent.width * Math.max(0, Math.min(1, appState.dwellRemainingSec / total)) : 0
                        color: appState && appState.dwellPausedForPedal ? red : "#fbbf24"
                    }
                }

                // Session-only measured thickness override (programs.json unchanged).
                Rectangle {
                    objectName: "run-measured-thickness-override-banner"
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 30 : 0
                    Layout.bottomMargin: visible ? 4 : 0
                    visible: appState ? appState.measuredThicknessOverrideActive : false
                    color: appState && appState.measuredThicknessOverrideUnresolvedCount > 0 ? red : "#C25E00"
                    radius: 5
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 3
                        spacing: 8
                        Text {
                            objectName: "run-measured-thickness-override-text"
                            Layout.fillWidth: true
                            text: !appState ? "" : appState.measuredThicknessOverrideText()
                                + (appState.measuredThicknessOverrideUnresolvedCount > 0
                                   ? qsTr(" · %1 BEND(S) UNRESOLVED").arg(appState.measuredThicknessOverrideUnresolvedCount) : "")
                            color: "white"
                            font.bold: true
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        SimButton { Layout.preferredWidth: 64; height: 24; label: qsTr("OFF"); base: charcoal; enabledState: appState ? !appState.runActive && !appState.runSimulatedRun : false; onClicked: if (appState) appState.setMeasuredThicknessOverride(false) }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 6
                    color: charcoal
                    border.color: ink
                    border.width: 1

                    // Square bottom-right corner for seamless continuity with canvas below
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: parent.radius
                        height: parent.radius
                        color: charcoal

                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 1
                            color: ink
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: ink
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6
                        SimButton { objectName: "run-toggle-list-button"; Layout.preferredWidth: 72; label: appState && appState.runBendListVisible ? "▲ LIST" : "▼ LIST"; base: blue; onClicked: if (appState) appState.runSimulationAction("toggle-list") }
                        SimButton { Layout.preferredWidth: 30; label: "◀"; enabledState: appState ? appState.selectedRunBend > 0 : false; onClicked: if (appState) appState.runSimulationAction("previous") }
                        SimButton { Layout.preferredWidth: 30; label: "▶"; enabledState: appState ? appState.selectedRunBend < appState.programBends.length - 1 : false; onClicked: if (appState) appState.runSimulationAction("next") }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { objectName: "run-sim-header-primary"; Layout.fillWidth: true; text: appState ? root.cleanHeaderText(appState.runSimulationHeader1()) : "NO BENDS"; color: "#F1F5F9"; font.bold: true; font.pixelSize: 11; elide: Text.ElideLeft }
                            Text { objectName: "run-sim-header-secondary"; Layout.fillWidth: true; text: appState ? root.cleanHeaderText(appState.runSimulationHeader2()) : "Select or create a bend program"; color: "#FBBF24"; font.bold: true; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                        SimButton { objectName: "run-angle-correction-button"; Layout.preferredWidth: 28; label: "∠°"; base: "#7C3AED"; enabledState: appState ? appState.selectedRunBend >= 0 && !appState.runSimulatedRun && !appState.physicalRunCommandPending : false; onClicked: angleCorrectionModal.open() }
                        SimButton { objectName: "run-measured-thickness-toggle"; Layout.preferredWidth: 58; visible: appState ? appState.measuredMaterialThicknessValid : false; label: "t MEAS"; base: appState && appState.measuredThicknessOverrideActive ? "#C25E00" : "#374151"; enabledState: appState ? !appState.runActive && !appState.runSimulatedRun : false; onClicked: if (appState) appState.setMeasuredThicknessOverride(!appState.measuredThicknessOverrideEnabled) }
                        SimButton { Layout.preferredWidth: 92; visible: false; label: "PLACEMENT"; base: appState && appState.runSceneMode === "PLACEMENT" ? blue : "#374151"; onClicked: if (appState) appState.runSimulationAction("placement") }
                        SimButton { Layout.preferredWidth: 64; label: "LIVE"; base: appState && appState.runSceneMode === "LIVE" ? blue : "#374151"; onClicked: if (appState) appState.runSimulationAction("live") }
                        SimButton { Layout.preferredWidth: 84; label: appState && appState.runSimulatedRun ? "STOP DEMO" : "SIM RUN"; base: appState && appState.runSimulatedRun ? "#16A34A" : "#374151"; onClicked: if (appState) appState.runSimulationAction("sim-run") }
                        SimButton { objectName: "run-sim-full-sequence-toggle"; Layout.preferredWidth: 84; label: root.simFullSequence ? qsTr("SEQ: ALL") : qsTr("SEQ: CURRENT"); base: root.simFullSequence ? "#0F766E" : "#374151"; onClicked: root.simFullSequence = !root.simFullSequence }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 0
                    color: lightGrey
                    border.color: ink
                    border.width: 1
                    RunExecutionCanvas { id: modernRunCanvas; anchors.fill: parent; backgaugeFingerStyle: appState ? appState.backgaugeFingerStyle : "ORIGINAL"; onToolingAppearanceToggleRequested: if (appState) appState.setRunToolingAppearance(appState.runToolingAppearance === "TRANSLUCENT" ? "SOLID" : "TRANSLUCENT"); metricUnits: appState ? appState.metricUnits === true : false; simulatedFullSequence: root.simFullSequence; onSimulatedCycleCompleted: root.advanceSimulatedBend(); visible: !root.designerBlankCanvas; sceneMode: appState ? appState.runSceneMode : "PLACEMENT"; liveProjectionMode: "SIDE"; live3DActive: live3DLoader.status === Loader.Ready; liveCameraOrientation: appState ? appState.runLiveCameraOrientation : "ISO_TOP_LEFT"; liveStatusCardVisible: live3DLoader.status !== Loader.Ready; toolingAppearance: appState ? appState.runToolingAppearance : "SOLID"; guides: appState ? appState.runShowMachineGuides : false; liveMaxFps: appState ? appState.liveAnimationMaxFps : 0; running: appState ? appState.runSimulatedRun || appState.runActive : false; simulatedPlayback: appState ? appState.runSimulatedRun : false; simJogRamSpeedIpm: appState ? appState.jogRamSpeed : 5; simBendRamSpeedIpm: appState ? appState.bendRamSpeed : 5; physicalTelemetryFresh: appState && appState.machineControl ? appState.machineControl.pressTelemetryFresh : false; physicalExecutionPhase: appState ? appState.executionPhase : ""; physicalPressState: appState ? appState.machineStatus : "UNKNOWN"; physicalRamPosition: appState ? appState.ramPosition : 0; physicalBackGaugeX: appState ? appState.backGaugeX : 0; physicalBackGaugeR: appState ? appState.backGaugeR : 0; backGaugeEnabled: appState ? appState.runBendUsesBackGauge() : true; backGaugeRetractDistanceIn: appState ? appState.backGaugeRetractBetweenBendsInch : 2.0; backGaugeBumpOffDistanceIn: appState ? appState.backGaugeBumpOffDistanceInch : 0.25; autoClampDwellSeconds: appState && appState.autoClampToBendEnabled ? appState.autoClampDwellSec : 0; physicalStartPosition: appState ? appState.runRamTarget("startPosition") : NaN; physicalClampPosition: appState ? appState.runRamTarget("clampPosition") : NaN; physicalFinalPosition: appState ? appState.runRamTarget("finalPosition") : NaN; label: appState && appState.runActive ? appState.runProgressTitle : (appState ? appState.runSimulationHeader1() : "NO BENDS"); detail: appState && appState.runActive ? appState.runOperatorPrompt() : (appState ? appState.runSimulationHeader2() : ""); programName: appState ? appState.activeProgram : ""; programPreviewJson: appState ? appState.activeProgramCadPreviewJson : ""; selectedBendIndex: appState ? appState.selectedRunBend : 0; selectedBend: appState ? appState.selectedBend : ({}); programBends: appState ? appState.programBends : []; punchCatalog: dataStore ? dataStore.punches : []; dieCatalog: dataStore ? dataStore.dies : []; punchCoverageSideToleranceIn: appState ? appState.punchCoverageSideToleranceIn : 0; runDebugLogPath: root.runDebugLogPath; runDebugLogsEnabled: appState ? appState.runPreviewDebugLogsEnabled : false; runDebugOverlaysEnabled: appState ? appState.runPreviewDebugOverlaysEnabled : false; runCadenceDebug: Qt.application.arguments.indexOf("--run-cadence-debug") !== -1; flatPatternContourRenderer: appState ? appState.runFlatPatternContourRenderer : "classic" }
                    Binding {
                        target: modernRunCanvas
                        property: "physicalRamToTableOpening"
                        value: appState ? appState.authoritativeRamToTableOpening() : NaN
                    }
                    Binding {
                        target: modernRunCanvas
                        property: "physicalMaterialClampRatePercentage"
                        value: appState ? appState.materialClampRatePercentage : 5.0
                    }
                    // LIVE 3D (Qt Quick 3D) replaces the former isometric
                    // canvas projection. The persisted "ISOMETRIC" mode now
                    // selects 3D; if Quick3D is unavailable the Loader errors
                    // and the 2D side view stays active.
                    Loader {
                        id: live3DLoader
                        objectName: "live-3d-view"
                        anchors.fill: parent
                        z: 3
                        // Popups (WiFi list, logs) sit above the scene; without
                        // this the scene's DragHandlers took the touch scroll.
                        enabled: !(root.appState && root.appState.popupVisible)
                        active: !root.designerBlankCanvas && appState
                            && appState.runSceneMode === "LIVE"
                            && appState.runLiveProjectionMode === "ISOMETRIC"
                        source: "LiveScene3D.qml"
                        onLoaded: {
                            item.canvas = modernRunCanvas
                            item.showInfo = Qt.binding(function() { return root.sceneInfoActive })
                        }
                        onStatusChanged: if (status === Loader.Error)
                            console.warn("[live3d] Qt Quick 3D view unavailable; using 2D side view")
                    }
                    Rectangle {
                        id: programSwitchOverlay
                        objectName: "run-program-switch-overlay"
                        anchors.fill: parent
                        z: 90
                        visible: root.appState ? root.appState.runProgramSwitching : false
                        color: "#e6eef3f8"
                        MouseArea { anchors.fill: parent; hoverEnabled: true }
                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("LOADING PROGRAM")
                                color: ink; font.bold: true; font.pixelSize: 18
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 360
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: root.appState ? root.appState.runProgramSwitchName : ""
                                color: ink; font.pixelSize: 14
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 240; height: 6; radius: 3; color: "#c9d3dc"; clip: true
                                Rectangle {
                                    id: programSwitchBar
                                    width: 80; height: parent.height; radius: 3; color: ink
                                    XAnimator on x {
                                        from: -80; to: 240; duration: 900
                                        loops: Animation.Infinite
                                        running: programSwitchOverlay.visible
                                    }
                                }
                            }
                        }
                    }
                    Timer {
                        // Completes the switch overlay once the new program's
                        // run frame is built (the main-thread work itself blocks
                        // signals, so poll shortly after it).
                        interval: 120
                        repeat: true
                        running: root.appState ? root.appState.runProgramSwitching : false
                        onTriggered: {
                            if (root.appState && root.appState.runProgramSwitchPendingIndex < 0
                                    && Date.now() - root.appState.runProgramSwitchStartedMs > 200
                                    && root.runPreviewFrameReady)
                                root.appState.finishRunProgramSwitch("ready")
                        }
                    }
                    Rectangle { anchors.fill: parent; anchors.leftMargin: 7; anchors.rightMargin: 7; anchors.topMargin: 2; anchors.bottomMargin: 1; color: "transparent"; border.color: "transparent" }
                    Text { anchors.centerIn: parent; visible: appState ? appState.programBends.length === 0 : true; text: "NO BEND MOVES AVAILABLE"; color: ink; font.bold: true; font.pixelSize: 18 }
                    Rectangle {
                        anchors.fill: parent
                        z: 100
                        color: lightGrey
                        visible: root.designerBlankCanvas
                        MouseArea { anchors.fill: parent }
                    }
                    Rectangle {
                        id: runBendListDropdownOverlay
                        objectName: "run-bend-list-table"
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
                        height: 30 + rowsScrollContainer.height + 44

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
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                    Text {
                                        Layout.preferredWidth: 64
                                        text: "ANGLE"
                                        color: "#94A3B8"
                                        font.bold: true
                                        font.pixelSize: 11
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
                                                font.pixelSize: 11
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
                                            Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: "#E2E8F0" }
                                            Text {
                                                text: "DIE & V-OPENING"
                                                color: "#94A3B8"
                                                font.bold: true
                                                font.pixelSize: 11
                                            }
                                        }
                                    }
                                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                    Text {
                                        Layout.preferredWidth: 120
                                        text: "BACK GAUGE (X / R)"
                                        color: "#94A3B8"
                                        font.bold: true
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                    Text {
                                        Layout.preferredWidth: 52
                                        text: "DIR"
                                        color: "#94A3B8"
                                        font.bold: true
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#334155" }

                                    Text {
                                        Layout.preferredWidth: 68
                                        text: "STATUS"
                                        color: "#94A3B8"
                                        font.bold: true
                                        font.pixelSize: 11
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
                                                height: 44 + rowDelegate.toolChangeHeight

                                                required property int index
                                                required property var modelData

                                                objectName: "run-bend-row-" + String(rowDelegate.index)
                                                readonly property var currentBend: modelData || ({})
                                                // Visual TOOL CHANGE step before this bend; bend numbers are unchanged.
                                                readonly property var toolChange: appState ? appState.toolChangeBeforeBend(appState.programBends, rowDelegate.index) : null
                                                readonly property real toolChangeHeight: toolChange ? 44 : 0
                                                readonly property bool toolChangeActive: !!(toolChange && appState && appState.runToolChangeActive && appState.selectedRunBend === rowDelegate.index)
                                                readonly property bool toolChangeSelected: !!(toolChange && appState && appState.runStartAtToolChange && appState.selectedRunBend === rowDelegate.index)

                                                // TOOL CHANGE step row: same height/columns as a bend row.
                                                // Clicking it selects the next bend and starts RUN at this tooling sequence.
                                                Rectangle {
                                                    id: toolChangeRow
                                                    objectName: "run-tool-change-row-" + String(rowDelegate.index)
                                                    visible: !!rowDelegate.toolChange
                                                    z: 2
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    height: rowDelegate.toolChangeHeight
                                                    readonly property bool hot: rowDelegate.toolChangeActive || rowDelegate.toolChangeSelected
                                                    color: rowDelegate.toolChangeActive ? "#3B2508" : (rowDelegate.toolChangeSelected ? "#2A2215" : (tcMouse.containsMouse ? "#231C14" : "#17130E"))
                                                    Rectangle { width: 4; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; color: "#F59E0B"; visible: toolChangeRow.hot }
                                                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: "#1E293B" }
                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 0
                                                        Item {
                                                            Layout.preferredWidth: 58
                                                            Layout.fillHeight: true
                                                            Rectangle {
                                                                anchors.centerIn: parent
                                                                width: 50; height: 24; radius: 12
                                                                color: toolChangeRow.hot ? "#2A2215" : "#1C1917"
                                                                border.color: toolChangeRow.hot ? "#F59E0B" : "#78350F"
                                                                border.width: 1
                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: (toolChangeRow.hot ? "\u25B6 " : "") + "TC"
                                                                    color: "#F59E0B"; font.bold: true; font.pixelSize: 11
                                                                }
                                                            }
                                                        }
                                                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#1E293B" }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            Layout.leftMargin: 10
                                                            Layout.alignment: Qt.AlignVCenter
                                                            spacing: 1
                                                            Text {
                                                                text: "\u21C4 " + (rowDelegate.toolChange && rowDelegate.toolChange.title ? rowDelegate.toolChange.title : "TOOL CHANGE")
                                                                      + "  \u00B7  BEFORE B" + String(rowDelegate.index + 1)
                                                                color: "#F59E0B"; font.bold: true; font.pixelSize: 12
                                                            }
                                                            Text {
                                                                Layout.fillWidth: true
                                                                elide: Text.ElideRight
                                                                color: "#D6D3D1"; font.pixelSize: 11
                                                                text: !rowDelegate.toolChange ? "" : rowDelegate.toolChange.summary
                                                            }
                                                        }
                                                        Rectangle {
                                                            Layout.preferredWidth: 72; Layout.preferredHeight: 24
                                                            Layout.rightMargin: 2
                                                            radius: 4
                                                            color: rowDelegate.toolChangeActive ? "#78350F" : (rowDelegate.toolChangeSelected ? "#2A2215" : "#1E293B")
                                                            border.color: toolChangeRow.hot ? "#F59E0B" : "#334155"
                                                            border.width: 1
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: rowDelegate.toolChangeActive ? "ACTIVE" : (rowDelegate.toolChangeSelected ? "SELECTED" : "TOOLING")
                                                                color: toolChangeRow.hot ? "#FDE68A" : "#94A3B8"
                                                                font.bold: true; font.pixelSize: 11
                                                            }
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: tcMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (appState && appState.selectRunToolChange(rowDelegate.index))
                                                                appState.runBendListVisible = false
                                                        }
                                                    }
                                                }
                                                // Same identity the header uses: AppState.selectedRunBend.
                                                readonly property bool executing: appState ? (appState.runActive || appState.runSimulatedRun) : false
                                                readonly property bool isSelected: appState ? appState.selectedRunBend === rowDelegate.index : false
                                                // Same ordering rule as the former list (seq before the selected bend);
                                                // only labelled DONE while a real or simulated run owns the sequence.
                                                readonly property bool isCompleted: executing && appState ? Number(currentBend.seq || rowDelegate.index + 1) < Number((appState.selectedBend || ({})).seq || appState.selectedRunBend + 1) : false
                                                readonly property string angleText: String(currentBend.angle || "90.0").replace(/\u00C2\u00B0|\u00B0/g, "") + "\u00B0"

                                                // Tool names come from the program bend (bendFromStorage/CAD resolve them
                                                // from the punch/die catalog). No invented fallbacks.
                                                readonly property string punchRaw: root.runToolText(currentBend.punch)
                                                readonly property string punchCatalog: root.runToolCatalog(rowDelegate.punchRaw)
                                                readonly property string punchTitle: root.runToolTitle(rowDelegate.punchRaw, /\bPUNCH\b/ig)
                                                readonly property string dieRaw: root.runToolText(currentBend.die)
                                                readonly property string dieCatalog: root.runToolCatalog(rowDelegate.dieRaw)
                                                readonly property string dieVOpening: appState ? appState.runDieOpeningText(currentBend) : ""
                                                readonly property string dieTitle: root.runToolTitle(rowDelegate.dieRaw, /\bDIE\b/ig)

                                                readonly property string xText: appState && appState.metricUnits ? Units.lenText(currentBend.x || "0", true) : (currentBend.x || "0.0000") + "\""
                                                readonly property string rText: appState ? (appState.metricUnits ? Units.len(appState.runBendRPosition(currentBend), true) : appState.runBendRPosition(currentBend).toFixed(4) + "\"") : "\u2014"
                                                readonly property string dirText: appState ? appState.runBendDirection(currentBend) : "UP"
                                                readonly property string statusText: isSelected ? (executing ? "ACTIVE" : "SELECTED") : (isCompleted ? "DONE" : (executing ? "PENDING" : "READY"))

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
                                                    anchors.topMargin: rowDelegate.toolChangeHeight
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
                                                                    font.pixelSize: 11
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
                                                                    font.pixelSize: 11
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
                                                                    color: rowDelegate.isSelected ? "#93C5FD" : "#64748B"
                                                                    font.family: "Monospace"
                                                                    font.pixelSize: 11
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
                                                                    font.pixelSize: 11
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
                                                                            font.pixelSize: 11
                                                                        }
                                                                    }
                                                                }
                                                                Text {
                                                                    width: parent.width
                                                                    visible: rowDelegate.dieCatalog.length > 0
                                                                    text: rowDelegate.dieCatalog
                                                                    color: rowDelegate.isSelected ? "#93C5FD" : "#64748B"
                                                                    font.family: "Monospace"
                                                                    font.pixelSize: 11
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
                                                                    Text { text: "X:"; color: "#94A3B8"; font.bold: true; font.pixelSize: 11 }
                                                                    Text {
                                                                        text: rowDelegate.xText
                                                                        color: rowDelegate.isSelected ? "#FBBF24" : (rowDelegate.isCompleted ? "#64748B" : "#E2E8F0")
                                                                        font.family: "Monospace"
                                                                        font.bold: true
                                                                        font.pixelSize: 11
                                                                    }
                                                                }

                                                                RowLayout {
                                                                    spacing: 4
                                                                    Text { text: "R:"; color: "#94A3B8"; font.bold: true; font.pixelSize: 11 }
                                                                    Text {
                                                                        text: rowDelegate.rText
                                                                        color: rowDelegate.isSelected ? "#FBBF24" : (rowDelegate.isCompleted ? "#64748B" : "#CBD5E1")
                                                                        font.family: "Monospace"
                                                                        font.bold: true
                                                                        font.pixelSize: 11
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
                                                                font.pixelSize: 11
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
                                                                text: rowDelegate.statusText
                                                                color: rowDelegate.isSelected ? "#D1FAE5" : (rowDelegate.isCompleted ? "#A7F3D0" : "#64748B")
                                                                font.bold: true
                                                                font.pixelSize: 11
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
                                                    // selectRunBend keeps the execution guard: it refuses while a
                                                    // run owns the sequence, so the list stays open in that case.
                                                    onClicked: {
                                                        if (appState && appState.selectRunBend(rowDelegate.index))
                                                            appState.runBendListVisible = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 3. TABLE FOOTER (Height: 44px, 36px touch targets)
                            Rectangle {
                                width: parent.width
                                height: 44
                                color: "#0B0F17"
                                border.color: "#334155"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12

                                    // Add Bend Button
                                    Rectangle {
                                        objectName: "run-bend-list-add"
                                        Layout.preferredHeight: 36
                                        Layout.preferredWidth: 120
                                        radius: 4
                                        color: addMouse.containsMouse ? "#B45309" : "#78350F"
                                        border.color: "#F59E0B"
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text { text: "+"; color: "#FDE68A"; font.bold: true; font.pixelSize: 13 }
                                            Text { text: "ADD BEND"; color: "#FDE68A"; font.bold: true; font.pixelSize: 11 }
                                        }

                                        MouseArea {
                                            id: addMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!appState)
                                                    return
                                                appState.runBendListVisible = false
                                                appState.openAddBendPopup(dataStore.bends, dataStore.punches, dataStore.dies, dataStore.materials)
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Total steps indicator
                                    Text {
                                        objectName: "run-bend-list-summary"
                                        text: String(appState ? appState.programBends.length : 0) + " TOTAL BENDS  |  " + (appState ? appState.activeProgram : "")
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 360
                                        color: "#64748B"
                                        font.bold: true
                                        font.pixelSize: 11
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Close Button
                                    Rectangle {
                                        objectName: "run-bend-list-close"
                                        Layout.preferredHeight: 36
                                        Layout.preferredWidth: 96
                                        radius: 4
                                        color: closeMouse.containsMouse ? "#334155" : "#1E293B"
                                        border.color: "#475569"
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text { text: "CLOSE"; color: "#E2E8F0"; font.bold: true; font.pixelSize: 11 }
                                            Text { text: "▲"; color: "#94A3B8"; font.pixelSize: 11 }
                                        }

                                        MouseArea {
                                            id: closeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (appState) appState.runBendListVisible = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    Layout.topMargin: 4
                    RowLayout {
                        anchors.fill: parent
                        spacing: 6
                        SimInfoButton { Layout.preferredWidth: 32; Layout.fillHeight: true; active: root.sceneInfoActive; onClicked: root.toggleSceneInfo() }
                        Rectangle {
                            objectName: "run-stage-ribbon"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 4
                            color: "#0B0F17"
                            border.color: "#1E293B"
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 1
                                spacing: 0
                                StageBay {
                                    objectName: "run-stage-start"
                                    label: "START"
                                    current: root.activeRunStage === 0
                                    value: appState ? appState.runRamTargetText("startPosition", " in") : "UNAVAILABLE"
                                }
                                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#1E293B" }
                                StageBay {
                                    objectName: "run-stage-clamp"
                                    label: "CLAMP"
                                    current: root.activeRunStage === 1
                                    value: appState ? appState.runRamTargetText("clampPosition", " in") : "UNAVAILABLE"
                                }
                                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#1E293B" }
                                StageBay {
                                    objectName: "run-stage-final"
                                    label: "FINAL"
                                    current: root.activeRunStage === 2
                                    value: appState ? appState.runRamTargetText("finalPosition", " in") : "UNAVAILABLE"
                                }
                                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#1E293B" }
                                StageBay {
                                    objectName: "run-stage-retract"
                                    label: "RETRACT"
                                    current: root.activeRunStage === 3
                                    value: appState ? appState.runRamTargetText("retractPosition", " in") : "UNAVAILABLE"
                                }
                            }
                        }
                    }
                    Popup {
                        id: sceneInfoPopup
                        y: -implicitHeight - 6
                        width: 330
                        modal: false
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        background: Rectangle { color: "white"; border.color: ink; radius: 4 }
                        contentItem: Text {
                            width: 310
                            padding: 8
                            text: appState ? appState.runSceneInfoText() : "Placement / Live preview"
                            color: ink
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

                Flickable {
                    visible: root.legacyRunVisible
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 7
                anchors.leftMargin: 7
                anchors.rightMargin: 7
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, legacyBendColumn.implicitHeight)

                ColumnLayout {
                    id: legacyBendColumn
                    width: parent.width - 7
                    height: Math.max(implicitHeight, parent.height)
                    spacing: 10

                    Repeater {
                        model: appState ? appState.programBends : []
                        BendCell {
                            Layout.fillWidth: true
                            readonly property var bend: modelData
                            metric: appState ? appState.metricUnits : false
                            selected: appState ? appState.selectedRunBend === index : index === 0
                            sequence: bend.seq || index + 1
                            bendName: bend.name || "Bend"
                            angle: bend.angle || "90.0"
                            compensation: bend.compensation || "0.0"
                            bendState: bend.state || "DRAFT"
                            xValue: bend.x || "0.0000"
                            rValue: bend.r || "0.0000"
                            speedValue: bend.speed || "100.000"
                            tonnage: bend.tonnage || "0.000"
                            thickness: bend.thickness || "0.0000"
                            materialName: bend.material || "Material"
                            punchName: bend.punch || "Punch"
                            dieName: bend.die || "Die"
                            onCellSelected: if (appState) appState.selectRunBend(index)
                            onDeleteRequested: if (appState) appState.deleteProgramBend(index)
                            onEditRequested: if (appState) appState.showPopup("EDIT BEND", bendName, 1)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 90
                        visible: appState ? appState.programBends.length === 0 : false
                        text: "NO BEND MOVES AVAILABLE"
                        color: ink
                        font.bold: true
                        font.pixelSize: 18
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.rightMargin: 7
                width: 15
                visible: appState ? appState.legacyRunUiEnabled : false
                color: "#c7c7c7"
                Rectangle { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; width: 15; height: 78; color: grey }
            }

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 7
                anchors.rightMargin: 7
                anchors.margins: 7
                visible: root.legacyRunVisible && (appState ? appState.runActive : false)
                color: "transparent"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 7

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 58
                        color: "#1f2328"
                        radius: 7
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            ColumnLayout { Layout.fillWidth: true; spacing: 3; Text { Layout.fillWidth: true; text: appState ? appState.activeProgram : "Program"; color: "white"; font.bold: true; font.pixelSize: 20; elide: Text.ElideRight } Text { Layout.fillWidth: true; text: appState ? "BEND #" + String(appState.selectedRunBend + 1) + " OF " + String(appState.programBends.length) : "BEND #1 OF 1"; color: "white"; font.bold: true; font.pixelSize: 12; elide: Text.ElideRight } }
                            ColumnLayout { Layout.preferredWidth: 190; spacing: 3; Text { Layout.fillWidth: true; text: "LIVE RUN"; color: "white"; font.bold: true; font.pixelSize: 16; horizontalAlignment: Text.AlignRight } Text { Layout.fillWidth: true; text: appState ? appState.currentRunPhaseLabel() : "STARTING"; color: "white"; font.bold: true; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight } }
                        }
                    }

                    Rectangle {
                        objectName: "legacy-physical-run-dwell-notice"
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 126 : 0
                        visible: appState && appState.executionPhase === "DWELL_TIMER_WAIT"
                        color: "#fff5cc"
                        border.color: "#d39200"
                        border.width: 3
                        radius: 6
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: qsTr("NOTICE"); color: "#5a3600"; font.bold: true; font.pixelSize: 15 }
                            Text { Layout.fillWidth: true; text: qsTr("PART HAS BEEN CLAMPED, THE BEND MOVE WILL START IN:"); color: ink; font.bold: true; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter }
                            Text { Layout.fillWidth: true; text: appState ? Number(appState.dwellRemainingSec).toFixed(1) + qsTr(" SECONDS") : qsTr("0.0 SECONDS"); color: red; font.bold: true; font.pixelSize: 25; horizontalAlignment: Text.AlignHCenter }
                            Text { Layout.fillWidth: true; text: appState && appState.dwellPausedForPedal ? qsTr("DWELL PAUSED. DOUBLE-TAP AND HOLD THE FOOT PEDAL TO CONTINUE THIS RUN.") : qsTr("RELEASING THE FOOT PEDAL PAUSES THE COUNTDOWN; IT DOES NOT CANCEL THE RUN."); color: "#5a3600"; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 7

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 2
                            columnSpacing: 7
                            RunExecutionCanvas { Layout.fillWidth: true; Layout.fillHeight: true; sceneMode: "PLACEMENT"; running: false; guides: false; label: "TOP VIEW"; detail: appState && appState.selectedBend.name ? appState.selectedBend.name : "Selected bend"; programPreviewJson: root.legacyRunVisible && appState ? appState.activeProgramCadPreviewJson : ""; selectedBendIndex: root.legacyRunVisible && appState ? appState.selectedRunBend : 0; selectedBend: root.legacyRunVisible && appState ? appState.selectedBend : ({}); punchCatalog: dataStore ? dataStore.punches : []; dieCatalog: dataStore ? dataStore.dies : []; runDebugLogPath: root.runDebugLogPath; runDebugLogsEnabled: appState ? appState.runPreviewDebugLogsEnabled : false; runDebugOverlaysEnabled: appState ? appState.runPreviewDebugOverlaysEnabled : true; flatPatternContourRenderer: appState ? appState.runFlatPatternContourRenderer : "classic" }
                            Item {
                                Layout.preferredWidth: 292
                                Layout.minimumWidth: 292
                                Layout.maximumWidth: 292
                                Layout.fillHeight: true
                                RunExecutionCanvas { anchors.fill: parent; backgaugeFingerStyle: appState ? appState.backgaugeFingerStyle : "ORIGINAL"; sceneMode: root.legacyRunVisible ? "LIVE" : "PLACEMENT"; liveProjectionMode: appState ? appState.runLiveProjectionMode : "SIDE"; liveCameraOrientation: appState ? appState.runLiveCameraOrientation : "ISO_TOP_LEFT"; toolingAppearance: appState ? appState.runToolingAppearance : "SOLID"; running: root.legacyRunVisible && appState ? appState.runActive : false; guides: root.legacyRunVisible; label: "SIDE VIEW"; detail: appState && appState.selectedBend.angle ? appState.selectedBend.angle + "° bend" : "90.0° bend"; programName: root.legacyRunVisible && appState ? appState.activeProgram : ""; programPreviewJson: root.legacyRunVisible && appState ? appState.activeProgramCadPreviewJson : ""; selectedBendIndex: root.legacyRunVisible && appState ? appState.selectedRunBend : 0; selectedBend: root.legacyRunVisible && appState ? appState.selectedBend : ({}); punchCatalog: dataStore ? dataStore.punches : []; dieCatalog: dataStore ? dataStore.dies : []; runDebugLogPath: root.runDebugLogPath; runDebugLogsEnabled: appState ? appState.runPreviewDebugLogsEnabled : false; runDebugOverlaysEnabled: appState ? appState.runPreviewDebugOverlaysEnabled : true; flatPatternContourRenderer: appState ? appState.runFlatPatternContourRenderer : "classic" }
                                LiveIsometricViewCube {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 6
                                    scale: 0.78
                                    transformOrigin: Item.TopRight
                                    z: 4
                                    visible: root.legacyRunVisible && appState
                                        && appState.runLiveProjectionMode === "ISOMETRIC"
                                    orientation: appState ? appState.runLiveCameraOrientation : "ISO_TOP_LEFT"
                                    onOrientationRequested: function(orientation) {
                                        if (appState)
                                            appState.setRunLiveCameraOrientation(orientation)
                                    }
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 82
                            columns: 3
                            columnSpacing: 7
                            ExecutionBendCard { Layout.fillWidth: true; Layout.preferredHeight: 82; bendNo: appState ? String(appState.selectedRunBend + 1) : "1"; bendName: appState ? (appState.selectedBend.name || "Bend") : "Bend"; angle: appState ? (appState.selectedBend.angle || "90.0") : "90.0"; thickness: appState ? (appState.selectedBend.thickness || "0.0000") : "0.0000"; punchName: appState ? (appState.selectedBend.punch || "Punch") : "Punch"; dieName: appState ? (appState.selectedBend.die || "Die") : "Die"; materialName: appState ? (appState.selectedBend.material || "Material") : "Material" }
                            ExecutionBackGaugeCard { Layout.fillWidth: true; Layout.preferredHeight: 82; metric: appState ? appState.metricUnits : false; xValue: appState ? (appState.selectedBend.x || "0.0000") : "0.0000"; rValue: appState ? (appState.selectedBend.r || "0.0000") : "0.0000"; speedValue: appState ? (appState.selectedBend.speed || "100.000") : "100.000" }
                            ExecutionTonnageCard { Layout.fillWidth: true; Layout.preferredHeight: 82; tonnage: appState ? (appState.selectedBend.tonnage || "0.000") : "0.000" }
                        }
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 35
            Layout.leftMargin: 49
            Layout.rightMargin: 7
            visible: appState ? appState.legacyRunUiEnabled : false
            columns: 4
            columnSpacing: 7
            FooterPanel { Layout.fillWidth: true; title: "START POSITION:"; value: appState ? appState.runRamTargetText("startPosition", " In") : "UNAVAILABLE" }
            FooterPanel { Layout.fillWidth: true; title: "CLAMP POSITION:"; value: appState ? appState.runRamTargetText("clampPosition", " In") : "UNAVAILABLE" }
            FooterPanel { Layout.fillWidth: true; title: "FINAL BEND POSITION:"; value: appState ? appState.runRamTargetText("finalPosition", " In") : "UNAVAILABLE" }
            IconButton { Layout.preferredWidth: 129; glyph: "+"; base: "orange"; glyphColor: ink; onClicked: if (appState) appState.openAddBendPopup(dataStore.bends, dataStore.punches, dataStore.dies, dataStore.materials) }
        }

        // v9 Tactile Power Deck: RUN actuator, AUTO CLAMP + dwell bay, 2x2 cycle matrix.
        RowLayout {
            id: bottomRowLayout
            objectName: "run-operator-deck"
            Layout.fillWidth: true
            // Nested layouts default to fillHeight; pin the deck so the canvas keeps the space.
            Layout.fillHeight: false
            Layout.preferredHeight: 74
            Layout.maximumHeight: 74
            Layout.leftMargin: 7
            Layout.rightMargin: 7
            Layout.bottomMargin: 7
            Layout.topMargin: 2
            spacing: 8
            ActionRun {
                objectName: "run-program-actuator"
                Layout.preferredWidth: 165
                Layout.fillHeight: true
                active: appState ? appState.runActive : false
                allowed: appState ? appState.runProgramAllowed : false
                grayed: appState ? appState.runProgramGrayed : false
                onClicked: if (appState) appState.runAction("run")
            }
            Rectangle {
                objectName: "run-auto-clamp-bay"
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
                    AutoClamp {
                        id: autoClampControl
                        objectName: "auto-clamp-to-bend-control"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        active: appState ? appState.autoClampEnabled : false
                        enabledState: appState ? appState.machineStatus !== "JOGGING"
                            && !(appState.machineControl && appState.machineControl.pressOperationActive) : false
                        onClicked: if (appState) appState.runAction("auto-clamp")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 4
                        DwellStepButton {
                            objectName: "dwell-decrement-button"
                            Layout.preferredWidth: 38
                            Layout.fillHeight: true
                            glyph: "\u2212"
                            enabledState: dwellTile.enabledState && dwellTile.dwellActive && dwellTile.dwell > 0
                            onClicked: root.stepAutoClampDwell(-1)
                        }
                        DwellTile {
                            id: dwellTile
                            objectName: "dwell-toggle-tile"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            dwellActive: appState ? appState.autoClampDwellEnabled : true
                            dwell: appState ? appState.autoClampDwellSec : 3.0
                            enabledState: appState ? appState.machineStatus !== "JOGGING"
                                && !(appState.machineControl && appState.machineControl.pressOperationActive)
                                && appState.autoClampEnabled : false
                            onClicked: if (appState) appState.runAction("auto-dwell")
                            onLongPressed: if (appState) {
                                var target = ({ text: appState.autoClampDwellSec.toFixed(1) })
                                appState.openOnScreenKeyboard(
                                    target, true, qsTr("DWELL TIME (SECONDS)"),
                                    function(value) {
                                        appState.setApplicationNumericSetting("autoClampToBendDwellSec", value)
                                    }, null, true)
                            }
                        }
                        DwellStepButton {
                            objectName: "dwell-increment-button"
                            Layout.preferredWidth: 38
                            Layout.fillHeight: true
                            glyph: "+"
                            enabledState: dwellTile.enabledState && dwellTile.dwellActive && dwellTile.dwell < 10
                            onClicked: root.stepAutoClampDwell(1)
                        }
                    }
                }
            }
            BendMode {
                id: bendModeControl
                objectName: "bendModeControl"
                Layout.fillWidth: true
                Layout.fillHeight: true
                mode: appState ? appState.bendMode : "PROGRAM_BEND_MODE"
                multipleBends: appState ? appState.multipleBendsProgram : false
                enabledState: appState ? appState.runProgramAllowed : false
                onModeRequested: function(mode) { if (appState) appState.setBendMode(mode) }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: appState ? appState.addBendPopupVisible : false
        color: "#99000000"
        z: 20
        MouseArea { anchors.fill: parent }

        Rectangle {
            width: Math.min(parent.width - 98, 760)
            height: Math.min(parent.height - 80, 520)
            anchors.centerIn: parent
            radius: 7
            color: paper
            border.color: "#7A7A7A"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    color: "#3F403F"
                    radius: 7
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: parent.radius; color: parent.color }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 14
                            color: "#26FFFFFF"
                            Text { anchors.centerIn: parent; text: "+"; color: "white"; font.bold: true; font.pixelSize: 16 }
                        }
                        Text { text: qsTr("ADD BEND MOVE"); color: "white"; font.bold: true; font.pixelSize: 17; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter }
                        Rectangle {
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 36
                            radius: 5
                            color: red
                            Text { anchors.centerIn: parent; text: qsTr("CLOSE"); color: "white"; font.bold: true; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (appState) appState.closeAddBendPopup() }
                        }
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: Math.max(height, addBendColumn.implicitHeight)

                    Column {
                        anchors.centerIn: parent
                        visible: appState ? appState.allBends.length === 0 : true
                        spacing: 8
                        Text { text: "⌕"; color: grey; font.bold: true; font.pixelSize: 34; horizontalAlignment: Text.AlignHCenter; width: 260 }
                        Text { text: "NO BENDS AVAILABLE"; color: grey; font.bold: true; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; width: 260 }
                    }

                    ColumnLayout {
                        id: addBendColumn
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: appState ? appState.allBends : []
                            AddBendRow {
                                Layout.fillWidth: true
                                readonly property var bend: modelData
                                selected: appState ? appState.selectedAddBendIndex === index : false
                                bendName: bend.name || "Bend"
                                angle: bend.angle || "90.0"
                                compensation: bend.compensation || "0.0"
                                compensationType: bend.state || "OVERBENT"
                                dateText: bend.date || "-"
                                punchName: bend.punch || "UNDEFINED"
                                dieName: bend.die || "UNDEFINED"
                                materialName: bend.material || "Material"
                                valid: bend.valid !== false
                                onClicked: if (appState) appState.selectAddBend(index)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: "white"
                    border.color: lightGrey
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        Item { Layout.fillWidth: true }
                        Text { text: appState ? appState.addBendStatus : ""; color: "#5E5E5E"; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                        Rectangle {
                            Layout.preferredWidth: 140
                            Layout.preferredHeight: 42
                            radius: 6
                            color: green
                            border.color: Qt.lighter(green, 1.2)
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: qsTr("ADD BEND")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (appState) appState.addSelectedBendToProgram()
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: appState ? appState.runConfirmationVisible : false
        color: "#99000000"
        z: 21
        MouseArea { anchors.fill: parent }

        Rectangle {
            width: Math.max(580, Math.min(parent.width * 0.70, 720))
            height: Math.max(340, Math.min(parent.height * 0.50, 420))
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
                    color: !appState ? red
                        : appState.bendMode === "SINGLE_BEND_MODE" ? "#16A34A"
                        : appState.bendMode === "SINGLE_BEND_REPEAT" ? "#0284C7"
                        : appState.bendMode === "PROGRAM_BEND_LOOP" ? "#7C3AED"
                        : red
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
                            visible: !!appState && !!appState.bendMode
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: modeLabel.implicitWidth + 14
                            radius: 4
                            color: "#33000000"
                            Text {
                                id: modeLabel
                                anchors.centerIn: parent
                                text: appState ? appState.bendMode.replace(/_/g, " ") : ""
                                color: "white"
                                font.bold: true
                                font.pixelSize: 11
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
                                    text: appState ? appState.activeProgram : "Program"
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
                                    text: appState && appState.bendModeIsProgramMode()
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
                                            color: !appState ? red
                                                : appState.bendMode === "SINGLE_BEND_MODE" ? "#16A34A"
                                                : appState.bendMode === "SINGLE_BEND_REPEAT" ? "#0284C7"
                                                : appState.bendMode === "PROGRAM_BEND_LOOP" ? "#7C3AED"
                                                : red
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            text: appState ? "#" + String(appState.selectedRunBend + 1) + "  ·  " + (appState.selectedBend.name || "Bend") : "#1  ·  Bend"
                                            color: "#0F172A"
                                            font.bold: true
                                            font.pixelSize: 14
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: appState ? appState.bendModeIsProgramMode() : false
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
                                        font.pixelSize: 11
                                        font.letterSpacing: 0.5
                                    }

                                    WarningPanel {
                                        visible: appState ? appState.bendModeIsRepeatable() : false
                                        Layout.fillWidth: true
                                        label: qsTr("PROGRAM WILL BE REPEATED")
                                        glyph: "↻"
                                    }

                                    WarningPanel {
                                        visible: appState ? appState.selectedBendNotTopMostWarning : false
                                        Layout.fillWidth: true
                                        label: qsTr("SELECTED BEND ISN'T TOP MOST")
                                        glyph: "!"
                                    }

                                    WarningPanel {
                                        objectName: "run-confirmation-measured-thickness"
                                        visible: appState ? appState.measuredThicknessOverrideActive : false
                                        Layout.fillWidth: true
                                        label: appState && appState.measuredThicknessOverrideActive
                                            ? qsTr("USING MEASURED t %1 (PROGRAM %2 %3)").arg(Units.len(appState.measuredMaterialThickness, appState.metricUnits, 4)).arg(appState.programThicknessText()).arg(appState.thicknessUnitLabel())
                                            : ""
                                        glyph: "t"
                                    }

                                    // All Clear Badge when no warnings apply
                                    Rectangle {
                                        visible: appState ? (!appState.bendModeIsRepeatable() && !appState.selectedBendNotTopMostWarning && !appState.measuredThicknessOverrideActive) : true
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
                                onClicked: if (appState) appState.confirmRunProgram()
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
                                onClicked: if (appState) appState.closeRunConfirmation()
                            }
                        }
                    }
                }
            }
        }
    }

    component ComboField: Rectangle {
        id: comboFieldRoot
        signal programSelected(int index)
        property string text: ""
        property var programs: []
        property int selectedIndex: 0
        readonly property bool menuOpen: programMenu.visible
        readonly property var selectedCompatibility: compatibilityAt(selectedIndex)
        function compatibilityAt(index) {
            return root.appState && programs && index >= 0 && index < programs.length
                ? root.appState.programCompatibility(programs[index]) : null
        }
        height: 35
        radius: 4
        color: "white"
        border.color: ink
        border.width: 1
        Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.right: selectedCompatibilityBadge.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: parent.text; color: ink; font.bold: true; font.pixelSize: 12; elide: Text.ElideRight }
        CompatibilityBadge { id: selectedCompatibilityBadge; objectName: "run-program-compatibility-selected"; anchors.right: comboArrow.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; info: comboFieldRoot.selectedCompatibility }
        Text { id: comboArrow; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "▼"; color: ink; font.pixelSize: 12 }
        // Toggle. With CloseOnPressOutside the same tap closed the menu and
        // then reached this MouseArea, which reopened it immediately.
        MouseArea { anchors.fill: parent; onClicked: programMenu.visible ? programMenu.close() : programMenu.open() }
        Menu {
            id: programMenu
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            y: comboFieldRoot.height + 1
            width: comboFieldRoot.width
            Repeater {
                model: comboFieldRoot.programs
                MenuItem {
                    id: programMenuItem
                    objectName: "run-program-menu-item-" + index
                    readonly property var compatibility: comboFieldRoot.compatibilityAt(index)
                    width: programMenu.width
                    text: (index === comboFieldRoot.selectedIndex ? "✓  " : "   ") + (modelData.name || "Untitled Program")
                    font.bold: index === comboFieldRoot.selectedIndex
                    onTriggered: comboFieldRoot.programSelected(index)
                    contentItem: Item {
                        implicitWidth: programMenuLabel.implicitWidth + programMenuBadge.implicitWidth + 8
                        implicitHeight: Math.max(programMenuLabel.implicitHeight, programMenuBadge.implicitHeight)
                        Text { id: programMenuLabel; anchors.left: parent.left; anchors.right: programMenuBadge.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: programMenuItem.text; font: programMenuItem.font; color: programMenuItem.palette.windowText; elide: Text.ElideRight }
                        CompatibilityBadge { id: programMenuBadge; objectName: "run-program-compatibility-" + index; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; info: programMenuItem.compatibility }
                    }
                }
            }
        }
    }

    // CAD export compatibility per program (AppState.programCompatibility).
    component CompatibilityBadge: Rectangle {
        property var info: null
        readonly property string status: info ? String(info.status || "") : ""
        readonly property string label: info ? String(info.label || "") : ""
        visible: label.length > 0
        implicitWidth: visible ? compatibilityBadgeText.implicitWidth + 12 : 0
        implicitHeight: 18
        width: implicitWidth
        height: implicitHeight
        radius: 3
        color: status === "current" ? root.green
             : status === "old-revision" ? "#c98a00"
             : status === "degraded" ? "#d35400"
             : status === "manual" ? root.grey : root.red
        Text { id: compatibilityBadgeText; anchors.centerIn: parent; text: parent.label; color: "white"; font.bold: true; font.pixelSize: 11 }
    }

    component ProgramNameField: Rectangle {
        signal textEdited(string value)
        property alias text: field.text
        readonly property alias input: field
        function openKeyboard() {
            if (root.appState)
                root.appState.openOnScreenKeyboard(
                    field, false, qsTr("PROGRAM NAME"),
                    function(value) { textEdited(value) })
        }
        height: 35
        radius: 4
        color: "white"
        border.color: ink
        border.width: 1
        TextInput { id: field; objectName: "run-program-name-input"; anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; verticalAlignment: TextInput.AlignVCenter; color: ink; font.bold: true; font.pixelSize: 12; selectByMouse: true; onTextEdited: parent.textEdited(text); TapHandler { onTapped: field.parent.openKeyboard() } }
    }

    component IconButton: Rectangle {
        signal clicked()
        property string glyph: ""
        property string iconSource: ""
        property color base: charcoal
        property color glyphColor: "white"
        property color borderColor: "transparent"
        height: 35
        radius: 4
        color: base
        border.color: borderColor
        border.width: borderColor === "transparent" ? 0 : 1
        Image { anchors.centerIn: parent; width: 16; height: 16; source: iconSource; fillMode: Image.PreserveAspectFit; visible: iconSource.length > 0 }
        Text { anchors.centerIn: parent; text: glyph; color: glyphColor; font.bold: true; font.pixelSize: 15; visible: iconSource.length === 0 }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    component TextButton: Rectangle {
        signal clicked()
        property string glyph: ""
        property string iconSource: ""
        property string label: ""
        property color base: charcoal
        height: 35
        radius: 4
        color: base
        RowLayout { anchors.centerIn: parent; spacing: 7; Image { Layout.preferredWidth: 15; Layout.preferredHeight: 15; source: iconSource; fillMode: Image.PreserveAspectFit; visible: iconSource.length > 0 } Text { text: glyph; color: "white"; font.bold: true; font.pixelSize: 13; visible: iconSource.length === 0 && glyph.length > 0 } Text { text: label; color: "white"; font.bold: true; font.pixelSize: 12 } }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    component Chip: Rectangle {
        property string label: ""
        property color base: charcoal
        height: 25
        radius: 4
        color: base
        Text { anchors.fill: parent; anchors.leftMargin: 7; anchors.rightMargin: 7; text: label; color: "white"; font.bold: true; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    }

    component BendCell: Rectangle {
        id: bendCellRoot
        signal cellSelected()
        signal deleteRequested()
        signal editRequested()
        property int sequence: 1
        property bool selected: false
        property string bendName: ""
        property string angle: "90.0"
        property string compensation: "0.0"
        property bool metric: false
        property string bendState: "DRAFT"
        property string xValue: "-1.0000"
        property string rValue: "0.0000"
        property string speedValue: "100.000"
        property string tonnage: "0.079"
        property string thickness: "0.1250"
        property string materialName: "Cold Rolled Steel"
        property string punchName: "Gooseneck 88° Punch"
        property string dieName: "4 Way Die (0.630in)"
        height: 102
        radius: 0
        color: paper
        border.width: 0
        Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 39; color: selected ? red : paper; radius: 7 }
        Rectangle { anchors.fill: parent; anchors.leftMargin: 43; anchors.margins: 4; color: paper; radius: 7 }
        MouseArea { anchors.fill: parent; onClicked: parent.cellSelected() }

        GridLayout {
            anchors.fill: parent
            anchors.margins: selected ? 6 : 10
            columns: 7
            columnSpacing: 7
            rowSpacing: 0

            Text { text: String(sequence); color: ink; font.bold: true; font.pixelSize: 18; Layout.preferredWidth: 25; Layout.rowSpan: 2; Layout.alignment: Qt.AlignVCenter }
            Text { text: "⋮⋮"; color: ink; font.bold: true; font.pixelSize: 28; Layout.preferredWidth: 24; Layout.rowSpan: 2; Layout.alignment: Qt.AlignVCenter }

            ColumnLayout {
                Layout.preferredWidth: 74
                Layout.rowSpan: 2
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Text { text: bendCellRoot.angle + "°"; color: ink; font.bold: true; font.pixelSize: 25; Layout.alignment: Qt.AlignHCenter }
                Text { text: "(" + bendCellRoot.compensation + "°)"; color: "#707070"; font.bold: true; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                Text { text: bendCellRoot.bendState; color: "#707070"; font.bold: true; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter; elide: Text.ElideRight }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.rowSpan: 2
                Layout.alignment: Qt.AlignVCenter
                spacing: 4
                Text { text: bendName; color: ink; font.bold: true; font.pixelSize: 15; elide: Text.ElideRight; Layout.fillWidth: true }
                RowLayout { spacing: 4; Chip { Layout.preferredWidth: 118; label: bendCellRoot.punchName; base: red } Chip { Layout.preferredWidth: 127; label: bendCellRoot.dieName; base: blue } }
                RowLayout { spacing: 4; Chip { Layout.preferredWidth: 58; label: bendCellRoot.thickness + "\""; base: charcoal } Chip { Layout.preferredWidth: 160; label: bendCellRoot.materialName; base: green } }
            }

            BackGaugePanel { Layout.preferredWidth: 205; Layout.preferredHeight: 82; metric: bendCellRoot.metric; xValue: bendCellRoot.xValue; rValue: bendCellRoot.rValue; speedValue: bendCellRoot.speedValue }
            TonnagePanel { Layout.preferredWidth: 105; Layout.preferredHeight: 82; tonnage: bendCellRoot.tonnage }

            ColumnLayout {
                Layout.preferredWidth: 31
                Layout.fillHeight: true
                spacing: 4
                IconButton { Layout.fillWidth: true; Layout.fillHeight: true; glyph: "■"; base: red; onClicked: bendCellRoot.deleteRequested() }
                IconButton { Layout.fillWidth: true; Layout.fillHeight: true; glyph: "✎"; base: blue; onClicked: bendCellRoot.editRequested() }
            }
        }
    }

    component BackGaugePanel: Rectangle {
        property bool metric: false
        property string xValue: "-1.0000"
        property string rValue: "0.0000"
        property string speedValue: "100.000"
        radius: 4
        color: lightGrey
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            Rectangle { Layout.fillWidth: true; height: 25; radius: 4; color: charcoal; Text { anchors.centerIn: parent; text: "BACKGAUGE FINGER LOWER EDGE"; color: "white"; font.bold: true; font.pixelSize: 11 } }
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 3
                columnSpacing: 0
                Text { text: "X"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: "R"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: "SPEED"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: metric ? Units.lenText(xValue, true).replace(" ", "\n") : xValue + "\nIn"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: metric ? Units.lenText(rValue, true).replace(" ", "\n") : rValue + "\nIn"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: Units.speedText(speedValue, metric) + "\n" + Units.speedLabel(metric); color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            }
        }
    }

    component TonnagePanel: Rectangle {
        property string tonnage: "0.079"
        radius: 4
        color: lightGrey
        ColumnLayout {
            anchors.fill: parent
            spacing: 2
            Rectangle { Layout.fillWidth: true; height: 25; radius: 4; color: charcoal; Text { anchors.centerIn: parent; text: "RAM LOAD"; color: "white"; font.bold: true; font.pixelSize: 11 } }
            Text { text: "BEND TONNAGE"; color: ink; font.bold: true; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
            Text { text: tonnage + "\nTONS"; color: ink; font.bold: true; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
        }
    }

    component FooterPanel: Rectangle {
        property string title: ""
        property string value: ""
        height: 35
        radius: 4
        color: "transparent"
        border.color: charcoal
        border.width: 2
        RowLayout { anchors.fill: parent; anchors.margins: 7; Text { text: title; color: ink; font.bold: true; font.pixelSize: 12 } Item { Layout.fillWidth: true } Text { text: value; color: ink; font.bold: true; font.pixelSize: 12 } }
    }

    component SimButton: Rectangle {
        id: simButtonRoot
        signal clicked()
        property string label: ""
        property color base: "#374151"
        property bool enabledState: true
        height: 28
        radius: 4
        color: enabledState ? (simButtonMouse.containsMouse ? Qt.lighter(base, 1.15) : base) : "#21262D"
        border.color: enabledState ? Qt.lighter(color, 1.25) : "#374151"
        border.width: 1
        opacity: enabledState ? 1.0 : 0.45
        Text { anchors.centerIn: parent; text: simButtonRoot.label; color: "white"; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter }
        MouseArea { id: simButtonMouse; anchors.fill: parent; hoverEnabled: true; enabled: simButtonRoot.enabledState; onClicked: simButtonRoot.clicked() }
    }

    // Styled as a ribbon segment so the DRO strip reads as one v9 bar.
    component SimInfoButton: Rectangle {
        signal clicked()
        property bool active: false
        objectName: "run-scene-info-button"
        radius: 4
        color: active ? "#1E293B" : "#0B0F17"
        border.color: active ? "#38BDF8" : "#1E293B"
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: "ⓘ"
            color: active ? "#38BDF8" : "#94A3B8"
            font.bold: true
            font.pixelSize: 17
        }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    // One bay of the v9 DRO ribbon; amber marks the stage the run is in.
    component StageBay: Rectangle {
        id: stageBayRoot
        property string label: ""
        property string value: ""
        property bool current: false
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 3
        color: current ? "#D97706" : "transparent"
        border.color: current ? "#F59E0B" : "transparent"
        border.width: current ? 1 : 0
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 4
            Text { text: stageBayRoot.label; color: stageBayRoot.current ? "black" : "#64748B"; font.bold: true; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Text {
                text: stageBayRoot.value
                color: stageBayRoot.current ? "black" : "#F8FAFC"
                font.bold: true
                font.pixelSize: stageBayRoot.value === "UNAVAILABLE" ? 11 : 11
            }
        }
    }

    component ActionRun: Rectangle {
        id: actionRunRoot
        signal clicked()
        property bool active: false
        property bool allowed: true
        property bool grayed: false
        readonly property bool ready: allowed && !grayed
        readonly property string titleText: active ? qsTr("STOP PROGRAM") : qsTr("RUN PROGRAM")
        readonly property string detailText: active ? qsTr("RUN ACTIVE")
            : (ready ? qsTr("READY") : qsTr("NOT READY"))
        radius: 5
        color: active ? "#B91C1C" : (ready ? "#16A34A" : "#4B5563")
        border.color: active ? "#DC2626" : (ready ? "#22C55E" : "#6B7280")
        border.width: 1

        scale: actionRunMouseArea.pressed ? 0.97 : 1.0
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 17
                color: actionRunRoot.active ? "#7F1D1D" : (actionRunRoot.ready ? "#14532D" : "#374151")
                border.color: actionRunRoot.border.color
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: actionRunRoot.active ? "■" : "▶"
                    color: "white"
                    font.bold: true
                    font.pixelSize: actionRunRoot.active ? 14 : 15
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: actionRunRoot.titleText
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                    font.letterSpacing: 0.5
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: actionRunRoot.detailText
                    color: actionRunRoot.active ? "#FECACA" : (actionRunRoot.ready ? "#DCFCE7" : "#CBD5E1")
                    font.bold: true
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: !actionRunRoot.allowed
                text: "!"
                color: "#FCA5A5"
                font.bold: true
                font.pixelSize: 18
            }
        }

        MouseArea {
            id: actionRunMouseArea
            anchors.fill: parent
            hoverEnabled: true
            // STOP must always be clickable while a run is active (machine is never IDLE then).
            enabled: actionRunRoot.active || (actionRunRoot.allowed && !actionRunRoot.grayed)
            onClicked: actionRunRoot.clicked()
        }
    }

    component ProgramProgress: Rectangle {
        property string title: "PROGRAM READY"
        property string subtitle: "Select a bend"
        height: 88
        radius: 0
        color: paper
        readonly property var stepNames: ["BACK GAUGE MOVE", "SAFETY START POSITION", "CLAMP MATERIAL", "BACK GAUGE BUMP", "BEND MOVE", "BACK GAUGE & RAM RETRACT"]
        readonly property int currentStep: 0
        Column {
            anchors.fill: parent
            spacing: 0
            Text { width: parent.width; height: 22; text: title || "Bend #1 in Progress"; color: ink; font.bold: true; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            Row {
                width: parent.width
                height: parent.height - 22
                leftPadding: 30
                rightPadding: 30
                Repeater {
                    model: 6
                    Item {
                        width: (parent.width - parent.leftPadding - parent.rightPadding) / 6
                        height: parent.height
                        Rectangle { anchors.left: parent.left; anchors.right: parent.horizontalCenter; anchors.verticalCenter: circle.verticalCenter; height: 12; visible: index > 0; color: index <= currentStep ? green : "transparent" }
                        Rectangle { anchors.left: parent.horizontalCenter; anchors.right: parent.right; anchors.verticalCenter: circle.verticalCenter; height: 12; color: index < 5 && index < currentStep ? green : (index < 5 ? "transparent" : "transparent") }
                        Rectangle {
                            id: circle
                            width: 39
                            height: 39
                            radius: 19.5
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            color: index < currentStep ? green : paper
                            border.color: index <= currentStep ? green : grey
                            border.width: 4
                            Text { anchors.centerIn: parent; text: index < currentStep ? "✓" : String(index + 1); color: index < currentStep ? "white" : grey; font.bold: true; font.pixelSize: index < currentStep ? 16 : 19 }
                        }
                        Text { anchors.left: parent.left; anchors.right: parent.right; anchors.top: circle.bottom; anchors.topMargin: 2; height: 24; text: stepNames[index]; color: grey; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignTop; wrapMode: Text.WordWrap; maximumLineCount: 2 }
                    }
                }
            }
        }
    }

    component AddBendRow: Rectangle {
        signal clicked()
        property bool selected: false
        property string bendName: ""
        property string angle: "90.0"
        property string compensation: "0.0"
        property string compensationType: "OVERBENT"
        property string dateText: "-"
        property string punchName: "UNDEFINED"
        property string dieName: "UNDEFINED"
        property string materialName: "Material"
        property bool valid: true
        height: 86
        opacity: valid ? 1.0 : 0.5
        color: selected ? "#fff2dc" : "white"
        border.color: selected ? red : lightGrey
        border.width: selected ? 2 : 1
        GridLayout {
            anchors.fill: parent
            anchors.margins: 8
            columns: 7
            columnSpacing: 8
            rowSpacing: 2
            Text { text: bendName; color: ink; font.bold: true; font.pixelSize: 14; elide: Text.ElideRight; Layout.columnSpan: 5; Layout.fillWidth: true }
            Text { text: "Punch"; color: red; font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 60 }
            Text { text: punchName; color: ink; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: "Bend Angle"; color: ink; font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 82 }
            Text { text: angle + "°"; color: ink; font.bold: true; font.pixelSize: 13; Layout.preferredWidth: 60 }
            Text { text: ""; Layout.preferredWidth: 4 }
            Text { text: dateText; color: "#555"; font.pixelSize: 11; Layout.preferredWidth: 150 }
            Text { text: ""; Layout.preferredWidth: 4 }
            Text { text: "Die"; color: blue; font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 60 }
            Text { text: dieName; color: ink; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: compensationType; color: ink; font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 82 }
            Text { text: compensation + "°"; color: ink; font.bold: true; font.pixelSize: 13; Layout.preferredWidth: 60 }
            Text { text: ""; Layout.preferredWidth: 4 }
            Text { text: ""; Layout.preferredWidth: 150 }
            Text { text: ""; Layout.preferredWidth: 4 }
            Text { text: "Material"; color: green; font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 60 }
            Text { text: materialName; color: ink; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
        }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    component RunPreviewPanel: Rectangle {
        property string title: "PREVIEW"
        property string label: "Bend"
        property string gaugeX: "0.0000"
        property bool metric: false
        radius: 4
        color: "white"
        border.color: lightGrey
        border.width: 1
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            Text { Layout.fillWidth: true; text: title; color: ink; font.bold: true; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#e9ecef"
                border.color: grey
                radius: 3
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = "#2b2c2b"
                        ctx.lineWidth = 4
                        ctx.beginPath()
                        ctx.moveTo(width * 0.18, height * 0.62)
                        ctx.lineTo(width * 0.52, height * 0.62)
                        ctx.lineTo(width * 0.76, height * 0.34)
                        ctx.stroke()
                        ctx.fillStyle = "#a82011"
                        ctx.fillRect(width * 0.46, height * 0.20, 8, height * 0.55)
                    }
                }
                Text { anchors.centerIn: parent; text: label + "\n" + (metric ? Units.lenText(gaugeX, true) : gaugeX + " in"); color: ink; font.bold: true; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    component RunSummaryCard: Rectangle {
        property string title: "TITLE"
        property string value: "Value"
        property string detail: "Detail"
        height: 72
        radius: 4
        color: "white"
        border.color: charcoal
        border.width: 2
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            Text { Layout.fillWidth: true; text: title; color: "#5a5a5a"; font.bold: true; font.pixelSize: 11; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; text: value; color: ink; font.bold: true; font.pixelSize: 14; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; text: detail; color: ink; font.pixelSize: 11; elide: Text.ElideRight }
        }
    }

    component ExecutionBendCard: Rectangle {
        property string bendNo: "1"
        property string bendName: "Bend"
        property string angle: "90.0"
        property string thickness: "0.0000"
        property string punchName: "Punch"
        property string dieName: "Die"
        property string materialName: "Material"
        radius: 7
        color: paper
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 3
            Text { Layout.fillWidth: true; text: "CURRENT BEND"; color: "#5a5a5a"; font.bold: true; font.pixelSize: 11; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; text: "#" + bendNo + "  " + bendName; color: ink; font.bold: true; font.pixelSize: 14; elide: Text.ElideRight }
            RowLayout { Layout.fillWidth: true; spacing: 4; Chip { Layout.preferredWidth: 64; label: angle + "°"; base: charcoal } Chip { Layout.preferredWidth: 82; label: thickness + "\""; base: charcoal } Chip { Layout.fillWidth: true; label: materialName; base: green } }
            RowLayout { Layout.fillWidth: true; spacing: 4; Chip { Layout.fillWidth: true; label: punchName; base: red } Chip { Layout.fillWidth: true; label: dieName; base: blue } }
        }
    }

    component ExecutionBackGaugeCard: Rectangle {
        property bool metric: false
        property string xValue: "0.0000"
        property string rValue: "0.0000"
        property string speedValue: "100.000"
        radius: 7
        color: lightGrey
        GridLayout {
            anchors.fill: parent
            anchors.margins: 7
            columns: 3
            columnSpacing: 4
            rowSpacing: 2
            Text { Layout.columnSpan: 3; Layout.fillWidth: true; text: "BACK GAUGE"; color: "#5a5a5a"; font.bold: true; font.pixelSize: 11; elide: Text.ElideRight }
            Rectangle { Layout.columnSpan: 3; Layout.fillWidth: true; Layout.preferredHeight: 24; color: "white"; radius: 4; Text { anchors.centerIn: parent; text: "BACKGAUGE FINGER LOWER EDGE"; color: ink; font.bold: true; font.pixelSize: 11 } }
            Text { text: "X"; color: charcoal; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: "R"; color: charcoal; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: "SPEED"; color: charcoal; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: metric ? Units.lenText(xValue, true).replace(" ", "\n") : xValue + "\nIn"; color: ink; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: metric ? Units.lenText(rValue, true).replace(" ", "\n") : rValue + "\nIn"; color: ink; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: Units.speedText(speedValue, metric) + "\n" + Units.speedLabel(metric); color: ink; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
        }
    }

    component ExecutionTonnageCard: Rectangle {
        property string tonnage: "0.000"
        radius: 7
        color: paper
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 4
            Text { Layout.fillWidth: true; text: "RAM LOAD"; color: "#5a5a5a"; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter }
            Item { Layout.fillHeight: true }
            Text { Layout.fillWidth: true; text: "BEND TONNAGE"; color: charcoal; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter }
            Text { Layout.fillWidth: true; text: tonnage + "\nTONS"; color: red; font.bold: true; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter }
            Item { Layout.fillHeight: true }
        }
    }

    // v9 AUTO CLAMP strip: full-width tap target with an ON/OFF badge.
    component AutoClamp: Rectangle {
        id: autoClampRoot
        signal clicked()
        property bool active: false
        property bool enabledState: true
        readonly property string labelText: qsTr("AUTO CLAMP TO BEND")
        radius: 4
        color: autoClampMouseArea.containsMouse && enabledState ? "#1F2937" : "#111827"
        border.color: "#374151"
        border.width: 1
        opacity: enabledState ? 1.0 : 0.45

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 6
            Text {
                text: autoClampRoot.labelText
                color: "white"
                font.bold: true
                font.pixelSize: 11
                font.letterSpacing: 0.5
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 20
                radius: 3
                color: autoClampRoot.active ? "#16A34A" : "#374151"
                border.color: autoClampRoot.active ? "#22C55E" : "#4B5563"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: autoClampRoot.active ? "ON" : "OFF"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
        }

        MouseArea {
            id: autoClampMouseArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: autoClampRoot.enabledState
            onClicked: autoClampRoot.clicked()
        }
    }

    component DwellStepButton: Rectangle {
        id: dwellStepRoot
        signal clicked()
        property string glyph: "+"
        property bool enabledState: true
        radius: 4
        color: dwellStepMouse.containsMouse && enabledState ? "#374151" : "#1E293B"
        border.color: "#475569"
        border.width: 1
        opacity: enabledState ? 1.0 : 0.4
        Text {
            anchors.centerIn: parent
            text: dwellStepRoot.glyph
            color: "white"
            font.bold: true
            font.pixelSize: 18
        }
        MouseArea {
            id: dwellStepMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: dwellStepRoot.enabledState
            onClicked: dwellStepRoot.clicked()
        }
    }

    // v9 dwell readout: tap toggles dwell, press-and-hold edits seconds.
    component DwellTile: Rectangle {
        id: dwellRoot
        signal clicked()
        signal longPressed()
        property bool dwellActive: true
        property real dwell: 3.0
        property bool enabledState: true
        readonly property string labelText: qsTr("DWELL")
        readonly property bool holding: dwellActive && dwell > 0
        readonly property string displayText: holding
            ? (Math.abs(dwell - Math.round(dwell)) < 0.05 ? String(Math.round(dwell)) : dwell.toFixed(1)) + " s"
            : qsTr("OFF")
        radius: 4
        color: "#030712"
        border.color: holding ? "#F59E0B" : "#374151"
        border.width: 1
        opacity: enabledState ? 1.0 : 0.45

        Column {
            anchors.centerIn: parent
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dwellRoot.displayText
                color: dwellRoot.holding ? "#FBBF24" : "#64748B"
                font.bold: true
                font.pixelSize: 15
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dwellRoot.holding ? qsTr("DWELL HOLD") : qsTr("DWELL OFF")
                color: dwellRoot.holding ? "#D97706" : "#475569"
                font.bold: true
                font.pixelSize: 11
            }
        }

        MouseArea {
            id: dwellMouseArea
            anchors.fill: parent
            enabled: dwellRoot.enabledState
            pressAndHoldInterval: 850
            property bool longPressHandled: false

            onPressed: longPressHandled = false
            onPressAndHold: {
                longPressHandled = true
                dwellRoot.longPressed()
            }
            onClicked: {
                if (!longPressHandled)
                    dwellRoot.clicked()
                longPressHandled = false
            }
            onCanceled: longPressHandled = false
        }
    }

    component WarningPanel: Rectangle {
        property string label: ""
        property string glyph: "!"
        height: 40
        radius: 6
        color: glyph === "t" ? "#EFF6FF" : "#FEF3C7"
        border.color: glyph === "t" ? "#BFDBFE" : "#FCD34D"
        border.width: 1
        RowLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 8
            Text {
                text: glyph
                color: parent.parent.glyph === "t" ? "#1D4ED8" : "#B45309"
                font.bold: true
                font.pixelSize: 14
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                text: label
                color: parent.parent.glyph === "t" ? "#1E40AF" : "#92400E"
                font.bold: true
                font.pixelSize: 11
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }

    // v9 2x2 cycle matrix. Program cycles stay disabled for single-bend
    // programs (AppState.setBendMode also forces SINGLE_BEND_MODE).
    component BendMode: Rectangle {
        id: bendModeRoot
        signal modeRequested(string mode)
        property string mode: "PROGRAM_BEND_MODE"
        property bool multipleBends: false
        property bool enabledState: true
        readonly property string modeText: mode === "SINGLE_BEND_MODE" ? qsTr("SINGLE BEND MODE") : mode === "SINGLE_BEND_REPEAT" ? qsTr("SINGLE BEND REPEAT") : mode === "PROGRAM_BEND_LOOP" ? qsTr("PROGRAM BEND LOOP") : qsTr("PROGRAM BEND MODE")
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

            ModeOption {
                objectName: "bend-mode-program-once-option"
                label: qsTr("PROGRAM BEND")
                selected: bendModeRoot.mode === "PROGRAM_BEND_MODE"
                enabledState: bendModeRoot.enabledState && bendModeRoot.multipleBends
                onClicked: bendModeRoot.modeRequested("PROGRAM_BEND_MODE")
            }
            ModeOption {
                objectName: "bend-mode-single-once-option"
                label: qsTr("SINGLE BEND")
                selected: bendModeRoot.mode === "SINGLE_BEND_MODE"
                enabledState: bendModeRoot.enabledState
                onClicked: bendModeRoot.modeRequested("SINGLE_BEND_MODE")
            }
            ModeOption {
                objectName: "bend-mode-program-loop-option"
                label: qsTr("PROGRAM LOOP")
                selected: bendModeRoot.mode === "PROGRAM_BEND_LOOP"
                enabledState: bendModeRoot.enabledState && bendModeRoot.multipleBends
                onClicked: bendModeRoot.modeRequested("PROGRAM_BEND_LOOP")
            }
            ModeOption {
                objectName: "bend-mode-single-repeat-option"
                label: qsTr("SINGLE REPEAT")
                selected: bendModeRoot.mode === "SINGLE_BEND_REPEAT"
                enabledState: bendModeRoot.enabledState
                onClicked: bendModeRoot.modeRequested("SINGLE_BEND_REPEAT")
            }
        }
    }

    component ModeOption: Rectangle {
        id: modeOptionRoot
        signal clicked()
        property string label: ""
        property bool selected: false
        property bool enabledState: true
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 4
        color: selected ? "#78350F" : (modeOptionMouse.containsMouse && enabledState ? "#1F2937" : "#111827")
        border.color: selected ? "#F59E0B" : "#374151"
        border.width: selected ? 1.5 : 1
        opacity: enabledState ? 1.0 : 0.35

        Row {
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: modeOptionRoot.selected ? "#F59E0B" : "#475569"
            }
            Text {
                text: modeOptionRoot.label
                color: modeOptionRoot.selected ? "white" : "#E2E8F0"
                font.bold: true
                font.pixelSize: 12
                font.letterSpacing: 0.5
            }
        }

        MouseArea {
            id: modeOptionMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: modeOptionRoot.enabledState
            onClicked: modeOptionRoot.clicked()
        }
    }

    // RUN angle correction: measured angle -> compensation for the next
    // sequences. Target: material OVERRIDE (if active) or ALL program bends.
    Rectangle {
        id: angleCorrectionModal
        objectName: "run-angle-correction-modal"
        property var info: null
        property real measured: 90
        property string target: "program"
        readonly property real currentSigned: !info ? 0
            : (target === "material" ? info.materialSignedCompensation : info.programSignedCompensation)
        readonly property real nextSigned: info
            ? Math.round((currentSigned - (measured - info.desired)) * 100) / 100 : 0
        function open() {
            info = appState ? appState.angleCorrectionInfo() : null
            if (!info) return
            measured = info.desired
            target = info.materialOverride ? "material" : "program"
            visible = true
        }
        function fmt(v) {
            return (v >= 0 ? "+" : "") + v.toFixed(2) + "° ("
                + (Math.abs(v) < 0.005 ? "0" : Math.abs(v).toFixed(2) + "° " + (v < 0 ? "UNDERBENT" : "OVERBENT")) + ")"
        }
        visible: false
        anchors.fill: parent
        z: 60
        color: "#99000000"
        MouseArea { anchors.fill: parent; onClicked: angleCorrectionModal.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: 400
            height: 320
            radius: 8
            color: "#1C1917"
            border.color: "#7C3AED"
            border.width: 2
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8
                Text {
                    text: "ANGLE CORRECTION · B" + (appState ? appState.selectedRunBend + 1 : "")
                    color: "#C4B5FD"; font.bold: true; font.pixelSize: 14
                }
                Text {
                    text: angleCorrectionModal.info
                        ? "Programmed " + angleCorrectionModal.info.desired.toFixed(1) + "° · measured angle:" : ""
                    color: "#D6D3D1"; font.pixelSize: 12
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    SimButton {
                        objectName: "run-angle-correction-target-material"
                        Layout.fillWidth: true; height: 34
                        label: "MATERIAL OVERRIDE"
                        base: angleCorrectionModal.target === "material" ? "#7C3AED" : "#374151"
                        enabledState: !!angleCorrectionModal.info && angleCorrectionModal.info.materialOverride
                        onClicked: angleCorrectionModal.target = "material"
                    }
                    SimButton {
                        objectName: "run-angle-correction-target-program"
                        Layout.fillWidth: true; height: 34
                        label: "ALL PROGRAM BENDS"
                        base: angleCorrectionModal.target === "program" ? "#7C3AED" : "#374151"
                        onClicked: angleCorrectionModal.target = "program"
                    }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: !angleCorrectionModal.info ? ""
                        : (angleCorrectionModal.target === "material"
                           ? "Current override (" + angleCorrectionModal.info.materialName + "): "
                           : "Current B" + (appState.selectedRunBend + 1) + " compensation: ")
                          + angleCorrectionModal.fmt(angleCorrectionModal.currentSigned)
                          + (angleCorrectionModal.target === "program" && angleCorrectionModal.info.materialOverride
                             ? "\nWarning: material override is active and masks program compensation." : "")
                    color: "#E9D5FF"; font.pixelSize: 12
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    SimButton { Layout.preferredWidth: 44; height: 40; label: "−1.0"; onClicked: angleCorrectionModal.measured -= 1 }
                    SimButton { Layout.preferredWidth: 44; height: 40; label: "−0.1"; onClicked: angleCorrectionModal.measured = Math.round((angleCorrectionModal.measured - 0.1) * 10) / 10 }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: 4
                        color: "white"
                        TextInput {
                            id: measuredAngleInput
                            objectName: "run-angle-correction-input"
                            anchors.fill: parent
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            font.bold: true; font.pixelSize: 18
                            text: angleCorrectionModal.measured.toFixed(1)
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            onEditingFinished: {
                                var v = Number(text)
                                if (isFinite(v) && v > 0 && v < 180) angleCorrectionModal.measured = v
                                else text = angleCorrectionModal.measured.toFixed(1)
                            }
                            TapHandler {
                                onTapped: if (appState) appState.openOnScreenKeyboard(
                                    measuredAngleInput, true, qsTr("MEASURED ANGLE"),
                                    function(value) {
                                        var v = Number(value)
                                        if (isFinite(v) && v > 0 && v < 180) angleCorrectionModal.measured = v
                                    })
                            }
                        }
                    }
                    SimButton { Layout.preferredWidth: 44; height: 40; label: "+0.1"; onClicked: angleCorrectionModal.measured = Math.round((angleCorrectionModal.measured + 0.1) * 10) / 10 }
                    SimButton { Layout.preferredWidth: 44; height: 40; label: "+1.0"; onClicked: angleCorrectionModal.measured += 1 }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    readonly property real err: angleCorrectionModal.info
                        ? angleCorrectionModal.measured - angleCorrectionModal.info.desired : 0
                    text: !angleCorrectionModal.info ? ""
                        : Math.abs(err) < 0.05 ? "On target: no change."
                        : (err > 0 ? "Under-bent (open) by " : "Over-bent (closed) by ") + Math.abs(err).toFixed(1)
                          + "° → bend " + (err > 0 ? "deeper" : "shallower") + ".\n"
                          + (angleCorrectionModal.target === "material" ? "Override "
                             : "All " + angleCorrectionModal.info.bendCount + " bends shift " + (-err).toFixed(2) + "°. B" + (appState.selectedRunBend + 1) + " ")
                          + angleCorrectionModal.fmt(angleCorrectionModal.currentSigned) + " → "
                          + angleCorrectionModal.fmt(angleCorrectionModal.nextSigned)
                    color: "#FBBF24"; font.pixelSize: 12
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    SimButton { Layout.fillWidth: true; height: 38; label: "CANCEL"; onClicked: angleCorrectionModal.visible = false }
                    SimButton {
                        objectName: "run-angle-correction-apply"
                        Layout.fillWidth: true; height: 38; label: "APPLY"; base: "#16A34A"
                        enabledState: !!angleCorrectionModal.info && Math.abs(angleCorrectionModal.measured - angleCorrectionModal.info.desired) >= 0.05
                        onClicked: if (appState && appState.applyMeasuredAngleCorrection(angleCorrectionModal.measured, angleCorrectionModal.target)) angleCorrectionModal.visible = false
                    }
                }
            }
        }
    }

    // RUN tool change operator panel (docs 42b). Visible only while the
    // TOOL_CHANGE step owns the run; it closes when the pedal release completes
    // SEAT. Centered over the canvas area.
    Rectangle {
        id: toolChangePanel
        objectName: "run-tool-change-panel"
        readonly property string tcState: appState ? appState.toolChangeState : "IDLE"
        visible: !!appState && appState.runToolChangeActive
            && tcState !== "DONE"
        z: 50
        x: runCanvasArea.x + (runCanvasArea.width - width) / 2
        y: runCanvasArea.y + Math.max(0, (runCanvasArea.height - height) / 2)
        width: Math.min(runCanvasArea.width - 24, 760)
        height: 318
        radius: 8
        color: "#1C1917"
        border.color: "#F59E0B"
        border.width: 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "\u21C4 TOOL CHANGE"
                    color: "#F59E0B"
                    font.bold: true
                    font.pixelSize: 15
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    color: "#D6D3D1"
                    font.pixelSize: 11
                    readonly property var info: appState ? appState.runToolChangeInfo : null
                    text: info ? (info.summary || (info.label + "  P: " + info.fromPunch + " \u2192 " + info.toPunch
                        + "   D: " + info.fromDie + " \u2192 " + info.toDie)) : ""
                }
            }

            Text {
                Layout.fillWidth: true
                text: appState ? appState.runToolChangePhaseLabel() + (toolChangePanel.tcState === "IDLE" ? "" : "") : ""
                color: toolChangePanel.tcState === "FAILED" ? "#FCA5A5" : "white"
                font.bold: true
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            // Front view of the bed: dashed = current stack, filled = new
            // stack, with each segment width and the stack start position.
            // Front view (operator side) of the bed, same scale for both:
            // left = on the machine now, right = what to install. Red = remove,
            // green = install, grey = segment that stays where it is.
            Canvas {
                id: toolLayout
                objectName: "run-tool-change-layout"
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                readonly property var rows: appState && appState.runToolChangeInfo
                    ? appState.toolChangeLayout(appState.runToolChangeInfo) : null
                readonly property bool metric: !!appState && appState.metricUnits
                onRowsChanged: requestPaint()
                onWidthChanged: requestPaint()
                onMetricChanged: requestPaint()

                function fmt(v) {
                    return metric ? (v * 25.4).toFixed(0) : String(Number(Number(v).toFixed(3)))
                }
                function same(a, list) {
                    for (var i = 0; i < list.length; ++i)
                        if (Math.abs(list[i].x - a.x) < 1e-3 && Math.abs(list[i].w - a.w) < 1e-3)
                            return true
                    return false
                }

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    if (!rows)
                        return
                    var gap = 16, panelW = (width - gap) / 2
                    var span = Math.max(1, rows.maxX - rows.minX)
                    var margin = 0.06 * span
                    var minX = rows.minX - margin, scale = (panelW - 8) / (span + 2 * margin)
                    var panels = [
                        { title: "ON MACHINE NOW", punch: rows.oldPunch, die: rows.oldDie,
                          otherP: rows.newPunch, otherD: rows.newDie, hot: "#EF4444", verb: "REMOVE" },
                        { title: "INSTALL", punch: rows.newPunch, die: rows.newDie,
                          otherP: rows.oldPunch, otherD: rows.oldDie, hot: "#22C55E", verb: "INSTALL" }
                    ]
                    ctx.font = "bold 10px sans-serif"
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    for (var p = 0; p < 2; ++p) {
                        var pan = panels[p], ox = p * (panelW + gap) + 4
                        var X = function(x) { return ox + (x - minX) * scale }
                        ctx.fillStyle = "#292524"
                        ctx.fillRect(ox - 4, 0, panelW, height)
                        ctx.fillStyle = p === 0 ? "#FCA5A5" : "#86EFAC"
                        ctx.textAlign = "left"
                        ctx.fillText(pan.title, ox, 9)
                        ctx.textAlign = "center"
                        // Ram beam and bed
                        ctx.fillStyle = "#44403C"
                        ctx.fillRect(ox, 18, panelW - 8, 8)
                        ctx.fillRect(ox, 128, panelW - 8, 8)
                        // Punches: holder block + tapered tip toward the die
                        for (var i = 0; i < pan.punch.length; ++i) {
                            var s = pan.punch[i], x0 = X(s.x) + 0.5, x1 = X(s.x + s.w) - 0.5
                            var keep = same(s, pan.otherP)
                            ctx.fillStyle = keep ? "#78716C" : pan.hot
                            ctx.beginPath()
                            ctx.moveTo(x0, 26); ctx.lineTo(x1, 26); ctx.lineTo(x1, 48)
                            ctx.lineTo(x1 - Math.min(6, (x1 - x0) / 3), 70)
                            ctx.lineTo(x0 + Math.min(6, (x1 - x0) / 3), 70); ctx.lineTo(x0, 48)
                            ctx.closePath(); ctx.fill()
                            ctx.strokeStyle = "#1C1917"; ctx.lineWidth = 1; ctx.stroke()
                            if (x1 - x0 > 16) { ctx.fillStyle = "#1C1917"; ctx.fillText(fmt(s.w), (x0 + x1) / 2, 40) }
                        }
                        // Dies: block with a V notch on top
                        for (var j = 0; j < pan.die.length; ++j) {
                            var d = pan.die[j], d0 = X(d.x) + 0.5, d1 = X(d.x + d.w) - 0.5
                            var keepD = same(d, pan.otherD)
                            ctx.fillStyle = keepD ? "#78716C" : pan.hot
                            ctx.fillRect(d0, 92, d1 - d0, 36)
                            ctx.strokeStyle = "#1C1917"; ctx.strokeRect(d0, 92, d1 - d0, 36)
                            ctx.strokeStyle = "#1C1917"; ctx.beginPath()
                            ctx.moveTo(d0, 96); ctx.lineTo(d1, 96); ctx.stroke()
                            if (d1 - d0 > 16) { ctx.fillStyle = "#1C1917"; ctx.fillText(fmt(d.w), (d0 + d1) / 2, 112) }
                        }
                        // Machine centerline
                        if (0 >= minX && 0 <= minX + span + 2 * margin) {
                            ctx.strokeStyle = "#FBBF24"; ctx.setLineDash([3, 3]); ctx.beginPath()
                            ctx.moveTo(X(0), 18); ctx.lineTo(X(0), 136); ctx.stroke(); ctx.setLineDash([])
                            ctx.fillStyle = "#FBBF24"; ctx.fillText("\u2104", X(0), 81)
                        }
                        // Stack extents relative to center
                        var ext = function(list) {
                            if (!list.length) return ""
                            var a = list[0].x, b = list[list.length - 1].x + list[list.length - 1].w
                            return fmt(a) + " \u2026 " + fmt(b)
                        }
                        ctx.fillStyle = "#D6D3D1"
                        ctx.textAlign = "right"
                        ctx.fillText("P " + ext(pan.punch) + "   D " + ext(pan.die), ox + panelW - 10, 9)
                        ctx.textAlign = "center"
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -12
                    color: "#A8A29E"; font.pixelSize: 9
                    text: "red = remove · green = install · grey = stays · positions from machine center (\u2104), "
                          + (toolLayout.metric ? "mm" : "in")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    objectName: "run-tool-change-jog-down"
                    visible: toolChangePanel.tcState === "AWAIT_TOUCH" || toolChangePanel.tcState === "TOUCH"
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 38
                    radius: 5
                    color: jogDownMouse.pressed ? "#7F1D1D" : "#B91C1C"
                    Text { anchors.centerIn: parent; text: "\u2193 HOLD JOG DOWN"; color: "white"; font.bold: true; font.pixelSize: 12 }
                    MouseArea {
                        id: jogDownMouse
                        anchors.fill: parent
                        onPressed: if (appState) appState.runToolChangeJogDown(true)
                        onReleased: if (appState) appState.runToolChangeJogDown(false)
                        onCanceled: if (appState) appState.runToolChangeJogDown(false)
                    }
                }

                Rectangle {
                    objectName: "run-tool-change-removed"
                    visible: toolChangePanel.tcState === "AWAIT_TOOLING_REMOVED"
                    Layout.preferredWidth: 170
                    Layout.preferredHeight: 38
                    radius: 5
                    color: removedMouse.pressed ? "#14532D" : "#16A34A"
                    Text { anchors.centerIn: parent; text: "TOOLING REMOVED"; color: "white"; font.bold: true; font.pixelSize: 12 }
                    MouseArea { id: removedMouse; anchors.fill: parent; onClicked: if (appState) appState.runToolChangeToolingRemoved() }
                }

                Rectangle {
                    objectName: "run-tool-change-seat-again"
                    visible: !!appState && appState.toolChangeSeatAgainAvailable && !appState.runToolChangeActive
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 38
                    radius: 5
                    color: seatAgainMouse.pressed ? "#1E3A8A" : "#2563EB"
                    Text { anchors.centerIn: parent; text: "SEAT AGAIN"; color: "white"; font.bold: true; font.pixelSize: 12 }
                    MouseArea { id: seatAgainMouse; anchors.fill: parent; onClicked: if (appState) appState.runToolChangeSeatAgain() }
                }

                Item { Layout.fillWidth: true }

                Text { text: "BACKOFF"; color: "#A8A29E"; font.bold: true; font.pixelSize: 11 }
                Repeater {
                    model: [0.125, 0.25]
                    Rectangle {
                        required property var modelData
                        readonly property bool chosen: !!appState && Math.abs(appState.toolChangeBackoff - modelData) < 1e-9
                        readonly property bool editable: toolChangePanel.tcState === "AWAIT_TOUCH" || toolChangePanel.tcState === "IDLE"
                        Layout.preferredWidth: 62
                        Layout.preferredHeight: 30
                        radius: 4
                        opacity: editable ? 1.0 : 0.5
                        color: chosen ? "#F59E0B" : "#292524"
                        border.color: "#57534E"
                        Text { anchors.centerIn: parent; text: appState && appState.metricUnits ? (Number(modelData) * 25.4).toFixed(2) : Number(modelData).toFixed(3); color: parent.chosen ? "#1C1917" : "white"; font.bold: true; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; enabled: parent.editable; onClicked: appState.setToolChangeBackoff(modelData) }
                    }
                }
            }
        }
    }
}
