import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: window
    Theme { id: theme; fontMode: window.fontMode }
    LayoutMetrics { id: metrics }
    readonly property var nativeMachineControlBackend: machineControl
    readonly property var nativeHostSystemBackend: hostSystem
    readonly property var nativeMachineFirmwareBackend: typeof machineFirmware !== "undefined" ? machineFirmware : null
    readonly property var nativeDisplaySleepController: displaySleepController
    AppState {
        id: appState
        machineControl: window.nativeMachineControlBackend
        hostSystem: window.nativeHostSystemBackend
        machineFirmware: window.nativeMachineFirmwareBackend
        licenseManager: typeof license !== "undefined" ? license : null
        offlineSimulationEnabled: offlineValidation || smokeCycle || runInteractionSmoke
            || captureFullPath.length > 0 || captureLeftPath.length > 0
            || captureRightPath.length > 0 || dumpLeftBounds || dumpRightBounds
            || snapshotCad || runSnapshotState.length > 0 || popupSnapshotState.length > 0
    }
    DataStore { id: smokeDataStore }

    width: 1366
    height: 768
    minimumWidth: 1366
    minimumHeight: 768
    maximumWidth: 1366
    maximumHeight: 768
    visible: true
    title: "BendCNC"
    color: "#f5f5f5"

    readonly property color red: "#a82011"
    readonly property color green: "#59a60c"
    readonly property color blue: "#2d83b2"
    readonly property color charcoal: "#2b2c2b"
    readonly property color grey: "#a8a8a8"
    readonly property color lightGrey: "#e0e0e0"
    readonly property color paper: "#f5f5f5"
    readonly property color ink: "#232323"
    // Owner-only commissioning socket {"command":"sim_run","action":...}.
    // Visual SIM RUN only (same path as the SIM RUN button); never starts a
    // real RUN and refuses while one is active.
    function remoteSimControl(action) {
        var state = function(ok, error) {
            var r = { ok: ok, simRunning: appState.runSimulatedRun, runActive: appState.runActive,
                      tab: selectedTab, bend: appState.selectedRunBend,
                      bends: appState.programBends ? appState.programBends.length : 0 }
            if (error) r.error = error
            return r
        }
        if (action === "status")
            return state(true)
        if (appState.runActive)
            return state(false, "REAL_RUN_ACTIVE")
        if (action === "start" || action === "stop") {
            if (selectedTab !== 0)
                selectedTab = 0
            if ((action === "start") !== appState.runSimulatedRun)
                appState.runSimulationAction("sim-run")
            return state(true)
        }
        if (action === "next" || action === "previous") {
            appState.runSimulationAction(action)
            return state(true)
        }
        return state(false, "UNKNOWN_ACTION")
    }
    property int selectedTab: 0
    property int previousNonManualTab: 0
    property int manualExitTargetTab: -1
    property bool internalTabChange: false
    property string tabLoadError: ""
    property string fontMode: "original"
    property string captureFullPath: ""
    property string captureLeftPath: ""
    property string captureRightPath: ""
    property string runDebugLogPath: argumentValue("--run-debug-log=", "")
    property string requestedProgramName: ""
    property bool dumpLeftBounds: false
    property string dumpLeftBoundsPath: ""
    property bool dumpRightBounds: false
    property string dumpRightBoundsPath: ""
    readonly property bool snapshotCad: Qt.application.arguments.indexOf("--snapshot-cad") !== -1
    property string runSnapshotState: ""
    property string popupSnapshotState: ""
    property int requestedProgramWaitTicks: 0
    property bool preserveCadResultForCapture: false
    property bool cadAutomationExitRequested: false
    readonly property int requestedProgramWaitLimit: 300
    readonly property var tabFiles: [
        "RunView.qml",
        "CreateBendV7View.qml",
        "ToolsV7View.qml",
        "BackGaugeControlView.qml",
        "ManualModeView.qml",
        "CadImportView.qml",
        "SettingsView.qml",
        "ProgramsView.qml"
    ]
    readonly property bool smokeCycle: Qt.application.arguments.indexOf("--smoke-cycle") !== -1
    readonly property bool runInteractionSmoke: Qt.application.arguments.indexOf("--run-interaction-smoke") !== -1
    readonly property bool offlineValidation: Qt.application.arguments.indexOf("--offline-validation") !== -1
    property int cycleTab: 0
    property int cycleWaitTicks: 0
    property int cycleReadyTab: -1
    property bool cycleAdvancePending: false
    property var runSmokeFailures: []

    onSelectedTabChanged: {
        tabLoadError = ""
        cycleWaitTicks = 0
        cycleReadyTab = -1
        leftTabLoader.active = false
        leftTabLoader.source = ""
        leftTabLoader.source = snapshotCad && selectedTab === 5
            ? "GeneratedCadSnapshotView.qml"
            : tabFiles[selectedTab]
        leftTabLoader.active = true
        console.log("TAB-LOAD-REQUEST index=" + selectedTab
                    + " source=" + tabFiles[selectedTab])
    }

    Binding {
        target: window.nativeDisplaySleepController
        property: "timeoutMinutes"
        value: appState.displaySleepMinutes
    }

    function setSelectedTabInternal(index) {
        internalTabChange = true
        selectedTab = index
        internalTabChange = false
    }

    function requestTabChange(index) {
        var requested = Math.max(0, Math.min(tabFiles.length - 1, Number(index)))
        if (requested === selectedTab)
            return true
        if (requested === 4) {
            previousNonManualTab = selectedTab
            setSelectedTabInternal(4)
            return true
        }
        if (selectedTab === 4) {
            // Browsing the Manual page never owns or changes machine state.
            // A confirmed native Manual lifecycle remains required by every
            // physical action through AppState.pressCanOperate.
            if (appState.manualModeEnabled || appState.manualActivationPending
                    || appState.manualLeavePending) {
                manualExitTargetTab = requested
                if (!appState.deactivateManualMode()) {
                    manualExitTargetTab = -1
                    return false
                }
                if (appState.manualLeavePending)
                    return false
                manualExitTargetTab = -1
            }
        }
        previousNonManualTab = requested
        setSelectedTabInternal(requested)
        return true
    }

    Connections {
        target: appState
        function onManualLeavePendingChanged() {
            if (!appState.manualLeavePending && window.manualExitTargetTab >= 0
                    && !appState.manualModeEnabled) {
                const target = window.manualExitTargetTab
                window.manualExitTargetTab = -1
                window.previousNonManualTab = target
                window.setSelectedTabInternal(target)
            }
        }
        function onManualModeStateChanged() {
            if (appState.manualModeState === "DISABLE REQUIRED")
                window.manualExitTargetTab = -1
        }
    }

    Timer {
        id: requestedProgramSelectionTimer
        interval: 100
        repeat: true
        onTriggered: {
            requestedProgramWaitTicks += 1
            if (requestedProgramWaitTicks >= requestedProgramWaitLimit) {
                stop()
                console.error("PROGRAM-SELECTION-TIMEOUT requested=" + requestedProgramName
                              + " active=" + appState.activeProgram
                              + " bends=" + String(appState.programBends.length))
                Qt.exit(3)
                return
            }
            if (requestedProgramName.length === 0) {
                stop()
                startCaptureTimers()
                return
            }
            if (String(appState.activeProgram).toLowerCase() !== requestedProgramName.toLowerCase()
                    || appState.programBends.length === 0
                    || appState.activeProgramCadPreviewJson.length === 0) {
                selectRequestedProgram()
                return
            }
            var requestedBend = parseInt(argumentValue("--run-bend=", ""))
            if (!isNaN(requestedBend)) {
                var requestedBendIndex = Math.max(0, requestedBend - 1)
                if (appState.selectedRunBend !== requestedBendIndex) {
                    appState.selectRunBend(requestedBendIndex)
                    return
                }
            }
            if (!leftTabLoader.item
                    || !leftTabLoader.item.hasOwnProperty("runPreviewFrameReady")
                    || leftTabLoader.item.runPreviewFrameReady !== true
                    || String(leftTabLoader.item.renderedPreviewProgramName).toLowerCase()
                    !== requestedProgramName.toLowerCase()
                    || Number(leftTabLoader.item.renderedPreviewBendIndex) !== appState.selectedRunBend
                    || String(leftTabLoader.item.renderedPreviewSceneMode) !== appState.runSceneMode)
                return
            stop()
            console.log("PROGRAM-SELECTED requested=" + requestedProgramName
                        + " active=" + appState.activeProgram
                        + " index=" + String(appState.selectedProgramIndex)
                        + " bends=" + String(appState.programBends.length)
                        + " renderedProgram=" + String(leftTabLoader.item.renderedPreviewProgramName || "")
                        + " renderedBend=" + String(Number(leftTabLoader.item.renderedPreviewBendIndex) + 1)
                        + " renderedMode=" + String(leftTabLoader.item.renderedPreviewSceneMode || "")
                        + " cadPart=" + String(leftTabLoader.item.renderedCadPartName || ""))
            startCaptureTimers()
        }
    }

    onRunDebugLogPathChanged: {
        if (leftTabLoader.item && leftTabLoader.item.hasOwnProperty("runDebugLogPath"))
            leftTabLoader.item.runDebugLogPath = runDebugLogPath
    }

    font.family: theme.appFontFamily
    font.pixelSize: 12

    function argumentValue(prefix, fallback) {
        for (var i = 0; i < Qt.application.arguments.length; i++) {
            if (Qt.application.arguments[i].indexOf(prefix) === 0)
                return Qt.application.arguments[i].substring(prefix.length)
        }
        return fallback
    }

    function logDisplayGeometry(phase) {
        console.log("DISPLAY-GEOMETRY phase=" + phase
                    + " window=" + width + "x" + height
                    + " screen=" + Screen.width + "x" + Screen.height
                    + " dpr=" + Screen.devicePixelRatio)
    }

    Timer {
        interval: 250
        running: true
        repeat: false
        onTriggered: logDisplayGeometry("settled")
    }

    Component.onCompleted: {
        logDisplayGeometry("initial")
        smokeDataStore.reload()
        appState.applyLocalSettings(smokeDataStore.localSettings)
        appState.applyUserSettings(smokeDataStore.userSettings)
        appState.setAllBends(smokeDataStore.bends, smokeDataStore.punches, smokeDataStore.dies, smokeDataStore.materials)
        appState.setProgramsFromStorage(smokeDataStore.programs, smokeDataStore.bends, smokeDataStore.punches, smokeDataStore.dies, smokeDataStore.materials, smokeDataStore.localSettings)
        var startupLegacyValue = argumentValue("--legacy-run-ui=", "")
        if (startupLegacyValue.length === 0
                && smokeDataStore.localSettings
                && smokeDataStore.localSettings.legacyRunUiEnabled === false)
            appState.legacyRunUiEnabled = false
        requestedProgramName = argumentValue("--program-name=", "")
        selectRequestedProgram()
        fontMode = argumentValue("--font-mode=", "original") === "current" ? "current" : "original"
        captureFullPath = argumentValue("--capture-full=", "")
        captureLeftPath = argumentValue("--capture-left=", "")
        captureRightPath = argumentValue("--capture-right=", "")
        runDebugLogPath = argumentValue("--run-debug-log=", "")
        runSnapshotState = argumentValue("--run-snapshot-state=", "")
        popupSnapshotState = argumentValue("--popup-snapshot=", "")
        dumpLeftBoundsPath = argumentValue("--dump-left-bounds=", "")
        dumpRightBoundsPath = argumentValue("--dump-right-bounds=", "")
        dumpLeftBounds = dumpLeftBoundsPath.length > 0 || Qt.application.arguments.indexOf("--dump-left-bounds") !== -1
        dumpRightBounds = dumpRightBoundsPath.length > 0 || Qt.application.arguments.indexOf("--dump-right-bounds") !== -1
        var requestedTab = parseInt(argumentValue("--tab=", "0"))
        if (!isNaN(requestedTab))
            setSelectedTabInternal(Math.max(0, Math.min(tabFiles.length - 1, requestedTab)))
        cycleTab = selectedTab
        if (runSnapshotState.length > 0)
            prepareRunSnapshotState(runSnapshotState)
        if (popupSnapshotState.length > 0)
            preparePopupSnapshotState(popupSnapshotState)
        prepareRunPreviewSnapshotArguments()
        prepareCadAutomationArguments()
        prepareRightPanelSnapshotArguments()
        prepareOnScreenKeyboardSnapshotArguments()
        requestedProgramSelectionTimer.start()
        if (runInteractionSmoke)
            runInteractionSmokeTimer.start()
    }

    function runSmokeAssert(condition, message) {
        if (!condition)
            runSmokeFailures.push(message)
    }

    function finishRunInteractionSmoke() {
        if (runSmokeFailures.length > 0) {
            console.log("RUN_INTERACTION_SMOKE_FAIL " + runSmokeFailures.join(" | "))
            Qt.exit(2)
        } else {
            console.log("RUN_INTERACTION_SMOKE_PASS")
            Qt.quit()
        }
    }

    function resetRunSnapshotData() {
        selectedTab = 0
        appState.hidePopup()
        appState.clearAlarm()
        appState.closeAddBendPopup()
        appState.closeRunConfirmation()
        appState.runActive = false
        appState.machineStatus = "IDLE"
        appState.applyLocalSettings(smokeDataStore.localSettings)
        appState.setAllBends(smokeDataStore.bends, smokeDataStore.punches, smokeDataStore.dies, smokeDataStore.materials)
        appState.setProgramsFromStorage(smokeDataStore.programs, smokeDataStore.bends, smokeDataStore.punches, smokeDataStore.dies, smokeDataStore.materials, smokeDataStore.localSettings)
        selectRequestedProgram()
    }

    function selectRequestedProgram() {
        if (requestedProgramName.length === 0 || appState.programs.length === 0)
            return
        var requested = requestedProgramName.toLowerCase()
        for (var i = 0; i < appState.programs.length; i++) {
            if (String(appState.programs[i].name || "").toLowerCase() === requested) {
                appState.selectedProgramIndex = i
                appState.selectedRunBend = appState.programs[i].bends && appState.programs[i].bends.length > 0 ? 0 : -1
                appState.syncActiveProgramState()
                appState.enforceBendModeForProgram()
                return
            }
        }
    }

    function startCaptureTimers() {
        if (preserveCadResultForCapture && appState.popupKind !== "cad-result")
            return
        if (captureFullPath.length > 0) {
            captureFullTimer.start()
        } else if (captureLeftPath.length > 0) {
            captureTimer.start()
        } else if (captureRightPath.length > 0) {
            captureRightTimer.start()
        } else if (dumpRightBounds) {
            rightBoundsDumpTimer.start()
        } else if (dumpLeftBounds) {
            boundsDumpTimer.start()
        }
    }

    function prepareRunSnapshotState(state) {
        resetRunSnapshotData()
        if (state === "add-bend") {
            appState.openAddBendPopup()
        } else if (state === "run-confirmation") {
            appState.openRunConfirmation()
        } else if (state === "bend-mode") {
            appState.runAction("bend-mode")
        } else if (state === "run-active") {
            appState.confirmRunProgram()
        } else if (state === "delete-alarm") {
            appState.runAction("delete")
        }
    }

    function preparePopupSnapshotState(state) {
        var normalized = String(state || "").toLowerCase()
        if (normalized === "home-back-gauge" || normalized === "home") {
            appState.moduleConnected = true
            appState.backGaugeBusy = false
            appState.backGaugeLimitX1 = false
            appState.backGaugeLimitX2 = false
            appState.backGaugeLimitR1 = false
            appState.backGaugeLimitR2 = false
            appState.requestBackGaugeHome()
        } else if (normalized === "homing" || normalized === "progress") {
            appState.showPopup("BACK GAUGE HOMING", "Back gauge axes are moving to machine zero.", 0.45, "blur", "CANCEL")
        } else if (normalized === "message" || normalized === "complete") {
            appState.showPopup("BACK GAUGE HOMED", "Back gauge axes homed to machine zero.", 1, "message", "CLOSE")
        } else if (normalized === "add-bend") {
            selectedTab = 0
            appState.addBendStatus = "Select a bend from the library to add it to the active program."
            appState.addBendPopupVisible = true
        } else if (normalized === "run-confirmation" || normalized === "run-confirm") {
            selectedTab = 0
            appState.runConfirmationVisible = true
        } else if (normalized === "wifi") {
            appState.showPopup("WIFI CONNECTION", "CONNECTED NETWORK", 0, "wifi")
        } else if (normalized === "vertical-diagram") {
            appState.showImagePopup("VERTICAL POSITIONS DIAGRAM",
                "START SAFETY CLEARANCE  5.673 in\n\n"
                + "BEND CLAMP POSITION  5.640 in\n\n"
                + "FINAL BEND POSITION  5.516 in\n\n"
                + "RETRACT AFTER BEND  -0.050 in\n\n"
                + "TOTAL BEND STROKE  0.126 in",
                "images/info/create_bend/vertical_diagram.png")
        } else if (normalized === "info") {
            appState.showPopup("INFO", "This classic-style information popup uses the same large paper body, dark header, close action, and bold markdown-like text treatment as InfoView.fxml.", 1, "info")
        } else if (normalized === "caution" || normalized === "warning") {
            appState.showPopup("CAUTION", "Verify the material, tooling, bend sequence, and all pinch points before moving the machine. This mirrors the red-header caution modal family.", 0, "caution")
        } else if (normalized === "alarm" || normalized === "alert") {
            appState.showAlarm("MACHINE ALARM", "Emergency stop or limit condition detected. Clear the condition before continuing.")
        } else if (normalized === "machine-log" || normalized === "log") {
            appState.clearMachineLog()
            appState.machineLogStatusReportsEnabled = true
            appState.appendMachineLog("SOFTWARE", "<VER>")
            appState.appendMachineLog("MACHINE", "<BendCNC 24.1.36>")
            appState.appendMachineLog("MACHINE", "<Idle|Y1:-0.0500|FS:0,0>")
            appState.appendMachineLog("SOFTWARE", "Byte 0x85")
            appState.toolbarAction("log")
        } else if (normalized === "manual-calibration") {
            setSelectedTabInternal(4)
            appState.openManualMeasurement("CALIBRATION")
        } else if (normalized === "manual-measurement") {
            setSelectedTabInternal(4)
            appState.applyUserSettings(Object.assign({}, appState.userSettingsModel, {
                manualDieTopCalibration: { value: -1.125, unit: "INCH", valid: true }
            }))
            appState.openManualMeasurement("MEASUREMENT")
        } else {
            appState.showPopup("WAITING FOR MACHINE INPUT", "Switch the machine to the requested state to continue.", 0.45, "blur")
        }
    }

    function prepareRunPreviewSnapshotArguments() {
        if (selectedTab !== 0)
            return
        var legacyValue = argumentValue("--legacy-run-ui=", "")
        var sceneValue = argumentValue("--run-scene-mode=", "")
        var bendValue = argumentValue("--run-bend=", "")
        var contourRendererValue = argumentValue("--flat-contour-renderer=", "")
        var liveProjectionValue = argumentValue("--run-live-projection=", "")
        var liveOrientationValue = argumentValue("--run-live-orientation=", "")
        var toolingAppearanceValue = argumentValue("--run-tooling-appearance=", "")
        if (legacyValue.length === 0 && sceneValue.length === 0 && bendValue.length === 0
            && contourRendererValue.length === 0 && liveProjectionValue.length === 0
            && liveOrientationValue.length === 0
            && toolingAppearanceValue.length === 0)
            return
        if (runSnapshotState.length === 0)
            resetRunSnapshotData()
        if (legacyValue.length > 0) {
            var normalizedLegacy = legacyValue.toLowerCase()
            appState.legacyRunUiEnabled = !(normalizedLegacy === "off" || normalizedLegacy === "false" || normalizedLegacy === "0")
        }
        if (bendValue.length > 0) {
            var bendIndex = parseInt(bendValue)
            if (!isNaN(bendIndex))
                appState.selectRunBend(Math.max(0, bendIndex - 1))
        }
        if (sceneValue.length > 0) {
            var normalizedScene = sceneValue.toUpperCase()
            if (normalizedScene === "LIVE")
                appState.runSimulationAction("live")
            else if (normalizedScene === "PLACEMENT")
                appState.runSimulationAction("placement")
        }
        if (contourRendererValue.length > 0) {
            var normalizedRenderer = contourRendererValue.toLowerCase()
            appState.runFlatPatternContourRenderer = normalizedRenderer === "canonical" || normalizedRenderer === "overlay" ? normalizedRenderer : "classic"
        }
        if (liveOrientationValue.length > 0)
            appState.runLiveCameraOrientation = appState.normalizeRunLiveCameraOrientation(
                liveOrientationValue)
        if (toolingAppearanceValue.length > 0)
            appState.runToolingAppearance = String(toolingAppearanceValue).toUpperCase() === "TRANSLUCENT"
                ? "TRANSLUCENT" : "SOLID"
        appState.runActive = false
        appState.runSimulatedRun = Qt.application.arguments.indexOf("--run-simulated-playback") !== -1
        appState.runBendListVisible = false
        appState.machineStatus = "IDLE"
    }

    function prepareRightPanelSnapshotArguments() {
        var loadValue = parseFloat(argumentValue("--right-panel-load=", ""))
        var ramValue = parseFloat(argumentValue("--right-panel-ram=", ""))
        var velocityValue = parseFloat(argumentValue("--right-panel-velocity=", ""))
        var statusValue = argumentValue("--right-panel-status=", "")
        if (!isNaN(loadValue))
            appState.liveTonnage = loadValue
        if (!isNaN(ramValue))
            appState.ramPosition = ramValue
        if (!isNaN(velocityValue))
            appState.commandedJogSpeed = velocityValue
        if (statusValue.length > 0)
            appState.machineStatus = statusValue
    }

    function prepareOnScreenKeyboardSnapshotArguments() {
        var kind = String(argumentValue("--osk=", "")).toLowerCase()
        if (kind !== "text" && kind !== "numeric")
            return
        appState.onScreenKeyboardKind = kind
        appState.onScreenKeyboardTitle = kind === "numeric" ? "MOVE TO X" : "REFERENCE STOP PROFILE"
        appState.onScreenKeyboardValue = kind === "numeric" ? "1.2500" : "LOWER FINGER"
        appState.onScreenKeyboardCursor = appState.onScreenKeyboardValue.length
        appState.onScreenKeyboardOriginalValue = kind === "numeric"
        appState.onScreenKeyboardShiftState = "NONE"
        appState.onScreenKeyboardSymbols = false
        appState.onScreenKeyboardVisible = true
    }

    // Generic packaged-app integration harness. It exercises the same import,
    // tooling selection, generation, popup, and persistence path as the CAD UI;
    // a second process can then prove that DataStore restores the saved program.
    function prepareCadAutomationArguments() {
        var importPath = argumentValue("--cad-import=", "")
        if (importPath.length === 0)
            return
        var finished = function(ok) {
            appState.cadLoadFinished.disconnect(finished)
            if (!ok) {
                console.error("CAD-AUTOMATION-IMPORT-FAILED path=" + importPath)
                Qt.callLater(function() { Qt.exit(4) })
                return
            }
            continueCadImportAutomation()
        }
        appState.cadLoadFinished.connect(finished)
        // A failed start reports through cadLoadFinished(false) as well.
        appState.cadLoadFile(importPath, smokeDataStore.punches,
                             smokeDataStore.dies, smokeDataStore.materials,
                             smokeDataStore.userSettings)
    }

    function continueCadImportAutomation() {
        // Wait for the 3D sequence planner so generation uses its order.
        if (appState.cadUnfoldState === "planning") {
            var resume = function() {
                if (appState.cadUnfoldState === "planning")
                    return
                appState.cadUnfoldStateChanged.disconnect(resume)
                console.log("CAD-AUTOMATION-PLAN state=" + appState.cadUnfoldState
                            + " order=" + appState.cadBends.map(function(row) { return row.id }).join(","))
                continueCadAutomation()
            }
            appState.cadUnfoldStateChanged.connect(resume)
            return
        }
        continueCadAutomation()
    }

    function continueCadAutomation() {
        var generatedName = argumentValue("--cad-program-name=", "")
        if (generatedName.length > 0)
            appState.cadProgramName = generatedName
        var requestedMove = argumentValue("--cad-move=", "")
        if (requestedMove.length > 0) {
            var moveParts = requestedMove.split(":")
            var fromSequence = moveParts.length === 2 ? parseInt(moveParts[0]) : NaN
            var toSequence = moveParts.length === 2 ? parseInt(moveParts[1]) : NaN
            if (isNaN(fromSequence) || isNaN(toSequence)
                    || !appState.moveCadBend(fromSequence - 1, toSequence - 1)) {
                console.error("CAD-AUTOMATION-MOVE-FAILED request=" + requestedMove)
                Qt.callLater(function() { Qt.exit(5) })
                return
            }
            console.log("CAD-AUTOMATION-MOVE request=" + requestedMove
                        + " order=" + appState.cadBends.map(function(row) { return row.id }).join(","))
        }
        if (Qt.application.arguments.indexOf("--cad-generate") !== -1) {
            appState.cadAction("generate")
            preserveCadResultForCapture = Qt.application.arguments.indexOf("--capture-cad-result") !== -1
            requestedProgramName = appState.cadProgramName
            selectRequestedProgram()
            if (Qt.application.arguments.indexOf("--cad-exit-after-generate") !== -1) {
                cadAutomationExitRequested = true
                cadAutomationExitTimer.start()
            }
        }
    }

    Timer {
        id: cadAutomationExitTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!cadAutomationExitRequested)
                return
            if (!appState.lastProgramPersistenceSucceeded) {
                console.error("CAD-AUTOMATION-PERSIST-FAILED name=" + appState.cadProgramName)
                Qt.exit(6)
                return
            }
            console.log("CAD-AUTOMATION-PERSISTED name=" + appState.cadProgramName)
            Qt.quit()
        }
    }

    function jsonEscape(value) {
        return String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
    }

    function collectBounds(item, depth, rows) {
        if (!item)
            return
        var point = item.mapToItem(columnLeftHost, 0, 0)
        rows.push("{\"depth\":" + depth
            + ",\"type\":\"" + jsonEscape(item.toString().split("(")[0]) + "\""
            + ",\"objectName\":\"" + jsonEscape(item.objectName || "") + "\""
            + ",\"x\":" + point.x.toFixed(3)
            + ",\"y\":" + point.y.toFixed(3)
            + ",\"width\":" + item.width.toFixed(3)
            + ",\"height\":" + item.height.toFixed(3) + "}")
        for (var i = 0; i < item.children.length; i++)
            collectBounds(item.children[i], depth + 1, rows)
    }

    function collectBoundsRelative(item, rootItem, depth, rows) {
        if (!item)
            return
        var point = item.mapToItem(rootItem, 0, 0)
        rows.push("{\"depth\":" + depth
            + ",\"type\":\"" + jsonEscape(item.toString().split("(")[0]) + "\""
            + ",\"objectName\":\"" + jsonEscape(item.objectName || "") + "\""
            + ",\"x\":" + point.x.toFixed(3)
            + ",\"y\":" + point.y.toFixed(3)
            + ",\"width\":" + item.width.toFixed(3)
            + ",\"height\":" + item.height.toFixed(3) + "}")
        for (var i = 0; i < item.children.length; i++)
            collectBoundsRelative(item.children[i], rootItem, depth + 1, rows)
    }

    Timer {
        id: boundsDumpTimer
        interval: 350
        repeat: false
        onTriggered: {
            var rows = []
            collectBounds(columnLeftHost, 0, rows)
            var json = "[" + rows.join(",") + "]"
            if (dumpLeftBoundsPath.length > 0) {
                var request = new XMLHttpRequest()
                request.open("PUT", "file:///" + dumpLeftBoundsPath.replace(/\\/g, "/"), false)
                request.send(json)
            } else {
                console.log("QML_BOUNDS_JSON_BEGIN")
                console.log(json)
                console.log("QML_BOUNDS_JSON_END")
            }
            Qt.quit()
        }
    }

    Timer {
        id: rightBoundsDumpTimer
        interval: 350
        repeat: false
        onTriggered: {
            var rows = []
            collectBoundsRelative(columnRightHost, columnRightHost, 0, rows)
            var json = "[" + rows.join(",") + "]"
            if (dumpRightBoundsPath.length > 0) {
                var request = new XMLHttpRequest()
                request.open("PUT", "file:///" + dumpRightBoundsPath.replace(/\\/g, "/"), false)
                request.send(json)
            } else {
                console.log("QML_RIGHT_BOUNDS_JSON_BEGIN")
                console.log(json)
                console.log("QML_RIGHT_BOUNDS_JSON_END")
            }
            Qt.quit()
        }
    }

    Timer {
        id: captureFullTimer
        interval: 350
        repeat: false
        onTriggered: {
            const captureLivePanel = window.offlineValidation
                && Qt.application.arguments.indexOf("--open-thc-live-tuning") !== -1
            const captureSurface = captureLivePanel
                ? (leftTabLoader.item ? leftTabLoader.item.liveTuningCaptureItem : null) : rootSurface
            if (!captureSurface) {
                console.error("ERROR: requested capture surface is unavailable")
                Qt.exit(4)
                return
            }
            const accepted = captureSurface.grabToImage(function(result) {
                if (!result.saveToFile(captureFullPath)) {
                    console.log("ERROR: failed to save QML capture: " + captureFullPath)
                    Qt.exit(4)
                    return
                }
                Qt.quit()
            }, Qt.size(window.width, window.height))
            if (!accepted) {
                console.error("ERROR: requested capture could not start")
                Qt.exit(4)
            }
        }
    }

    Timer {
        id: captureTimer
        // --capture-delay-ms= lets async LIVE topology validation settle first.
        interval: Math.max(350, parseInt(argumentValue("--capture-delay-ms=", "350")) || 350)
        repeat: false
        onTriggered: {
            columnLeftHost.grabToImage(function(result) {
                if (!result.saveToFile(captureLeftPath))
                    console.log("ERROR: failed to save QML capture: " + captureLeftPath)
                Qt.quit()
            }, Qt.size(864, columnLeftHost.height))
        }
    }

    Timer {
        id: captureRightTimer
        interval: 350
        repeat: false
        onTriggered: {
            columnRightHost.grabToImage(function(result) {
                if (!result.saveToFile(captureRightPath))
                    console.log("ERROR: failed to save QML capture: " + captureRightPath)
                Qt.quit()
            }, Qt.size(metrics.columnRightWidth, columnRightHost.height))
        }
    }

    Timer {
        id: smokeCycleTimer
        interval: 100
        running: smokeCycle
        repeat: true
        onTriggered: {
            if (cycleAdvancePending) {
                cycleAdvancePending = false
                selectedTab = cycleTab
                return
            }
            if (cycleReadyTab !== cycleTab
                    || leftTabLoader.source.toString().indexOf(tabFiles[cycleTab]) === -1) {
                cycleWaitTicks += 1
                if (cycleWaitTicks >= 100) {
                    console.error("TAB-LOAD-TIMEOUT index=" + selectedTab
                                  + " source=" + tabFiles[selectedTab])
                    stop()
                    Qt.exit(4)
                }
                return
            }
            cycleTab += 1
            if (cycleTab >= tabFiles.length) {
                stop()
                Qt.callLater(Qt.quit)
                return
            }
            cycleAdvancePending = true
        }
    }

    Timer {
        id: runInteractionSmokeTimer
        interval: 450
        repeat: false
        onTriggered: {
            selectedTab = 0
            runSmokeFailures = []
            appState.hidePopup()
            appState.clearAlarm()
            appState.closeAddBendPopup()
            appState.closeRunConfirmation()
            appState.runActive = false
            appState.machineStatus = "IDLE"
            appState.applyLocalSettings(smokeDataStore.localSettings)
            appState.setAllBends(smokeDataStore.bends, smokeDataStore.punches, smokeDataStore.dies, smokeDataStore.materials)
            appState.setProgramsFromStorage(smokeDataStore.programs, smokeDataStore.bends, smokeDataStore.punches, smokeDataStore.dies, smokeDataStore.materials, smokeDataStore.localSettings)

            runSmokeAssert(!appState.legacyRunUiEnabled, "modern run UI should be default")
            runSmokeAssert(appState.programBends.length > 0, "sample program should contain bend moves")
            runSmokeAssert(appState.activeProgramCadPreviewJson.length > 0, "run renderer should have CAD preview JSON")

            appState.runAction("bend-mode")
            runSmokeAssert(appState.bendModePopupVisible, "bend mode action should open popup")
            appState.setBendMode("PROGRAM_BEND_LOOP")
            runSmokeAssert(appState.bendMode === "PROGRAM_BEND_LOOP", "bend mode option should update mode")
            runSmokeAssert(!appState.bendModePopupVisible, "bend mode option should close popup")

            appState.runAction("auto-clamp")
            runSmokeAssert(appState.autoClampEnabled, "auto clamp action should enable state")
            appState.runAction("auto-clamp")
            runSmokeAssert(!appState.autoClampEnabled, "auto clamp action should disable state")

            appState.openAddBendPopup()
            runSmokeAssert(appState.addBendPopupVisible, "add bend button should open popup")
            runSmokeAssert(appState.allBends.length > 0, "add bend popup should preserve loaded storage bends")
            var validBendIndex = -1
            for (var smokeBendIndex = 0; smokeBendIndex < appState.allBends.length; smokeBendIndex++) {
                if (appState.validateProgramBend(appState.allBends[smokeBendIndex]).length === 0) {
                    validBendIndex = smokeBendIndex
                    break
                }
            }
            if (validBendIndex >= 0) {
                appState.selectAddBend(validBendIndex)
                appState.addSelectedBendToProgram()
                runSmokeAssert(!appState.addBendPopupVisible, "successful add bend should close popup")
                runSmokeAssert(appState.popupVisible && appState.popupTitle === "ADD BEND", "successful add bend should show ADD BEND popup")
            } else {
                appState.selectAddBend(0)
                appState.addSelectedBendToProgram()
                runSmokeAssert(appState.addBendPopupVisible,
                               "invalid storage bend should remain in add-bend popup")
                runSmokeAssert(appState.alarmVisible,
                               "invalid storage bend should show a validation alarm")
                appState.clearAlarm()
                appState.closeAddBendPopup()
            }
            appState.hidePopup()

            appState.runAction("run")
            runSmokeAssert(appState.runConfirmationVisible, "run action should open confirmation popup")
            appState.confirmRunProgram()
            runSmokeAssert(appState.runActive, "confirming run should activate execution overlay")
            runSmokeAssert(appState.machineStatus === "RUNNING", "confirming run should set machine running")
            runSmokeAssert(appState.popupVisible && appState.popupTitle === "RUN PROGRAM", "confirming run should show machine popup")
            appState.hidePopup()
            appState.runAction("run")
            runSmokeAssert(!appState.runActive && appState.machineStatus === "IDLE", "run action during active run should pause")
            appState.hidePopup()

            appState.runAction("edit")
            runSmokeAssert(appState.runProgramEditing, "edit action should enter edit mode")
            appState.runAction("cancel")
            runSmokeAssert(!appState.runProgramEditing, "cancel action should leave edit mode")
            appState.runAction("duplicate")
            runSmokeAssert(appState.runProgramEditing && appState.runProgramNameDraft.indexOf("COPY") >= 0, "duplicate action should enter copy edit mode")
            appState.runAction("save")
            runSmokeAssert(!appState.runProgramEditing, "save action should leave edit mode")
            appState.runAction("delete")
            runSmokeAssert((appState.popupVisible && appState.popupTitle === "DELETE PROGRAM")
                           || (appState.alarmVisible && appState.alarmTitle === "DELETE PROGRAM"),
                           "delete action should report its persistence result")
            appState.clearAlarm()

            appState.runAction("new")
            runSmokeAssert(appState.runProgramEditing, "new action should enter edit mode")
            runSmokeAssert(appState.programBends.length === 0, "new action should create an empty program")
            runSmokeAssert(appState.selectedRunBend === -1, "new empty program should not select a bend")

            finishRunInteractionSmoke()
        }
    }

    component IconText: Text {
        font.family: theme.iconFontFamily
        font.pixelSize: 15
        font.bold: true
        color: "white"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component FlatButton: Rectangle {
        id: button
        property alias text: label.text
        property string icon: ""
        property color buttonColor: "orange"
        property color textColor: "white"
        property int labelSize: 12
        property bool bold: true
        radius: 4
        color: buttonColor
        height: 35

        RowLayout {
            anchors.centerIn: parent
            spacing: 6
            IconText { text: button.icon; visible: button.icon.length > 0; color: button.textColor }
            Text {
                id: label
                color: button.textColor
                font.pixelSize: button.labelSize
                font.bold: button.bold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    component ConnectionPill: Rectangle {
        property string title: "MACHINE"
        property string value: "LS-BEND 1.1"
        width: 220
        height: 35
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            spacing: 6
            Text { text: title; color: ink; font.bold: true; font.pixelSize: 14; Layout.alignment: Qt.AlignVCenter }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 4
                color: green
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    spacing: 7
                    Text { text: value; color: "white"; font.bold: false; font.pixelSize: 14; Layout.fillWidth: true }
                    IconText { text: "↻"; font.pixelSize: 14 }
                    Rectangle {
                        Layout.preferredWidth: 35
                        Layout.fillHeight: true
                        color: grey
                        radius: 4
                        IconText { anchors.centerIn: parent; text: "×"; font.pixelSize: 14 }
                    }
                }
            }
        }
    }

    Item {
        id: rootSurface
        anchors.fill: parent

        ColumnLayout {
            id: mainPanel
            objectName: "mainPanel viewportRoot MainView ActionBarView ToolBar MachinePopupView ColumnLeft ColumnRight MachineAlarmPopupView main-grid popup-container alarm-popup caution-popup"
            anchors.fill: parent
            spacing: 0

        ActionBarView {
            objectName: "action-bar"
            appState: appState
            Layout.fillWidth: true
            Layout.preferredHeight: 40
        }

        ToolBarView {
            objectName: "toolbar"
            appState: appState
            Layout.fillWidth: true
            Layout.preferredHeight: 50
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: paper

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 5
                    anchors.bottomMargin: 5
                    spacing: 10

                    ColumnLayout {
                        id: columnLeftHost
                        Layout.preferredWidth: metrics.columnLeftWidth
                        Layout.minimumWidth: metrics.columnLeftWidth
                        Layout.maximumWidth: metrics.columnLeftWidth
                        Layout.fillHeight: true
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: metrics.tabHeaderHeight
                            color: charcoal
                            radius: 7
                            antialiasing: true
                            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 7; color: charcoal }
                            Row {
                                anchors.fill: parent
                                spacing: 0
                                Repeater {
                                    model: metrics.tabOrder.length
                                    delegate: Rectangle {
                                        // index = display position; tabIndex = stable tab identity.
                                        readonly property int tabIndex: metrics.tabOrder[index]
                                        objectName: "left-tab-" + tabIndex
                                        width: metrics.tabWidths[tabIndex]
                                        height: metrics.tabHeaderHeight
                                        color: tabIndex === selectedTab ? red : "transparent"
                                        radius: (index === 0 && index === selectedTab) ? 7 : 0
                                        antialiasing: index === 0 && index === selectedTab

                                        Rectangle {
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: parent.radius
                                            color: parent.color
                                            visible: index === 0 && index === selectedTab
                                        }
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: parent.radius
                                            color: parent.color
                                            visible: index === 0 && index === selectedTab
                                        }

                                        Text {
                                            id: tabLabel
                                            anchors.centerIn: parent
                                            text: metrics.tabLabels[parent.tabIndex]
                                            color: "white"
                                            font.bold: true
                                            font.pixelSize: 14
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: window.requestTabChange(parent.tabIndex)
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: lightGrey
                            radius: 7
                            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: metrics.contentTopOverlap; color: lightGrey }
                            Loader {
                                id: leftTabLoader
                                anchors.fill: parent
                                source: tabFiles[0]
                                onStatusChanged: {
                                    if (status === Loader.Loading) {
                                        window.tabLoadError = ""
                                        console.log("TAB-LOAD-LOADING index=" + window.selectedTab
                                                    + " source=" + source)
                                    } else if (status === Loader.Ready) {
                                        window.tabLoadError = ""
                                        window.cycleReadyTab = window.selectedTab
                                        console.log("TAB-LOAD-READY index=" + window.selectedTab
                                                    + " source=" + source)
                                    } else if (status === Loader.Error) {
                                        window.tabLoadError = "Unable to load "
                                            + metrics.tabLabels[window.selectedTab] + "."
                                        console.error("TAB-LOAD-ERROR index=" + window.selectedTab
                                                      + " source=" + source)
                                    }
                                }
                                onLoaded: {
                                    if (item && item.hasOwnProperty("appState"))
                                        item.appState = appState
                                    // PROGRAMS tab: opening a program hands the operator to RUN.
                                    if (item && typeof item.openInRunRequested === "function")
                                        item.openInRunRequested.connect(function() { window.requestTabChange(0) })
                                    if (window.offlineValidation && window.selectedTab === 4
                                            && item && item.hasOwnProperty("liveTuningOpen")
                                            && Qt.application.arguments.indexOf("--open-thc-live-tuning") !== -1)
                                        item.liveTuningOpen = true
                                    if (item && item.hasOwnProperty("openProfilePopupOnCompleted"))
                                        item.openProfilePopupOnCompleted = Qt.application.arguments.indexOf("--open-profile-popup") !== -1
                                    if (item && item.hasOwnProperty("runDebugLogPath"))
                                        item.runDebugLogPath = runDebugLogPath
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: leftTabLoader.status === Loader.Error
                                color: paper
                                z: 1

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width - 48, 560)
                                    spacing: 12

                                    Text {
                                        Layout.fillWidth: true
                                        text: window.tabLoadError
                                        color: red
                                        font.pixelSize: 20
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "The component did not initialize. See the application log for TAB-LOAD-ERROR and QML diagnostics."
                                        color: ink
                                        font.pixelSize: 14
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }

                    ColumnRightView {
                        id: columnRightHost
                        objectName: "column-right"
                        appState: appState
                        Layout.preferredWidth: metrics.columnRightWidth
                        Layout.minimumWidth: metrics.columnRightWidth
                        Layout.maximumWidth: metrics.columnRightWidth
                        Layout.fillHeight: true
                    }
                }
            }
        }
        }

        MachinePopupLayer {
            id: machinePopupLayer
            anchors.fill: parent
            appState: appState
            onViewRunRequested: requestTabChange(0)
        }

        MachineAlarmPopupLayer {
            id: machineAlarmPopupLayer
            anchors.fill: parent
            appState: appState
        }

        ManualMeasurementPopup {
            id: manualMeasurementPopup
            anchors.fill: parent
            appState: appState
        }

        LicensePanel {
            id: licensePanel
            anchors.fill: parent
            appState: appState
        }

        // CAD PC pairing request from the Fusion add-in (code-less): the
        // operator accepts or rejects on this screen; 60 s timeout on the press.
        Rectangle {
            id: cadPairRequestOverlay
            readonly property var hs: window.nativeHostSystemBackend
            anchors.fill: parent
            z: 9000
            color: "#99000000"
            visible: hs !== null && hs !== undefined && hs.cadPairingRequestPending
            MouseArea { anchors.fill: parent; preventStealing: true }
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 460)
                height: cadPairRequestColumn.implicitHeight + 32
                radius: 8
                color: "#FFFFFF"
                Column {
                    id: cadPairRequestColumn
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    Text {
                        text: qsTr("CAD PC PAIRING REQUEST")
                        font.bold: true; font.pixelSize: 16; color: "#0F172A"
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: 13; color: "#0F172A"
                        text: cadPairRequestOverlay.visible
                              ? qsTr("PC \"%1\" (%2) wants to send parts to this machine and read its tooling and material preferences.")
                                    .arg(cadPairRequestOverlay.hs.cadPairingRequestLabel)
                                    .arg(cadPairRequestOverlay.hs.cadPairingRequestAddress)
                              : ""
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                        font.pixelSize: 10; color: "#475569"
                        text: cadPairRequestOverlay.visible
                              ? qsTr("Key: ") + cadPairRequestOverlay.hs.cadPairingRequestFingerprint : ""
                    }
                    Row {
                        spacing: 12
                        anchors.right: parent.right
                        Button {
                            objectName: "cad-pair-reject"
                            text: qsTr("REJECT")
                            width: 130; height: 44
                            onClicked: cadPairRequestOverlay.hs.rejectCadPairingRequest()
                        }
                        Button {
                            objectName: "cad-pair-accept"
                            text: qsTr("ACCEPT")
                            width: 130; height: 44
                            onClicked: cadPairRequestOverlay.hs.acceptCadPairingRequest()
                        }
                    }
                }
            }
        }

        // Hosted in its own popup so it stacks above modal popups (CAD import
        // browser, rename dialogs); a plain Item would render underneath them.
        Popup {
            id: onScreenKeyboardPopup
            parent: Overlay.overlay
            x: 0; y: 0
            width: parent ? parent.width : 0
            height: parent ? parent.height : 0
            padding: 0
            modal: false
            focus: false
            z: 10000
            closePolicy: Popup.NoAutoClose
            background: null
            visible: appState.onScreenKeyboardVisible
            OnScreenKeyboard {
                id: onScreenKeyboard
                anchors.fill: parent
                appState: appState
            }
        }

        // Supervised flash without UI restart: modal while the helper owns the
        // Press port (QUEUING..terminal). Blocks all input underneath.
        Rectangle {
            id: firmwareFlashOverlay
            readonly property var fw: window.nativeMachineFirmwareBackend
            readonly property string fwState: fw ? fw.flashState : ""
            anchors.fill: parent
            z: 20000
            color: "#cc1b1c1b"
            visible: fw !== null && fw.busy
                     && ["QUEUING", "QUEUED", "FLASHING", "ROLLING_BACK"].indexOf(fwState) >= 0
            MouseArea { anchors.fill: parent; hoverEnabled: true; preventStealing: true }
            Column {
                anchors.centerIn: parent
                spacing: 18
                width: parent.width * 0.6
                BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: firmwareFlashOverlay.visible }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    color: "white"
                    font.pixelSize: 34
                    font.bold: true
                    text: firmwareFlashOverlay.fwState === "ROLLING_BACK"
                          ? qsTr("Restoring original firmware…") : qsTr("Installing firmware…")
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#e0e0e0"
                    font.pixelSize: 18
                    text: qsTr("Do not power off the machine. The press will reconnect automatically when finished.")
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#a8a8a8"
                    font.pixelSize: 14
                    text: firmwareFlashOverlay.fw ? firmwareFlashOverlay.fw.flashMessage : ""
                }
                // Same progress the Maintenance tab shows: stage + helper log tail.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Repeater {
                        model: [qsTr("QUEUED"), qsTr("FLASHING"), qsTr("RECONNECT")]
                        Rectangle {
                            readonly property int stage: firmwareFlashOverlay.fwState === "FLASHING"
                                || firmwareFlashOverlay.fwState === "ROLLING_BACK" ? 1 : 0
                            width: 150; height: 34; radius: 6
                            color: index < stage ? "#2E7D32" : (index === stage ? "#F59E0B" : "#3A3B3A")
                            Text {
                                anchors.centerIn: parent
                                text: (index + 1) + ". " + modelData
                                color: "white"; font.pixelSize: 15; font.bold: true
                            }
                        }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 150
                    radius: 6
                    color: "#111211"
                    border.color: "#3A3B3A"
                    visible: logTailText.text.length > 0
                    clip: true
                    Text {
                        id: logTailText
                        anchors.fill: parent
                        anchors.margins: 10
                        text: firmwareFlashOverlay.fw ? firmwareFlashOverlay.fw.flashLogTail : ""
                        color: "#B8C4B8"
                        font.pixelSize: 13
                        font.family: "monospace"
                        wrapMode: Text.NoWrap
                        verticalAlignment: Text.AlignBottom
                    }
                }
            }
        }
    }
}
