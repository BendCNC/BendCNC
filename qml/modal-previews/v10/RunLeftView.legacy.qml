import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../.." as Production
import "../.."


Item {
    id: root
    property var appState: null
    property var dataStore: null
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
    readonly property string iconRoot: "../../icons/"
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

            ComboField { Layout.fillWidth: true; Layout.columnSpan: 2; visible: appState ? !appState.runProgramEditing : true; text: appState ? appState.activeProgram : "Enclosure Box - Electronics Module"; programs: appState ? appState.programs : []; selectedIndex: appState ? appState.selectedProgramIndex : 0; onProgramSelected: function(index) { if (appState) appState.selectProgram(index) } }
            ProgramNameField { id: programNameEditor; objectName: "run-program-name-field"; Layout.fillWidth: true; Layout.columnSpan: 2; visible: appState ? appState.runProgramEditing : false; text: appState ? appState.runProgramNameDraft : "UNTITLED PROGRAM"; onTextEdited: function(value) { if (appState) appState.runProgramNameDraft = value } }
            IconButton { Layout.preferredWidth: 35; iconSource: root.iconRoot + "fa-pen.svg"; base: "white"; glyphColor: ink; borderColor: ink; visible: appState ? !appState.runProgramEditing : true; onClicked: root.beginProgramNameEdit() }
            IconButton { Layout.preferredWidth: 35; iconSource: root.iconRoot + "fa-trash.svg"; base: red; glyphColor: "white"; visible: appState ? !appState.runProgramEditing : true; onClicked: if (appState) appState.runAction("delete") }
            IconButton { Layout.preferredWidth: 35; iconSource: root.iconRoot + "fa-times.svg"; base: red; glyphColor: "white"; visible: appState ? appState.runProgramEditing : false; onClicked: if (appState) appState.runAction("cancel") }
            TextButton { Layout.preferredWidth: 94; iconSource: root.iconRoot + "fa-file-white.svg"; label: "NEW"; base: blue; onClicked: if (appState) appState.runAction("new") }
            TextButton { Layout.preferredWidth: 82; iconSource: root.iconRoot + "fa-save.svg"; label: "SAVE"; base: green; onClicked: if (appState) appState.runAction("save") }
            TextButton { Layout.preferredWidth: 116; iconSource: root.iconRoot + "fa-file-white.svg"; label: "DUPLICATE"; base: "orange"; onClicked: if (appState) appState.runAction("duplicate") }
        }

        Rectangle {
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
                spacing: 0

                Rectangle {
                    id: activeRunHeader
                    objectName: "active-run-header"
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 68 : 0
                    visible: appState ? appState.runActive : false
                    color: "#1f2328"
                    border.color: green
                    border.width: 2
                    radius: 5

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 10
                            Layout.fillHeight: true
                            Layout.topMargin: 8
                            Layout.bottomMargin: 8
                            color: green
                            radius: 3
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: appState ? qsTr("LIVE RUN — %1").arg(appState.activeProgram) : qsTr("LIVE RUN")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 16
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: appState
                                    ? qsTr("BEND %1 OF %2 · %3").arg(appState.selectedRunBend + 1)
                                        .arg(appState.programBends.length).arg(appState.runProgressSubtitle)
                                    : qsTr("BEND 1 OF 1")
                                color: "#d7d7d7"
                                font.bold: true
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            objectName: "run-operator-prompt"
                            Layout.preferredWidth: Math.min(430, activeRunHeader.width * 0.48)
                            Layout.fillHeight: true
                            text: appState ? appState.runOperatorPrompt() : qsTr("STARTING")
                            color: "#00f0ff"
                            font.bold: true
                            font.pixelSize: 20
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                        }
                    }
                }

                Rectangle {
                    id: dwellNotice
                    objectName: "physical-run-dwell-notice"
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 126 : 0
                    visible: appState && appState.runActive
                        && appState.executionPhase === "DWELL_TIMER_WAIT"
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
                        Text { Layout.fillWidth: true; text: appState && appState.dwellPausedForPedal ? qsTr("DWELL PAUSED. PRESS AND HOLD THE FOOT PEDAL TO CONTINUE THIS RUN.") : qsTr("RELEASING THE FOOT PEDAL PAUSES THE COUNTDOWN; IT DOES NOT CANCEL THE RUN."); color: "#5a3600"; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 37
                    radius: 7
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
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        spacing: 6
                        SimButton { Layout.preferredWidth: 70; label: appState && appState.runBendListVisible ? "▲ LIST" : "▼ LIST"; base: blue; onClicked: if (appState) appState.runSimulationAction("toggle-list") }
                        SimButton { Layout.preferredWidth: 29; label: "◀"; base: grey; enabledState: appState ? appState.selectedRunBend > 0 : false; onClicked: if (appState) appState.runSimulationAction("previous") }
                        SimButton { Layout.preferredWidth: 29; label: "▶"; base: grey; enabledState: appState ? appState.selectedRunBend < appState.programBends.length - 1 : false; onClicked: if (appState) appState.runSimulationAction("next") }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { Layout.fillWidth: true; text: appState ? appState.runSimulationHeader1() : "NO BENDS"; color: "#eaeaea"; font.bold: true; font.pixelSize: 11; elide: Text.ElideLeft }
                            Text { Layout.fillWidth: true; text: appState ? appState.runSimulationHeader2() : "Select or create a bend program"; color: "#f2b766"; font.bold: true; font.pixelSize: 10; elide: Text.ElideRight }
                        }
                        SimButton { Layout.preferredWidth: 86; label: "PLACEMENT"; base: appState && appState.runSceneMode === "PLACEMENT" ? blue : grey; onClicked: if (appState) appState.runSimulationAction("placement") }
                        SimButton { Layout.preferredWidth: 58; label: "LIVE"; base: appState && appState.runSceneMode === "LIVE" ? blue : grey; onClicked: if (appState) appState.runSimulationAction("live") }
                        LiveViewMenu { Layout.preferredWidth: 64; visible: appState && appState.runSceneMode === "LIVE"; mode: appState ? appState.runLiveProjectionMode : "SIDE"; onModeRequested: function(mode) { if (appState) appState.setRunLiveProjectionMode(mode) } }
                        SimButton { Layout.preferredWidth: 78; label: appState && appState.runSimulatedRun ? "STOP DEMO" : "SIM RUN"; base: appState && appState.runSimulatedRun ? green : grey; onClicked: if (appState) appState.runSimulationAction("sim-run") }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 0
                    color: lightGrey
                    border.color: ink
                    border.width: 1
                    RunExecutionCanvas { id: modernRunCanvas; anchors.fill: parent; visible: !root.designerBlankCanvas; sceneMode: appState ? appState.runSceneMode : "PLACEMENT"; liveProjectionMode: appState ? appState.runLiveProjectionMode : "SIDE"; liveCameraOrientation: appState ? appState.runLiveCameraOrientation : "ISO_TOP_LEFT"; liveStatusCardVisible: !(appState && appState.runSceneMode === "LIVE" && appState.runLiveProjectionMode === "ISOMETRIC"); toolingAppearance: appState ? appState.runToolingAppearance : "SOLID"; guides: appState ? appState.runShowMachineGuides : false; running: appState ? appState.runSimulatedRun || appState.runActive : false; simulatedPlayback: appState ? appState.runSimulatedRun : false; physicalTelemetryFresh: appState && appState.machineControl ? appState.machineControl.pressTelemetryFresh : false; physicalExecutionPhase: appState ? appState.executionPhase : ""; physicalPressState: appState ? appState.machineStatus : "UNKNOWN"; physicalRamPosition: appState ? appState.ramPosition : 0; physicalBackGaugeX: appState ? appState.backGaugeX : 0; physicalBackGaugeR: appState ? appState.backGaugeR : 0; backGaugeEnabled: appState ? appState.runBendUsesBackGauge() : true; backGaugeRetractDistanceIn: appState ? appState.backGaugeRetractBetweenBendsInch : 2.0; backGaugeBumpOffDistanceIn: appState ? appState.backGaugeBumpOffDistanceInch : 0.25; autoClampDwellSeconds: appState && appState.autoClampToBendEnabled ? appState.autoClampDwellSec : 0; physicalStartPosition: appState ? appState.runRamTarget("startPosition") : NaN; physicalClampPosition: appState ? appState.runRamTarget("clampPosition") : NaN; physicalFinalPosition: appState ? appState.runRamTarget("finalPosition") : NaN; label: appState && appState.runActive ? appState.runProgressTitle : (appState ? appState.runSimulationHeader1() : "NO BENDS"); detail: appState && appState.runActive ? appState.runOperatorPrompt() : (appState ? appState.runSimulationHeader2() : ""); programName: appState ? appState.activeProgram : ""; programPreviewJson: appState ? appState.activeProgramCadPreviewJson : ""; selectedBendIndex: appState ? appState.selectedRunBend : 0; selectedBend: appState ? appState.selectedBend : ({}); punchCatalog: dataStore ? dataStore.punches : []; dieCatalog: dataStore ? dataStore.dies : []; punchCoverageSideToleranceIn: appState ? appState.punchCoverageSideToleranceIn : 0; runDebugLogPath: root.runDebugLogPath; runDebugLogsEnabled: appState ? appState.runPreviewDebugLogsEnabled : false; runDebugOverlaysEnabled: appState ? appState.runPreviewDebugOverlaysEnabled : false; runCadenceDebug: Qt.application.arguments.indexOf("--run-cadence-debug") !== -1; flatPatternContourRenderer: appState ? appState.runFlatPatternContourRenderer : "classic" }
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
                    LiveIsometricViewCube {
                        objectName: "live-isometric-view-cube"
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 12
                        anchors.topMargin: 12
                        z: 4
                        visible: appState && appState.runSceneMode === "LIVE"
                            && appState.runLiveProjectionMode === "ISOMETRIC"
                        orientation: appState ? appState.runLiveCameraOrientation : "ISO_TOP_LEFT"
                        onOrientationRequested: function(orientation) {
                            if (appState)
                                appState.setRunLiveCameraOrientation(orientation)
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
                    ColumnLayout {
                        visible: appState ? appState.runBendListVisible : false
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 0
                        spacing: 0
                        z: 5
                        Repeater {
                            model: appState ? appState.programBends : []
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 29
                                color: appState && appState.selectedRunBend === index ? "#00f0ff" : charcoal
                                readonly property var bend: modelData
                                readonly property bool completed: appState ? Number(bend.seq || index + 1) < Number(appState.selectedBend.seq || appState.selectedRunBend + 1) : false
                                Text { anchors.fill: parent; anchors.leftMargin: 8; verticalAlignment: Text.AlignVCenter; text: (appState && appState.selectedRunBend === index ? "▶" : (completed ? "✓" : " ")) + "  B" + String(index + 1) + "/" + String(appState ? appState.programBends.length : 0) + "  |  " + (bend.angle || "90.0") + "°  |  " + (appState ? appState.compactPunchName(bend.punch) : "PUNCH") + "  |  " + (appState ? appState.compactDieName(bend.die) : "DIE") + "  |  X:" + (bend.x || "0.0000") + "\"  |  " + (appState ? appState.runBendDirection(bend) : "UP"); color: appState && appState.selectedRunBend === index ? "#121212" : (completed ? "#00cc66" : "#eaeaea"); font.bold: true; font.pixelSize: 11; elide: Text.ElideRight }
                                MouseArea { anchors.fill: parent; onClicked: { if (appState) { appState.selectRunBend(index); appState.runBendListVisible = false } } }
                            }
                        }
                        SimButton { Layout.fillWidth: true; Layout.preferredHeight: 29; label: "+ ADD BEND"; base: "orange"; onClicked: if (appState) { appState.runBendListVisible = false; appState.openAddBendPopup(dataStore.bends, dataStore.punches, dataStore.dies, dataStore.materials) } }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 0
                        spacing: 6
                        SimInfoButton {
                            Layout.preferredWidth: 32
                            Layout.fillHeight: true
                            active: root.sceneInfoActive
                            onClicked: root.toggleSceneInfo()
                        }
                        // United DRO-style Axis Panel for START, CLAMP, FINAL, RETRACT
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            Row {
                                anchors.fill: parent
                                spacing: 0
                                clip: true

                                // 1. START (Cyan #0E7490) - Rounded Left
                                Item {
                                    width: Math.floor(parent.width / 4)
                                    height: parent.height
                                    clip: true

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: parent.width + 6
                                        color: "#0E7490"
                                        radius: 6
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 46
                                            height: 18
                                            radius: 3
                                            color: "#083344"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "START"
                                                color: "#38BDF8"
                                                font.bold: true
                                                font.pixelSize: 9
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: appState ? appState.runRamTargetText("startPosition", " in") : "UNAVAILABLE"
                                            color: "white"
                                            font.bold: true
                                            font.pixelSize: text === "UNAVAILABLE" ? 10 : 15
                                            font.family: "Segoe UI, monospace"
                                        }
                                    }
                                }

                                // 2. CLAMP (Amber #C25E00) - Square Middle
                                Item {
                                    width: Math.floor(parent.width / 4)
                                    height: parent.height
                                    clip: true

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#C25E00"
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 46
                                            height: 18
                                            radius: 3
                                            color: "#451A03"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "CLAMP"
                                                color: "#FBBF24"
                                                font.bold: true
                                                font.pixelSize: 9
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: appState ? appState.runRamTargetText("clampPosition", " in") : "UNAVAILABLE"
                                            color: "white"
                                            font.bold: true
                                            font.pixelSize: text === "UNAVAILABLE" ? 10 : 15
                                            font.family: "Segoe UI, monospace"
                                        }
                                    }
                                }

                                // 3. FINAL (Green #166534) - Square Middle
                                Item {
                                    width: Math.floor(parent.width / 4)
                                    height: parent.height
                                    clip: true

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#166534"
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 46
                                            height: 18
                                            radius: 3
                                            color: "#052E16"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "FINAL"
                                                color: "#4ADE80"
                                                font.bold: true
                                                font.pixelSize: 9
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: appState ? appState.runRamTargetText("finalPosition", " in") : "UNAVAILABLE"
                                            color: "white"
                                            font.bold: true
                                            font.pixelSize: text === "UNAVAILABLE" ? 10 : 15
                                            font.family: "Segoe UI, monospace"
                                        }
                                    }
                                }

                                // 4. RETRACT (Purple #6D28D9) - Rounded Right
                                Item {
                                    width: parent.width - Math.floor(parent.width / 4) * 3
                                    height: parent.height
                                    clip: true

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: parent.width + 6
                                        color: "#6D28D9"
                                        radius: 6
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 48
                                            height: 18
                                            radius: 3
                                            color: "#2E1065"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "RETRACT"
                                                color: "#C4B5FD"
                                                font.bold: true
                                                font.pixelSize: 8
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: appState ? appState.runRamTargetText("retractPosition", " in") : "UNAVAILABLE"
                                            color: "white"
                                            font.bold: true
                                            font.pixelSize: text === "UNAVAILABLE" ? 10 : 15
                                            font.family: "Segoe UI, monospace"
                                        }
                                    }
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
                            Text { Layout.fillWidth: true; text: appState && appState.dwellPausedForPedal ? qsTr("DWELL PAUSED. PRESS AND HOLD THE FOOT PEDAL TO CONTINUE THIS RUN.") : qsTr("RELEASING THE FOOT PEDAL PAUSES THE COUNTDOWN; IT DOES NOT CANCEL THE RUN."); color: "#5a3600"; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
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
                                RunExecutionCanvas { anchors.fill: parent; sceneMode: root.legacyRunVisible ? "LIVE" : "PLACEMENT"; liveProjectionMode: appState ? appState.runLiveProjectionMode : "SIDE"; liveCameraOrientation: appState ? appState.runLiveCameraOrientation : "ISO_TOP_LEFT"; toolingAppearance: appState ? appState.runToolingAppearance : "SOLID"; running: root.legacyRunVisible && appState ? appState.runActive : false; guides: root.legacyRunVisible; label: "SIDE VIEW"; detail: appState && appState.selectedBend.angle ? appState.selectedBend.angle + "° bend" : "90.0° bend"; programName: root.legacyRunVisible && appState ? appState.activeProgram : ""; programPreviewJson: root.legacyRunVisible && appState ? appState.activeProgramCadPreviewJson : ""; selectedBendIndex: root.legacyRunVisible && appState ? appState.selectedRunBend : 0; selectedBend: root.legacyRunVisible && appState ? appState.selectedBend : ({}); punchCatalog: dataStore ? dataStore.punches : []; dieCatalog: dataStore ? dataStore.dies : []; runDebugLogPath: root.runDebugLogPath; runDebugLogsEnabled: appState ? appState.runPreviewDebugLogsEnabled : false; runDebugOverlaysEnabled: appState ? appState.runPreviewDebugOverlaysEnabled : true; flatPatternContourRenderer: appState ? appState.runFlatPatternContourRenderer : "classic" }
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
                            ExecutionBackGaugeCard { Layout.fillWidth: true; Layout.preferredHeight: 82; xValue: appState ? (appState.selectedBend.x || "0.0000") : "0.0000"; rValue: appState ? (appState.selectedBend.r || "0.0000") : "0.0000"; speedValue: appState ? (appState.selectedBend.speed || "100.000") : "100.000" }
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

        RowLayout {
            id: bottomRowLayout
            z: 100
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            Layout.leftMargin: 7
            Layout.rightMargin: 7
            Layout.bottomMargin: 7
            Layout.topMargin: 4
            spacing: 6

            ActionRun {
                Layout.fillWidth: true
                Layout.preferredWidth: 260
                active: appState ? appState.runActive : false
                allowed: appState ? appState.runProgramAllowed : false
                grayed: appState ? appState.runProgramGrayed : false
                onClicked: if (appState) appState.runAction("run")
            }
            AutoClamp {
                id: autoClampControl
                objectName: "auto-clamp-to-bend-control"
                Layout.preferredWidth: 175
                active: appState ? appState.autoClampEnabled : false
                enabledState: appState ? appState.machineStatus !== "JOGGING"
                    && !(appState.machineControl && appState.machineControl.pressOperationActive) : false
                onClicked: if (appState) appState.runAction("auto-clamp")
            }
            DwellTile {
                objectName: "dwell-toggle-tile"
                Layout.preferredWidth: 175
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
            BendMode {
                id: bendModeControl
                objectName: "bendModeControl"
                Layout.preferredWidth: 220
                mode: appState ? appState.bendMode : "PROGRAM_BEND_MODE"
                popupOpen: appState ? appState.bendModePopupVisible : false
                multipleBends: appState ? appState.multipleBendsProgram : false
                enabledState: appState ? appState.runProgramAllowed : false
                onClicked: if (appState) appState.runAction("bend-mode")
                onModeRequested: function(mode) { if (appState) appState.setBendMode(mode) }
                onPopupDismissed: if (appState) appState.bendModePopupVisible = false
            }
        }
    }

    // Click-outside dismisser for BendMode popup selector across the entire left panel
    MouseArea {
        anchors.fill: parent
        z: 90
        visible: bendModeControl.popupOpen
        onClicked: {
            bendModeControl.popupDismissed()
        }
    }

    // Click-outside dismisser covering sibling buttons on the bottom row
    MouseArea {
        x: bottomRowLayout.x
        y: bottomRowLayout.y
        width: Math.max(0, bottomRowLayout.width - bendModeControl.width)
        height: bottomRowLayout.height
        z: 150
        visible: bendModeControl.popupOpen
        onClicked: {
            bendModeControl.popupDismissed()
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
                                            font.pixelSize: 10
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
                                        font.pixelSize: 10
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

                                    // All Clear Badge when no warnings apply
                                    Rectangle {
                                        visible: appState ? (!appState.bendModeIsRepeatable() && !appState.selectedBendNotTopMostWarning) : true
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
        Text { id: compatibilityBadgeText; anchors.centerIn: parent; text: parent.label; color: "white"; font.bold: true; font.pixelSize: 10 }
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

            BackGaugePanel { Layout.preferredWidth: 205; Layout.preferredHeight: 82; xValue: bendCellRoot.xValue; rValue: bendCellRoot.rValue; speedValue: bendCellRoot.speedValue }
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
        property string xValue: "-1.0000"
        property string rValue: "0.0000"
        property string speedValue: "100.000"
        radius: 4
        color: lightGrey
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            Rectangle { Layout.fillWidth: true; height: 25; radius: 4; color: charcoal; Text { anchors.centerIn: parent; text: "BACKGAUGE FINGER LOWER EDGE"; color: "white"; font.bold: true; font.pixelSize: 10 } }
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 3
                columnSpacing: 0
                Text { text: "X"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: "R"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: "SPEED"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: xValue + "\nIn"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: rValue + "\nIn"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Text { text: speedValue + "\nIPM"; color: ink; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
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
            Rectangle { Layout.fillWidth: true; height: 25; radius: 4; color: charcoal; Text { anchors.centerIn: parent; text: "RAM LOAD"; color: "white"; font.bold: true; font.pixelSize: 10 } }
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
        signal clicked()
        property string label: ""
        property color base: grey
        property bool enabledState: true
        height: 29
        radius: 4
        color: enabledState ? base : "#737373"
        opacity: enabledState ? 1.0 : 0.45
        Text { anchors.centerIn: parent; text: label; color: "white"; font.bold: true; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
        MouseArea { anchors.fill: parent; enabled: parent.enabledState; onClicked: parent.clicked() }
    }

    component LiveViewMenu: Rectangle {
        id: liveViewMenuRoot
        signal modeRequested(string mode)
        property string mode: "SIDE"
        height: 29
        radius: 4
        color: blue
        border.color: "#83c7e8"
        border.width: activeFocus ? 2 : 0
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("LIVE view: %1").arg(mode === "ISOMETRIC" ? qsTr("Isometric") : qsTr("Side"))
        Text {
            anchors.centerIn: parent
            text: (liveViewMenuRoot.mode === "ISOMETRIC" ? qsTr("ISO") : qsTr("SIDE")) + "  ▼"
            color: "white"
            font.bold: true
            font.pixelSize: 9
        }
        MouseArea { anchors.fill: parent; onClicked: liveProjectionMenu.open() }
        Keys.onSpacePressed: liveProjectionMenu.open()
        Keys.onReturnPressed: liveProjectionMenu.open()
        Menu {
            id: liveProjectionMenu
            y: liveViewMenuRoot.height + 1
            width: Math.max(150, liveViewMenuRoot.width)
            MenuItem {
                text: (liveViewMenuRoot.mode === "SIDE" ? "✓  " : "   ") + qsTr("Side view")
                onTriggered: liveViewMenuRoot.modeRequested("SIDE")
            }
            MenuItem {
                text: (liveViewMenuRoot.mode === "ISOMETRIC" ? "✓  " : "   ") + qsTr("Isometric view")
                onTriggered: liveViewMenuRoot.modeRequested("ISOMETRIC")
            }
        }
    }

    component SimInfoButton: Rectangle {
        signal clicked()
        property bool active: false
        radius: 5
        color: active ? "#64748B" : "#475569"
        border.color: active ? "#94A3B8" : "#64748B"
        border.width: 1
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: 1; color: "#30FFFFFF"
        }
        Text {
            anchors.centerIn: parent
            text: "ⓘ"
            color: active ? "#38BDF8" : "#FFFFFF"
            font.bold: true
            font.pixelSize: 16
        }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    component SimMetric: Rectangle {
        property string badge: ""
        property color badgeBg: "#083344"
        property color badgeFg: "#38BDF8"
        property color baseColor: "#0E7490"
        property string value: ""
        radius: 5
        color: baseColor

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 8
            spacing: 4

            Rectangle {
                Layout.preferredWidth: badge.length > 5 ? 48 : 46
                Layout.preferredHeight: 18
                radius: 3
                color: badgeBg
                Text {
                    anchors.centerIn: parent
                    text: badge
                    color: badgeFg
                    font.bold: true
                    font.pixelSize: badge.length > 5 ? 8 : 9
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: value
                color: "white"
                font.bold: true
                font.pixelSize: value === "UNAVAILABLE" ? 10 : 16
                font.family: "Segoe UI, monospace"
            }
        }
    }

    component ActionRun: Rectangle {
        id: actionRunRoot
        signal clicked()
        property bool active: false
        property bool allowed: true
        property bool grayed: false
        height: 64
        radius: 8
        color: active ? "#B91C1C" : (!allowed || grayed ? grey : "#15803D")
        border.color: active ? "#DC2626" : (!allowed || grayed ? "#8E8E8E" : "#22C55E")
        border.width: 1.5

        scale: actionRunMouseArea.pressed ? 0.96 : (actionRunMouseArea.containsMouse ? 1.01 : 1.0)
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

        // Centered lockup: Icon Pod + Bold Title
        Row {
            anchors.centerIn: parent
            spacing: 12

            Rectangle {
                width: 38
                height: 38
                radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: "#30000000"
                Text {
                    anchors.centerIn: parent
                    text: actionRunRoot.active ? "■" : "▶"
                    color: "white"
                    font.bold: true
                    font.pixelSize: actionRunRoot.active ? 18 : 20
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: actionRunRoot.active ? qsTr("STOP PROGRAM") : qsTr("RUN PROGRAM")
                color: "white"
                font.bold: true
                font.pixelSize: 16
                font.letterSpacing: 0.5
            }

            Text {
                visible: !actionRunRoot.allowed
                text: "!"
                color: "#FCA5A5"
                font.bold: true
                font.pixelSize: 20
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: actionRunMouseArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.allowed && !parent.grayed
            onClicked: parent.clicked()
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
                        Text { anchors.left: parent.left; anchors.right: parent.right; anchors.top: circle.bottom; anchors.topMargin: 2; height: 24; text: stepNames[index]; color: grey; font.bold: true; font.pixelSize: 9; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignTop; wrapMode: Text.WordWrap; maximumLineCount: 2 }
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
                Text { anchors.centerIn: parent; text: label + "\n" + gaugeX + " in"; color: ink; font.bold: true; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter }
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
            Text { text: "X"; color: charcoal; font.bold: true; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: "R"; color: charcoal; font.bold: true; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: "SPEED"; color: charcoal; font.bold: true; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: xValue + "\nIn"; color: ink; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: rValue + "\nIn"; color: ink; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: speedValue + "\nIPM"; color: ink; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
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

    component AutoClamp: Rectangle {
        id: autoClampRoot
        signal clicked()
        property bool active: false
        property bool enabledState: true
        readonly property string labelText: qsTr("AUTO CLAMP TO BEND")
        height: 64
        radius: 8
        color: active ? "#0E7490" : "#334155"
        border.color: active ? "#155E75" : "#1E293B"
        border.width: 1.5
        opacity: enabledState ? 1.0 : 0.55

        scale: autoClampMouseArea.pressed ? 0.96 : (autoClampMouseArea.containsMouse ? 1.01 : 1.0)
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

        // 3D tactile bevels
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 2; radius: 8; color: "#25FFFFFF" }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 2; radius: 8; color: "#35000000" }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            // Machined icon pod
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 18
                color: "#25000000"
                border.color: "#30000000"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: autoClampRoot.active ? "✓" : "—"
                    color: autoClampRoot.active ? "#67E8F9" : "#94A3B8"
                    font.bold: true
                    font.pixelSize: 18
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: autoClampRoot.labelText
                        color: "white"
                        font.bold: true
                        font.pixelSize: 12
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 16
                        radius: 4
                        color: autoClampRoot.active ? "#155E75" : "#1E293B"
                        Text {
                            anchors.centerIn: parent
                            text: autoClampRoot.active ? "ON" : "OFF"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 9
                        }
                    }
                }

                Text {
                    text: autoClampRoot.active ? qsTr("CLAMP TO BEND") : qsTr("PEDAL CONTROL")
                    color: autoClampRoot.active ? "#CFFAFE" : "#94A3B8"
                    font.pixelSize: 10
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
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

    component DwellTile: Rectangle {
        id: dwellRoot
        signal clicked()
        signal longPressed()
        property bool dwellActive: true
        property real dwell: 3.0
        property bool enabledState: true
        readonly property string labelText: qsTr("DWELL")
        height: 64
        radius: 8
        color: dwellActive ? "#C25E00" : "#334155"
        border.color: dwellActive ? "#8C4300" : "#1E293B"
        border.width: 1.5
        opacity: enabledState ? 1.0 : 0.55

        scale: dwellMouseArea.pressed ? 0.96 : (dwellMouseArea.containsMouse ? 1.01 : 1.0)
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

        // 3D tactile bevels
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 2; radius: 8; color: "#25FFFFFF" }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 2; radius: 8; color: "#35000000" }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            // Machined icon pod
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 18
                color: "#25000000"
                border.color: "#30000000"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: dwellRoot.dwellActive ? "⏱" : "—"
                    color: dwellRoot.dwellActive ? "#FDE047" : "#94A3B8"
                    font.bold: true
                    font.pixelSize: 16
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: dwellRoot.labelText
                        color: "white"
                        font.bold: true
                        font.pixelSize: 12
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 16
                        radius: 4
                        color: dwellRoot.dwellActive ? "#8C4300" : "#1E293B"
                        Text {
                            anchors.centerIn: parent
                            text: dwellRoot.dwellActive ? "ON" : "OFF"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 9
                        }
                    }
                }

                Text {
                    text: dwellRoot.dwellActive ? dwellRoot.dwell.toFixed(1) + "s " + qsTr("DELAY") : qsTr("NO DELAY")
                    color: dwellRoot.dwellActive ? "#FEF3C7" : "#94A3B8"
                    font.pixelSize: 10
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            id: dwellMouseArea
            anchors.fill: parent
            hoverEnabled: true
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

    component BendMode: Item {
        id: bendModeRoot
        signal clicked()
        signal modeRequested(string mode)
        signal popupDismissed()
        property string mode: "PROGRAM_BEND_MODE"
        readonly property string modeText: mode === "SINGLE_BEND_MODE" ? qsTr("SINGLE BEND MODE") : mode === "SINGLE_BEND_REPEAT" ? qsTr("SINGLE BEND REPEAT") : mode === "PROGRAM_BEND_LOOP" ? qsTr("PROGRAM BEND LOOP") : qsTr("PROGRAM BEND MODE")
        readonly property string modeDetail: mode === "SINGLE_BEND_MODE" ? qsTr("RUN CURRENT BEND ONCE") : mode === "SINGLE_BEND_REPEAT" ? qsTr("REPEAT CURRENT BEND") : mode === "PROGRAM_BEND_LOOP" ? qsTr("REPEAT FULL SEQUENCE") : qsTr("RUN FULL SEQUENCE ONCE")
        readonly property color modeColor: mode === "SINGLE_BEND_MODE" ? "#10B981"
            : mode === "SINGLE_BEND_REPEAT" ? "#0284C7"
            : mode === "PROGRAM_BEND_LOOP" ? "#8B5CF6" : "#991B1B"
        readonly property color modeBorderColor: mode === "SINGLE_BEND_MODE" ? "#059669"
            : mode === "SINGLE_BEND_REPEAT" ? "#0369A1"
            : mode === "PROGRAM_BEND_LOOP" ? "#7C3AED" : "#EF4444"

        property bool popupOpen: false
        property bool multipleBends: false
        property bool enabledState: true

        height: 64

        // Button Card with self-contained tactile press/hover animation
        // (Scales visual card only; does NOT scale parent Item coordinate origin)
        Rectangle {
            id: buttonCard
            anchors.fill: parent
            radius: 8
            color: bendModeRoot.modeColor
            border.color: bendModeRoot.modeBorderColor
            border.width: 1.5
            opacity: bendModeRoot.enabledState ? 1.0 : 0.55

            scale: bendModeMouseArea.pressed ? 0.96 : (bendModeMouseArea.containsMouse ? 1.01 : 1.0)
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 9
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: bendModeRoot.modeText
                        color: "white"
                        font.bold: true
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: bendModeRoot.modeDetail
                        color: bendModeRoot.mode === "SINGLE_BEND_MODE" ? "#A7F3D0" : bendModeRoot.mode === "SINGLE_BEND_REPEAT" ? "#BAE6FD" : bendModeRoot.mode === "PROGRAM_BEND_LOOP" ? "#DDD6FE" : "#FCA5A5"
                        font.bold: true
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 14
                    color: "#30FFFFFF"

                    Text {
                        anchors.centerIn: parent
                        text: "▲"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 11
                        rotation: bendModeRoot.popupOpen ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        MouseArea {
            id: bendModeMouseArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: bendModeRoot.enabledState
            onClicked: {
                bendModeRoot.clicked()
            }
        }

        // =====================================================================
        // UPWARD EXTENDING POPUP SELECTOR (SELECTOR A: PRECISION CAD DOCK)
        // Stays natively inside RunLeftView: zero jumping, zero edge collision
        // =====================================================================
        Item {
            id: contentPopup
            anchors.bottom: parent.top
            anchors.bottomMargin: 8
            anchors.right: parent.right
            width: 260
            height: bendModeRoot.multipleBends ? 251 : 141
            z: 2000
            visible: opacity > 0.001
            opacity: bendModeRoot.popupOpen ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            // Consume clicks inside popup background so they don't hit underlying elements
            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "#0B0F17"
                border.color: bendModeRoot.modeBorderColor
                border.width: 1.5

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: 12
                    color: "transparent"
                    border.color: "#30000000"
                    border.width: 2
                    z: -1
                }
            }

            Column {
                id: optionColumn
                width: parent.width
                spacing: 5
                topPadding: 8
                bottomPadding: 8

                // Header Bar
                RowLayout {
                    width: parent.width - 16
                    x: 8
                    spacing: 6
                    Rectangle { width: 4; height: 12; radius: 2; color: bendModeRoot.modeBorderColor }
                    Text {
                        text: qsTr("CYCLE SELECTOR")
                        color: "#94A3B8"
                        font.bold: true
                        font.pixelSize: 9
                        font.letterSpacing: 0.8
                        Layout.fillWidth: true
                    }
                    Text {
                        text: qsTr("CYCLE MODE")
                        color: "#64748B"
                        font.bold: true
                        font.pixelSize: 8
                    }
                }

                Rectangle {
                    width: parent.width - 16
                    x: 8
                    height: 1
                    color: "#1E293B"
                }

                ModeOption {
                    badge: "1"
                    label: qsTr("SINGLE BEND")
                    detail: qsTr("Executes current bend and stops")
                    selected: bendModeRoot.mode === "SINGLE_BEND_MODE"
                    accent: "#10B981"
                    onClicked: {
                        bendModeRoot.modeRequested("SINGLE_BEND_MODE")
                    }
                }
                ModeOption {
                    badge: "1x"
                    label: qsTr("SINGLE REPEAT")
                    detail: qsTr("Continuously repeats active bend")
                    selected: bendModeRoot.mode === "SINGLE_BEND_REPEAT"
                    accent: "#0284C7"
                    onClicked: {
                        bendModeRoot.modeRequested("SINGLE_BEND_REPEAT")
                    }
                }
                ModeOption {
                    visible: bendModeRoot.multipleBends
                    badge: "1..N"
                    label: qsTr("PROGRAM ONCE")
                    detail: qsTr("Runs full 1→N sequence once")
                    selected: bendModeRoot.mode === "PROGRAM_BEND_MODE"
                    accent: "#EF4444"
                    onClicked: {
                        bendModeRoot.modeRequested("PROGRAM_BEND_MODE")
                    }
                }
                ModeOption {
                    visible: bendModeRoot.multipleBends
                    badge: "LOOP"
                    label: qsTr("PROGRAM LOOP")
                    detail: qsTr("Repeats full sequence continuously")
                    selected: bendModeRoot.mode === "PROGRAM_BEND_LOOP"
                    accent: "#8B5CF6"
                    onClicked: {
                        bendModeRoot.modeRequested("PROGRAM_BEND_LOOP")
                    }
                }
            }
        }
    }

    component ModeOption: Rectangle {
        id: modeOptionRoot
        signal clicked()
        property string badge: ""
        property string label: ""
        property string detail: ""
        property bool selected: false
        property color accent: "#EF4444"
        property bool hovered: false
        x: 8
        width: parent ? parent.width - 16 : 244
        height: visible ? 50 : 0
        implicitHeight: height
        radius: 7
        color: selected ? "#1E2638" : (hovered ? "#141A26" : "transparent")
        border.color: selected ? accent : (hovered ? "#334155" : "transparent")
        border.width: selected ? 1.5 : 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 8

            // Technical badge squircle pod
            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 6
                color: modeOptionRoot.selected ? modeOptionRoot.accent : "#1E293B"
                Text {
                    anchors.centerIn: parent
                    text: modeOptionRoot.badge
                    color: "white"
                    font.bold: true
                    font.pixelSize: modeOptionRoot.badge.length > 2 ? 9 : 11
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: modeOptionRoot.label
                    color: modeOptionRoot.selected ? "white" : "#CBD5E1"
                    font.bold: true
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: modeOptionRoot.detail
                    color: modeOptionRoot.selected ? "#94A3B8" : "#64748B"
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }

            // Radio check indicator
            Rectangle {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                radius: 10
                color: modeOptionRoot.selected ? modeOptionRoot.accent : "transparent"
                border.color: modeOptionRoot.selected ? modeOptionRoot.accent : "#475569"
                border.width: 1.5
                Text {
                    anchors.centerIn: parent
                    text: "✓"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                    visible: modeOptionRoot.selected
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: modeOptionRoot.hovered = true
            onExited: modeOptionRoot.hovered = false
            onClicked: modeOptionRoot.clicked()
        }
    }
}
