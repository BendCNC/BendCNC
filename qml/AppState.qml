import QtQuick
import QtCore
import QtQml.WorkerScript
import Qt.labs.settings
import "core/BendCalculator.js" as BendCalculator
import "core/ToolingPlanningEngine.js" as ToolingEngine
import "core/UnfoldPlanMapping.js" as UnfoldPlan
import "core/execution/ExecutionStateModel.js" as ExecutionModel
import "core/execution/DwellAndBailOut.js" as DwellAndBailOut
import "core/storage/EntityStorage.js" as EntityStorage
import "core/storage/EntityEditingManager.js" as EntityEditingManager
import "core/settings/SettingsModel.js" as SettingsModel
import "core/machine/BackGauge.js" as BackGauge
import "core/Units.js" as Units
import "core/sheetmetal/SheetMetalPoseGraph.js" as SheetMetalPoseGraph

QtObject {
    id: appState

    // The native controller owns all production machine state. Legacy reducer
    // mutation is available only when a test/snapshot explicitly opts in.
    property var machineControl: null
    property bool offlineSimulationEnabled: false
    property bool persistentLegacyRunUiSettingLoaded: false

    property Settings persistentSettings: Settings {
        category: "BendCNC"
    }

    // Program switch feedback: true from the tap until the new run frame is
    // ready. The actual switch is deferred one tick so the overlay can paint
    // before the synchronous model/scene work blocks the GUI thread.
    property bool runProgramSwitching: false
    property string runProgramSwitchName: ""
    property int runProgramSwitchPendingIndex: -1
    property double runProgramSwitchStartedMs: 0
    property Timer runProgramSwitchTimer: Timer {
        interval: 40
        repeat: false
        onTriggered: {
            var index = runProgramSwitchPendingIndex
            runProgramSwitchPendingIndex = -1
            if (index >= 0)
                selectProgram(index)
        }
    }
    // Safety net: never leave the overlay stuck.
    property Timer runProgramSwitchWatchdog: Timer {
        interval: 20000
        repeat: false
        onTriggered: finishRunProgramSwitch("timeout")
    }

    property bool popupVisible: false
    property string popupTitle: ""
    property string popupBody: ""
    property string popupKind: "blur"
    property real popupProgress: 0
    property string popupButtonText: "CANCEL"
    property string popupCancelButtonText: "CANCEL"
    property string popupAction: ""
    property string popupImageSource: ""
    property var popupPrimaryHandler: null
    property var popupCancelHandler: null
    property var popupResultData: ({})
    property bool lastProgramPersistenceSucceeded: false
    property bool alarmVisible: false
    property string alarmTitle: "MACHINE ALARM"
    property string alarmBody: ""
    property var logEntries: []
    property ListModel machineLogModel: ListModel { }
    property bool machineLogStatusReportsEnabled: false
    property bool machineLogAutoScrollEnabled: true
    property int machineLogMaximumEntries: 10000
    property var hostSystem: null
    // Cloud license / 30-day trial (LicenseManager). Gates only *starting* a
    // physical RUN; never interrupts a cycle in progress.
    property var licenseManager: null
    property bool licensePanelVisible: false
    readonly property bool licenseEnforced: licenseManager ? licenseManager.enforced === true : false
    readonly property bool licenseRunAllowed: licenseManager ? licenseManager.runAllowed === true : true
    function openLicensePanel() { licensePanelVisible = true }
    function closeLicensePanel() { licensePanelVisible = false }
    function licenseBlocksPhysicalRun() {
        if (offlineSimulationEnabled || licenseRunAllowed)
            return false
        log("LICENSE", "Physical RUN blocked: license status " + String(licenseManager.status))
        openLicensePanel()
        return true
    }
    // Settings -> Maintenance -> MACHINE FIRMWARE (MachineFirmwareBackend).
    property var machineFirmware: null
    readonly property bool machineFirmwareUiGateClear: !runActive && !runToolChangeActive
        && !manualActivationPending
    onHostSystemChanged: if (hostSystem)
        Qt.callLater(function() { hostSystem.checkForApplicationUpdates() })
    readonly property var wifiNetworks: hostSystem ? hostSystem.wifiNetworks : []
    readonly property bool wifiConnected: {
        for (let index = 0; index < wifiNetworks.length; ++index) {
            if (wifiNetworks[index] && wifiNetworks[index].connected === true)
                return true
        }
        return false
    }
    readonly property string systemSummary: hostSystem ? hostSystem.systemSummary : "System service unavailable"
    readonly property bool cpuLoadAvailable: hostSystem
        ? hostSystem.cpuLoadAvailable : false
    readonly property real cpuLoadPercent: cpuLoadAvailable
        ? hostSystem.cpuLoadPercent : 0
    readonly property bool cpuTemperatureAvailable: hostSystem
        ? hostSystem.cpuTemperatureAvailable : false
    readonly property real cpuTemperatureCelsius: cpuTemperatureAvailable
        ? hostSystem.cpuTemperatureCelsius : 0
    readonly property string cpuLoadText: cpuLoadAvailable
        ? cpuLoadPercent.toFixed(1) + "%" : "--"
    readonly property string cpuTemperatureText: cpuTemperatureAvailable
        ? cpuTemperatureCelsius.toFixed(1) + "°C" : "--"
    readonly property string cpuLoadLevel: !cpuLoadAvailable ? "unknown"
        : (cpuLoadPercent < 51 ? "low" : (cpuLoadPercent < 76 ? "medium" : "high"))
    readonly property string cpuTemperatureLevel: !cpuTemperatureAvailable ? "unknown"
        : (cpuTemperatureCelsius < 60 ? "low"
           : (cpuTemperatureCelsius < 80 ? "medium" : "high"))
    readonly property bool memoryAvailable: hostSystem
        ? hostSystem.memoryAvailable : false
    readonly property real memoryUsedPercent: memoryAvailable
        ? hostSystem.memoryUsedPercent : 0
    readonly property real memoryUsedBytes: memoryAvailable
        ? hostSystem.memoryUsedBytes : 0
    readonly property real memoryTotalBytes: memoryAvailable
        ? hostSystem.memoryTotalBytes : 0
    readonly property string memoryText: memoryAvailable
        ? hostSystem.memoryUsageText : "--"
    readonly property string memoryDetailText: memoryAvailable
        ? (memoryUsedBytes / 1073741824).toFixed(1) + " / "
          + (memoryTotalBytes / 1073741824).toFixed(1) + " GiB"
        : "--"
    readonly property string memoryLevel: !memoryAvailable ? "unknown"
        : (memoryUsedPercent < 75 ? "low"
           : (memoryUsedPercent < 90 ? "medium" : "high"))
    readonly property bool hostOperationsAvailable: hostSystem && !hostSystem.offlineValidation
        && !hostSystem.operationActive
    readonly property bool hostOperationActive: hostSystem ? hostSystem.operationActive : false
    readonly property real hostOperationProgress: hostSystem ? hostSystem.operationProgress : 0
    property string selectedUpdatePackage: ""
    readonly property var systemLogs: hostSystem ? hostSystem.systemLogs : []
    readonly property string applicationVersion: hostSystem
        ? String(hostSystem.applicationVersion || "") : ""
    readonly property bool applicationUpdateAvailable: hostSystem
        ? hostSystem.applicationUpdateAvailable === true : false
    readonly property string applicationUpdateVersion: hostSystem
        ? String(hostSystem.applicationUpdateVersion || "") : ""
    readonly property bool moduleUpdateAvailable: false
    readonly property var remoteFirmwareImage: {
        var images = machineFirmware ? machineFirmware.images : []
        for (var i = 0; images && i < images.length; i++)
            if (images[i].remote === true)
                return images[i]
        return null
    }
    readonly property bool machineUpdateAvailable: remoteFirmwareImage !== null
        && machineFirmware && !machineFirmware.busy
        && String(remoteFirmwareImage.sha256 || "") !== String(machineFirmware.appliedHash || "")
    property string lastLoggedUpdateKey: ""
    property string latestLog: "Ready"
    property bool machineConnected: offlineSimulationEnabled
        ? true : (machineControl ? machineControl.pressConnected : false)
    property bool moduleConnected: offlineSimulationEnabled
        ? true : (machineControl ? machineControl.moduleConnected : false)
    // A stale "<DEVICE> CONNECTION FAILED" alarm closes itself once that device reconnects.
    onMachineConnectedChanged: if (machineConnected) clearConnectionAlarm("MACHINE")
    onModuleConnectedChanged: if (moduleConnected) clearConnectionAlarm("BACK GAUGE")
    function clearConnectionAlarm(name) {
        if (alarmVisible && alarmTitle === name + " CONNECTION FAILED")
            clearAlarm()
    }
    readonly property string machineConnectionState: offlineSimulationEnabled
        ? "READY" : (machineControl ? machineControl.pressConnectionState : "DISCONNECTED")
    readonly property string moduleConnectionState: offlineSimulationEnabled
        ? "READY" : (machineControl ? machineControl.moduleConnectionState : "DISCONNECTED")
    readonly property bool machineControllerAlarm: !offlineSimulationEnabled
        && machineConnectionState === "READY"
        && machineStatus !== "UNKNOWN" && machineStatus !== "IDLE"
        && machineStatus !== "STARTUP_HOMING_REQUIRED"
        && machineStatus !== "HOMING" && machineStatus !== "HOMING_BUMP"
        && machineStatus !== "SAFETY_JOG" && machineStatus !== "SAFETY_JOG_HOLD"
        && machineStatus !== "CLAMP_JOG" && machineStatus !== "CLAMP_JOG_HOLD"
        && machineStatus !== "BEND_JOG" && machineStatus !== "BEND_DEPTH_REACHED"
        && machineStatus !== "BEND_JOG_HOLD" && machineStatus !== "RETRACT_JOG"
        && machineStatus !== "RELEASE_LOAD_RETRACT" && machineStatus !== "PRIMING_MODE"
    readonly property bool moduleControllerAlarm: !offlineSimulationEnabled
        && moduleConnectionState === "READY"
        && (backGaugeStatus === "ALARM" || backGaugeStatus.indexOf("DOOR_") === 0)
    readonly property string machineToolbarState: machineControllerAlarm
        ? "READY_WITH_ALARM" : machineConnectionState
    readonly property string moduleToolbarState: moduleControllerAlarm
        ? "READY_WITH_ALARM" : moduleConnectionState
    property string machineName: machineControl && machineControl.pressFirmwareVersion.length > 0
        ? "LS-BEND " + machineControl.pressFirmwareVersion : "LS-BEND"
    property string moduleName: machineControl && machineControl.moduleFirmwareVersion.length > 0
        ? "BACK GAUGE " + machineControl.moduleFirmwareVersion : "BACK GAUGE"
    property string lastConnectionFailureDevice: ""
    property string lastConnectionFailureReason: ""
    property string lastHomeFailureDevice: ""
    property string lastHomeFailureReason: ""
    property real backGaugeX: offlineSimulationEnabled
        ? 0 : (machineControl && machineControl.moduleTelemetryFresh ? machineControl.moduleWorkX : 0)
    property real backGaugeR: offlineSimulationEnabled
        ? 0 : (machineControl && machineControl.moduleTelemetryFresh ? machineControl.moduleWorkR : 0)
    property real backGaugeMachineX: offlineSimulationEnabled
        ? 0 : (machineControl && machineControl.moduleTelemetryFresh ? machineControl.moduleMachineX : 0)
    property real backGaugeMachineR: offlineSimulationEnabled
        ? 0 : (machineControl && machineControl.moduleTelemetryFresh ? machineControl.moduleMachineR : 0)
    readonly property bool backGaugePositionAvailable: offlineSimulationEnabled
        || (machineControl && machineControl.moduleTelemetryFresh)
    property string backGaugeStatus: offlineSimulationEnabled
        ? "IDLE" : (machineControl ? machineControl.moduleState : "UNKNOWN")
    property bool backGaugeBusy: offlineSimulationEnabled
        ? false : (machineControl ? machineControl.moduleOperationActive : false)
    property bool backGaugeContinuousJog: true
    property string backGaugeActiveDirection: ""
    readonly property var backGaugeCoordinateSystems: ["G54", "G55", "G56", "G57", "G58", "G59"]
    readonly property var defaultBackGaugeCoordinateNames: ({
        G54: "LOWER FINGER EDGE",
        G55: "UPPER FINGER EDGE",
        G56: "LOWER FINGER EDGE",
        G57: "UPPER FINGER EDGE",
        G59: "CUSTOM"
    })
    // Die-height compensation. AUTO: R is corrected by (active die height - die height
    // recorded when the reference R was set). Each reference belongs to the AUTO or the
    // MANUAL list; the selector shows only the list of the current mode.
    property bool backGaugeDieCompensationAuto: true
    readonly property var defaultBackGaugeReferenceModes: ({
        G54: "AUTO", G55: "AUTO", G56: "MANUAL", G57: "MANUAL", G59: "MANUAL"
    })
    property var backGaugeReferenceModes: ({})
    property var backGaugeCalibrationDies: ({})
    readonly property string backGaugeCompensationMode: backGaugeDieCompensationAuto ? "AUTO" : "MANUAL"
    function backGaugeReferenceMode(system) {
        var key = String(system || backGaugeCoordinateSystem)
        return backGaugeReferenceModes[key] || defaultBackGaugeReferenceModes[key] || "MANUAL"
    }
    // Visible references: named slots (defaults or operator-added) of the current mode.
    readonly property var backGaugeActiveCoordinateSystems: {
        var list = []
        for (var i = 0; i < backGaugeCoordinateSystems.length; i++) {
            var id = backGaugeCoordinateSystems[i]
            if ((defaultBackGaugeCoordinateNames[id] || backGaugeCoordinateNames[id])
                    && backGaugeReferenceMode(id) === backGaugeCompensationMode)
                list.push(id)
        }
        return list
    }
    function backGaugeSlotUsed(id) {
        return !!(defaultBackGaugeCoordinateNames[id] || backGaugeCoordinateNames[id])
    }
    function setBackGaugeDieCompensationAuto(enabled) {
        backGaugeDieCompensationAuto = enabled === true
        persistUserSetting("backGaugeDieCompensationAuto", backGaugeDieCompensationAuto)
        var list = backGaugeActiveCoordinateSystems
        if (list.length > 0 && list.indexOf(backGaugeCoordinateSystem) < 0)
            selectBackGaugeCoordinateSystem(list[0])
        log("BACK GAUGE", "Die height compensation " + backGaugeCompensationMode)
    }
    function dieRecordForBend(bend) {
        var library = programToolingLibrary || ({})
        var die = findById(library.dies, String(valueOr(bend || selectedBend || ({}), "dieId", "")))
        var h = die ? Number(die.heightInch) : NaN
        return die && h > 0 ? { dieId: String(die.id || ""), name: String(die.name || ""), heightInch: h } : null
    }
    function backGaugeCalibrationDie(system) {
        return backGaugeCalibrationDies[String(system || backGaugeCoordinateSystem)] || null
    }
    function recordBackGaugeCalibrationDie(system) {
        var die = dieRecordForBend(selectedBend)
        if (!die)
            return false
        var map = Object.assign({}, backGaugeCalibrationDies)
        map[String(system || backGaugeCoordinateSystem)] = die
        backGaugeCalibrationDies = map
        persistUserSetting("backGaugeCalibrationDies", map)
        log("BACK GAUGE", "Calibration die for " + system + ": " + die.name + " " + die.heightInch.toFixed(3) + " in")
        return true
    }
    // R correction (in) added to a programmed R for the given reference and bend.
    function backGaugeDieCompensationR(system, bend) {
        var key = String(system || backGaugeCoordinateSystem)
        if (!backGaugeDieCompensationAuto || backGaugeReferenceMode(key) !== "AUTO")
            return 0
        var cal = backGaugeCalibrationDie(key)
        var active = dieRecordForBend(bend)
        if (!cal || !active || !(Number(cal.heightInch) > 0))
            return 0
        return active.heightInch - Number(cal.heightInch)
    }
    function addBackGaugeCoordinateSystem(name) {
        var clean = String(name || "").trim()
        if (clean.length === 0)
            return ""
        for (var i = 0; i < backGaugeCoordinateSystems.length; i++) {
            var id = backGaugeCoordinateSystems[i]
            if (backGaugeSlotUsed(id))
                continue
            var modes = Object.assign({}, backGaugeReferenceModes)
            modes[id] = backGaugeCompensationMode
            backGaugeReferenceModes = modes
            persistUserSetting("backGaugeReferenceModes", modes)
            if (!selectBackGaugeCoordinateSystem(id))
                return ""
            renameBackGaugeCoordinateSystem(clean)
            return id
        }
        showPopup("NO FREE REFERENCE", "All 6 work coordinate slots (G54-G59) are in use.", 1, "caution", "CLOSE")
        return ""
    }
    // Contact point on the finger side profile (inches from the front-bottom corner of the
    // nose) and the default R elevation for that reference. EDGE = sheet flush on the step
    // edge (R 0). FACE = finger lowered 0.25 in so the sheet bears on the vertical face and
    // cannot slip over the edge. dx 0.972 = original STEP finger tongue tip (4.0) to
    // step face (3.028); see docs/backgauge-finger-original.md.
    // FLAT finger step face at 3.00 in -> dx 1.0.
    readonly property real backGaugeFaceDx: backgaugeFingerStyle === "FLAT" ? 1.0 : 0.972
    readonly property var backGaugeReferenceGeometry: ({
        G54: { dx: 0.0, dy: 0.0,   r: 0.0 },
        G55: { dx: backGaugeFaceDx, dy: 0.375, r: 0.0 },
        G56: { dx: 0.0, dy: 0.0,   r: 0.0 },
        G57: { dx: backGaugeFaceDx, dy: 0.375, r: 0.0 }
    })
    function backGaugeReferencePoint(system) {
        return backGaugeReferenceGeometry[String(system || backGaugeCoordinateSystem)]
            || { dx: 0.0, dy: 0.0, r: 0.0 }
    }
    property string backGaugeCoordinateSystem: "G54"
    property var backGaugeCoordinateOffsets: ({ G54: { x: 0, r: 0 }, G55: { x: 0, r: 0 }, G56: { x: 0, r: 0 }, G57: { x: 0, r: 0 }, G58: { x: 0, r: 0 }, G59: { x: 0, r: 0 } })
    property var backGaugeCoordinateNames: ({})
    readonly property var backGaugeCoordinateProfiles: {
        var profiles = []
        for (var index = 0; index < backGaugeCoordinateSystems.length; index++) {
            var id = backGaugeCoordinateSystems[index]
            profiles.push({ id: id, label: backGaugeCoordinateDisplayName(id) })
        }
        return profiles
    }
    property var backGaugeStepPresets: [0.0005, 0.001, 0.01, 0.1]
    property var backGaugeSpeedPresets: [1, 10, 25, 50, 75, 100]
    property real backGaugeMinJogStep: 0.0005
    property real backGaugeMaxJogStep: 22
    property real backGaugeMinJogSpeed: 1
    property real backGaugeMaxJogSpeed: 100
    property bool backGaugeLimitX1: offlineSimulationEnabled
        ? false : (machineControl ? machineControl.moduleLimitX1 : false)
    property bool backGaugeLimitX2: offlineSimulationEnabled
        ? false : (machineControl ? machineControl.moduleLimitX2 : false)
    property bool backGaugeLimitR1: offlineSimulationEnabled
        ? false : (machineControl ? machineControl.moduleLimitR1 : false)
    property bool backGaugeLimitR2: offlineSimulationEnabled
        ? false : (machineControl ? machineControl.moduleLimitR2 : false)
    property var backGaugeLastCommands: []
    property string backGaugeUnit: "INCH"
    property string virtualInputMode: "ALWAYS"
    property bool onScreenKeyboardVisible: false
    property string onScreenKeyboardKind: "text"
    property string onScreenKeyboardTitle: "ENTER VALUE"
    property string onScreenKeyboardValue: ""
    property int onScreenKeyboardCursor: 0
    property bool onScreenKeyboardOriginalValue: false
    property string onScreenKeyboardShiftState: "NONE"
    property bool onScreenKeyboardSymbols: false
    property var onScreenKeyboardTarget: null
    property var onScreenKeyboardCommitHandler: null
    property var onScreenKeyboardCancelHandler: null
    property real jogStep: 0.1
    property real jogSpeed: 100
    property string machineStatus: offlineSimulationEnabled
        ? "IDLE" : (machineControl ? machineControl.pressMachineState : "UNKNOWN")

    function homeFailureMessage(reason) {
        if (reason === "HOME_RECOVERY_NOT_SETTLED")
            return "Home was not started: recovery standstill or safe position is not yet qualified. Keep the machine stopped; request Home again only after it is stable. If refusal persists, inspect the fault and position. No Home is queued."
        if (reason === "CONTROLLER_ALARM_ACTIVE")
            return "Home was rejected by the controller: a retained safety fault requires inspection. Home did not clear the alarm. No automatic retry is queued."
        return "The controller did not complete homing: " + String(reason).replace(/_/g, " ") + "."
    }

    function automaticTonnageHoldFailureMessage(reason) {
        if (reason === "FORCE_TIMEOUT" || reason === "THC_ERROR_FORCE_TIMEOUT")
            return qsTr("The force target was not held for five fresh consecutive samples within 60 seconds. Keep the press stopped, inspect the setup, then use the confirmed Home action before another AUTO attempt. No Home or AUTO retry is queued.")
        if (reason === "THC_ERROR_FORMAT" || reason === "THC_ERROR_ARGUMENT")
            return qsTr("The controller refused the %1 T automatic target. The installed firmware only runs AUTO at 1.00 T until the AUTO-target firmware is flashed; set the target to 1.00 T or use PEDAL.")
                .arg(Number(contactProfileTarget).toFixed(2))
        return String(reason || "FAILED").replace(/_/g, " ")
    }

    property Connections machineControlConnections: Connections {
        target: appState.machineControl
        ignoreUnknownSignals: true

        function onRamLevelOffsetReported(inches) {
            appState.ramLevelOffset = Number(inches)
        }

        function onConnectionFailed(device, reason) {
            if (String(device || "") === appState.lastHomeFailureDevice
                    && String(reason || "UNKNOWN") === appState.lastHomeFailureReason) {
                appState.lastHomeFailureDevice = ""
                appState.lastHomeFailureReason = ""
                return
            }
            appState.lastConnectionFailureDevice = String(device || "")
            appState.lastConnectionFailureReason = String(reason || "UNKNOWN")
            if (String(device || "") === "press" && appState.contactProfileActive)
                appState.finishTonnageHoldProfile(false, "CONNECTION_FAILED")
            if (String(device || "") === "press"
                    && (appState.manualPendingOperation.length > 0
                        || appState.manualActivationPending || appState.manualLeavePending
                    || appState.tonnageHoldActive))
                appState.failManualLifecycle()
            if (appState.runActive)
                appState.failPhysicalRun(String(device || "CONTROLLER").toUpperCase()
                                         + "_CONNECTION_FAILED_" + String(reason || "UNKNOWN"))
            appState.showBackendFailure(device, reason)
        }

        function onRemoteRunRequested() {
            appState.handleRemoteRunRequest()
        }

        function onToolChangeEvent(event, position) {
            appState.handleToolChangeEvent(String(event || ""), position)
        }

        function onOperationRejected(device, operation, reason) {
            var normalizedDevice = String(device || "")
            var normalizedReason = String(reason || "UNKNOWN")
            if (String(operation || "") === "connect"
                    && normalizedDevice === appState.lastConnectionFailureDevice
                    && normalizedReason === appState.lastConnectionFailureReason)
                return
            appState.showBackendRejection(device, operation, reason)
        }

        function onCommandOperationFinished(id, device, operation, state, error) {
            var normalizedOperation = String(operation || "")
            var normalizedDevice = String(device || "")
            var normalizedState = String(state || "")
            if (normalizedDevice === "press"
                    && normalizedOperation === "automatic-thc-contact-profile") {
                var owner = appState.contactProfileOwner
                appState.finishTonnageHoldProfile(normalizedState === "COMPLETED",
                                                  String(error || normalizedState))
                if (normalizedState === "COMPLETED" && owner !== "MANUAL") {
                    // The owning feature (Calibrate / Measure, ...) shows its
                    // own result; a completion popup would only cover it.
                    appState.log("TONNAGE HOLD", "Automatic " + Number(appState.contactProfileTarget).toFixed(2)
                                 + " T hold completed for " + (owner || "UNKNOWN"))
                } else if (normalizedState === "COMPLETED") {
                    appState.showPopup("AUTOMATIC HOLD COMPLETE",
                                       "Five fresh samples within ±" + appState.automaticHoldAcceptanceBand.toFixed(2)
                                       + " T were confirmed, release clearance completed, and the press returned to IDLE.",
                                       1, "message", "CLOSE")
                } else {
                    appState.showAlarm("AUTOMATIC HOLD FAILED",
                                       appState.automaticTonnageHoldFailureMessage(
                                           String(error || "FAILED")))
                }
                return
            }
            if (normalizedDevice === "press"
                    && normalizedOperation.indexOf("tool-change-") === 0) {
                appState.handleToolChangeOperationFinished(normalizedOperation,
                                                           normalizedState,
                                                           String(error || ""))
                return
            }
            if (normalizedDevice === "press"
                    && normalizedOperation === appState.bleedPendingOperation
                    && (appState.bleedPendingOperationId === undefined
                        || Number(id) === Number(appState.bleedPendingOperationId))) {
                appState.handleBleedOperationFinished(normalizedOperation,
                                                      normalizedState,
                                                      String(error || ""))
                return
            }
            if (normalizedDevice === "press"
                    && normalizedOperation === "set-ram-to-table-opening"
                    && appState.ramToTableSaveOperationId !== undefined
                    && Number(id) === Number(appState.ramToTableSaveOperationId)) {
                appState.ramToTableSaveOperationId = undefined
                if (appState.manualCalibrationOpeningOperationId !== undefined
                        && Number(id) === Number(appState.manualCalibrationOpeningOperationId)) {
                    appState.handleManualCalibrationOpeningFinished(normalizedState,
                                                                    String(error || ""))
                    return
                }
                if (normalizedState === "COMPLETED") {
                    appState.editedRamToTableOpening = NaN
                    appState.showPopup("CONTROLLER SETTINGS",
                                       "Ram To Table Opening Distance saved to controller EEPROM.",
                                       1, "message", "CLOSE")
                } else {
                    appState.showAlarm("CONTROLLER SETTINGS SAVE FAILED",
                                       String(error || "CONTROLLER_CONFIRMATION_FAILED").replace(/_/g, " "))
                }
                return
            }
            if (normalizedDevice === "press"
                    && normalizedOperation === appState.manualPendingOperation
                    && (appState.manualPendingOperationId === undefined
                        || Number(id) === Number(appState.manualPendingOperationId))
                    && appState.handleManualOperationFinished(
                    normalizedOperation, normalizedState, String(error || "")))
                return
            if (normalizedOperation === "home" && normalizedDevice === "press"
                    && appState.pressHomeOperationId !== undefined
                    && Number(id) === Number(appState.pressHomeOperationId)) {
                appState.pressHomeOperationId = undefined
                if (appState.backGaugeHomeOperationId === undefined)
                    appState.hidePopup()
                if (normalizedState === "COMPLETED") {
                    appState.log("MACHINE",
                                 "Controller telemetry confirmed homing completed")
                    if (appState.combinedHomeBackGaugePending) {
                        appState.combinedHomeBackGaugePending = false
                        appState.startBackGaugeHome()
                    }
                } else {
                    appState.combinedHomeBackGaugePending = false
                    appState.lastHomeFailureDevice = normalizedDevice
                    appState.lastHomeFailureReason = String(error || "HOMING_FAILED")
                    appState.showAlarm("MACHINE HOMING FAILED",
                                       appState.homeFailureMessage(appState.lastHomeFailureReason))
                }
            } else if (normalizedOperation === "home" && normalizedDevice === "module"
                       && appState.backGaugeHomeOperationId !== undefined
                       && Number(id) === Number(appState.backGaugeHomeOperationId)) {
                appState.backGaugeHomeOperationId = undefined
                if (appState.pressHomeOperationId === undefined)
                    appState.hidePopup()
                if (normalizedState === "COMPLETED") {
                    appState.log("BACK GAUGE",
                                 "Controller telemetry confirmed homing completed")
                } else {
                    appState.lastHomeFailureDevice = normalizedDevice
                    appState.lastHomeFailureReason = String(error || "HOMING_FAILED")
                    appState.showAlarm("BACK GAUGE HOMING FAILED",
                                       "The controller did not complete homing: "
                                       + appState.lastHomeFailureReason.replace(/_/g, " ") + ".")
                }
            } else if (normalizedOperation === "home" && normalizedState === "COMPLETED") {
                appState.log(normalizedDevice === "press" ? "MACHINE" : "BACK GAUGE",
                             "Controller telemetry confirmed homing completed")
            } else if (normalizedOperation === "home" && normalizedState === "FAILED") {
                appState.lastHomeFailureDevice = normalizedDevice
                appState.lastHomeFailureReason = String(error || "HOMING_FAILED")
                appState.showAlarm(normalizedDevice === "press" ? "MACHINE HOMING FAILED"
                                                                : "BACK GAUGE HOMING FAILED",
                                   appState.homeFailureMessage(appState.lastHomeFailureReason))
            } else if (appState.runActive && appState.physicalRunCommandPending
                       && normalizedOperation === appState.physicalRunPendingOperation
                       && normalizedDevice === appState.physicalRunPendingDevice
                       && Number(id) === Number(appState.physicalRunPendingOperationId)) {
                appState.handlePhysicalRunOperationFinished(normalizedOperation,
                                                            normalizedState,
                                                            String(error || ""))
            } else if (normalizedState === "COMPLETED") {
                appState.log(normalizedDevice === "press" ? "MACHINE" : "BACK GAUGE",
                             normalizedOperation + " completed from controller telemetry")
                if (normalizedDevice === "module")
                    appState.backGaugeActiveDirection = ""
                if (normalizedDevice === "press")
                    appState.manualModeState = "IDLE"
            } else if (normalizedState === "FAILED") {
                if (normalizedDevice === "module")
                    appState.backGaugeActiveDirection = ""
                if (normalizedDevice === "press")
                    appState.manualModeState = "IDLE"
                appState.showAlarm(normalizedDevice === "press" ? "MACHINE OPERATION FAILED"
                                                                 : "BACK GAUGE OPERATION FAILED",
                                   normalizedOperation.replace(/-/g, " ").toUpperCase()
                                   + ": " + String(error || "FAILED").replace(/_/g, " "))
            }
        }
        function onPressSerialLogLine(source, content) {
            appState.appendMachineLog(source, content)
        }
        function onRamTargetPositionChanged() {
            if (appState.machineControl.pressTelemetryFresh)
                appState.lastValidRamTargetPosition = Number(appState.machineControl.ramTargetPosition)
        }
        function onRamPositionY1Changed() {
            if (appState.machineControl.pressTelemetryFresh
                    && appState.machineControl.independentRamTelemetryAvailable)
                appState.lastValidRamPhysicalPosition =
                    (Number(appState.machineControl.ramPositionY1)
                     + Number(appState.machineControl.ramPositionY2)) / 2.0
        }
        function onRamPositionY2Changed() {
            if (appState.machineControl.pressTelemetryFresh
                    && appState.machineControl.independentRamTelemetryAvailable)
                appState.lastValidRamPhysicalPosition =
                    (Number(appState.machineControl.ramPositionY1)
                     + Number(appState.machineControl.ramPositionY2)) / 2.0
        }
        function onRamCommandedJogPositionChanged() {
            if (machineControl.pressTelemetryFresh)
                appState.lastValidCommandedJogPosition = Number(machineControl.ramCommandedJogPosition)
        }
        function onRamDistanceToGoChanged() {
            if (machineControl.pressTelemetryFresh)
                appState.lastValidDistanceToGo = Number(machineControl.ramDistanceToGo)
        }
        function onPressTelemetryFreshChanged() {
            if (!appState.machineControl.pressTelemetryFresh)
                return
            appState.lastValidRamTargetPosition = Number(appState.machineControl.ramTargetPosition)
            if (appState.machineControl.independentRamTelemetryAvailable)
                appState.lastValidRamPhysicalPosition =
                    (Number(appState.machineControl.ramPositionY1)
                     + Number(appState.machineControl.ramPositionY2)) / 2.0
            appState.lastValidCommandedJogPosition = Number(appState.machineControl.ramCommandedJogPosition)
            appState.lastValidDistanceToGo = Number(appState.machineControl.ramDistanceToGo)
        }
        function onTelemetryChanged() {
            if (appState.manualMeasurementSampler.running)
                appState.sampleManualMeasurement()
        }
    }

    property Connections hostSystemConnections: Connections {
        target: appState.hostSystem
        ignoreUnknownSignals: true

        function onWifiConnectionFinished(success, ssid, error) {
            if (success) {
                appState.popupBody = "CONNECTED TO " + String(ssid || "")
            } else {
                appState.showAlarm("WIFI CONNECTION",
                                   String(error || "WiFi connection failed."))
            }
        }

        function onUpdateAvailabilityChanged() {
            var h = appState.hostSystem
            if (!h)
                return
            var key = String(h.updateCheckError || "") + "|" + appState.applicationUpdateVersion
                + "|" + String(h.applicationUpdateState || "") + "|" + String(h.applicationUpdateMessage || "")
            if (key === appState.lastLoggedUpdateKey)
                return
            appState.lastLoggedUpdateKey = key
            if (String(h.updateCheckError || "").length > 0)
                appState.log("UPDATE", String(h.updateCheckError))
            else if (appState.applicationUpdateAvailable)
                appState.log("UPDATE", "Application " + appState.applicationUpdateVersion
                             + " is newer than " + appState.applicationVersion)
            if (String(h.applicationUpdateMessage || "").length > 0)
                appState.log("UPDATE", String(h.applicationUpdateState) + ": " + String(h.applicationUpdateMessage))
            if (h.applicationUpdateState === "FAILED")
                appState.showPopup("APPLICATION UPDATE FAILED", String(h.applicationUpdateMessage), 1, "message", "CLOSE")
        }
    }
    readonly property bool independentRamTelemetryAvailable: !offlineSimulationEnabled
        && machineControl && machineControl.independentRamTelemetryAvailable
    readonly property real ramPositionY1: independentRamTelemetryAvailable ? machineControl.ramPositionY1 : 0
    readonly property real ramPositionY2: independentRamTelemetryAvailable ? machineControl.ramPositionY2 : 0
    readonly property real ramLoadY1: independentRamTelemetryAvailable ? machineControl.ramLoadY1 : 0
    readonly property real ramLoadY2: independentRamTelemetryAvailable ? machineControl.ramLoadY2 : 0
        // Current position is physical ram position: the mean of the two
        // independent encoder channels. The legacy controller trajectory is
        // retained only as a fallback when independent telemetry is absent.
                property real lastValidRamTargetPosition: 0
                property real lastValidRamPhysicalPosition: 0
                property real lastValidCommandedJogPosition: 0
                property real lastValidDistanceToGo: 0
                readonly property real rawRamPosition: offlineSimulationEnabled ? ramPosition
                : machineControl && machineControl.pressTelemetryFresh
                    && independentRamTelemetryAvailable
                    ? (ramPositionY1 + ramPositionY2) / 2.0
                    : independentRamTelemetryAvailable
                        ? lastValidRamPhysicalPosition : rawRamControlPosition
                readonly property real rawRamControlPosition: offlineSimulationEnabled ? ramPosition
                : machineControl && machineControl.pressTelemetryFresh
                    ? Number(machineControl.ramTargetPosition) : lastValidRamTargetPosition
        readonly property real rawRamVelocity: offlineSimulationEnabled ? 0
                : machineControl && machineControl.ramVelocity !== undefined
                    ? Number(machineControl.ramVelocity) : 0
        readonly property bool measuredRamVelocityAvailable: offlineSimulationEnabled
            || (machineControl && machineControl.pressTelemetryFresh
                && machineControl.measuredRamVelocityAvailable === true)
        readonly property real measuredRamVelocity: offlineSimulationEnabled ? rawRamVelocity
            : measuredRamVelocityAvailable ? Number(machineControl.measuredRamVelocity) : 0
        readonly property bool motorRpmAvailable: !offlineSimulationEnabled
            && machineControl && machineControl.pressTelemetryFresh
            && machineControl.motorRpmAvailable === true
        readonly property real motorRpmY1: motorRpmAvailable ? Number(machineControl.motorRpmY1) : 0
        readonly property real motorRpmY2: motorRpmAvailable ? Number(machineControl.motorRpmY2) : 0
        property real ramPosition: 0
    property real commandedJogPosition: offlineSimulationEnabled
        ? -0.05 : (machineControl && machineControl.pressTelemetryFresh
            ? machineControl.ramCommandedJogPosition : lastValidCommandedJogPosition)
    property real commandedJogSpeed: offlineSimulationEnabled
        ? 0 : (machineControl && machineControl.pressTelemetryFresh ? machineControl.ramJogSpeed : 0)
    property real distanceToGo: offlineSimulationEnabled
        ? 0 : (machineControl && machineControl.pressTelemetryFresh
            ? machineControl.ramDistanceToGo : lastValidDistanceToGo)
    property real bendRamSpeed: 5
    property real jogRamSpeed: 5
    // Event-driven: follows telemetry only when it changes (the former 16 ms
    // copy timer woke the GUI thread 60x/s while idle).
    property Binding ramPresentationBinding: Binding {
        target: appState
        property: "ramPosition"
        value: appState.rawRamPosition
        when: !appState.offlineSimulationEnabled && appState.machineConnected
        restoreMode: Binding.RestoreNone
    }
    // Editable while disconnected (no motion possible) or while the press is idle.
    readonly property bool ramSpeedCanEdit: offlineSimulationEnabled
        || !machineConnected
        || (machineConnected && machineControl && machineControl.pressTelemetryFresh
            && machineStatus === "IDLE" && !machineControl.pressOperationActive
            && !runActive && !tonnageHoldActive
            && (manualModeState === "IDLE" || manualModeState === "ENABLED"))
    property bool tonnageHoldStopRequested: false
    property bool leftSafetyJog: offlineSimulationEnabled
        ? false : (machineControl ? machineControl.safetyJogLeft : false)
    property bool rightSafetyJog: offlineSimulationEnabled
        ? false : (machineControl ? machineControl.safetyJogRight : false)
    property bool bendJogPedal: offlineSimulationEnabled
        ? false : (machineControl ? machineControl.bendPedal : false)
    readonly property bool physicalPedalActive: offlineSimulationEnabled
        ? bendJogPedal
        : (machineControl && machineControl.pressTelemetryFresh
            ? (machineControl.physicalPedalAvailable === true
                ? machineControl.physicalPedal : machineControl.bendPedal)
            : false)
    property bool antiBindSwitch: offlineSimulationEnabled
        ? false : (machineControl ? machineControl.antiBind : false)
    property string activeProgram: "Enclosure Box - Electronics Module"
    property string activeProgramCadPreviewJson: ""
    property var programs: [
        {
            name: "Enclosure Box - Electronics Module",
            source: "sample",
            bends: [
                { seq: 1, name: "Enclosure Box - Small Flange", angle: "90.0", compensation: "0.8", state: "OVERBENT", x: "-1.0000", r: "0.0000", speed: "100.000", tonnage: "0.079", thickness: "0.1250", material: "Cold Rolled Steel (e.g. A366/1008)", punch: "Gooseneck 88° Punch", die: "4 Way Die (0.630in)", startPosition: "-1.7890", clampPosition: "-1.8452", finalPosition: "-2.0726" },
                { seq: 2, name: "Enclosure Box - Large Flange", angle: "90.0", compensation: "0.8", state: "OVERBENT", x: "-2.0000", r: "0.0000", speed: "100.000", tonnage: "0.036", thickness: "0.1250", material: "Cold Rolled Steel (e.g. A366/1008)", punch: "Gooseneck 88° Punch", die: "4 Way Die (0.630in)", startPosition: "-1.7890", clampPosition: "-1.8452", finalPosition: "-2.0726" }
            ]
        }
    ]
    property int selectedProgramIndex: 0
    // PROGRAMS tab: one-level folder names (may be empty folders). Each
    // program stores its own `folder` ("" = unfiled); this list is kept in
    // local-settings.json so empty folders survive a restart.
    property var programFolders: []
    property var programBends: programs.length > 0 ? programs[0].bends : []
    property var selectedBend: programBends.length > 0 ? programBends[0] : ({})
    property int selectedRunBend: 0
    property bool runActive: false
    property bool runProgramEditing: false
    property string runProgramNameDraft: activeProgram
    property bool legacyRunUiEnabled: false
    // Traditional 2D Placement is retired; LIVE (3D) is the default scene.
    property string runSceneMode: "LIVE"
    property bool runBendListVisible: false
    property bool runShowMachineGuides: false
    property bool runSimulatedRun: false
    property bool runPreviewDebugLogsEnabled: false
    // Production rendering keeps diagnostic skeletons, collision windows, and
    // occlusion overlays off. Operators can still enable them from Settings,
    // but normal animation should spend its frame budget on the part/tooling.
    property bool runPreviewDebugOverlaysEnabled: false
    property string runFlatPatternContourRenderer: "classic"
    // LIVE is Qt Quick 3D only; the 2D Canvas engine is archived at git tag
    // legacy-canvas-live-engine.
    readonly property string runLiveProjectionMode: "ISOMETRIC"
    property string runLiveCameraOrientation: "ISO_TOP_LEFT"
    property string runToolingAppearance: "SOLID"
    property var allBends: []
    property bool addBendPopupVisible: false
    property bool runConfirmationVisible: false
    property var pressHomeOperationId: undefined
    property var backGaugeHomeOperationId: undefined
    property bool combinedHomeBackGaugePending: false
    property int selectedAddBendIndex: -1
    property string addBendStatus: "Select a bend to add to the active program"
    property var runValidationMessages: []
    property string runProgressTitle: ""
    property string runProgressSubtitle: ""
    property bool backGaugeHomed: offlineSimulationEnabled
        ? true : (machineControl ? machineControl.moduleHomed : false)
        property bool backGaugeReady: offlineSimulationEnabled
            ? (moduleConnected && !backGaugeBusy
                && backGaugeStatus !== "STOP" && backGaugeStatus !== "ALARM")
            : (machineControl ? machineControl.moduleReady : false)
        property bool backGaugeCanOperate: backGaugeReady && backGaugeHomed
            && (backGaugeStatus === "IDLE" || backGaugeStatus === "HOMED")
        // Original Java MachineIdleMonitorModel: after 60 min continuously in
        // press IDLE, kill hydraulic power and show a warning. Leaving IDLE
        // stops the timer; re-entering IDLE restarts the hour.
        property int idleHydraulicShutdownMs: 3600000
        readonly property bool pressIdleForShutdown: !offlineSimulationEnabled && machineControl
            ? (machineControl.pressConnected === true && machineControl.pressMachineState === "IDLE")
            : false
        property Timer idleHydraulicShutdownTimer: Timer {
            interval: appState.idleHydraulicShutdownMs
            repeat: false
            running: appState.pressIdleForShutdown
            onTriggered: appState.idleHydraulicShutdown()
        }
        function idleHydraulicShutdown() {
            if (!pressIdleForShutdown || !machineControl.killHydraulics()) {
                log("HYDRAULICS", "Idle shutdown skipped: " + (machineControl ? machineControl.lastRejectReason : "NO_CONTROL"))
                return
            }
            log("HYDRAULICS", "Hydraulic power shut down after 60 min idle")
            showPopup(qsTr("Hydraulic shutdown"),
                      qsTr("The press was idle for 60 minutes, so hydraulic power was shut down. Activate the press again to continue."),
                      0, "caution", qsTr("Close"))
        }
        property Timer backGaugeHomingTimer: Timer {
        interval: 450
        repeat: false
        onTriggered: appState.completeBackGaugeHome()
        }
        property Timer backGaugeResetTimer: Timer {
            interval: 250
            repeat: false
            onTriggered: appState.completeBackGaugeReset()
            }
    readonly property bool runProgramAllowed: selectedRunBend >= 0 && programBends.length > 0
    readonly property bool runProgramGrayed: machineStatus !== "IDLE"
        || !(machineConnected && moduleConnected && backGaugeReady && backGaugeHomed)
        || (!offlineSimulationEnabled && (!machineControl
            || !machineControl.moduleTelemetryFresh
            || machineControl.moduleState !== "IDLE"
            || machineControl.moduleOperationActive))
        || (!offlineSimulationEnabled && (!machineControl
            || !machineControl.pressReady || !machineControl.pressHomed
            || !machineControl.pressTelemetryFresh
            || machineControl.pressOperationActive))
    readonly property bool pressCanOperate: offlineSimulationEnabled
        || (machineConnected && machineControl && machineControl.pressReady
            && machineControl.pressHomed && machineControl.pressTelemetryFresh
            && machineStatus === "IDLE" && !machineControl.pressOperationActive
            && manualModeEnabled && manualModeArmed
            && manualModeState !== "DISABLE REQUIRED"
            && !manualActivationPending && !manualLeavePending)
    readonly property bool contactProfileCanOperate: !offlineSimulationEnabled
        && machineConnected && machineControl && machineControl.pressReady
        && machineControl.pressHomed && machineControl.pressTelemetryFresh
        && machineStatus === "IDLE" && !machineControl.pressOperationActive
    readonly property bool pressCanPanelJog: offlineSimulationEnabled
        || (machineConnected && machineControl && machineControl.pressReady
            && machineControl.panelJogSupported
            && machineControl.pressHomed && machineControl.pressTelemetryFresh
            && machineStatus === "IDLE" && !machineControl.pressOperationActive
            && !manualActivationPending && !manualLeavePending
            && manualModeState !== "DISABLE REQUIRED")
    readonly property bool pressCanAbort: offlineSimulationEnabled
        || (machineConnected && machineControl && machineControl.pressOperationActive)
    readonly property bool pressCanHome: offlineSimulationEnabled
        || (machineConnected && machineControl && machineControl.pressTelemetryFresh
            && !machineControl.pressOperationActive
            && (machineStatus === "IDLE"
                || machineStatus === "STARTUP_HOMING_REQUIRED"
                || machineControllerAlarm))
    property bool selectedBendNotTopMostWarning: selectedRunBend > 0
    property bool autoClampEnabled: false
    property bool bendRepressReleased: false
    property bool bendRepressDone: false
    property real autoClampDwellSec: 3.0
    readonly property bool autoClampDwellEnabled: autoClampDwellSec > 0
    property real lastNonZeroDwellSec: 3.0
    // Execution state machine parity (ports ExecutionStateModel + DwellAndBailOut).
    // Phase index walks ExecutionModel.BEND_PHASE_SEQUENCE during an active run.
    property int executionPhaseIndex: 0
    property string executionPhase: "STARTING"
    property var dwellTimerState: null      // DwellAndBailOut dwell-timer state object
    property var bailOutState: null         // DwellAndBailOut bail-out reducer state
    property string lastBailOutReason: ""
    property bool dwellStartedForBend: false // true once the dwell timer has been started this bend
    property real dwellRemainingSec: 0
    property bool dwellPausedForPedal: false
    property string physicalRunWaitAction: ""
    property string physicalRunPendingOperation: ""
    property string physicalRunPendingDevice: ""
    property var physicalRunPendingOperationId: undefined
    property bool physicalRunCommandPending: false
    property bool physicalRunUsesBackGauge: true
    property real physicalRunBackGaugeSpeed: 0
    property real physicalRunRetractPlane: 0
    property string bendMode: "PROGRAM_BEND_MODE"
    property bool bendModePopupVisible: false
    property bool multipleBendsProgram: programBends.length > 1
    property string manualModeState: "IDLE"
    property bool manualModeArmed: offlineSimulationEnabled
    readonly property bool manualModeEnabled: offlineSimulationEnabled
        ? manualModeArmed : (machineControl ? machineControl.manualModeEnabled : false)
    property string manualPendingOperation: ""
    property var manualPendingOperationId: undefined
    property string manualPendingAction: ""
    property var manualPendingPreviousSetting: undefined
    property bool manualActivationPending: false
    property bool manualLeavePending: false
    property real manualJogStep: 0.1
    property bool manualRepeatStroke: false
    property bool manualRepeatJog: false
    property bool tonnageHoldActive: false
    property bool contactProfileActive: false
    // Target sent with the running AUTO hold (Manual panel target, or the
    // measuring tonnage in Measure). 1.00 T keeps the validated bare profile.
    property real contactProfileTarget: 1.0
    // Feature that started the running tonnage hold profile ("MANUAL",
    // "MEASUREMENT", "CALIBRATION", ...). Completion is routed by owner, so
    // any feature can reuse the profile without the Manual AUTO wrapper.
    property string contactProfileOwner: ""
    signal tonnageHoldProfileFinished(string owner, bool completed, string reason)

    // Tool change (docs 42b): TOUCH/BACKOFF, optional MOVE after TOOLING
    // REMOVED, pedal SEAT at 1.00 T. Firmware TCH capability required.
    property real toolChangeBackoff: 0.25            // 0.250 (default) or 0.125 in
    readonly property bool toolChangeSupported: !!(machineControl && machineControl.toolChangeSupported)
    // IDLE, TOUCH, BACKOFF, AWAIT_TOOLING_REMOVED, MOVE, AWAIT_SEAT, SEAT,
    // SEAT_PAUSED, DONE, FAILED
    property string toolChangeState: "IDLE"
    property real toolChangeContact: NaN
    property real toolChangeOldPunchHeight: NaN
    property real toolChangeNewPunchHeight: NaN
    property string toolChangeFailure: ""
    // SEAT AGAIN stays available until the next sequence starts.
    property bool toolChangeSeatAgainAvailable: false
    readonly property real toolChangeTouchMargin: 0.25
    property var toolChangeTouchHeartbeat: Timer {
        interval: 250; repeat: true
        onTriggered: if (!appState.machineControl
                         || !appState.machineControl.heartbeatToolChangeTouch()) stop()
    }
    // RUN integration: TOOL_CHANGE step inserted before a bend whose
    // tooling phase differs from the previous bend (no renumbering).
    property bool runToolChangeActive: false
    property var runToolChangeInfo: null
    property bool runToolChangeJogHeld: false
    property var toolChangeOfflineTimer: Timer {
        interval: 700; repeat: false
        onTriggered: appState.advanceOfflineToolChange()
    }
    onToolChangeStateChanged: {
        if (toolChangeState !== "TOUCH" && toolChangeState !== "BACKOFF")
            toolChangeTouchHeartbeat.stop()
        captureSeatLevelSkew()
        handleRunToolChangeStateChanged()
        handleStandaloneSeatStateChanged()
    }
    onRamPositionY1Changed: captureSeatLevelSkew()
    onRamPositionY2Changed: captureSeatLevelSkew()
    onLeftSafetyJogChanged: handleRunToolChangeJogInput()
    onRightSafetyJogChanged: handleRunToolChangeJogInput()
    onBendJogPedalChanged: {
        handleRunToolChangePedal()
        if (physicalRunWaitAction === "NEXT_BEND_PEDAL_TAP")
            processPhysicalRunOperatorGate()
    }
    readonly property real automaticTonnageHoldMinimum: 0.5
    readonly property real automaticTonnageHoldMaximum: 20.0
    // HOLDING acceptance half-band (T): five fresh samples within target +/-
    // this value qualify HOLD entry (firmware TH_HOLD_QUALIFY_BAND_T, env
    // v53_hold_band_005). Display only; firmware owns qualification.
    readonly property real automaticHoldAcceptanceBand: 0.05
    property real tonnageHoldTarget: 1.0
    // Target actually sent with the running PEDAL hold. A Measure PEDAL uses
    // the measuring tonnage, not the Manual panel target.
    property real tonnageHoldActiveTarget: NaN
    property real liveTonnage: offlineSimulationEnabled ? 0 : ramLoadY1 + ramLoadY2
    property bool manualMeasurementVisible: false
    property string manualMeasurementMode: ""
    // A mode transition is deferred until the active press action has stopped.
    // The modal must never relabel an in-progress calibration as a measurement.
    property string manualMeasurementPendingMode: ""
    // Measuring force for Calibrate and Measure (persisted, 0.5–1.0 T) so thin
    // or soft material is not crushed. Both modes share it so the die top is
    // calibrated at the same frame deflection it is measured at. Both PEDAL and
    // AUTO use it.
    property real manualMeasurementTonnage: 1.0
    readonly property real manualMeasurementTonnageMinimum: 0.5
    readonly property real manualMeasurementTonnageMaximum: 1.0
    // Load the sampler averages against and the modal shows as TARGET.
    readonly property real manualMeasurementTargetTonnage: contactProfileActive
        ? contactProfileTarget
        : tonnageHoldActive
            ? (isFinite(tonnageHoldActiveTarget) ? tonnageHoldActiveTarget : tonnageHoldTarget)
            : (manualMeasurementMode === "MEASUREMENT" || manualMeasurementMode === "CALIBRATION"
               ? manualMeasurementTonnage : tonnageHoldTarget)
    property real manualKnownPieceThickness: 1.0
    property string manualKnownPieceUnit: "INCH"
    readonly property real manualKnownPieceDisplayValue: manualKnownPieceUnit === "MILLIMETER"
        ? manualKnownPieceThickness * 25.4 : manualKnownPieceThickness
    readonly property int manualMeasurementRequiredSamples: 100
    readonly property int manualMeasurementMinimumSamples: 30
    readonly property int manualMeasurementSampleIntervalMs: 100
    // Measured from the first in-band sample, never from the button press.
    // It stays below the 60 s AUTO hold observation so the average always
    // completes (or accepts its partial result) before the automatic release.
    readonly property int manualMeasurementMaximumDurationMs: 30000
    // Every fresh sample within this band of the target load is averaged. A
    // slow load fluctuation inside the band never restarts the average. The
    // former 0.06 T peak-to-peak window was below the 0.1 T per-ram status
    // resolution, so any rounding flip restarted it and AUTO timed out.
    readonly property real manualMeasurementLoadBand: 0.10
    // Gross-fault guard only (slip or lost contact): older samples outside
    // this Y range are discarded. It is not a convergence criterion.
    readonly property real manualMeasurementMaximumPositionRange: 0.005
    // Optional (Settings, default OFF): accept the average as soon as it is
    // stable instead of always waiting for the fixed sample count, so both
    // modes can be compared. Stable = at least the minimum samples and the
    // running mean moved no more than the tolerance over the last window of
    // accepted samples. Position only: the load band and the AUTO HOLDING
    // gate still decide which frames are averaged.
    property bool manualMeasurementConvergenceEnabled: false
    // Same rule for Calibrate; off keeps the fixed sample count.
    property bool manualCalibrationConvergenceEnabled: false
    // AUTO MEASURE ON CLAMP: the first bend of a run measures the sheet with the
    // contact profile at the minimum measuring tonnage (0.5 T; readings below
    // about 0.35 t are invalid) before the clamp, then runs with that thickness.
    // A part whose bending tonnage is below autoMeasureViabilityMargin x 0.5 T
    // would yield on the V, so it is measured resting on a reference block.
    property bool autoMeasureOnClampEnabled: false
    property real autoMeasureReferenceBlockThickness: 0
    readonly property real autoMeasureViabilityMargin: 2.0
    readonly property real autoMeasureMaximumDeviation: 0.15
    property bool runAutoMeasureDone: false
    property bool runAutoMeasureActive: false
    property bool runAutoMeasureOnBlock: false
    property bool runAutoMeasureBlockConfirmed: false
    property real runAutoMeasureResult: NaN
    // Measure and Calibrate have separate toggles; with Calibrate's off the
    // die-top reference keeps the fixed sample count.
    readonly property bool manualMeasurementConvergenceActive:
        (manualMeasurementConvergenceEnabled && manualMeasurementMode === "MEASUREMENT")
        || (manualCalibrationConvergenceEnabled && manualMeasurementMode === "CALIBRATION")
    readonly property int manualMeasurementConvergenceWindow: 20
    readonly property real manualMeasurementConvergenceTolerance: 0.0002
    property var manualMeasurementMeanHistory: []
    property real manualMeasurementConvergenceSpread: NaN
    // "" | CONVERGED | FIXED | TIME LIMIT: rule that accepted the last result.
    property string manualMeasurementAcceptedCriterion: ""
    property int manualMeasurementQualifiedSamples: 0
    property real manualMeasurementSampleSum: 0
    property var manualMeasurementPositionSamples: []
    property var manualMeasurementLoadY1Samples: []
    property var manualMeasurementLoadY2Samples: []
    property real manualMeasurementPositionMinimum: NaN
    property real manualMeasurementPositionMaximum: NaN
    property real manualMeasurementLoadY1Sum: 0
    property real manualMeasurementLoadY2Sum: 0
    property real manualMeasurementLoadTotalMinimum: NaN
    property real manualMeasurementLoadTotalMaximum: NaN
    property real manualMeasurementAcceptedLoadY1Mean: NaN
    property real manualMeasurementAcceptedLoadY2Mean: NaN
    property real manualMeasurementAcceptedLoadMean: NaN
    property real manualMeasurementAcceptedLoadPeak: NaN
    property int manualMeasurementAcceptedSamples: 0
    property int manualMeasurementAcceptedDurationMs: 0
    // Latched so a timeout requests exactly one stop, not one per sampler tick.
    property bool manualMeasurementTimedOut: false
    property double manualMeasurementWindowStartedMs: 0
    property double manualMeasurementLastSampleMs: 0
    property double manualMeasurementSyntheticTimeMs: 0
    property double manualMeasurementLastTelemetrySequence: -1
    property real manualMeasurementResult: NaN
    property string manualMeasurementStatus: "READY"
    property bool manualMeasurementClosePending: false
    readonly property real manualMeasurementRamMean: offlineSimulationEnabled
        ? ramPosition : (independentRamTelemetryAvailable
            ? (ramPositionY1 + ramPositionY2) / 2.0 : NaN)
    readonly property bool manualMeasurementTelemetryReady: offlineSimulationEnabled
        || (machineControl && machineControl.pressTelemetryFresh
            && independentRamTelemetryAvailable)
    readonly property bool manualDieTopCalibrationValid: userSettingsModel
        && userSettingsModel.manualDieTopCalibration
        && userSettingsModel.manualDieTopCalibration.valid === true
    readonly property real manualDieTopCalibration: userSettingsModel
        && userSettingsModel.manualDieTopCalibration
        ? Number(userSettingsModel.manualDieTopCalibration.value) : 0
    readonly property real manualUnknownPieceThickness: manualDieTopCalibrationValid
        && isFinite(manualMeasurementRamMean)
        ? manualMeasurementRamMean - manualDieTopCalibration
          - (manualMeasurementOnReferencePiece ? manualCalibrationReferenceThickness : 0) : NaN
    // Reference piece recorded by the last calibration (NaN for calibrations
    // saved before the metadata existed). Thin material is measured stacked on
    // this rigid piece, so the piece itself is subtracted from the stack.
    readonly property real manualCalibrationReferenceThickness: userSettingsModel
        && userSettingsModel.manualDieTopCalibration
        && Number(userSettingsModel.manualDieTopCalibration.referenceThickness) > 0
        ? Number(userSettingsModel.manualDieTopCalibration.referenceThickness) : NaN
    property bool manualMeasurementOnReferencePiece: false
    // Raw stack above the calibrated die top for the last measurement; equals
    // the result unless the piece was measured on the reference piece.
    property real manualMeasurementStackResult: NaN
    // Provisional value of the frames averaged so far, so the operator sees
    // the result converge instead of a blank field until completion. Uses the
    // same formulas as completeManualMeasurement(); never persisted.
    readonly property bool manualMeasurementAveraging: manualMeasurementProcessActive
        && manualMeasurementQualifiedSamples > 0 && !isFinite(manualMeasurementResult)
    readonly property real manualMeasurementRunningValue: {
        if (!manualMeasurementAveraging)
            return NaN
        const mean = manualMeasurementSampleSum / manualMeasurementQualifiedSamples
        if (manualMeasurementMode === "CALIBRATION")
            return mean - manualKnownPieceThickness
        if (!manualDieTopCalibrationValid)
            return NaN
        return mean - manualDieTopCalibration
            - (manualMeasurementOnReferencePiece ? manualCalibrationReferenceThickness : 0)
    }
    // Tooling the operator confirms for calibration. Heights come from the
    // tooling library; together with the qualified die top they define the
    // ram-to-table opening: opening = punchH + dieH - dieTop.
    property string manualCalibrationPunchId: ""
    property string manualCalibrationPunchName: ""
    property real manualCalibrationPunchHeight: NaN
    property string manualCalibrationDieId: ""
    property string manualCalibrationDieName: ""
    property real manualCalibrationDieHeight: NaN
    readonly property bool manualCalibrationToolingValid: manualCalibrationPunchHeight > 0
        && manualCalibrationDieHeight > 0
    readonly property real manualCalibrationOpeningMinimum: 7.950
    readonly property real manualCalibrationOpeningMaximum: 8.750
    // Every in-range change waits for APPLY OPENING. A change larger than
    // this is additionally logged as suspicious: it usually means the
    // selected punch/die is not the tooling actually installed.
    readonly property real manualCalibrationOpeningReviewDelta: 0.050
    // Current authoritative opening and the opening the running die top
    // would produce, shown while the calibration is still averaging.
    readonly property real manualCalibrationCurrentOpening: authoritativeRamToTableOpening()
    readonly property real manualCalibrationLiveOpening: manualMeasurementMode === "CALIBRATION"
        && manualCalibrationToolingValid && isFinite(manualMeasurementRunningValue)
        ? manualCalibrationPunchHeight + manualCalibrationDieHeight - manualMeasurementRunningValue
        : NaN
    readonly property int manualCalibrationOpeningWaitMs: 30000
    property real manualCalibrationOpeningPrevious: NaN
    property real manualCalibrationOpeningCandidate: NaN
    // "" | NO TOOLING | OUT OF RANGE | UNCHANGED | REVIEW | WAITING | BUSY |
    // SENT | APPLIED | FAILED
    property string manualCalibrationOpeningState: ""
    property var manualCalibrationOpeningOperationId: undefined
    property double manualCalibrationOpeningDeadlineMs: 0
    readonly property bool manualCalibrationOpeningCanApply: isFinite(manualCalibrationOpeningCandidate)
        && manualCalibrationOpeningCandidate >= manualCalibrationOpeningMinimum
        && manualCalibrationOpeningCandidate <= manualCalibrationOpeningMaximum
        && (manualCalibrationOpeningState === "REVIEW"
            || manualCalibrationOpeningState === "BUSY"
            || manualCalibrationOpeningState === "FAILED")
    property Timer manualCalibrationOpeningTimer: Timer {
        interval: 250
        repeat: true
        running: appState.manualCalibrationOpeningState === "WAITING"
        onTriggered: appState.tryApplyManualCalibrationOpening()
    }
    // Thickness released by the operator for bend programs.
    readonly property bool measuredMaterialThicknessValid: userSettingsModel
        && userSettingsModel.measuredMaterialThickness
        && userSettingsModel.measuredMaterialThickness.valid === true
        && Number(userSettingsModel.measuredMaterialThickness.value) > 0
    readonly property real measuredMaterialThickness: measuredMaterialThicknessValid
        ? Number(userSettingsModel.measuredMaterialThickness.value) : NaN
    // Session-only override: the active program runs with the released
    // measured thickness without editing programs.json. Never persisted, so
    // every app start begins with the program's own thickness.
    property bool measuredThicknessOverrideEnabled: false
    readonly property bool measuredThicknessOverrideActive: measuredThicknessOverrideEnabled
        && measuredMaterialThicknessValid
    property bool measuredThicknessOverrideResyncPending: false
    property int measuredThicknessOverrideUnresolvedCount: 0
    // Tooling library used to recompute bends; cached from the last storage load.
    property var programToolingLibrary: ({ punches: [], dies: [], materials: [] })
    // Program bends exactly as stored (Create Bend edits these). programBends
    // carries the runtime values, which differ only while the override is active.
    property var storedProgramBends: programs.length > 0 ? programs[0].bends : []
    onMeasuredThicknessOverrideActiveChanged: refreshMeasuredThicknessOverride()
    onMeasuredMaterialThicknessChanged: if (measuredThicknessOverrideActive)
        refreshMeasuredThicknessOverride()
    onRunActiveChanged: {
        if (runActive)
            lastRunStartedMs = Date.now()
        else if (measuredThicknessOverrideResyncPending) {
            measuredThicknessOverrideResyncPending = false
            syncActiveProgramState()
        }
    }
    property bool manualMeasurementUsedForProgram: false
    readonly property bool manualMeasurementProcessActive: tonnageHoldActive
        || contactProfileActive
    onManualMeasurementProcessActiveChanged: {
        if (!manualMeasurementProcessActive && manualMeasurementClosePending)
            Qt.callLater(finalizeManualMeasurementClose)
        else if (!manualMeasurementProcessActive
                 && manualMeasurementPendingMode.length > 0)
            Qt.callLater(finalizeManualMeasurementModeSwitch)
    }
    property Timer manualMeasurementSampler: Timer {
        interval: appState.manualMeasurementSampleIntervalMs
        repeat: true
        running: (appState.manualMeasurementVisible || appState.runAutoMeasureActive)
            && appState.manualMeasurementProcessActive
            && !isFinite(appState.manualMeasurementResult)
            && !appState.manualMeasurementTimedOut
        onTriggered: appState.sampleManualMeasurement()
    }
    // Machine/material settings consumed by the BendCalculator parity engine.
    // Defaults mirror the Java app's disconnected state (limits.json + default-local-settings).
    property real materialClampRatePercentage: 5.0
    property real desktopRamToTableOpening: 0.0
    property real editedRamToTableOpening: NaN
    property var ramToTableSaveOperationId: undefined
    // Phase 5.3: full validated settings models (ports Local/UserSettingsModel).
    // These hold every settings field (not just the calc-relevant ones), validated
    // through SettingsModel.validate*; the individual bound props above remain the
    // primary UI bindings. Populated by applyLocalSettings/applyUserSettings.
    property var localSettingsModel: SettingsModel.defaultLocalSettings()
    property var userSettingsModel: SettingsModel.defaultUserSettings()
    // Additional user-settings fields surfaced for the Settings tab parity.
    property bool autoClampToBendEnabled: true
    property real backGaugeRetractBetweenBendsInch: 2.0
    property real backGaugeBumpOffDistanceInch: 0.25
    property real defaultBackGaugeRPositionInch: -0.25
    property real manualModeMaxTonnagePerRam: 12.5
    readonly property real manualSafetyPlaneClearance: userSettingsModel
        && userSettingsModel.manualModeSafetyPlaneClearance
        ? Number(userSettingsModel.manualModeSafetyPlaneClearance.value) : 0.05
    readonly property real manualStartRamPosition: userSettingsModel
        && userSettingsModel.manualModeStartRamPosition
        ? Number(userSettingsModel.manualModeStartRamPosition.value) : -1.0
    readonly property real manualEndRamPosition: userSettingsModel
        && userSettingsModel.manualModeEndRamPosition
        ? Number(userSettingsModel.manualModeEndRamPosition.value) : -1.0001
    readonly property real manualMoveToPosition: userSettingsModel
        && userSettingsModel.manualModeMoveToPosition
        ? Number(userSettingsModel.manualModeMoveToPosition.value) : -2.0
    readonly property real manualStrokeDistance: Math.abs(manualEndRamPosition
                                                          - manualStartRamPosition)
    property real punchCoverageSideToleranceIn: 0.55
    property bool desktopFrameDeflectionCompensationEnabled: false
    property int jogHoldTimeoutSeconds: 300
    property int displaySleepMinutes: 0
    // LIVE animation frame cap (0 = max available). Persisted in Qt settings.
    property int liveAnimationMaxFps: persistentSettings && Number(persistentSettings.value("liveAnimationMaxFps", 0)) || 0
    readonly property var liveAnimationFpsChoices: [5, 10, 15, 20, 30, 0]
    function liveAnimationFpsText(value) {
        var v = value === undefined ? liveAnimationMaxFps : Number(value)
        return v > 0 ? (v + " FPS") : "MAX"
    }
    function setLiveAnimationFpsText(text) {
        var v = text === "MAX" ? 0 : parseInt(text)
        if (!isFinite(v) || v < 0)
            return
        liveAnimationMaxFps = v
        persistentSettings.setValue("liveAnimationMaxFps", v)
        persistentSettings.sync()
        log("SETTINGS", "LIVE animation FPS limit " + liveAnimationFpsText(v))
    }
    // Display units: inches/IPM (default) or metric (mm/cm, mm/s). Display only;
    // all stored values and firmware commands stay in inches.
    property bool metricUnits: persistentSettings && String(persistentSettings.value("metricUnits", "false")) === "true"
    function setMetricUnits(enabled) {
        metricUnits = enabled === true
        persistentSettings.setValue("metricUnits", metricUnits ? "true" : "false")
        persistentSettings.sync()
        log("SETTINGS", "Display units " + (metricUnits ? "METRIC" : "IMPERIAL"))
    }
    // RUN pedal mode (firmware $PM=), sent before every physical RUN.
    readonly property var runPedalModeChoices: ["BTN / 2TAP", "BTN / 1TAP", "2TAP / 1TAP", "1TAP / 2TAP", "1TAP / 1TAP"]
    property int runPedalMode: persistentSettings && Number(persistentSettings.value("runPedalMode", 0)) || 0
    function setRunPedalModeText(text) {
        var v = runPedalModeChoices.indexOf(text)
        if (v < 0 || runActive)
            return
        runPedalMode = v
        persistentSettings.setValue("runPedalMode", v)
        persistentSettings.sync()
        log("SETTINGS", "RUN pedal mode " + text + " (jog / bend)")
    }
    // When on, a finished bend waits for a pedal tap (press + release) before
    // the next sequence starts, so the back gauge does not move while the
    // operator is still removing the part. Off keeps automatic advance.
    property bool runAdvanceOnPedalTap: persistentSettings
        ? persistentSettings.value("runAdvanceOnPedalTap", false) === true
            || persistentSettings.value("runAdvanceOnPedalTap", false) === "true"
        : false
    // Off skips BACK_GAUGE_AND_RAM_RETRACT_MOVE's X back-off (planner-driven
    // retract distance will replace the fixed value later).
    property bool backGaugeRetractBetweenBendsEnabled: persistentSettings
        ? String(persistentSettings.value("backGaugeRetractBetweenBendsEnabled", "true")) === "true"
        : true
    function setBackGaugeRetractBetweenBendsEnabled(enabled) {
        backGaugeRetractBetweenBendsEnabled = enabled === true
        if (persistentSettings) {
            persistentSettings.setValue("backGaugeRetractBetweenBendsEnabled", backGaugeRetractBetweenBendsEnabled)
            persistentSettings.sync()
        }
        log("SETTINGS", "Back gauge retract between bends " + (backGaugeRetractBetweenBendsEnabled ? "ON" : "OFF"))
    }
    // Experimental: tool-change SEAT seats punches with equal Y1/Y2 force
    // (firmware TH:SEATEQ) instead of encoder-position leveling.
    property bool toolChangeEqualForceSeat: persistentSettings
        ? String(persistentSettings.value("toolChangeEqualForceSeat", "false")) === "true"
        : false
    function setToolChangeEqualForceSeat(enabled) {
        toolChangeEqualForceSeat = enabled === true
        if (persistentSettings) {
            persistentSettings.setValue("toolChangeEqualForceSeat", toolChangeEqualForceSeat ? "true" : "false")
            persistentSettings.sync()
        }
        log("SETTINGS", "Tool change equal tonnage seat " + (toolChangeEqualForceSeat ? "ON" : "OFF"))
    }
    property bool nextBendTapReleased: false
    property bool nextBendTapPressed: false
    function setRunAdvanceOnPedalTap(enabled) {
        runAdvanceOnPedalTap = enabled === true
        if (persistentSettings) {
            persistentSettings.setValue("runAdvanceOnPedalTap", runAdvanceOnPedalTap)
            persistentSettings.sync()
        }
        log("SETTINGS", "Pedal tap for next bend " + (runAdvanceOnPedalTap ? "ON" : "OFF"))
    }
    // Edge-driven so a quick tap between 100 ms gate ticks is not missed.
    onPhysicalPedalActiveChanged: {
        if (runPedalMode === 3 || runPedalMode === 4)
            handleRunToolChangePedal()
        if (physicalRunWaitAction === "NEXT_BEND_PEDAL_TAP")
            processPhysicalRunOperatorGate()
    }
    function awaitNextBendPedalTap() {
        if (!runAdvanceOnPedalTap || offlineSimulationEnabled)
            return
        nextBendTapReleased = false
        nextBendTapPressed = false
        physicalRunWaitAction = "NEXT_BEND_PEDAL_TAP"
        runProgressSubtitle = runOperatorPrompt()
    }
    // Remote RUN via the commissioning socket (run_program). Off by default
    // and not persisted across restarts unless explicitly enabled.
    property bool remoteRunAllowed: persistentSettings && String(persistentSettings.value("remoteRunAllowed", "false")) === "true"
    onRemoteRunAllowedChanged: if (machineControl && machineControl.setRemoteRunAllowed) machineControl.setRemoteRunAllowed(remoteRunAllowed)
    onMachineControlChanged: if (machineControl && machineControl.setRemoteRunAllowed) machineControl.setRemoteRunAllowed(remoteRunAllowed)
    // Back gauge finger model for the LIVE canvas and G55/G57 contact geometry.
    readonly property var backgaugeFingerStyleChoices: ["ORIGINAL", "FLAT"]
    property string backgaugeFingerStyle: persistentSettings
        && String(persistentSettings.value("backgaugeFingerStyle", "ORIGINAL")) === "FLAT" ? "FLAT" : "ORIGINAL"
    function setBackgaugeFingerStyle(style) {
        backgaugeFingerStyle = String(style).toUpperCase() === "FLAT" ? "FLAT" : "ORIGINAL"
        persistentSettings.setValue("backgaugeFingerStyle", backgaugeFingerStyle)
        persistentSettings.sync()
        log("SETTINGS", "Back gauge finger " + backgaugeFingerStyle)
    }
    function setRemoteRunAllowed(enabled) {
        remoteRunAllowed = enabled === true
        persistentSettings.setValue("remoteRunAllowed", remoteRunAllowed ? "true" : "false")
        persistentSettings.sync()
        log("SETTINGS", "Remote RUN " + (remoteRunAllowed ? "enabled" : "disabled"))
    }
    function handleRemoteRunRequest() {
        if (!remoteRunAllowed || runActive)
            return
        log("RUN", "Remote RUN requested for " + activeProgram)
        if (runProgramGrayed) {
            showAlarm("CAN'T RUN PROGRAM", "Remote RUN rejected: machine or Back Gauge not ready.")
            return
        }
        confirmRunProgram()
    }
    property bool safetyPopupsEnabled: true
    // Tonnage-protection settings surfaced in the application module. Mock-safe
    // defaults mirror the prior hard-coded display (disconnected machine).
    property bool tonnageProtectionEnabled: false
    property real airTonnageThreshold: 0.0
    property string bleedState: "IDLE"
    property string bleedPendingOperation: ""
    property var bleedPendingOperationId: undefined
    readonly property bool bleedActive: bleedState !== "IDLE"
    readonly property bool bleedLatchSupported: !offlineSimulationEnabled && machineControl
        && machineControl.pressConnected && machineControl.pressReady
        && machineControl.pressTelemetryFresh
        && machineControl.primingLatchSupported
    readonly property bool bleedLatchY1: bleedLatchSupported && machineControl.primingLatchY1
    readonly property bool bleedLatchY2: bleedLatchSupported && machineControl.primingLatchY2
    property real cadBendCount: 0
    property bool cadImported: false
    property bool cadHasErrors: false
    property string cadFileName: "No file imported"
    property string cadPartName: "-"
    property string cadProgramName: "Program name"
    property string cadMaterial: "-"
    property string cadThickness: "-"
    property string cadFlatPattern: "-"
    property string cadStatusMessage: "No file loaded"
    property string cadLoadedFilePath: ""
    property real cadThicknessValue: 0
    property real cadTensileStrength: 0
    property real cadSpringBack: 0
    property real cadKFactor: 0
    property real cadFlatWidth: 0
    property real cadFlatLength: 0
    property var sandboxWrites: []
    property var cadBends: []
    property int cadSelectedBendIndex: -1
    property var cadLoadedJson: ({})
    property bool cadManualSequenceOverride: false
    property var cadSuggestedOrderIds: []
    // Compact unfold plan (3D mesh-verified sequence) for the loaded CAD file;
    // null while planning, unavailable, or failed (heuristic order is used).
    property var cadUnfoldPlan: null
    // Full planner result behind cadUnfoldPlan (null for old BEND files that only
    // embed the compact view). This, not the compact rows, is persisted.
    property var cadUnfoldPlanFull: null
    property string cadUnfoldState: ""
    property string cadUnfoldRequestId: ""
    property string cadUnfoldFileUrl: ""
    property string cadUnfoldRequestKey: ""
    // Operator order sent to the planner (operationTemplates); null = free search.
    property var cadForcedOrderTemplates: null
    // Consecutive manual moves restart one replan (start() cancels the
    // running one) instead of waiting for each plan to finish.
    property Timer cadForcedOrderTimer: Timer {
        interval: 1000
        repeat: false
        onTriggered: appState.startCadForcedOrderPlan()
    }
    readonly property var cadToolingOptions: UnfoldPlan.toolingOptions(cadUnfoldPlan)
    readonly property bool cadUnfoldPlannerAvailable: typeof unfoldPlanner !== "undefined"
        && unfoldPlanner !== null && unfoldPlanner.available()
    property Connections cadUnfoldConnections: Connections {
        target: typeof unfoldPlanner !== "undefined" ? unfoldPlanner : null
        function onFinished(requestId, planJson) {
            if (requestId !== appState.cadUnfoldRequestId)
                return
            try {
                var full = JSON.parse(planJson)
                full.planRequestKey = appState.cadUnfoldRequestKey
                if (!full.plannerEngine)
                    full.plannerEngine = unfoldPlanner.engineLabel
                appState.log("CAD PLAN", "Plan from " + full.plannerEngine)
                if (appState.applyCadUnfoldPlan(UnfoldPlan.compactPlan(full), full))
                    appState.embedCadUnfoldPlan(full)
            } catch (error) {
                appState.cadUnfoldState = "failed"
                appState.log("CAD PLAN", "Invalid unfold plan: " + String(error))
            }
        }
        function onFailed(requestId, message) {
            if (requestId !== appState.cadUnfoldRequestId)
                return
            appState.cadForcedOrderTemplates = null
            appState.cadUnfoldState = "failed"
            appState.cadStatusMessage = "3D sequence planner failed - heuristic order kept"
            appState.log("CAD PLAN", message + " [" + unfoldPlanner.engineLabel + "]")
        }
        function onProgressTextChanged() {
            if (appState.cadUnfoldState === "planning" && unfoldPlanner.progressText.length > 0)
                appState.cadStatusMessage = unfoldPlanner.progressText
        }
    }
    property var cadPunchCatalog: []
    property var cadDieCatalog: []
    property var cadMaterialCatalog: []
    property var cadSelectedMaterial: null

    function cloneBends(bends) {
        var result = []
        for (var i = 0; i < bends.length; i++) {
            var bend = bends[i]
            var copy = {}
            for (var key in bend)
                copy[key] = bend[key]
            copy.seq = i + 1
            result.push(copy)
        }
        return result
    }

    function syncActiveProgramState() {
        if (programs.length === 0) {
            activeProgram = "No Program Loaded"
            activeProgramCadPreviewJson = ""
            storedProgramBends = []
            measuredThicknessOverrideUnresolvedCount = 0
            programBends = []
            selectedRunBend = -1
            selectedBend = ({})
            return
        }
        selectedProgramIndex = Math.max(0, Math.min(selectedProgramIndex, programs.length - 1))
        var program = programs[selectedProgramIndex]
        activeProgram = program.name || "Untitled Program"
        activeProgramCadPreviewJson = program.cadPreviewJson || ""
        storedProgramBends = cloneBends(program.bends || [])
        var runtimeBends = cloneBends(program.bends || [])
        var unresolved = 0
        if (measuredThicknessOverrideActive) {
            for (var bendIndex = 0; bendIndex < runtimeBends.length; bendIndex++) {
                runtimeBends[bendIndex] = effectiveProgramBend(runtimeBends[bendIndex])
                if (runtimeBends[bendIndex].measuredThicknessOverride !== "APPLIED")
                    unresolved += 1
            }
        }
        measuredThicknessOverrideUnresolvedCount = unresolved
        programBends = runtimeBends
        if (programBends.length === 0) {
            selectedRunBend = -1
            selectedBend = ({})
        } else {
            selectedRunBend = Math.max(0, Math.min(selectedRunBend, programBends.length - 1))
            selectedBend = programBends[selectedRunBend]
        }
    }

    function applyLocalSettings(settings) {
        // Phase 5.3: validate the raw JSON through the ported LocalSettingsModel
        // (null/finite/range guards + overlays force-enable). rawText omitted here
        // (DataStore already parsed it); pass the JSON string so the overlays-key
        // rule still works when the field is genuinely absent.
        var rawText = settings ? JSON.stringify(settings) : null
        var model = SettingsModel.validateLocalSettings(settings ? settings : null, SettingsModel.defaultLocalSettings(), rawText)
        localSettingsModel = model
        programFolders = normalizedProgramFolders(model.programFolders)

        var hasExplicitLegacySetting = settings && settings.legacyRunUiEnabled !== undefined
        var fallbackLegacy = model.legacyRunUiEnabled !== undefined ? model.legacyRunUiEnabled !== false : false
        var persistedLegacy = persistentSettings.value("legacyRunUiEnabled", fallbackLegacy)
        if (hasExplicitLegacySetting) {
            legacyRunUiEnabled = model.legacyRunUiEnabled === true
        } else if (typeof persistedLegacy === "string") {
            var normalizedLegacy = persistedLegacy.toLowerCase()
            legacyRunUiEnabled = !(normalizedLegacy === "false" || normalizedLegacy === "off" || normalizedLegacy === "0" || normalizedLegacy.length === 0)
        } else {
            legacyRunUiEnabled = persistedLegacy === true
        }
        // The Settings toggle was removed; never strand a press in the legacy
        // layout from an old persisted value (--legacy-run CLI still applies).
        legacyRunUiEnabled = false
        runPreviewDebugLogsEnabled = model.runPreviewDebugLogsEnabled === true
        runPreviewDebugOverlaysEnabled = model.runPreviewDebugOverlaysEnabled === true
        var contourMode = model.runFlatPatternContourRenderer !== undefined ? String(model.runFlatPatternContourRenderer).toLowerCase() : "classic"
        runFlatPatternContourRenderer = contourMode === "canonical" || contourMode === "overlay" ? contourMode : "classic"
        runLiveCameraOrientation = normalizeRunLiveCameraOrientation(
            model.runLiveCameraOrientation)
        runToolingAppearance = String(model.runToolingAppearance || "SOLID").toUpperCase() === "TRANSLUCENT"
            ? "TRANSLUCENT" : "SOLID"
        if (isFinite(Number(model.desktopRamToTableOpening)))
            desktopRamToTableOpening = Number(model.desktopRamToTableOpening)
        safetyPopupsEnabled = model.safetyPopupsEnabled !== false
        virtualInputMode = String(model.virtualInputMode || "ALWAYS").toUpperCase()
        backGaugeUnit = String(model.currentUnit || "INCH").toUpperCase() === "MILLIMETER"
            ? "MILLIMETER" : "INCH"
        if (model.backGaugeJogStep) {
            var loadedStep = backGaugeUnit === "INCH"
                ? Number(model.backGaugeJogStep.inchesValue)
                : Number(model.backGaugeJogStep.millimetersValue)
            if (isFinite(loadedStep))
                jogStep = loadedStep
        }
        if (model.backGaugeJogSpeed) {
            var loadedSpeed = backGaugeUnit === "INCH"
                ? Number(model.backGaugeJogSpeed.inchesValue)
                : Number(model.backGaugeJogSpeed.millimetersValue)
            if (isFinite(loadedSpeed))
                jogSpeed = loadedSpeed
        }
        if (model.bendRamSpeed && isFinite(Number(model.bendRamSpeed.value)))
            bendRamSpeed = Math.max(0.5, Math.min(15, Number(model.bendRamSpeed.value)))
        if (model.jogRamSpeed && isFinite(Number(model.jogRamSpeed.value)))
            jogRamSpeed = Math.max(0.5, Math.min(15, Number(model.jogRamSpeed.value)))
        if (Math.abs(Number(model.toolChangeBackoff) - 0.125) < 1e-9)
            toolChangeBackoff = 0.125
        backGaugeContinuousJog = model.backGaugeContinuousJog === true
        backGaugeCoordinateNames = SettingsModel.loadCoordinateSystemNames(
            writableCurrentDataPath("coordinate-system-names.json"),
            defaultBackGaugeCoordinateNames, settingsIo())
        if (isFinite(Number(model.punchCoverageSideToleranceIn)))
            punchCoverageSideToleranceIn = Math.min(0.75, Math.max(0, Number(model.punchCoverageSideToleranceIn)))
        if (isFinite(Number(model.airTonnageThreshold)))
            airTonnageThreshold = Math.max(0, Math.min(12.5, Number(model.airTonnageThreshold)))
        tonnageProtectionEnabled = model.tonnageProtectionEnabled !== false
        desktopFrameDeflectionCompensationEnabled = model.desktopFrameDeflectionCompensationEnabled === true
        manualMeasurementConvergenceEnabled = model.manualMeasurementConvergenceEnabled === true
        manualCalibrationConvergenceEnabled = model.manualCalibrationConvergenceEnabled === true
        autoMeasureOnClampEnabled = model.autoMeasureOnClampEnabled === true
        if (isFinite(Number(model.autoMeasureReferenceBlockThickness)))
            autoMeasureReferenceBlockThickness = Math.max(0, Math.min(2,
                Number(model.autoMeasureReferenceBlockThickness)))
        if (isFinite(Number(model.manualMeasurementTonnage)))
            manualMeasurementTonnage = Math.max(manualMeasurementTonnageMinimum,
                Math.min(manualMeasurementTonnageMaximum, Number(model.manualMeasurementTonnage)))
        if (isFinite(Number(model.jogHoldTimeoutSeconds)) && Number(model.jogHoldTimeoutSeconds) > 0)
            jogHoldTimeoutSeconds = Number(model.jogHoldTimeoutSeconds)
        displaySleepMinutes = Number(model.displaySleepMinutes)
        if (model.lastBendMode) {
            bendMode = model.lastBendMode
            enforceBendModeForProgram()
        }
        persistentLegacyRunUiSettingLoaded = true
        log("SETTINGS", "Legacy Run UI " + (legacyRunUiEnabled ? "enabled" : "disabled"))
    }

    // Captures user-settings values the BendCalculator parity engine depends on.
    function applyUserSettings(settings) {
        // Phase 5.3: validate through the ported UserSettingsModel (NaN/null guards).
        var model = SettingsModel.validateUserSettings(settings ? settings : null, SettingsModel.defaultUserSettings())
        userSettingsModel = model
        if (isFinite(Number(model.materialClampRate)))
            materialClampRatePercentage = Number(model.materialClampRate)
        autoClampToBendEnabled = model.autoClampToBendEnabled !== false
        autoClampEnabled = autoClampToBendEnabled
        backGaugeDieCompensationAuto = model.backGaugeDieCompensationAuto !== false
        backGaugeReferenceModes = model.backGaugeReferenceModes || ({})
        backGaugeCalibrationDies = model.backGaugeCalibrationDies || ({})
        if (isFinite(Number(model.autoClampToBendDwellSec)))
            autoClampDwellSec = Number(model.autoClampToBendDwellSec)
        if (autoClampDwellSec > 0)
            lastNonZeroDwellSec = autoClampDwellSec
        if (isFinite(Number(model.backGaugeRetractBetweenBendsInch)))
            backGaugeRetractBetweenBendsInch = Number(model.backGaugeRetractBetweenBendsInch)
        if (isFinite(Number(model.backGaugeBumpOffDistanceInch)))
            backGaugeBumpOffDistanceInch = Number(model.backGaugeBumpOffDistanceInch)
        if (isFinite(Number(model.defaultBackGaugeRPositionInch)))
            defaultBackGaugeRPositionInch = Number(model.defaultBackGaugeRPositionInch)
        if (isFinite(Number(model.manualModeMaxTonnagePerRam)))
            manualModeMaxTonnagePerRam = Number(model.manualModeMaxTonnagePerRam)
        if (model.jogStep && isFinite(Number(model.jogStep.value)))
            manualJogStep = Number(model.jogStep.value)
    }

    // Phase 5.3: settings IO backend (reuses the entity FileIo backend; read-only
    // XHR fallback under qml.exe). Used for backup-guarded settings persistence.
    function settingsIo() {
        return entityStorageBackend()
    }

    function writableCurrentDataPath(fileName) {
        if (storageIoOverride !== null && typeof storageIoOverride.storageFilePath === "function")
            return storageIoOverride.storageFilePath(fileName)
        if (typeof fileIo !== "undefined" && fileIo !== null
                && typeof fileIo.storageFilePath === "function")
            return fileIo.storageFilePath(fileName)
        return "data/current/" + fileName
    }

    // persistLocalSetting(key, value): mutate the validated local model and write
    // local-settings.json backup-guarded (FileIo) or sandbox when no real backend.
    // Returns true when a real production write succeeded.
    function persistLocalSetting(key, value) {
        if (!localSettingsModel) localSettingsModel = SettingsModel.defaultLocalSettings()
        localSettingsModel[key] = value
        var url = writableCurrentDataPath("local-settings.json")
        if (!storageBackendReady) {
            recordSandboxWrite("settings", key, value)
            log("SETTINGS", "Sandbox local setting " + key + " = " + String(value))
            return false
        }
        var r = SettingsModel.save(url, localSettingsModel, settingsIo(), {})
        log("SETTINGS", "Persist local " + key + " = " + String(value) + (r.ok ? " (ok)" : " FAILED " + (r.reason || "")))
        return r.ok === true
    }

    function setRamSpeed(kind, value) {
        if (!ramSpeedCanEdit)
            return false
        var parsed = Number(value)
        if (!isFinite(parsed))
            return false
        var clamped = Math.max(0.5, Math.min(15, parsed))
        if (kind !== "bend" && kind !== "jog")
            return false
        var settingKey = kind + "RamSpeed"
        var previousValue = kind === "bend" ? bendRamSpeed : jogRamSpeed
        var previousSetting = localSettingsModel && localSettingsModel[settingKey] !== undefined
                ? localSettingsModel[settingKey] : { value: previousValue, unit: "INCH" }
        var persisted = false
        if (kind === "bend") {
            bendRamSpeed = clamped
            persisted = persistLocalSetting(settingKey, { value: clamped, unit: "INCH" })
        } else if (kind === "jog") {
            jogRamSpeed = clamped
            persisted = persistLocalSetting(settingKey, { value: clamped, unit: "INCH" })
        }
        if (storageBackendReady && !persisted) {
            localSettingsModel[settingKey] = previousSetting
            if (kind === "bend")
                bendRamSpeed = previousValue
            else
                jogRamSpeed = previousValue
            return false
        }
        log("SETTINGS", (kind === "bend" ? "Bend" : "Jog")
            + " ram speed = " + clamped.toFixed(1) + " IPM")
        return true
    }

    function setApplicationNumericSetting(key, value) {
        var parsed = Number(value)
        if (!isFinite(parsed))
            return false
        var propertyName = ""
        var userSetting = true
        var minimum = 0
        var maximum = 0
        if (key === "materialClampRate") {
            propertyName = "materialClampRatePercentage"
            maximum = 100
        } else if (key === "autoClampToBendDwellSec") {
            propertyName = "autoClampDwellSec"
            maximum = 10
        } else if (key === "punchCoverageSideToleranceIn") {
            propertyName = "punchCoverageSideToleranceIn"
            maximum = 0.75
            userSetting = false
        } else if (key === "airTonnageThreshold") {
            propertyName = "airTonnageThreshold"
            maximum = 12.5
            userSetting = false
        } else if (key === "manualModeMaxTonnagePerRam") {
            propertyName = "manualModeMaxTonnagePerRam"
            minimum = 0.5
            maximum = 12.5
        } else if (key === "autoMeasureReferenceBlockThickness") {
            propertyName = "autoMeasureReferenceBlockThickness"
            maximum = 2
            userSetting = false
        } else {
            return false
        }
        var clamped = Math.max(minimum, Math.min(maximum, parsed))
        var previousValue = Number(appState[propertyName])
        var model = userSetting ? userSettingsModel : localSettingsModel
        var previousSetting = model && model[key] !== undefined ? model[key] : previousValue
        appState[propertyName] = clamped
        var persisted = userSetting ? persistUserSetting(key, clamped)
                                    : persistLocalSetting(key, clamped)
        if (storageBackendReady && !persisted) {
            model[key] = previousSetting
            appState[propertyName] = previousValue
            return false
        }
        return true
    }

    function cycleVirtualInputMode() {
        var modes = ["ALWAYS", "AUTOMATIC", "NEVER"]
        var current = modes.indexOf(String(virtualInputMode).toUpperCase())
        var nextValue = modes[(current + 1 + modes.length) % modes.length]
        var previous = virtualInputMode
        virtualInputMode = nextValue
        var persisted = persistLocalSetting("virtualInputMode", nextValue)
        if (storageBackendReady && !persisted) {
            virtualInputMode = previous
            return false
        }
        return true
    }

    function displaySleepText() {
        return displaySleepMinutes === 0 ? qsTr("OFF")
            : qsTr("%1 MIN").arg(displaySleepMinutes)
    }

    function cycleDisplaySleepMinutes() {
        var choices = [0, 5, 10, 30]
        var current = choices.indexOf(Number(displaySleepMinutes))
        var nextValue = choices[(current + 1 + choices.length) % choices.length]
        var previous = displaySleepMinutes
        displaySleepMinutes = nextValue
        var persisted = persistLocalSetting("displaySleepMinutes", nextValue)
        if (storageBackendReady && !persisted) {
            displaySleepMinutes = previous
            return false
        }
        return true
    }

    function setTonnageProtectionEnabled(value) {
        var previous = tonnageProtectionEnabled
        tonnageProtectionEnabled = value === true
        var persisted = persistLocalSetting("tonnageProtectionEnabled",
                                            tonnageProtectionEnabled)
        if (storageBackendReady && !persisted) {
            tonnageProtectionEnabled = previous
            return false
        }
        return true
    }

    // persistUserSetting(key, value): same for user-settings.json.
    function persistUserSetting(key, value) {
        if (!userSettingsModel) userSettingsModel = SettingsModel.defaultUserSettings()
        userSettingsModel[key] = value
        var url = writableCurrentDataPath("user-settings.json")
        if (!storageBackendReady) {
            recordSandboxWrite("settings", key, value)
            log("SETTINGS", "Sandbox user setting " + key + " = " + String(value))
            return false
        }
        var r = SettingsModel.save(url, userSettingsModel, settingsIo(), {})
        log("SETTINGS", "Persist user " + key + " = " + String(value) + (r.ok ? " (ok)" : " FAILED " + (r.reason || "")))
        return r.ok === true
    }
    function setBackGaugeUserSetting(key, value) {
        var parsed = Number(value)
        if (!isFinite(parsed))
            return false
        var propertyName = ""
        var minValue = 0
        var maxValue = 0
        if (key === "backGaugeRetractBetweenBendsInch") {
            propertyName = "backGaugeRetractBetweenBendsInch"
            maxValue = 5
        } else if (key === "backGaugeBumpOffDistanceInch") {
            propertyName = "backGaugeBumpOffDistanceInch"
            maxValue = 10
        } else if (key === "defaultBackGaugeRPositionInch") {
            propertyName = "defaultBackGaugeRPositionInch"
            minValue = -10
            maxValue = 10
        } else {
            return false
        }
        var clamped = Math.max(minValue, Math.min(maxValue, parsed))
        var previousValue = Number(appState[propertyName])
        var previousSetting = userSettingsModel && userSettingsModel[key] !== undefined
            ? userSettingsModel[key] : previousValue
        appState[propertyName] = clamped
        var persisted = persistUserSetting(key, clamped)
        if (storageBackendReady && !persisted) {
            userSettingsModel[key] = previousSetting
            appState[propertyName] = previousValue
            return false
        }
        return true
    }

    function manualSettingValue(key, fallback) {
        if (!userSettingsModel || userSettingsModel[key] === undefined
                || userSettingsModel[key] === null)
            return fallback
        var setting = userSettingsModel[key]
        return setting && setting.value !== undefined ? Number(setting.value) : Number(setting)
    }

    function setManualSetting(key, value) {
        if (!offlineSimulationEnabled && (manualLeavePending
            || manualModeState === "DISABLE REQUIRED"))
            return false
        var parsed = Number(value)
        if (!isFinite(parsed))
            return false
        var minValue = -4.0
        var maxValue = -0.05
        if (key === "manualModeSafetyPlaneClearance") {
            minValue = 0.0
            maxValue = 1.0
        } else if (key === "manualModeMaxTonnagePerRam") {
            minValue = 0.5
            maxValue = 12.5
        } else if (key === "jogStep") {
            minValue = 0.0005
            maxValue = 4.0
        }
        var clamped = Math.max(minValue, Math.min(maxValue, parsed))
        if (key === "manualModeStartRamPosition") {
            clamped = Math.min(-0.05 - manualSafetyPlaneClearance, clamped)
        } else if (key === "manualModeEndRamPosition") {
            clamped = Math.min(manualStartRamPosition - 0.0001, clamped)
        }

        var previous = userSettingsModel[key]
        var nextValue = key === "manualModeMaxTonnagePerRam"
            ? clamped : { value: clamped, unit: "INCH" }
        if (key === "jogStep")
            nextValue = { value: clamped, unit: "INCH" }
        var persisted = persistUserSetting(key, nextValue)
        if (storageBackendReady && !persisted) {
            userSettingsModel[key] = previous
            return false
        }
        userSettingsModel = Object.assign({}, userSettingsModel)
        if (key === "manualModeMaxTonnagePerRam")
            manualModeMaxTonnagePerRam = clamped
        else if (key === "jogStep")
            manualJogStep = clamped
        if (key === "manualModeMaxTonnagePerRam" && !offlineSimulationEnabled
                && machineControl && machineConnected) {
            if (!machineControl.setManualModeMaxTonnage(clamped)) {
                userSettingsModel[key] = previous
                userSettingsModel = Object.assign({}, userSettingsModel)
                manualModeMaxTonnagePerRam = Number(previous)
                persistUserSetting(key, previous)
                return false
            }
            manualPendingPreviousSetting = previous
            setManualPending("manual-max-tonnage", "setting",
                             "UPDATING TEMPORARY TONNAGE LIMIT")
        }
        log("MANUAL", "Setting " + key + " = " + clamped.toFixed(4))
        return true
    }

    function openManualMeasurement(mode) {
        var normalized = String(mode || "").toUpperCase()
        if (normalized !== "CALIBRATION" && normalized !== "MEASUREMENT")
            return false
        manualMeasurementPendingMode = ""
        // Thin-on-reference is an explicit per-session choice: a stale toggle
        // would silently subtract the reference from a normal piece.
        manualMeasurementOnReferencePiece = false
        // A fresh session never shows the outcome of an older calibration,
        // but an opening write that is still pending keeps its state.
        if (manualCalibrationOpeningState !== "WAITING"
                && manualCalibrationOpeningState !== "SENT")
            clearManualCalibrationOpening()
        return configureManualMeasurementMode(normalized)
    }

    function configureManualMeasurementMode(normalized) {
        manualMeasurementClosePending = false
        manualMeasurementMode = normalized
        manualMeasurementResult = NaN
        manualMeasurementStackResult = NaN
        manualMeasurementUsedForProgram = false
        resetManualMeasurementAcquisition("")
        clearManualMeasurementAcceptedSnapshot()
        manualMeasurementStatus = normalized === "CALIBRATION"
            ? "ENTER KNOWN PIECE SIZE" : (manualDieTopCalibrationValid
                ? "READY FOR PIECE" : "CALIBRATION REQUIRED")
        manualMeasurementVisible = true
        return true
    }

    function switchManualMeasurementMode(mode) {
        var normalized = String(mode || "").toUpperCase()
        if (normalized !== "CALIBRATION" && normalized !== "MEASUREMENT")
            return false
        if (normalized === manualMeasurementMode) {
            manualMeasurementPendingMode = ""
            return true
        }
        if (!manualMeasurementVisible)
            return configureManualMeasurementMode(normalized)
        if (!manualMeasurementProcessActive)
            return configureManualMeasurementMode(normalized)

        manualMeasurementPendingMode = normalized
        manualMeasurementStatus = "STOPPING BEFORE MODE SWITCH"
        var stopAccepted = stopManualMeasurementProcess()
        if (!manualMeasurementProcessActive) {
            finalizeManualMeasurementModeSwitch()
            return true
        }
        if (!stopAccepted) {
            manualMeasurementPendingMode = ""
            return false
        }
        return true
    }

    function finalizeManualMeasurementModeSwitch() {
        var mode = manualMeasurementPendingMode
        manualMeasurementPendingMode = ""
        if (mode === "CALIBRATION" || mode === "MEASUREMENT")
            configureManualMeasurementMode(mode)
    }

    function finalizeManualMeasurementClose() {
        manualMeasurementClosePending = false
        manualMeasurementPendingMode = ""
        manualMeasurementVisible = false
        resetManualMeasurementAcquisition("")
    }

    function closeManualMeasurement() {
        if (manualMeasurementProcessActive) {
            manualMeasurementClosePending = true
            manualMeasurementStatus = "STOPPING BEFORE CLOSE"
            if (!stopManualMeasurementProcess()) {
                manualMeasurementClosePending = false
                return false
            }
            if (!manualMeasurementProcessActive)
                finalizeManualMeasurementClose()
            return true
        }
        finalizeManualMeasurementClose()
        return true
    }

    function setManualKnownPieceUnit(unit) {
        var normalized = String(unit || "").toUpperCase()
        if (normalized !== "INCH" && normalized !== "MILLIMETER")
            return false
        manualKnownPieceUnit = normalized
        manualMeasurementResult = NaN
        resetManualMeasurementWindow("READY FOR KNOWN PIECE")
        clearManualMeasurementAcceptedSnapshot()
        return true
    }

    function setManualMeasurementTonnage(value) {
        var parsed = Math.round(Number(value) * 100) / 100
        if (manualMeasurementProcessActive || !isFinite(parsed))
            return false
        if (parsed < manualMeasurementTonnageMinimum - 1e-9
                || parsed > manualMeasurementTonnageMaximum + 1e-9) {
            showAlarm("MEASURING TONNAGE OUT OF RANGE",
                      "Enter a measuring tonnage from " + manualMeasurementTonnageMinimum.toFixed(2)
                      + " to " + manualMeasurementTonnageMaximum.toFixed(2) + " T.")
            return false
        }
        if (Math.abs(parsed - manualMeasurementTonnage) < 1e-9)
            return true
        manualMeasurementTonnage = parsed
        persistLocalSetting("manualMeasurementTonnage", parsed)
        log("MANUAL", "Measuring tonnage " + parsed.toFixed(2) + " T")
        return true
    }

    function setManualKnownPieceThickness(value, unit) {
        var parsed = Number(value)
        var normalized = String(unit || manualKnownPieceUnit).toUpperCase()
        if (normalized !== "INCH" && normalized !== "MILLIMETER")
            return false
        var canonicalInches = normalized === "MILLIMETER" ? parsed / 25.4 : parsed
        if (!isFinite(canonicalInches) || canonicalInches <= 0 || canonicalInches > 10)
            return false
        manualKnownPieceThickness = canonicalInches
        manualMeasurementResult = NaN
        resetManualMeasurementWindow("READY FOR KNOWN PIECE")
        clearManualMeasurementAcceptedSnapshot()
        return true
    }

    // kind: "PUNCH" | "DIE"; item: tooling library entry (id, name, heightInch).
    function setManualCalibrationTooling(kind, item) {
        var normalized = String(kind || "").toUpperCase()
        if (normalized !== "PUNCH" && normalized !== "DIE")
            return false
        if (manualMeasurementProcessActive)
            return false
        var height = item ? Number(item.heightInch) : NaN
        var valid = item && isFinite(height) && height > 0
        var id = valid ? String(item.id || "") : ""
        var name = valid ? String(item.name || "") : ""
        if (normalized === "PUNCH") {
            manualCalibrationPunchId = id
            manualCalibrationPunchName = name
            manualCalibrationPunchHeight = valid ? height : NaN
        } else {
            manualCalibrationDieId = id
            manualCalibrationDieName = name
            manualCalibrationDieHeight = valid ? height : NaN
        }
        return valid === true
    }

    // Default calibration tooling: the program's selected bend (what the
    // operator is about to run), else the tooling of the last calibration.
    function resolveManualCalibrationTooling(punches, dies) {
        var record = userSettingsModel && userSettingsModel.manualDieTopCalibration
            ? userSettingsModel.manualDieTopCalibration : ({})
        var bend = selectedBend || ({})
        var punch = findById(punches, String(bend.punchId || ""))
            || findById(punches, String(record.punchId || ""))
        var die = findById(dies, String(bend.dieId || ""))
            || findById(dies, String(record.dieId || ""))
        setManualCalibrationTooling("PUNCH", punch)
        setManualCalibrationTooling("DIE", die)
        return manualCalibrationToolingValid
    }

    function setManualMeasurementOnReferencePiece(enabled) {
        var next = enabled === true
        if (manualMeasurementProcessActive)
            return false
        if (next && !(manualCalibrationReferenceThickness > 0)) {
            showAlarm("REFERENCE PIECE UNKNOWN",
                      "The active calibration does not record its reference piece. Recalibrate with the reference piece before measuring thin material on it.")
            return false
        }
        manualMeasurementOnReferencePiece = next
        manualMeasurementResult = NaN
        manualMeasurementStackResult = NaN
        manualMeasurementUsedForProgram = false
        clearManualMeasurementAcceptedSnapshot()
        resetManualMeasurementWindow(manualDieTopCalibrationValid
            ? "READY FOR PIECE" : "CALIBRATION REQUIRED")
        return true
    }

    function setMeasuredThicknessOverride(enabled) {
        var next = enabled === true
        if (next === measuredThicknessOverrideEnabled)
            return true
        if (runActive || runSimulatedRun) {
            showAlarm("MEASURED THICKNESS OVERRIDE",
                      "Stop the run before changing the thickness used by the program.")
            return false
        }
        if (next && !measuredMaterialThicknessValid) {
            showAlarm("NO MEASURED THICKNESS",
                      "Measure a piece and press USE IN PROGRAM before overriding the program thickness.")
            return false
        }
        measuredThicknessOverrideEnabled = next
        log("RUN", next
            ? "Measured thickness override ON: " + measuredMaterialThickness.toFixed(4)
              + " in (session only, programs unchanged)"
            : "Measured thickness override OFF: program thickness restored")
        if (next && measuredThicknessOverrideUnresolvedCount > 0)
            showAlarm("MEASURED THICKNESS OVERRIDE",
                      String(measuredThicknessOverrideUnresolvedCount)
                      + " bend(s) of this program cannot be recalculated (punch, die or material"
                      + " not resolved). RUN stays blocked for them until the override is turned off.")
        return true
    }

    function refreshMeasuredThicknessOverride() {
        // Never replace the targets owned by an admitted run; apply afterwards.
        if (runActive) {
            measuredThicknessOverrideResyncPending = true
            log("RUN", "Measured thickness change deferred until the run ends")
            return
        }
        syncActiveProgramState()
    }

    function thicknessUnitLabel() { return metricUnits ? "mm" : "in" }

    function programThicknessText() {
        var values = []
        for (var i = 0; i < storedProgramBends.length; i++) {
            var bend = storedProgramBends[i] || ({})
            var thickness = finiteNumber(valueOr(bend, "materialThickness", valueOr(bend, "thickness", NaN)), NaN)
            var text = thickness > 0 ? (metricUnits ? (thickness * 25.4).toFixed(2) : thickness.toFixed(4)) : "—"
            if (values.indexOf(text) < 0)
                values.push(text)
        }
        return values.join(" / ")
    }

    function measuredThicknessOverrideText() {
        if (!measuredThicknessOverrideActive)
            return ""
        var program = programThicknessText()
        return "MEASURED t " + Units.len(measuredMaterialThickness, metricUnits, 4)
            + (program.length > 0 ? " · PROGRAM t " + program + (metricUnits ? " mm" : " in") : "")
            + " · NOT SAVED"
    }

    function measuredThicknessBendCalc(bend, thickness, punchRef, dieRef, materialRef) {
        return calcBendParity(Object.assign({}, bend, {
            materialThickness: thickness,
            overrideFinalBendPositionEnabled: false
        }), punchRef, dieRef, materialRef)
    }

    // Runtime copy of a program bend recalculated for the measured thickness.
    // Stored positions may use either the height-stack or the machine
    // convention, so only the calculator deltas for the thickness change are
    // applied (punch clearance and ram-to-table opening cancel out). A final
    // position the operator overrode stays fixed.
    function effectiveProgramBend(bend) {
        var source = bend || ({})
        var programThickness = finiteNumber(valueOr(source, "materialThickness",
                                                    valueOr(source, "thickness", NaN)), NaN)
        var thickness = measuredMaterialThickness
        var marker = {
            programThickness: programThickness,
            programStartPosition: source.startPosition,
            programClampPosition: source.clampPosition,
            programFinalPosition: source.finalPosition,
            measuredThicknessOverride: "UNRESOLVED"
        }
        var library = programToolingLibrary || ({})
        var punchRef = findById(library.punches, valueOr(source, "punchId", ""))
        var dieRef = findById(library.dies, valueOr(source, "dieId", ""))
        var materialRef = findById(library.materials, valueOr(source, "materialId", ""))
        var base = programThickness > 0 && thickness > 0
            ? measuredThicknessBendCalc(source, programThickness, punchRef, dieRef, materialRef) : null
        var measured = base
            ? measuredThicknessBendCalc(source, thickness, punchRef, dieRef, materialRef) : null
        var start = Number(source.startPosition)
        var clamp = Number(source.clampPosition)
        var finalPosition = Number(source.finalPosition)
        if (!measured || !isFinite(start) || !isFinite(clamp) || !isFinite(finalPosition))
            return Object.assign({}, source, marker)
        // FINAL-CLAMP is independent of clearance and opening; a mismatch
        // with the calculator means an operator-entered final position.
        var finalFixed = source.overrideFinalBendPositionEnabled === true
            && Math.abs((finalPosition - clamp)
                        - (base.calculatedFinalBendPosition - base.clampPosition)) > 0.0003
        var nextStart = start + measured.startSafetyClearance - base.startSafetyClearance
        var nextClamp = clamp + measured.clampPosition - base.clampPosition
        var nextFinal = finalFixed ? finalPosition
            : finalPosition + measured.calculatedFinalBendPosition - base.calculatedFinalBendPosition
        if (!(nextStart > nextClamp && nextClamp > nextFinal))
            return Object.assign({}, source, marker)
        var retract = Number(source.retractPosition)
        var tonnage = Number(source.tonnage)
        var ratio = thickness / programThickness
        var effective = Object.assign({}, source, marker, {
            measuredThicknessOverride: "APPLIED",
            measuredThicknessFinalFixed: finalFixed,
            thickness: formatNumber(thickness, 4, "0.0000"),
            materialThickness: thickness,
            startPosition: formatNumber(nextStart, 4, "0.0000"),
            clampPosition: formatNumber(nextClamp, 4, "0.0000"),
            finalPosition: formatNumber(nextFinal, 4, "0.0000")
        })
        var retractDelta = Number(measured.retractAfterBend) - Number(base.retractAfterBend)
        if (isFinite(retract) && isFinite(retractDelta))
            effective.retractPosition = formatNumber(retract + retractDelta, 4, "0.0000")
        if (isFinite(tonnage))
            effective.tonnage = formatNumber(tonnage * ratio * ratio, 3, "0.000")
        if (!finalFixed && source.overrideFinalBendPositionEnabled === true)
            effective.overriddenFinalBendPosition = nextFinal
        return effective
    }

    function useManualMeasurementForProgram() {
        var value = Number(manualMeasurementResult)
        if (manualMeasurementMode !== "MEASUREMENT" || !isFinite(value) || value <= 0) {
            showAlarm("NO VALID MEASUREMENT",
                      "Measure a piece first. Only a positive measured thickness can be used by bend programs.")
            return false
        }
        const previous = userSettingsModel ? userSettingsModel.measuredMaterialThickness : undefined
        const next = {
            value: value,
            unit: "INCH",
            valid: true,
            onReferencePiece: manualMeasurementOnReferencePiece,
            referenceThickness: manualMeasurementOnReferencePiece
                ? manualCalibrationReferenceThickness : null,
            measuredAt: new Date().toISOString()
        }
        const persisted = persistUserSetting("measuredMaterialThickness", next)
        if (storageBackendReady && !persisted) {
            userSettingsModel.measuredMaterialThickness = previous
            showAlarm("THICKNESS SAVE FAILED",
                      "The measured thickness could not be saved for bend programs.")
            return false
        }
        userSettingsModel = Object.assign({}, userSettingsModel)
        manualMeasurementUsedForProgram = true
        manualMeasurementStatus = "READY FOR BEND PROGRAM"
        log("MANUAL", "Measured thickness " + value.toFixed(4) + " in released for bend programs")
        return true
    }

    function clearManualCalibrationOpening() {
        manualCalibrationOpeningState = ""
        manualCalibrationOpeningCandidate = NaN
        manualCalibrationOpeningPrevious = NaN
        manualCalibrationOpeningDeadlineMs = 0
    }

    // Called once per completed calibration with the derived opening.
    function prepareManualCalibrationOpening(opening) {
        manualCalibrationOpeningCandidate = opening
        manualCalibrationOpeningPrevious = authoritativeRamToTableOpening()
        if (!isFinite(opening)) {
            manualCalibrationOpeningState = "NO TOOLING"
            log("MANUAL", "Calibration without punch/die heights: opening not updated")
            return false
        }
        if (opening < manualCalibrationOpeningMinimum || opening > manualCalibrationOpeningMaximum) {
            manualCalibrationOpeningState = "OUT OF RANGE"
            showAlarm("CALIBRATED OPENING OUT OF RANGE",
                      "The die top and the selected punch/die give a ram-to-table opening of "
                      + opening.toFixed(4) + " in, outside " + manualCalibrationOpeningMinimum.toFixed(3)
                      + "-" + manualCalibrationOpeningMaximum.toFixed(3)
                      + " in. Check the selected tooling. The opening was not changed.")
            return false
        }
        const previous = manualCalibrationOpeningPrevious
        if (isFinite(previous) && Math.abs(opening - previous) < 0.00005) {
            manualCalibrationOpeningState = "UNCHANGED"
            return true
        }
        // Never written automatically: the operator confirms every change
        // with APPLY OPENING.
        manualCalibrationOpeningState = "REVIEW"
        const large = !isFinite(previous)
            || Math.abs(opening - previous) > manualCalibrationOpeningReviewDelta
        log("MANUAL", "Calibrated opening " + opening.toFixed(4) + " in (current "
            + (isFinite(previous) ? previous.toFixed(4) : "unknown")
            + ") waiting for APPLY OPENING"
            + (large ? "; large change, verify installed punch/die" : ""))
        return false
    }

    function applyManualCalibrationOpening() {
        const opening = Number(manualCalibrationOpeningCandidate)
        if (!isFinite(opening) || opening < manualCalibrationOpeningMinimum
                || opening > manualCalibrationOpeningMaximum)
            return false
        if (manualCalibrationOpeningState === "SENT"
                || manualCalibrationOpeningState === "APPLIED")
            return false
        if (offlineSimulationEnabled) {
            desktopRamToTableOpening = opening
            persistLocalSetting("desktopRamToTableOpening", opening)
            manualCalibrationOpeningState = "APPLIED"
            log("MANUAL", "Calibrated opening " + opening.toFixed(4) + " in applied (offline)")
            return true
        }
        manualCalibrationOpeningDeadlineMs = Date.now() + manualCalibrationOpeningWaitMs
        manualCalibrationOpeningState = "WAITING"
        tryApplyManualCalibrationOpening()
        return true
    }

    // The controller accepts the EEPROM write only at rest; calibration ends
    // while the hold is still releasing, so the write waits for IDLE.
    function tryApplyManualCalibrationOpening() {
        if (manualCalibrationOpeningState !== "WAITING")
            return false
        if (!machineControl || typeof machineControl.setRamToTableOpening !== "function") {
            manualCalibrationOpeningState = "FAILED"
            return false
        }
        const machineState = String(machineControl.pressMachineState || "")
        const ready = machineControl.pressConnected === true
            && String(machineControl.pressConnectionState || "") === "READY"
            && machineControl.pressTelemetryFresh === true
            && (machineState === "IDLE" || machineState === "STARTUP_HOMING_REQUIRED"
                || machineState === "HYDRAULIC_SHUTDOWN")
            && machineControl.pressOperationActive !== true
            && machineControl.commandOperationActive !== true
            && !manualMeasurementProcessActive
            && ramToTableSaveOperationId === undefined
        if (!ready) {
            if (Date.now() >= manualCalibrationOpeningDeadlineMs) {
                manualCalibrationOpeningState = "BUSY"
                log("MANUAL", "Calibrated opening not saved: press did not return to rest")
            }
            return false
        }
        if (!machineControl.setRamToTableOpening(Number(manualCalibrationOpeningCandidate))) {
            manualCalibrationOpeningState = "FAILED"
            return false
        }
        manualCalibrationOpeningOperationId = Number(machineControl.operationId)
        ramToTableSaveOperationId = manualCalibrationOpeningOperationId
        manualCalibrationOpeningState = "SENT"
        return true
    }

    function handleManualCalibrationOpeningFinished(result, error) {
        manualCalibrationOpeningOperationId = undefined
        if (result === "COMPLETED") {
            manualCalibrationOpeningState = "APPLIED"
            log("MANUAL", "Calibrated opening " + Number(manualCalibrationOpeningCandidate).toFixed(4)
                + " in saved to controller EEPROM")
            if (!manualMeasurementVisible)
                showPopup("CALIBRATION", "Ram To Table Opening Distance updated from calibration and saved to controller EEPROM.",
                          1, "message", "CLOSE")
            return
        }
        manualCalibrationOpeningState = "FAILED"
        var reason = String(error || "CONTROLLER_CONFIRMATION_FAILED")
        var detail = reason === "RAM_TO_TABLE_EEPROM_BUSY"
            ? "Controller refused the EEPROM write because its control loop is not at rest. Press STOP, wait for IDLE and retry APPLY OPENING."
            : reason === "RAM_TO_TABLE_STOP_TIMEOUT"
            ? "Controller did not confirm STOP before the EEPROM write. Check the connection and retry APPLY OPENING."
            : reason.replace(/_/g, " ")
        log("MANUAL", "Calibrated opening save failed: " + reason)
        showAlarm("CALIBRATED OPENING SAVE FAILED", detail)
    }

    function clearManualMeasurementAcceptedSnapshot() {
        manualMeasurementAcceptedLoadY1Mean = NaN
        manualMeasurementAcceptedLoadY2Mean = NaN
        manualMeasurementAcceptedLoadMean = NaN
        manualMeasurementAcceptedLoadPeak = NaN
        manualMeasurementAcceptedSamples = 0
        manualMeasurementAcceptedDurationMs = 0
        manualMeasurementAcceptedCriterion = ""
    }

    function resetManualMeasurementWindow(status) {
        manualMeasurementQualifiedSamples = 0
        manualMeasurementSampleSum = 0
        manualMeasurementMeanHistory = []
        manualMeasurementConvergenceSpread = NaN
        manualMeasurementPositionSamples = []
        manualMeasurementLoadY1Samples = []
        manualMeasurementLoadY2Samples = []
        manualMeasurementPositionMinimum = NaN
        manualMeasurementPositionMaximum = NaN
        manualMeasurementLoadY1Sum = 0
        manualMeasurementLoadY2Sum = 0
        manualMeasurementLoadTotalMinimum = NaN
        manualMeasurementLoadTotalMaximum = NaN
        manualMeasurementWindowStartedMs = 0
        manualMeasurementLastSampleMs = 0
        if (String(status || "").length > 0)
            manualMeasurementStatus = status
    }

    function resetManualMeasurementAcquisition(status) {
        resetManualMeasurementWindow(status)
        manualMeasurementTimedOut = false
        manualMeasurementSyntheticTimeMs = 0
        manualMeasurementLastTelemetrySequence = offlineSimulationEnabled
            ? -1 : (machineControl ? Number(machineControl.pressTelemetrySequence) : -1)
    }

    function startManualMeasurementProcess(kind) {
        var normalized = String(kind || "").toUpperCase()
        if (manualMeasurementMode === "MEASUREMENT"
                && !manualDieTopCalibrationValid) {
            showAlarm("MEASUREMENT CALIBRATION REQUIRED",
                      "Calibrate the die top with a known piece before measuring an unknown piece.")
            return false
        }
        if (manualMeasurementMode === "MEASUREMENT" && manualMeasurementOnReferencePiece
                && !(manualCalibrationReferenceThickness > 0)) {
            showAlarm("REFERENCE PIECE UNKNOWN",
                      "The active calibration does not record its reference piece. Recalibrate before measuring thin material on it.")
            return false
        }
        if (manualMeasurementMode === "CALIBRATION"
                && manualCalibrationOpeningState !== "SENT")
            clearManualCalibrationOpening()
        resetManualMeasurementAcquisition("")
        clearManualMeasurementAcceptedSnapshot()
        manualMeasurementResult = NaN
        manualMeasurementStackResult = NaN
        manualMeasurementUsedForProgram = false
        manualMeasurementStatus = "WAITING FOR CONTACT"
        if (normalized === "AUTO")
            return startTonnageHoldProfile(manualMeasurementTonnage, manualMeasurementMode, true)
        if (normalized === "PEDAL")
            return manualAction("tonnage-hold", manualMeasurementTonnage)
        return false
    }

    function stopManualMeasurementProcess() {
        if (contactProfileActive)
            return cancelTonnageHoldProfile()
        if (tonnageHoldActive)
            return manualAction("tonnage-hold")
        return true
    }

    function finishManualMeasurementProcess() {
        if (contactProfileActive)
            return releaseTonnageHoldProfile()
        if (tonnageHoldActive)
            return manualAction("tonnage-hold")
        return true
    }

    // Reusable tonnage hold profile (firmware THC contact profile: approach,
    // regulate to target, qualify HOLD, release clearance). Independent of
    // Manual mode; any feature may own it. Returns false if not started.
    function startTonnageHoldProfile(target, owner, confirm) {
        if (offlineSimulationEnabled || contactProfileActive)
            return false
        if (!machineControl || !contactProfileCanOperate) {
            showAlarm("AUTOMATIC HOLD NOT READY",
                      "Home the press and wait for fresh IDLE telemetry before starting the automatic profile.")
            return false
        }
        var holdTarget = Math.round(Number(target) * 1000) / 1000
        if (!isFinite(holdTarget) || holdTarget < automaticTonnageHoldMinimum - 1e-9
                || holdTarget > automaticTonnageHoldMaximum + 1e-9) {
            showAlarm("AUTOMATIC HOLD TARGET OUT OF RANGE",
                      "Set an automatic hold target from " + automaticTonnageHoldMinimum.toFixed(2)
                      + " to " + automaticTonnageHoldMaximum.toFixed(2) + " T.")
            return false
        }
        var holdOwner = String(owner || "MANUAL")
        var begin = function() {
            if (!machineControl.startAutomaticThcContactProfile(holdTarget, Number(bendRamSpeed)))
                return false
            contactProfileTarget = holdTarget
            contactProfileOwner = holdOwner
            contactProfileActive = true
            if (holdOwner === "MANUAL")
                manualModeState = "AUTOMATIC HOLD RUNNING"
            return true
        }
        if (!confirm)
            return begin()
        showConfirmation("START AUTOMATIC " + holdTarget.toFixed(2) + " T HOLD",
                         "The press will approach at 5 IPM, regulate to " + holdTarget.toFixed(2)
                         + " T, require five fresh samples from "
                         + (holdTarget - automaticHoldAcceptanceBand).toFixed(2)
                         + " to " + (holdTarget + automaticHoldAcceptanceBand).toFixed(2)
                         + " T, then retract 0.25 in automatically."
                         + (Math.abs(holdTarget - 1.0) > 1e-9
                            ? " Targets other than 1.00 T need the AUTO-target controller firmware." : ""),
                         function() { begin() })
        return true
    }

    function cancelTonnageHoldProfile() {
        if (!contactProfileActive)
            return true
        if (!machineControl || !machineControl.cancelThcCommissioning())
            return false
        if (contactProfileOwner === "MANUAL")
            manualModeState = "AUTOMATIC HOLD CANCELLING"
        return true
    }

    // Typed release while HOLDING (owner accepted its sample window).
    function releaseTonnageHoldProfile() {
        return contactProfileActive && !!machineControl
            && machineControl.releaseThcCommissioning()
    }

    function finishTonnageHoldProfile(completed, reason) {
        if (!contactProfileActive)
            return
        var owner = contactProfileOwner
        contactProfileActive = false
        contactProfileOwner = ""
        if (owner === "MANUAL")
            manualModeState = manualModeEnabled ? "ENABLED" : "IDLE"
        if (owner === "RUN_AUTO_MEASURE")
            Qt.callLater(handleRunAutoMeasureFinished, completed, String(reason || ""))
        tonnageHoldProfileFinished(owner, completed, String(reason || ""))
    }

    function setToolChangeBackoff(value) {
        toolChangeBackoff = Math.abs(Number(value) - 0.25) < 1e-9 ? 0.25 : 0.125
        persistLocalSetting("toolChangeBackoff", toolChangeBackoff)
    }

    // Ram target after TOOLING REMOVED. Down = more negative position; a
    // taller new punch reaches lower, so the ram rises by the difference.
    function toolChangeMoveTarget(contact, backoff, oldHeight, newHeight) {
        return Number(contact) + Number(backoff) + (Number(newHeight) - Number(oldHeight))
    }

    // Missing or invalid heights block the tool change before TOUCH.
    function beginToolChange(oldPunchHeight, newPunchHeight) {
        var oldH = Number(oldPunchHeight), newH = Number(newPunchHeight)
        if (!(isFinite(oldH) && oldH > 0 && isFinite(newH) && newH > 0)) {
            toolChangeState = "FAILED"
            toolChangeFailure = "MISSING_TOOLING_HEIGHT"
            showAlarm("TOOL CHANGE BLOCKED", "Old and new punch heights are required.")
            return false
        }
        if (!toolChangeSupported) {
            showAlarm("TOOL CHANGE NOT AVAILABLE", "The press firmware does not report the tool change capability.")
            return false
        }
        toolChangeOldPunchHeight = oldH
        toolChangeNewPunchHeight = newH
        toolChangeContact = NaN
        toolChangeFailure = ""
        toolChangeSeatAgainAvailable = false
        toolChangeState = "AWAIT_TOUCH"
        return true
    }

    // Jog-down held: starts TOUCH and renews the lease while held.
    function toolChangeJogDownPressed(computedContact) {
        if (toolChangeState !== "AWAIT_TOUCH" || !machineControl)
            return false
        var floor = Math.max(-4.0, Number(computedContact) - toolChangeTouchMargin)
        if (!isFinite(floor) || !machineControl.startToolChangeTouch(toolChangeBackoff, floor))
            return false
        toolChangeState = "TOUCH"
        toolChangeTouchHeartbeat.start()
        return true
    }

    // Release before contact cancels (no retry); after contact BACKOFF is
    // firmware-owned and the heartbeat is no longer needed.
    // The firmware evaluates the THC lease through BACKOFF too, so the
    // heartbeat keeps running after contact until BACKOFF_DONE.
    function toolChangeJogDownReleased() {
        if (toolChangeState !== "TOUCH")
            return
        toolChangeTouchHeartbeat.stop()
        // A quick tap/release before contact is not a fault: the firmware
        // confirms CANCELLED and the step re-arms at AWAIT_TOUCH.
        toolChangeTouchReleaseCancel = true
        if (!machineControl || !machineControl.cancelThcCommissioning()) {
            toolChangeTouchReleaseCancel = false
        }
    }
    property bool toolChangeTouchReleaseCancel: false

    function confirmToolingRemoved() {
        if (toolChangeState !== "AWAIT_TOOLING_REMOVED" || !machineControl)
            return false
        var target = toolChangeMoveTarget(toolChangeContact, toolChangeBackoff,
                                          toolChangeOldPunchHeight, toolChangeNewPunchHeight)
        if (!machineControl.startToolChangeMove(target))
            return false
        toolChangeState = "MOVE"
        return true
    }

    function startToolChangeSeat() {
        if ((toolChangeState !== "AWAIT_SEAT" && !toolChangeSeatAgainAvailable) || !machineControl)
            return false
        // A RUN started at the tool change has not run STARTING yet, so
        // physicalRunRetractPlane is still its default 0 (> -0.05, firmware
        // rejects TH:SEAT with ARGUMENT). Use the bend's retract target.
        var plane = -0.05
        if (standaloneSeatActive) {
            // Standalone: return to where the seat started, not the top.
            plane = Math.min(-0.05, rawRamPosition)
            if (!isFinite(plane)) plane = -0.05
        } else if (runActive) {
            plane = physicalRunRetractPlane
            if (!isFinite(plane) || plane > -0.05)
                plane = runRamTarget("retractPosition")
            if (!isFinite(plane) || plane > -0.05)
                plane = -0.05
        }
        if (!machineControl.startToolChangeSeat(bendRamSpeed, jogRamSpeed, plane,
                                                toolChangeEqualForceSeat === true))
            return false
        toolChangeState = "SEAT"
        return true
    }

    // Standalone SEAT (Manual view, outside RUN): arms the same pedal-owned
    // firmware seat (EQ when enabled) without TOUCH/BACKOFF/MOVE.
    property bool standaloneSeatActive: false
    readonly property bool standaloneSeatAvailable: !runActive && toolChangeSupported
        && (offlineSimulationEnabled || pressCanOperate)
    function startStandaloneSeat() {
        if (standaloneSeatActive || runActive || runToolChangeActive)
            return false
        if (!offlineSimulationEnabled && (!toolChangeSupported || !pressCanOperate)) {
            showAlarm("SEAT NOT AVAILABLE", "Enable Manual with the press homed and idle; the firmware must report tool change.")
            return false
        }
        toolChangeFailure = ""
        toolChangeSeatAgainAvailable = false
        seatLevelSkew = NaN
        if (!offlineSimulationEnabled && machineControl)
            machineControl.queryRamLevelOffset()
        standaloneSeatActive = true
        toolChangeState = "AWAIT_SEAT"
        if (offlineSimulationEnabled)
            return true
        if (!startToolChangeSeat()) {
            standaloneSeatActive = false
            toolChangeState = "IDLE"
            showAlarm("SEAT REJECTED", "The press did not accept the seat command.")
            return false
        }
        log("MANUAL", "Standalone seat armed" + (toolChangeEqualForceSeat ? " (equal tonnage)" : "") + "; hold the pedal")
        return true
    }
    // Ram leveling (firmware $L): Y1-Y2 measured while the standalone seat
    // holds is added to the stored Y2 offset. Takes effect at the next HOME.
    property real ramLevelOffset: NaN      // firmware-reported, inches
    property real seatLevelSkew: NaN       // last Y1-Y2 during SEAT_HOLD
    readonly property bool ramLevelAvailable: !offlineSimulationEnabled && !standaloneSeatActive
        && isFinite(ramLevelOffset) && isFinite(seatLevelSkew)
    function captureSeatLevelSkew() {
        if (standaloneSeatActive && toolChangeState === "SEAT_HOLD" && independentRamTelemetryAvailable)
            seatLevelSkew = ramPositionY1 - ramPositionY2
    }
    function applyRamLevel() {
        if (!ramLevelAvailable || !machineControl)
            return false
        var next = ramLevelOffset + seatLevelSkew
        if (Math.abs(next) > 0.100) {
            showAlarm("LEVEL OUT OF RANGE", "Offset " + next.toFixed(4) + " in exceeds 0.100 in. Check the punch seat and homing.")
            return false
        }
        if (!machineControl.setRamLevelOffset(next)) {
            showAlarm("LEVEL REJECTED", "The press must be connected and idle.")
            return false
        }
        log("MANUAL", "Ram level offset Y2 " + ramLevelOffset.toFixed(4) + " -> " + next.toFixed(4)
            + " in (seated skew " + seatLevelSkew.toFixed(4) + "); HOME to apply")
        seatLevelSkew = NaN
        showPopup("LEVEL", "Level offset saved: " + next.toFixed(4) + " in. Run HOME to apply it.")
        return true
    }
    function stopStandaloneSeat() {
        if (!standaloneSeatActive)
            return
        toolChangeOfflineTimer.stop()
        if (!offlineSimulationEnabled && machineControl
                && (toolChangeState === "SEAT" || toolChangeState === "SEAT_PAUSED"
                    || toolChangeState === "SEAT_HOLD"))
            machineControl.stopTonnageHold()
        standaloneSeatActive = false
        endToolChange()
    }
    function handleStandaloneSeatStateChanged() {
        if (!standaloneSeatActive)
            return
        if (toolChangeState === "DONE" || toolChangeState === "FAILED") {
            log("MANUAL", "Standalone seat " + (toolChangeState === "DONE" ? "complete" : "failed: " + toolChangeFailure))
            standaloneSeatActive = false
            toolChangeSeatAgainAvailable = false
            toolChangeState = "IDLE"
        }
    }

    // Next sequence start retires SEAT AGAIN.
    function endToolChange() {
        toolChangeTouchHeartbeat.stop()
        toolChangeSeatAgainAvailable = false
        toolChangeState = "IDLE"
    }

    function handleToolChangeEvent(event, position) {
        if (event === "CONTACT") {
            toolChangeContact = Number(position)
            toolChangeState = "BACKOFF"
        } else if (event === "SEAT_PAUSED") {
            toolChangeState = "SEAT_PAUSED"
        } else if (event === "SEAT_RESUMED") {
            toolChangeState = "SEAT"
        } else if (event === "SEAT_HOLDING") {
            toolChangeState = "SEAT_HOLD"
        }
    }

    function handleToolChangeOperationFinished(operation, state, error) {
        toolChangeTouchHeartbeat.stop()
        var releaseCancel = toolChangeTouchReleaseCancel
        toolChangeTouchReleaseCancel = false
        if (state !== "COMPLETED" && releaseCancel && toolChangeState === "TOUCH"
                && String(error || state).indexOf("CANCELLED") >= 0) {
            toolChangeState = "AWAIT_TOUCH"
            log("RUN", "Tool change TOUCH paused (pedal released before contact); hold the pedal to continue")
            // Pedal/palms pressed again before CANCELLED arrived: that press
            // was swallowed while still in TOUCH, so re-evaluate held inputs.
            runToolChangeJogHeld = false
            Qt.callLater(function() {
                handleRunToolChangePedal()
                handleRunToolChangeJogInput()
            })
            return
        }
        if (state !== "COMPLETED") {
            toolChangeFailure = error || state
            toolChangeState = "FAILED"
            if (operation === "tool-change-seat")
                toolChangeSeatAgainAvailable = true
            showAlarm("TOOL CHANGE FAILED", toolChangeFailure)
            return
        }
        if (operation === "tool-change-touch") {
            var same = Math.abs(toolChangeOldPunchHeight - toolChangeNewPunchHeight) < 1e-6
            toolChangeState = same ? "AWAIT_SEAT" : "AWAIT_TOOLING_REMOVED"
        } else if (operation === "tool-change-move") {
            toolChangeState = "AWAIT_SEAT"
        } else if (operation === "tool-change-seat") {
            toolChangeState = "DONE"
            toolChangeSeatAgainAvailable = true
        }
    }

    // --- RUN TOOL_CHANGE step ---------------------------------------------

    function toolingPunchHeight(bend) {
        var library = programToolingLibrary || ({})
        var ref = bend ? findById(library.punches, valueOr(bend, "punchId", "")) : null
        var h = ref ? Number(ref.heightInch) : NaN
        return isFinite(h) && h > 0 ? h : NaN
    }

    function segmentsKey(list) {
        return (list || []).map(function(v) { return Number(v).toFixed(3) }).join(",")
    }

    // Tool change marker before bend `index` (display + run). Null when the
    // tooling setup is unchanged from the previous bend.
    function toolChangeBeforeBend(bends, index) {
        if (!bends || index <= 0 || index >= bends.length)
            return null
        var prev = bends[index - 1] || {}, next = bends[index] || {}
        var phaseChanged = finiteNumber(prev.toolingPhaseIndex, 0)
            !== finiteNumber(next.toolingPhaseIndex, 0)
        var punchChanged = String(prev.punchId || prev.punch || "") !== String(next.punchId || next.punch || "")
            || segmentsKey(prev.punchSegmentWidths) !== segmentsKey(next.punchSegmentWidths)
        var dieChanged = String(prev.dieId || prev.die || "") !== String(next.dieId || next.die || "")
            || segmentsKey(prev.dieSegmentWidths) !== segmentsKey(next.dieSegmentWidths)
        if (!phaseChanged && !punchChanged && !dieChanged)
            return null
        if (!punchChanged && !dieChanged)
            return null
        // Side-by-side stations already installed on the table: no pause.
        var prevRack = finiteNumber(prev.toolingRackIndex, NaN)
        if (isFinite(prevRack) && prevRack === finiteNumber(next.toolingRackIndex, NaN))
            return null
        var label = punchChanged && dieChanged ? "TOOLING" : (punchChanged ? "PUNCH" : "DIE")
        var describe = function(name, widths) {
            var w = (widths || []).map(function(v) { return String(Number(v)) }).join("-")
            return String(name || "") + (w ? " " + w : "")
        }
        // Per tool: "profile" (different punch/die), "segments" (same profile,
        // different stack of pieces; piece order alone is not a change) or "none".
        var sortedKey = function(list) {
            return segmentsKey((list || []).slice().sort(function(a, b) { return Number(a) - Number(b) }))
        }
        var kindOf = function(idA, idB, widthsA, widthsB) {
            if (String(idA) !== String(idB)) return "profile"
            return sortedKey(widthsA) !== sortedKey(widthsB) ? "segments" : "none"
        }
        var punchKind = kindOf(prev.punchId || prev.punch || "", next.punchId || next.punch || "",
                               prev.punchSegmentWidths, next.punchSegmentWidths)
        var dieKind = kindOf(prev.dieId || prev.die || "", next.dieId || next.die || "",
                             prev.dieSegmentWidths, next.dieSegmentWidths)
        if (punchKind === "none" && dieKind === "none")
            return null
        var widthsText = function(widths) {
            return (widths || []).map(function(v) { return String(Number(v)) }).join("-")
        }
        var part = function(tool, kind, nameA, nameB, widthsA, widthsB) {
            if (kind === "none") return tool + " unchanged"
            if (kind === "segments") return tool + " SEGMENTS " + widthsText(widthsA) + " \u2192 " + widthsText(widthsB)
            return tool + " " + describe(nameA, widthsA) + " \u2192 " + describe(nameB, widthsB)
        }
        var profileChange = punchKind === "profile" || dieKind === "profile"
        return {
            title: profileChange ? (punchKind === "profile" && dieKind === "profile" ? "TOOL CHANGE"
                                    : (punchKind === "profile" ? "PUNCH CHANGE" : "DIE CHANGE"))
                                 : "SEGMENT EDIT",
            punchKind: punchKind,
            dieKind: dieKind,
            summary: part("PUNCH", punchKind, prev.punch, next.punch, prev.punchSegmentWidths, next.punchSegmentWidths)
                     + "  \u00B7  " + part("DIE", dieKind, prev.die, next.die, prev.dieSegmentWidths, next.dieSegmentWidths),
            label: label,
            beforeIndex: index,
            fromPunch: describe(prev.punch, prev.punchSegmentWidths),
            toPunch: describe(next.punch, next.punchSegmentWidths),
            fromDie: describe(prev.die, prev.dieSegmentWidths),
            toDie: describe(next.die, next.dieSegmentWidths),
            oldPunchHeight: toolingPunchHeight(prev),
            newPunchHeight: toolingPunchHeight(next),
            prevBend: prev,
            nextBend: next
        }
    }

    // Front-view placement of the old and new segment stacks (inches along
    // the bed). A stack without a stored start is centered on 0.
    function toolChangeLayout(info) {
        var stack = function(bend, widthsKey, startKey) {
            var widths = (bend && bend[widthsKey]) || []
            var total = 0
            for (var i = 0; i < widths.length; ++i) total += Math.max(0, Number(widths[i]) || 0)
            var start = Number(bend ? bend[startKey] : NaN)
            if (!isFinite(start)) start = -total / 2
            start += finiteNumber(bend ? bend.toolingStationOffsetIn : 0, 0)
            var out = [], x = start
            for (var j = 0; j < widths.length; ++j) {
                var w = Math.max(0, Number(widths[j]) || 0)
                out.push({ x: x, w: w })
                x += w
            }
            return out
        }
        var prev = info ? info.prevBend : null, next = info ? info.nextBend : null
        var rows = {
            oldPunch: stack(prev, "punchSegmentWidths", "punchSegmentStartIn"),
            newPunch: stack(next, "punchSegmentWidths", "punchSegmentStartIn"),
            oldDie: stack(prev, "dieSegmentWidths", "dieSegmentStartIn"),
            newDie: stack(next, "dieSegmentWidths", "dieSegmentStartIn")
        }
        var minX = Infinity, maxX = -Infinity
        for (var k in rows)
            rows[k].forEach(function(s) { minX = Math.min(minX, s.x); maxX = Math.max(maxX, s.x + s.w) })
        if (!isFinite(minX)) { minX = -1; maxX = 1 }
        rows.minX = minX
        rows.maxX = maxX
        return rows
    }

    function runToolChangePhaseLabel() {
        switch (toolChangeState) {
        case "AWAIT_TOUCH": return "STEP 1 — " + ((runPedalMode === 3 || runPedalMode === 4) ? "TAP AND HOLD THE PEDAL" : "DOUBLE-TAP AND HOLD THE PEDAL") + " (OR HOLD JOG DOWN) TO BRING THE PUNCH DOWN TO THE DIE"
        case "TOUCH": return "STEP 1 — LOWERING TO CONTACT… KEEP THE PEDAL HELD"
        case "BACKOFF": return "STEP 1 — CONTACT. BACKING OFF " + toolChangeBackoff.toFixed(3) + " IN — YOU MAY RELEASE THE PEDAL"
        case "AWAIT_TOOLING_REMOVED": return "STEP 2 — LOOSEN THE CLAMPS AND REMOVE THE OLD TOOLING, THEN PRESS TOOLING REMOVED"
        case "MOVE": return "STEP 2 — MOVING TO THE NEW PUNCH HEIGHT…"
        case "AWAIT_SEAT": return (Math.abs(toolChangeOldPunchHeight - toolChangeNewPunchHeight) < 1e-6
                                   ? "STEP 2 — LOOSEN THE CLAMPS, REMOVE THE OLD TOOLING AND INSTALL THE NEW TOOLING AS SHOWN"
                                   : "STEP 3 — INSTALL THE NEW TOOLING AS SHOWN")
                                  + ", THEN " + (runBendSingleTap() ? "TAP AND HOLD" : "DOUBLE-TAP AND HOLD") + " THE PEDAL TO SEAT IT AT 1.00 T"
        case "SEAT": return "STEP 4 — SEATING… KEEP THE PEDAL HELD UNTIL 1.00 T IS REACHED"
        case "SEAT_HOLD": return "STEP 5 — 1.00 T REACHED: KEEP HOLDING, TIGHTEN THE PUNCH CLAMP SCREWS, THEN RELEASE THE PEDAL TO FINISH"
        case "SEAT_PAUSED": return "SEAT PAUSED (PEDAL RELEASED BEFORE 1.00 T) — " + (runBendSingleTap() ? "TAP AND HOLD" : "DOUBLE-TAP AND HOLD") + " THE PEDAL TO CONTINUE"
        case "DONE": return "TOOL CHANGE COMPLETE"
        case "FAILED": return "TOOL CHANGE FAILED — " + toolChangeFailure
        }
        return "TOOL CHANGE"
    }

    function enterRunToolChange(info) {
        runToolChangeInfo = info
        runToolChangeActive = true
        runToolChangeJogHeld = false
        executionPhase = "TOOL_CHANGE"
        physicalRunWaitAction = ""
        runProgressTitle = "Tool change before Bend #" + String(info.beforeIndex + 1)
        log("RUN", "Tool change (" + info.label + ") before bend " + String(info.beforeIndex + 1)
            + ": punch " + info.fromPunch + " -> " + info.toPunch
            + ", die " + info.fromDie + " -> " + info.toDie)
        if (offlineSimulationEnabled) {
            var oldH = isFinite(info.oldPunchHeight) ? info.oldPunchHeight : 4.0
            var newH = isFinite(info.newPunchHeight) ? info.newPunchHeight : oldH
            toolChangeOldPunchHeight = oldH
            toolChangeNewPunchHeight = newH
            toolChangeContact = NaN
            toolChangeFailure = ""
            toolChangeSeatAgainAvailable = false
            toolChangeState = "AWAIT_TOUCH"
        } else if (!beginToolChange(info.oldPunchHeight, info.newPunchHeight)) {
            runToolChangeActive = false
            failPhysicalRun("TOOL_CHANGE_BLOCKED")
            return false
        }
        runProgressSubtitle = runToolChangePhaseLabel()
        return true
    }

    function runToolChangeComputedContact() {
        var info = runToolChangeInfo
        if (!info || !info.prevBend)
            return NaN
        var opening = machineControl ? finiteRunValue(machineControl.ramToTableOpening, 0) : 0
        var thickness = finiteNumber(info.prevBend.materialThickness,
                                     finiteNumber(info.prevBend.thickness, 0))
        return physicalRunRamTarget(Number(info.prevBend.clampPosition) - thickness, opening)
    }

    function runToolChangeJogDown(pressed) {
        if (!runToolChangeActive)
            return false
        if (pressed) {
            if (toolChangeState !== "AWAIT_TOUCH" || runToolChangeJogHeld)
                return toolChangeState === "TOUCH"
            runToolChangeJogHeld = true
            if (offlineSimulationEnabled) {
                toolChangeState = "TOUCH"
                toolChangeOfflineTimer.restart()
                return true
            }
            var ok = toolChangeJogDownPressed(runToolChangeComputedContact())
            if (!ok)
                runToolChangeJogHeld = false
            return ok
        }
        if (!runToolChangeJogHeld)
            return false
        runToolChangeJogHeld = false
        if (toolChangeState === "TOUCH") {
            if (offlineSimulationEnabled) {
                toolChangeOfflineTimer.stop()
                toolChangeState = "AWAIT_TOUCH"
            } else {
                toolChangeJogDownReleased()
            }
        }
        return true
    }

    function handleRunToolChangeJogInput() {
        if (!runToolChangeActive)
            return
        var both = leftSafetyJog && rightSafetyJog
        if (both && toolChangeState === "AWAIT_TOUCH")
            runToolChangeJogDown(true)
        else if (!both && runToolChangeJogHeld)
            runToolChangeJogDown(false)
    }

    function runToolChangeToolingRemoved() {
        if (!runToolChangeActive || toolChangeState !== "AWAIT_TOOLING_REMOVED")
            return false
        if (offlineSimulationEnabled) {
            toolChangeState = "MOVE"
            toolChangeOfflineTimer.restart()
            return true
        }
        return confirmToolingRemoved()
    }

    function runToolChangeSeatAgain() {
        if (!toolChangeSeatAgainAvailable || !runActive || physicalRunCommandPending)
            return false
        runToolChangeActive = true
        executionPhaseIndex = 0
        executionPhase = "TOOL_CHANGE"
        if (offlineSimulationEnabled) {
            toolChangeState = "AWAIT_SEAT"
            return true
        }
        return startToolChangeSeat()
    }

    // Offline: the pedal drives SEAT; release after HOLD completes.
    function handleRunToolChangePedal() {
        if (!runToolChangeActive && !standaloneSeatActive)
            return
        // Pedal hold drives TOUCH (advance to contact, firmware backoff);
        // SEAT is pedal-owned in firmware once armed.
        // Modes 3/4 (1TAP jog): TOUCH follows the held pedal; else double-tap latch.
        var touchPedal = (runPedalMode === 3 || runPedalMode === 4) ? physicalPedalActive : bendJogPedal
        if (touchPedal && toolChangeState === "AWAIT_TOUCH") {
            runToolChangeJogDown(true)
            return
        }
        if (!touchPedal && runToolChangeJogHeld) {
            runToolChangeJogDown(false)
            return
        }
        if (!offlineSimulationEnabled)
            return
        if (bendJogPedal && (toolChangeState === "AWAIT_SEAT" || toolChangeState === "SEAT_PAUSED")) {
            toolChangeState = "SEAT"
            toolChangeOfflineTimer.restart()
        } else if (!bendJogPedal && toolChangeState === "SEAT") {
            toolChangeOfflineTimer.stop()
            toolChangeState = "SEAT_PAUSED"
        } else if (!bendJogPedal && toolChangeState === "SEAT_HOLD") {
            toolChangeState = "DONE"
            toolChangeSeatAgainAvailable = true
        }
    }

    function advanceOfflineToolChange() {
        if (toolChangeState === "TOUCH") {
            toolChangeContact = ramPosition - 0.5
            toolChangeState = "BACKOFF"
            toolChangeOfflineTimer.restart()
        } else if (toolChangeState === "BACKOFF") {
            var same = Math.abs(toolChangeOldPunchHeight - toolChangeNewPunchHeight) < 1e-6
            toolChangeState = same ? "AWAIT_SEAT" : "AWAIT_TOOLING_REMOVED"
        } else if (toolChangeState === "MOVE") {
            toolChangeState = "AWAIT_SEAT"
        } else if (toolChangeState === "SEAT") {
            toolChangeState = "SEAT_HOLD"   // HOLD reached
        }
    }

    function handleRunToolChangeStateChanged() {
        if (!runToolChangeActive)
            return
        runProgressSubtitle = runToolChangePhaseLabel()
        if (toolChangeState === "AWAIT_SEAT" && !offlineSimulationEnabled) {
            // Seat is pedal-owned in firmware; arm it as soon as tooling is ready.
            if (!startToolChangeSeat())
                failPhysicalRun("TOOL_CHANGE_SEAT_REJECTED")
        } else if (toolChangeState === "DONE") {
            finishRunToolChange()
        } else if (toolChangeState === "FAILED") {
            failPhysicalRun("TOOL_CHANGE_" + String(toolChangeFailure || "FAILED"))
        }
    }

    function finishRunToolChange() {
        runToolChangeActive = false
        runToolChangeJogHeld = false
        executionPhaseIndex = 0
        executionPhase = ExecutionModel.BendPhase.STARTING.name
        runProgressTitle = "Bend #" + String(selectedRunBend + 1) + " in Progress"
        runProgressSubtitle = currentRunPhaseLabel()
        log("RUN", "Tool change complete; continuing with bend " + String(selectedRunBend + 1))
        if (!offlineSimulationEnabled)
            Qt.callLater(dispatchPhysicalRunPhase)
    }

    function abortRunToolChange() {
        toolChangeOfflineTimer.stop()
        runToolChangeActive = false
        runToolChangeJogHeld = false
        runToolChangeInfo = null
        // SEAT runs under the TH lease (NativeTonnageHold); THC cancel is rejected there.
        var thcMoving = ["TOUCH", "BACKOFF", "MOVE"]
        if (!offlineSimulationEnabled && machineControl) {
            if (thcMoving.indexOf(toolChangeState) >= 0)
                machineControl.cancelThcCommissioning()
            else if (toolChangeState === "SEAT" || toolChangeState === "SEAT_PAUSED"
                     || toolChangeState === "SEAT_HOLD")
                machineControl.stopTonnageHold()
        }
        if (toolChangeState !== "IDLE")
            endToolChange()
    }

    function sampleManualMeasurement() {
        if (manualMeasurementTimedOut)
            return false
        var nowMs = offlineSimulationEnabled
            ? manualMeasurementSyntheticTimeMs + manualMeasurementSampleIntervalMs
            : Date.now()
        if (offlineSimulationEnabled)
            manualMeasurementSyntheticTimeMs = nowMs
        // The duration budget starts with the first averaged sample, so the
        // confirmation, approach and force acquisition never consume it.
        if (manualMeasurementWindowStartedMs > 0
                && nowMs - manualMeasurementWindowStartedMs
                    >= manualMeasurementMaximumDurationMs) {
            if (manualMeasurementQualifiedSamples >= manualMeasurementMinimumSamples)
                return completeManualMeasurement(nowMs, "TIME LIMIT")
            manualMeasurementStatus = "ACQUISITION TIMEOUT"
            manualMeasurementTimedOut = true
            Qt.callLater(stopManualMeasurementProcess)
            return false
        }
        if (!manualMeasurementTelemetryReady || !isFinite(manualMeasurementRamMean)) {
            manualMeasurementStatus = "WAITING FOR FRESH Y1 / Y2"
            return false
        }
        var sequence = offlineSimulationEnabled
            ? manualMeasurementLastTelemetrySequence + 1
            : Number(machineControl.pressTelemetrySequence)
        if (!offlineSimulationEnabled && sequence === manualMeasurementLastTelemetrySequence)
            return false
        if (manualMeasurementLastSampleMs > 0
                && nowMs - manualMeasurementLastSampleMs > 750)
            resetManualMeasurementWindow("TELEMETRY GAP · STABILIZING")
        manualMeasurementLastTelemetrySequence = sequence
        manualMeasurementLastSampleMs = nowMs
        // AUTO averages only the regulated HOLD: force acquisition is not a
        // measurement, and the typed release is admitted only while HOLDING.
        if (!offlineSimulationEnabled && contactProfileActive
                && String(machineControl.thcCommissioningState || "") !== "HOLDING") {
            manualMeasurementStatus = "WAITING FOR HOLD"
            return false
        }
        var target = manualMeasurementTargetTonnage
        var position = Number(manualMeasurementRamMean)
        var loadY1 = offlineSimulationEnabled ? target / 2 : Number(ramLoadY1)
        var loadY2 = offlineSimulationEnabled ? target / 2 : Number(ramLoadY2)
        if (!isFinite(loadY1) || !isFinite(loadY2) || loadY1 < 0 || loadY2 < 0) {
            resetManualMeasurementWindow("WAITING FOR VALID TONNAGE")
            return false
        }
        // Status loads arrive rounded to 0.1 T per ram; the epsilon keeps
        // 0.9 and 1.1 T symmetric (1.1 - 1.0 is 0.10000000000000009).
        if (Math.abs(loadY1 + loadY2 - target) > manualMeasurementLoadBand + 1e-6) {
            // Skip, never restart: samples already averaged stay valid.
            manualMeasurementStatus = manualMeasurementQualifiedSamples > 0
                ? (manualMeasurementConvergenceActive ? "CONVERGING " : "AVERAGING ")
                  + manualMeasurementQualifiedSamples + " / "
                  + manualMeasurementRequiredSamples + " · OUTSIDE BAND"
                : "WAITING FOR TARGET"
            return false
        }
        if (manualMeasurementWindowStartedMs <= 0)
            manualMeasurementWindowStartedMs = nowMs
        var positions = manualMeasurementPositionSamples.slice()
        var loadsY1 = manualMeasurementLoadY1Samples.slice()
        var loadsY2 = manualMeasurementLoadY2Samples.slice()
        positions.push(position)
        loadsY1.push(loadY1)
        loadsY2.push(loadY2)
        while (positions.length > 1
               && Math.max.apply(null, positions) - Math.min.apply(null, positions)
                   > manualMeasurementMaximumPositionRange) {
            positions.shift()
            loadsY1.shift()
            loadsY2.shift()
        }
        manualMeasurementPositionSamples = positions
        manualMeasurementLoadY1Samples = loadsY1
        manualMeasurementLoadY2Samples = loadsY2
        manualMeasurementQualifiedSamples = positions.length
        manualMeasurementSampleSum = sampleArraySum(positions)
        manualMeasurementLoadY1Sum = sampleArraySum(loadsY1)
        manualMeasurementLoadY2Sum = sampleArraySum(loadsY2)
        manualMeasurementPositionMinimum = Math.min.apply(null, positions)
        manualMeasurementPositionMaximum = Math.max.apply(null, positions)
        var acceptedLoadTotals = []
        for (var acceptedIndex = 0; acceptedIndex < loadsY1.length; ++acceptedIndex)
            acceptedLoadTotals.push(loadsY1[acceptedIndex] + loadsY2[acceptedIndex])
        manualMeasurementLoadTotalMinimum = Math.min.apply(null, acceptedLoadTotals)
        manualMeasurementLoadTotalMaximum = Math.max.apply(null, acceptedLoadTotals)
        var means = manualMeasurementMeanHistory.slice()
        means.push(manualMeasurementSampleSum / manualMeasurementQualifiedSamples)
        while (means.length > manualMeasurementConvergenceWindow)
            means.shift()
        manualMeasurementMeanHistory = means
        manualMeasurementConvergenceSpread = means.length >= manualMeasurementConvergenceWindow
            ? Math.max.apply(null, means) - Math.min.apply(null, means) : NaN
        if (manualMeasurementConvergenceActive) {
            manualMeasurementStatus = "CONVERGING " + manualMeasurementQualifiedSamples
                + " / " + manualMeasurementRequiredSamples
                + (isFinite(manualMeasurementConvergenceSpread)
                   ? " · Δ " + manualMeasurementConvergenceSpread.toFixed(5) : "")
            if (manualMeasurementQualifiedSamples >= manualMeasurementMinimumSamples
                    && isFinite(manualMeasurementConvergenceSpread)
                    && manualMeasurementConvergenceSpread
                        <= manualMeasurementConvergenceTolerance + 1e-9)
                return completeManualMeasurement(nowMs, "CONVERGED")
        } else {
            manualMeasurementStatus = "AVERAGING " + manualMeasurementQualifiedSamples
                + " / " + manualMeasurementRequiredSamples
        }
        if (manualMeasurementQualifiedSamples < manualMeasurementRequiredSamples)
            return false
        return completeManualMeasurement(nowMs, "FIXED")
    }

    function sampleArraySum(samples) {
        var total = 0
        for (var index = 0; index < samples.length; ++index)
            total += Number(samples[index])
        return total
    }

    function completeManualMeasurement(nowMs, criterion) {
        var durationMs = nowMs - manualMeasurementWindowStartedMs
        const mean = manualMeasurementSampleSum / manualMeasurementQualifiedSamples
        manualMeasurementAcceptedCriterion = String(criterion || "FIXED")
        log("MANUAL", manualMeasurementMode + " accepted criterion=" + manualMeasurementAcceptedCriterion
            + " convergence=" + (manualMeasurementConvergenceActive ? "on" : "off")
            + " targetT=" + Number(manualMeasurementTargetTonnage).toFixed(2)
            + " samples=" + manualMeasurementQualifiedSamples
            + " durationMs=" + Math.round(durationMs)
            + " meanY=" + mean.toFixed(5)
            + " spread=" + (isFinite(manualMeasurementConvergenceSpread)
                            ? manualMeasurementConvergenceSpread.toFixed(5) : "n/a")
            + " rangeY=" + (manualMeasurementPositionMaximum - manualMeasurementPositionMinimum).toFixed(5))
        manualMeasurementAcceptedLoadY1Mean = manualMeasurementLoadY1Sum
            / manualMeasurementQualifiedSamples
        manualMeasurementAcceptedLoadY2Mean = manualMeasurementLoadY2Sum
            / manualMeasurementQualifiedSamples
        manualMeasurementAcceptedLoadMean = manualMeasurementAcceptedLoadY1Mean
            + manualMeasurementAcceptedLoadY2Mean
        manualMeasurementAcceptedLoadPeak = manualMeasurementLoadTotalMaximum
        manualMeasurementAcceptedSamples = manualMeasurementQualifiedSamples
        manualMeasurementAcceptedDurationMs = Math.round(durationMs)
        if (manualMeasurementMode === "CALIBRATION") {
            const dieTop = mean - manualKnownPieceThickness
            const previous = userSettingsModel.manualDieTopCalibration
            // Contact Y = punchH + dieH + t - opening (BendCalculator start
            // clearance without punch-to-material clearance), so the measured
            // contact on the known piece defines the opening for this tooling.
            const tooling = manualCalibrationToolingValid
            const opening = tooling
                ? manualCalibrationPunchHeight + manualCalibrationDieHeight - dieTop : NaN
            const next = {
                value: dieTop,
                unit: "INCH",
                valid: true,
                referenceThickness: manualKnownPieceThickness,
                contactPosition: mean,
                punchId: tooling ? manualCalibrationPunchId : "",
                punchName: tooling ? manualCalibrationPunchName : "",
                punchHeight: tooling ? manualCalibrationPunchHeight : null,
                dieId: tooling ? manualCalibrationDieId : "",
                dieName: tooling ? manualCalibrationDieName : "",
                dieHeight: tooling ? manualCalibrationDieHeight : null,
                ramToTableOpening: tooling ? opening : null,
                calibratedAt: new Date().toISOString()
            }
            const persisted = persistUserSetting("manualDieTopCalibration", next)
            if (storageBackendReady && !persisted) {
                userSettingsModel.manualDieTopCalibration = previous
                manualMeasurementStatus = "CALIBRATION SAVE FAILED"
                showAlarm("CALIBRATION SAVE FAILED",
                          "The measured die-top reference could not be saved. The previous calibration remains active.")
                return false
            }
            userSettingsModel = Object.assign({}, userSettingsModel)
            manualMeasurementResult = dieTop
            manualMeasurementStatus = "CALIBRATION COMPLETE"
            prepareManualCalibrationOpening(opening)
        } else {
            const stack = mean - manualDieTopCalibration
            manualMeasurementStackResult = stack
            manualMeasurementResult = manualMeasurementOnReferencePiece
                ? stack - manualCalibrationReferenceThickness : stack
            manualMeasurementStatus = manualMeasurementResult > 0
                ? "MEASUREMENT COMPLETE" : "NO PIECE DETECTED"
        }
        Qt.callLater(finishManualMeasurementProcess)
        return true
    }

    // ---- Entity storage backend (Phase 4) -------------------------------------
    // Bridges core/storage/EntityStorage.js to the C++ FileIo singleton when present
    // (packaged app), with an XHR read fallback for tooling/qml.exe. Writes go through
    // FileIo only — pure-QML XHR cannot create new files, so without FileIo we refuse
    // production writes (safety-first) and the UI keeps changes in memory.
    // True only when the C++ FileIo context property is available (packaged app), which
    // is the only path that can safely create/overwrite storage JSON with a backup.
    // Tests may inject an in-memory backend; production uses the C++ FileIo context
    // property. Both paths exercise the same backup-guarded EntityStorage contract.
    property var storageIoOverride: null
    property bool storageBackendReady: storageIoOverride !== null
        || (typeof fileIo !== "undefined" && fileIo !== null)
    function entityStorageBackend() {
        if (storageIoOverride !== null)
            return storageIoOverride
        var hasFileIo = (typeof fileIo !== "undefined" && fileIo !== null)
        return {
            read: function (url) {
                if (hasFileIo) {
                    var t = fileIo.read(url)
                    return (t === undefined || t === null || t === "") ? null : t
                }
                try {
                    var xhr = new XMLHttpRequest()
                    xhr.open("GET", url, false)
                    xhr.send(null)
                    var ok = (xhr.status === 200 || xhr.status === 0)
                    var body = ok ? xhr.responseText : null
                    return (body === undefined || body === null || body === "") ? null : body
                } catch (e) { return null }
            },
            write: function (url, text) {
                if (hasFileIo) return fileIo.write(url, text)
                log("STORAGE", "No FileIo backend — refused production write to " + url)
                return false
            },
            exists: function (url) {
                if (hasFileIo) return fileIo.exists(url)
                return this.read(url) !== null
            }
        }
    }

    // persistEntities(kind, items): backup-guarded write of an entity collection.
    // kind -> file name under data/current/ (dies/punches/materials/programs/...).
    function persistEntities(kind, items) {
        if (!storageBackendReady) {
            log("STORAGE", "Save " + kind + " refused: persistent storage unavailable")
            return false
        }
        var fileUrl = writableCurrentDataPath(kind + ".json")
        var io = entityStorageBackend()
        var result = EntityStorage.save(fileUrl, items, { io: io, backup: true })
        if (result.ok) {
            log("STORAGE", "Saved " + kind + " (" + (items ? items.length : 0) + " items)"
                + (result.backupUrl ? " — backup kept" : ""))
        } else {
            log("STORAGE", "Save " + kind + " FAILED" + (result.reason ? " (" + result.reason + ")" : ""))
        }
        return result.ok
    }

    // loadEntities(kind): read a collection (default-resource fallback handled by caller).
    function loadEntities(kind) {
        var fileUrl = writableCurrentDataPath(kind + ".json")
        return EntityStorage.load(fileUrl, null, entityStorageBackend())
    }

    function persistEntityTransaction(collections) {
        if (!storageBackendReady)
            return false
        let operations = []
        for (let index = 0; collections && index < collections.length; index++) {
            operations.push({
                fileUrl: writableCurrentDataPath(collections[index].kind + ".json"),
                items: collections[index].items
            })
        }
        let result = EntityStorage.saveTransaction(operations, { io: entityStorageBackend() })
        if (!result.ok)
            log("STORAGE", "Transaction FAILED " + String(result.reason || "unknown")
                + (result.failedUrl ? " at " + result.failedUrl : ""))
        return result.ok === true
    }

    function uniqueEntityId(prefix, collections) {
        let existing = ({})
        for (let listIndex = 0; collections && listIndex < collections.length; listIndex++) {
            let list = collections[listIndex] || []
            for (let itemIndex = 0; itemIndex < list.length; itemIndex++)
                existing[String(list[itemIndex] && list[itemIndex].id || "")] = true
        }
        let entropy = Math.floor(Math.random() * 0x100000000).toString(36)
        let base = String(prefix || "entity") + "-" + String(Date.now()) + "-" + entropy
        let candidate = base
        let suffix = 1
        while (existing[candidate])
            candidate = base + "-" + String(suffix++)
        return candidate
    }

    function nextUnusedName(baseName, records) {
        let requested = String(baseName || "Untitled").trim()
        if (requested.length === 0)
            requested = "Untitled"
        let used = ({})
        for (let index = 0; records && index < records.length; index++)
            used[String(records[index] && records[index].name || "").trim().toLowerCase()] = true
        let candidate = requested
        let suffix = 1
        while (used[candidate.toLowerCase()])
            candidate = requested + " " + String(suffix++)
        return candidate
    }

    // persistPrograms(action, name): backup-guarded write of the current `programs` array.
    // Returns true only when a real FileIo backend is present AND the write succeeded, so
    // callers can fall through to the existing sandbox popup otherwise. Surfaces an alarm
    // (no silent data loss) when a write is attempted but the backup-guard refuses it.
    function persistPrograms(action, name) {
        lastProgramPersistenceSucceeded = false
        if (!storageBackendReady)
            return false
        var ok = persistEntities("programs", programs)
        if (ok) {
            lastProgramPersistenceSucceeded = true
            if (action !== "generate") {
                showPopup(action.toUpperCase() + " PROGRAM",
                          (name || activeProgram) + " saved to storage (backup-guarded).",
                          1, "blur", "CLOSE")
            }
            return true
        }
        showAlarm(action.toUpperCase() + " PROGRAM", "Could not write programs.json safely. No changes were made to production storage.")
        return true
    }

    function persistRunPreviewDebugSetting(key, value) {
        if (!localSettingsModel)
            localSettingsModel = SettingsModel.defaultLocalSettings()
        localSettingsModel[key] = value
        var url = writableCurrentDataPath("local-settings.json")
        if (!storageBackendReady) {
            recordSandboxWrite("settings", key, value)
            log("SETTINGS", "Sandbox local setting " + key + " = " + String(value))
            return
        }
        var result = SettingsModel.save(url, localSettingsModel, settingsIo(), {})
        log("SETTINGS", "Persisted " + key + " = " + String(value) + (result.ok ? " (ok)" : " FAILED " + (result.reason || "")))
    }

    function persistLegacyRunUiSetting() {
        persistentSettings.setValue("legacyRunUiEnabled", legacyRunUiEnabled)
        persistentSettings.sync()
        log("SETTINGS", "Persisted Legacy Run UI in Qt settings " + (legacyRunUiEnabled ? "enabled" : "disabled"))
        persistLocalSetting("legacyRunUiEnabled", legacyRunUiEnabled)
    }

    function setActiveProgram(name, bends, source, cadPreviewJson) {
        var nextPrograms = programs.slice(0)
        var requestedName = String(name || "Untitled Program").trim()
        if (requestedName.length === 0)
            requestedName = "Untitled Program"
        var existingIndex = -1
        if (source === "cad") {
            for (var programIndex = 0; programIndex < nextPrograms.length; programIndex++) {
                if (String(nextPrograms[programIndex] && nextPrograms[programIndex].name || "").trim().toLowerCase()
                        === requestedName.toLowerCase()) {
                    existingIndex = programIndex
                    break
                }
            }
        }
        var uniqueName = existingIndex >= 0
            ? requestedName : nextUnusedName(requestedName, nextPrograms)
        var stamp = programTimestamp()
        var program = { id: uniqueEntityId("program", [nextPrograms]), name: uniqueName,
            source: source || "qml", bends: cloneBends(bends || []), cadPreviewJson: cadPreviewJson || "",
            folder: "", createdAt: stamp, updatedAt: stamp }
        if (existingIndex >= 0) {
            var existingProgram = nextPrograms[existingIndex] || {}
            program.id = existingProgram.id || program.id
            program.folder = String(existingProgram.folder || "")
            program.createdAt = String(existingProgram.createdAt || stamp)
            nextPrograms[existingIndex] = program
        } else {
            nextPrograms.push(program)
            existingIndex = nextPrograms.length - 1
        }
        programs = nextPrograms
        selectedProgramIndex = existingIndex
        selectedRunBend = program.bends.length > 0 ? 0 : -1
        syncActiveProgramState()
    }

    function requestProgramSelection(index) {
        if (programs.length === 0 || index === selectedProgramIndex)
            return
        var target = programs[Math.max(0, Math.min(index, programs.length - 1))] || {}
        runProgramSwitchName = String(target.name || "")
        runProgramSwitchStartedMs = Date.now()
        runProgramSwitching = true
        runProgramSwitchPendingIndex = index
        runProgramSwitchWatchdog.restart()
        runProgramSwitchTimer.restart()
    }

    function finishRunProgramSwitch(reason) {
        if (!runProgramSwitching)
            return
        runProgramSwitching = false
        runProgramSwitchWatchdog.stop()
        log("RUN", "Program switch " + reason + " in " + String(Date.now() - runProgramSwitchStartedMs) + " ms: " + activeProgram)
    }

    function selectProgram(index) {
        if (programs.length === 0)
            return
        var nextIndex = Math.max(0, Math.min(index, programs.length - 1))
        var changed = selectedProgramIndex !== nextIndex
        selectedProgramIndex = nextIndex
        if (changed) {
            selectedRunBend = programs[selectedProgramIndex].bends && programs[selectedProgramIndex].bends.length > 0 ? 0 : -1
            resetRunPresentationState()
        }
        syncActiveProgramState()
        var selectedProgram = programs[selectedProgramIndex] || {}
        persistLocalSetting("lastSelectedProgramId", valueOr(selectedProgram, "id", ""))
        persistLocalSetting("lastSelectedProgramName", valueOr(selectedProgram, "name", activeProgram))
        enforceBendModeForProgram()
        log("RUN", "Program selected: " + activeProgram)
    }

    // ------------------------------------------------------------------
    // PROGRAMS tab library operations. Every function returns
    // { ok, reason } (plus extras) and never touches machine state. They are
    // refused while a program runs or a program switch is still loading.
    // ------------------------------------------------------------------
    function programTimestamp() {
        return new Date().toISOString()
    }

    // Programs saved before created/updated existed (or with one of them
    // missing/unparseable) showed an empty date. Use the sibling stamp, then
    // the first-load time, so every row has a date that persists on save.
    function programStampOrFallback(source, key, siblingKey) {
        var valid = function(v) {
            var text = String(v === undefined || v === null ? "" : v)
            return text.length > 0 && isFinite(Date.parse(text)) ? text : ""
        }
        return valid(source ? source[key] : "")
            || valid(source ? source[siblingKey] : "")
            || programTimestamp()
    }

    function normalizedProgramFolders(list) {
        var out = []
        var seen = ({})
        for (var i = 0; list && i < list.length; i++) {
            var name = String(list[i] === null || list[i] === undefined ? "" : list[i]).trim()
            var key = name.toLowerCase()
            if (name.length === 0 || seen[key])
                continue
            seen[key] = true
            out.push(name)
        }
        return out
    }

    // Stored folders plus any folder referenced by a program, A-Z.
    function programFolderNames() {
        var merged = programFolders.slice(0)
        for (var i = 0; i < programs.length; i++)
            merged.push(programs[i] ? programs[i].folder : "")
        merged = normalizedProgramFolders(merged)
        merged.sort(function(a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : (a.toLowerCase() > b.toLowerCase() ? 1 : 0) })
        return merged
    }

    function programLibraryBusyReason() {
        if (runActive)
            return "Stop the running program first."
        if (runProgramSwitching)
            return "A program is still loading."
        return ""
    }

    function programLibraryResult(ok, reason, extras) {
        var result = Object.assign({ ok: ok === true, reason: String(reason || "") }, extras || {})
        if (!result.ok)
            log("PROGRAMS", "Refused: " + result.reason)
        return result
    }

    // RUN angle correction: the operator measures the bent part and enters
    // the real angle. The signed error (reversed = negative = UNDERBENT) is
    // applied to the material OVERRIDE (when active) or to EVERY bend of the
    // program, so the following sequences are corrected. Never one bend only.
    function signedMaterialCompensation(materialRef) {
        var comp = finiteNumber(valueOr(materialRef, "materialAngleCompensationDeg", 0), 0)
        return valueOr(materialRef, "materialAngleCompensationReversed", false) === true ? -comp : comp
    }

    function angleCorrectionInfo() {
        var bend = selectedRunBend >= 0 && selectedRunBend < storedProgramBends.length
            ? storedProgramBends[selectedRunBend] : null
        if (!bend)
            return null
        var library = programToolingLibrary || ({})
        var materialRef = findById(library.materials, valueOr(bend, "materialId", ""))
        var comp = finiteNumber(valueOr(bend, "angleCompensation", 0), 0)
        var programSigned = valueOr(bend, "angleCompensationReversed", false) === true ? -comp : comp
        var override = valueOr(materialRef, "materialAngleOverrideEnabled", false) === true
        var materialSigned = signedMaterialCompensation(materialRef)
        return {
            desired: finiteNumber(valueOr(bend, "desiredBendAngle", valueOr(bend, "angle", 90)), 90),
            signedCompensation: override ? materialSigned : programSigned,
            programSignedCompensation: programSigned,
            materialSignedCompensation: materialSigned,
            materialOverride: override,
            materialName: materialRef && materialRef.name ? materialRef.name : "",
            bendCount: storedProgramBends.length
        }
    }

    // target: "material" (override) or "program" (all bends).
    function applyMeasuredAngleCorrection(measuredAngle, target) {
        var measured = Number(measuredAngle)
        if (runSimulatedRun || physicalRunCommandPending || !isFinite(measured)
                || measured <= 0 || measured >= 180)
            return false
        var info = angleCorrectionInfo()
        if (!info)
            return false
        var correction = -(measured - info.desired)
        if (target === "material")
            return applyMaterialAngleCorrection(info, measured, correction)
        return applyProgramAngleCorrection(info, measured, correction)
    }

    function applyMaterialAngleCorrection(info, measured, correction) {
        var library = programToolingLibrary || ({})
        var bend = storedProgramBends[selectedRunBend]
        var materialId = String(valueOr(bend, "materialId", ""))
        var materials = JSON.parse(JSON.stringify(library.materials || []))
        var mIndex = -1
        for (var i = 0; i < materials.length; i++)
            if (String(materials[i].id) === materialId) { mIndex = i; break }
        if (mIndex < 0 || materials[mIndex].materialAngleOverrideEnabled !== true) {
            showAlarm("ANGLE CORRECTION", "Material override is not active for this bend.")
            return false
        }
        var oldSigned = info.materialSignedCompensation
        var nextSigned = Math.round((oldSigned + correction) * 100) / 100
        var nextMaterial = Object.assign({}, materials[mIndex], {
            materialAngleCompensationDeg: Math.abs(nextSigned),
            materialAngleCompensationReversed: nextSigned < 0
        })
        // FINAL must stay below CLAMP on every bend of this program using it.
        for (var b = 0; b < storedProgramBends.length; b++) {
            var sb = storedProgramBends[b]
            if (String(valueOr(sb, "materialId", "")) !== materialId)
                continue
            var calc = calcBendParity(Object.assign({}, sb, { overrideFinalBendPositionEnabled: false }),
                findById(library.punches, valueOr(sb, "punchId", "")),
                findById(library.dies, valueOr(sb, "dieId", "")), nextMaterial)
            var clamp = Number(sb.clampPosition)
            if (calc && isFinite(clamp) && !(calc.calculatedFinalBendPosition < clamp)) {
                showAlarm("ANGLE CORRECTION", "Correction would put FINAL above CLAMP on B" + (b + 1) + ". Not applied.")
                return false
            }
        }
        materials[mIndex] = nextMaterial
        if (!persistEntities("materials", materials)) {
            showAlarm("ANGLE CORRECTION", "Could not save the material. No changes were made.")
            return false
        }
        refreshToolingLibrary(library.punches, library.dies, materials)
        log("RUN", "Angle correction (MATERIAL OVERRIDE " + info.materialName + "): measured "
            + measured.toFixed(1) + " deg vs " + info.desired.toFixed(1) + " deg; override "
            + oldSigned.toFixed(2) + " -> " + nextSigned.toFixed(2) + " deg")
        return true
    }

    function applyProgramAngleCorrection(info, measured, correction) {
        var library = programToolingLibrary || ({})
        var nextPrograms = programs.slice()
        var program = Object.assign({}, nextPrograms[selectedProgramIndex])
        var bends = cloneBends(program.bends || [])
        var skipped = []
        for (var b = 0; b < bends.length; b++) {
            var bend = bends[b]
            var punchRef = findById(library.punches, valueOr(bend, "punchId", ""))
            var dieRef = findById(library.dies, valueOr(bend, "dieId", ""))
            var materialRef = findById(library.materials, valueOr(bend, "materialId", ""))
            var comp = finiteNumber(valueOr(bend, "angleCompensation", 0), 0)
            var oldSigned = valueOr(bend, "angleCompensationReversed", false) === true ? -comp : comp
            var nextSigned = Math.round((oldSigned + correction) * 100) / 100
            var calcBase = Object.assign({}, bend, { overrideFinalBendPositionEnabled: false })
            var before = calcBendParity(calcBase, punchRef, dieRef, materialRef)
            var after = calcBendParity(Object.assign({}, calcBase, {
                angleCompensation: Math.abs(nextSigned),
                angleCompensationReversed: nextSigned < 0
            }), punchRef, dieRef, materialRef)
            var finalPosition = Number(bend.finalPosition)
            var clamp = Number(bend.clampPosition)
            var delta = before && after
                ? after.calculatedFinalBendPosition - before.calculatedFinalBendPosition : NaN
            if (!isFinite(delta) || !isFinite(finalPosition)) {
                skipped.push("B" + (b + 1))
                continue
            }
            var nextFinal = finalPosition + delta
            if (isFinite(clamp) && !(nextFinal < clamp)) {
                showAlarm("ANGLE CORRECTION", "Correction would put FINAL above CLAMP on B" + (b + 1) + ". Not applied.")
                return false
            }
            var updated = Object.assign({}, bend, {
                angleCompensation: Math.abs(nextSigned),
                angleCompensationReversed: nextSigned < 0,
                compensation: formatNumber(Math.abs(nextSigned), 1, "0.0"),
                state: nextSigned < 0 ? "UNDERBENT" : "OVERBENT",
                finalPosition: formatNumber(nextFinal, 4, "0.0000")
            })
            if (bend.overrideFinalBendPositionEnabled === true
                    && isFinite(Number(bend.overriddenFinalBendPosition)))
                updated.overriddenFinalBendPosition = Number(bend.overriddenFinalBendPosition) + delta
            bends[b] = updated
        }
        if (skipped.length === bends.length) {
            showAlarm("ANGLE CORRECTION", "No bend could be recalculated (punch, die or material not resolved).")
            return false
        }
        program.bends = bends
        nextPrograms[selectedProgramIndex] = program
        if (!commitProgramLibrary(nextPrograms)) {
            showAlarm("ANGLE CORRECTION", "Could not save the program. No changes were made.")
            return false
        }
        syncActiveProgramState()
        if (skipped.length > 0)
            showAlarm("ANGLE CORRECTION", "Not recalculated (tooling not resolved): " + skipped.join(", "))
        log("RUN", "Angle correction (ALL BENDS): measured " + measured.toFixed(1) + " deg vs "
            + info.desired.toFixed(1) + " deg; compensation shift " + correction.toFixed(2)
            + " deg on " + (bends.length - skipped.length) + " bends")
        return true
    }

    function commitProgramLibrary(nextPrograms) {
        if (storageBackendReady && !persistEntities("programs", nextPrograms))
            return false
        programs = nextPrograms
        return true
    }

    function storeProgramFolders(nextFolders) {
        programFolders = normalizedProgramFolders(nextFolders)
        persistLocalSetting("programFolders", programFolders)
    }

    function programFolderExists(name) {
        var key = String(name || "").trim().toLowerCase()
        var names = programFolderNames()
        for (var i = 0; i < names.length; i++) {
            if (names[i].toLowerCase() === key)
                return true
        }
        return false
    }

    function createProgramFolder(name) {
        var folder = String(name || "").trim()
        if (folder.length === 0)
            return programLibraryResult(false, "Folder name is empty.")
        if (folder.length > 32)
            return programLibraryResult(false, "Folder name is longer than 32 characters.")
        if (programFolderExists(folder))
            return programLibraryResult(false, "Folder already exists.")
        storeProgramFolders(programFolders.concat([folder]))
        log("PROGRAMS", "Folder created: " + folder)
        return programLibraryResult(true, "", { name: folder })
    }

    function renameProgramFolder(oldName, newName) {
        var busy = programLibraryBusyReason()
        if (busy.length > 0)
            return programLibraryResult(false, busy)
        var from = String(oldName || "").trim()
        var to = String(newName || "").trim()
        if (from.length === 0 || !programFolderExists(from))
            return programLibraryResult(false, "Folder not found.")
        if (to.length === 0)
            return programLibraryResult(false, "Folder name is empty.")
        if (to.length > 32)
            return programLibraryResult(false, "Folder name is longer than 32 characters.")
        if (to.toLowerCase() !== from.toLowerCase() && programFolderExists(to))
            return programLibraryResult(false, "Folder already exists.")
        var nextPrograms = programs.slice(0)
        var moved = 0
        for (var i = 0; i < nextPrograms.length; i++) {
            if (String(nextPrograms[i] && nextPrograms[i].folder || "").trim().toLowerCase() === from.toLowerCase()) {
                nextPrograms[i] = Object.assign({}, nextPrograms[i], { folder: to })
                moved++
            }
        }
        if (moved > 0 && !commitProgramLibrary(nextPrograms))
            return programLibraryResult(false, "Could not write programs.json.")
        var nextFolders = []
        for (var f = 0; f < programFolders.length; f++) {
            if (programFolders[f].toLowerCase() !== from.toLowerCase())
                nextFolders.push(programFolders[f])
        }
        nextFolders.push(to)
        storeProgramFolders(nextFolders)
        log("PROGRAMS", "Folder renamed: " + from + " -> " + to + " (" + moved + " programs)")
        return programLibraryResult(true, "", { name: to, moved: moved })
    }

    // Programs are never deleted with their folder; they become unfiled.
    function deleteProgramFolder(name) {
        var busy = programLibraryBusyReason()
        if (busy.length > 0)
            return programLibraryResult(false, busy)
        var folder = String(name || "").trim()
        if (folder.length === 0 || !programFolderExists(folder))
            return programLibraryResult(false, "Folder not found.")
        var nextPrograms = programs.slice(0)
        var moved = 0
        for (var i = 0; i < nextPrograms.length; i++) {
            if (String(nextPrograms[i] && nextPrograms[i].folder || "").trim().toLowerCase() === folder.toLowerCase()) {
                nextPrograms[i] = Object.assign({}, nextPrograms[i], { folder: "" })
                moved++
            }
        }
        if (moved > 0 && !commitProgramLibrary(nextPrograms))
            return programLibraryResult(false, "Could not write programs.json.")
        var nextFolders = []
        for (var f = 0; f < programFolders.length; f++) {
            if (programFolders[f].toLowerCase() !== folder.toLowerCase())
                nextFolders.push(programFolders[f])
        }
        storeProgramFolders(nextFolders)
        log("PROGRAMS", "Folder deleted: " + folder + " (" + moved + " programs unfiled)")
        return programLibraryResult(true, "", { moved: moved })
    }

    // Organizational only: does not change the program's updatedAt.
    function moveProgramToFolder(index, folderName) {
        var busy = programLibraryBusyReason()
        if (busy.length > 0)
            return programLibraryResult(false, busy)
        if (index < 0 || index >= programs.length)
            return programLibraryResult(false, "Program not found.")
        var folder = String(folderName || "").trim()
        if (folder.length > 0 && !programFolderExists(folder))
            return programLibraryResult(false, "Folder not found.")
        var nextPrograms = programs.slice(0)
        nextPrograms[index] = Object.assign({}, nextPrograms[index], { folder: folder })
        if (!commitProgramLibrary(nextPrograms))
            return programLibraryResult(false, "Could not write programs.json.")
        log("PROGRAMS", "Moved " + String(nextPrograms[index].name || "") + " -> " + (folder.length > 0 ? folder : "(unfiled)"))
        return programLibraryResult(true, "", { folder: folder })
    }

    function renameProgramAt(index, name) {
        var busy = programLibraryBusyReason()
        if (busy.length > 0)
            return programLibraryResult(false, busy)
        if (index < 0 || index >= programs.length)
            return programLibraryResult(false, "Program not found.")
        var nextName = String(name || "").trim()
        if (nextName.length === 0)
            return programLibraryResult(false, "Program name is empty.")
        for (var i = 0; i < programs.length; i++) {
            if (i !== index && String(programs[i] && programs[i].name || "").trim().toLowerCase() === nextName.toLowerCase())
                return programLibraryResult(false, "A program with that name already exists.")
        }
        var nextPrograms = programs.slice(0)
        nextPrograms[index] = Object.assign({}, nextPrograms[index], { name: nextName, updatedAt: programTimestamp() })
        if (!commitProgramLibrary(nextPrograms))
            return programLibraryResult(false, "Could not write programs.json.")
        if (index === selectedProgramIndex) {
            activeProgram = nextName
            if (runProgramEditing)
                runProgramNameDraft = nextName
            persistLocalSetting("lastSelectedProgramName", nextName)
        }
        log("PROGRAMS", "Renamed program -> " + nextName)
        return programLibraryResult(true, "", { name: nextName })
    }

    function duplicateProgramAt(index) {
        var busy = programLibraryBusyReason()
        if (busy.length > 0)
            return programLibraryResult(false, busy)
        if (index < 0 || index >= programs.length)
            return programLibraryResult(false, "Program not found.")
        var source = programs[index] || {}
        var nextPrograms = programs.slice(0)
        var stamp = programTimestamp()
        var copyName = nextUnusedName(String(source.name || "Untitled Program") + " COPY", nextPrograms)
        nextPrograms.push(Object.assign({}, source, {
            id: uniqueEntityId("program", [nextPrograms]), name: copyName,
            bends: cloneBends(source.bends || []), createdAt: stamp, updatedAt: stamp }))
        if (!commitProgramLibrary(nextPrograms))
            return programLibraryResult(false, "Could not write programs.json.")
        log("PROGRAMS", "Duplicated " + String(source.name || "") + " -> " + copyName)
        return programLibraryResult(true, "", { name: copyName, index: nextPrograms.length - 1 })
    }

    function deleteProgramAt(index) {
        var busy = programLibraryBusyReason()
        if (busy.length > 0)
            return programLibraryResult(false, busy)
        if (index < 0 || index >= programs.length)
            return programLibraryResult(false, "Program not found.")
        var deletedName = String(programs[index] && programs[index].name || "")
        var wasSelected = index === selectedProgramIndex
        var nextPrograms = programs.slice(0)
        nextPrograms.splice(index, 1)
        if (!commitProgramLibrary(nextPrograms))
            return programLibraryResult(false, "Could not write programs.json.")
        if (wasSelected) {
            runProgramEditing = false
            selectedProgramIndex = nextPrograms.length > 0 ? Math.max(0, index - 1) : -1
            selectedRunBend = nextPrograms.length > 0 && nextPrograms[selectedProgramIndex].bends
                && nextPrograms[selectedProgramIndex].bends.length > 0 ? 0 : -1
            resetRunPresentationState()
            syncActiveProgramState()
            if (nextPrograms.length > 0) {
                persistLocalSetting("lastSelectedProgramId", valueOr(nextPrograms[selectedProgramIndex], "id", ""))
                persistLocalSetting("lastSelectedProgramName", activeProgram)
                enforceBendModeForProgram()
            }
        } else if (index < selectedProgramIndex) {
            // Same program stays active; only its position moved.
            selectedProgramIndex = selectedProgramIndex - 1
        }
        log("PROGRAMS", "Deleted program " + deletedName)
        return programLibraryResult(true, "", { name: deletedName })
    }

    // Loads the program through the same deferred switch RUN's dropdown uses.
    function openProgramInRun(index) {
        var busy = programLibraryBusyReason()
        if (busy.length > 0)
            return programLibraryResult(false, busy)
        if (index < 0 || index >= programs.length)
            return programLibraryResult(false, "Program not found.")
        if (index !== selectedProgramIndex) {
            runProgramEditing = false
            requestProgramSelection(index)
        }
        return programLibraryResult(true, "", { name: String(programs[index].name || "") })
    }

    // Tools edits (e.g. material angle OVERRIDE) must reach already-mapped
    // programs: swap the library and recompute each bend's derived values.
    function refreshToolingLibrary(punches, dies, materials) {
        programToolingLibrary = { punches: punches || [], dies: dies || [], materials: materials || [] }
        var remapped = []
        for (var p = 0; p < programs.length; p++) {
            var program = programs[p] || {}
            var bends = []
            for (var b = 0; program.bends && b < program.bends.length; b++)
                bends.push(bendFromStorage(program.bends[b], punches, dies, materials))
            remapped.push(Object.assign({}, program, { bends: bends }))
        }
        programs = remapped
        syncActiveProgramState()
        log("TOOLS", "Tooling library refreshed; programs recalculated")
    }

    function setProgramsFromStorage(storedPrograms, storedBends, punches, dies, materials, settings) {
        if (!storedPrograms)
            return
        if (storedPrograms.length === 0) {
            // Real (empty) storage: start blank, no built-in sample program.
            if (storageBackendReady) {
                programs = []
                activeProgram = ""
                activeProgramCadPreviewJson = ""
                selectedProgramIndex = 0
                selectedRunBend = -1
            }
            return
        }
        if (punches || dies || materials)
            programToolingLibrary = { punches: punches || [], dies: dies || [], materials: materials || [] }
        var bendById = ({})
        for (var b = 0; storedBends && b < storedBends.length; b++)
            bendById[String(valueOr(storedBends[b], "id", ""))] = storedBends[b]
        var mappedPrograms = []
        for (var p = 0; p < storedPrograms.length; p++) {
            var sourceProgram = storedPrograms[p] || {}
            var mappedBends = []
            if (sourceProgram.bends && sourceProgram.bends.length) {
                var cadMaterial = cadPreviewMaterial(valueOr(sourceProgram, "cadPreviewJson", ""))
                for (var inlineIndex = 0; inlineIndex < sourceProgram.bends.length; inlineIndex++)
                    mappedBends.push(bendFromStorage(canonicalCadProgramBend(
                        sourceProgram.bends[inlineIndex], cadMaterial), punches, dies, materials))
            } else {
                for (var idIndex = 0; sourceProgram.bendIds && idIndex < sourceProgram.bendIds.length; idIndex++) {
                    var storageBend = bendById[String(sourceProgram.bendIds[idIndex])]
                    if (storageBend)
                        mappedBends.push(bendFromStorage(storageBend, punches, dies, materials))
                }
            }
            mappedPrograms.push({
                id: valueOr(sourceProgram, "id", ""),
                name: valueOr(sourceProgram, "name", "Untitled Program"),
                source: valueOr(sourceProgram, "source", "storage"),
                bends: mappedBends,
                cadPreviewJson: valueOr(sourceProgram, "cadPreviewJson", ""),
                folder: String(valueOr(sourceProgram, "folder", "")),
                createdAt: programStampOrFallback(sourceProgram, "createdAt", "updatedAt"),
                updatedAt: programStampOrFallback(sourceProgram, "updatedAt", "createdAt")
            })
        }
        programs = mappedPrograms
        selectedProgramIndex = 0
        var preferredId = settings ? valueOr(settings, "lastSelectedProgramId", "") : ""
        var preferredName = settings ? valueOr(settings, "lastSelectedProgramName", "") : ""
        var firstCadProgramIndex = -1
        var latestCadProgramIndex = -1
        var preferredProgramIndex = -1
        for (var i = 0; i < programs.length; i++) {
            if (String(programs[i].cadPreviewJson || "").length > 0) {
                latestCadProgramIndex = i
            }
            if (firstCadProgramIndex < 0 && String(programs[i].cadPreviewJson || "").length > 0)
                firstCadProgramIndex = i
            if (preferredProgramIndex < 0 && ((preferredId.length > 0 && programs[i].id === preferredId) || (preferredName.length > 0 && programs[i].name === preferredName)))
                preferredProgramIndex = i
        }
        if (preferredProgramIndex >= 0)
            selectedProgramIndex = preferredProgramIndex
        else if (latestCadProgramIndex >= 0)
            selectedProgramIndex = latestCadProgramIndex
        if (preferredProgramIndex < 0 && String(programs[selectedProgramIndex].cadPreviewJson || "").length === 0 && firstCadProgramIndex >= 0)
            selectedProgramIndex = firstCadProgramIndex
        selectedRunBend = programs[selectedProgramIndex].bends.length > 0 ? 0 : -1
        syncActiveProgramState()
        if (settings && settings.lastBendMode) {
            bendMode = settings.lastBendMode
            enforceBendModeForProgram()
        }
    }

    function appendBendToProgram(bend) {
        if (programs.length === 0)
            programs = [{ name: "QML Scratch Program", source: "qml", bends: [] }]
        selectedProgramIndex = Math.max(0, Math.min(selectedProgramIndex, programs.length - 1))
        var nextPrograms = programs.slice(0)
        var program = nextPrograms[selectedProgramIndex]
        var bends = cloneBends(program.bends || [])
        var nextBend = {}
        for (var key in bend)
            nextBend[key] = bend[key]
        nextBend.seq = bends.length + 1
        bends.push(nextBend)
        nextPrograms[selectedProgramIndex] = Object.assign({}, program, { name: program.name || activeProgram, source: program.source || "qml", bends: bends, cadPreviewJson: program.cadPreviewJson || activeProgramCadPreviewJson, updatedAt: programTimestamp() })
        programs = nextPrograms
        selectedRunBend = bends.length - 1
        syncActiveProgramState()
        return nextBend
    }

    function normalizeName(item, fallback) {
        return item && item.name !== undefined && item.name !== null && String(item.name).length > 0 ? String(item.name) : fallback
    }

    // Run the 1:1 Java BendCalculator port when tooling+material are resolved.
    // Returns the computeBend(...) result, or null when inputs are insufficient.
    function calcBendParity(bend, punchRef, dieRef, materialRef) {
        if (!punchRef || !dieRef || !materialRef)
            return null
        var thickness = Number(valueOr(bend, "materialThickness", valueOr(bend, "thickness", 0)))
        var vdie = Number(valueOr(dieRef, "vdieOpeningInch", 0))
        if (!(thickness > 0) || !(vdie > 0))
            return null
        // Material-level angle compensation (Tools > Materials). When its
        // OVERRIDE PROGRAMS toggle is on it replaces the per-bend value, so
        // imported CAD programs cannot add their own springback on top.
        var materialOverride = valueOr(materialRef, "materialAngleOverrideEnabled", false) === true
        var effectiveCompensation = materialOverride
            ? Number(valueOr(materialRef, "materialAngleCompensationDeg", 0))
            : Number(valueOr(bend, "angleCompensation", valueOr(bend, "compensation", 0)))
        var effectiveReversed = materialOverride
            ? valueOr(materialRef, "materialAngleCompensationReversed", false) === true
            : valueOr(bend, "angleCompensationReversed", false)
        return BendCalculator.computeBend({
            bend: {
                materialThickness: thickness,
                bendWidth: Number(valueOr(bend, "bendWidth", valueOr(bend, "width", 0))),
                desiredBendAngle: Number(valueOr(bend, "desiredBendAngle", valueOr(bend, "angle", 90))),
                angleCompensation: effectiveCompensation,
                angleCompensationReversed: effectiveReversed,
                punchToMaterialClearance: Number(valueOr(bend, "punchToMaterialClearance", 0.0306)),
                additionalRetractAfterBend: Number(valueOr(bend, "additionalRetractAfterBend", 0)),
                overrideFinalBendPositionEnabled: valueOr(bend, "overrideFinalBendPositionEnabled", false),
                overriddenFinalBendPosition: Number(valueOr(bend, "overriddenFinalBendPosition", NaN))
            },
            punch: { heightInch: Number(valueOr(punchRef, "heightInch", NaN)) },
            die: { heightInch: Number(valueOr(dieRef, "heightInch", NaN)), vdieOpeningInch: vdie },
            material: {
                materialTensileStrengthPsi: Number(valueOr(materialRef, "materialTensileStrengthPsi", NaN)),
                insideRadiusRuleOfThumb: Number(valueOr(materialRef, "insideRadiusRuleOfThumb", NaN)),
                materialSpringback: Number(valueOr(materialRef, "materialSpringback", NaN))
            },
            settings: { materialClampRatePercentage: materialClampRatePercentage },
            machine: { ramToTableOpening: desktopRamToTableOpening }
        })
    }

    function cadPreviewMaterial(cadPreviewJson) {
        if (!cadPreviewJson)
            return null
        try {
            return JSON.parse(cadPreviewJson).material || null
        } catch (error) {
            return null
        }
    }

    // CAD generation used to store only display keys (angle, thickness, x, r,
    // tonnage). On reload bendFromStorage then defaulted the editable fields:
    // springback dropped to 0, clearance 0.05 instead of 0.0306 and width 0,
    // which moved START/FINAL and zeroed the tonnage; CREATE BEND could not
    // save those bends at all. Rebuild the inputs the generator actually used.
    function canonicalCadProgramBend(bend, cadMaterial) {
        if (!bend || String(bend.state || "") !== "CAD" || bend.desiredBendAngle !== undefined)
            return bend
        var thickness = finiteNumber(bend.thickness, 0)
        var tensile = finiteNumber(valueOr(cadMaterial, "tensile_psi", NaN), NaN)
        var vdie = finiteNumber(bend.vdieValue, 0)
        var tonnage = finiteNumber(bend.tonnage, NaN)
        // The generator's tonnage is linear in width with the CAD tensile.
        var width = thickness > 0 && vdie > 0 && tensile > 0 && tonnage > 0
            ? tonnage * vdie / (Math.pow(thickness * 25.4, 2.0) * tensile * 1.099644E-6) : NaN
        var result = Object.assign({}, bend, {
            materialThickness: thickness,
            desiredBendAngle: finiteNumber(bend.angle, 90),
            angleCompensation: finiteNumber(valueOr(cadMaterial, "springBack_deg", 0), 0),
            angleCompensationReversed: false,
            punchToMaterialClearance: 0.0306,
            additionalRetractAfterBend: 0,
            backGaugeXPosition: finiteNumber(bend.x, 0),
            backGaugeRPosition: finiteNumber(bend.r, 0),
            backGaugeJogSpeed: finiteNumber(bend.speed, 100)
        })
        if (isFinite(width))
            result.bendWidth = Number(width.toFixed(3))
        return result
    }

    function bendFromStorage(bend, punches, dies, materials) {
        var angle = valueOr(bend, "desiredBendAngle", valueOr(bend, "angle", 90))
        var compensation = valueOr(bend, "angleCompensation", valueOr(bend, "compensation", 0))
        var x = valueOr(bend, "backGaugeXPosition", valueOr(bend, "x", 0))
        var r = valueOr(bend, "backGaugeRPosition", valueOr(bend, "r", 0))
        var speed = valueOr(bend, "backGaugeJogSpeed", valueOr(bend, "speed", 100))
        var thickness = valueOr(bend, "materialThickness", valueOr(bend, "thickness", 0))
        var width = valueOr(bend, "bendWidth", valueOr(bend, "width", 0))
        var punchRef = findById(punches, valueOr(bend, "punchId", ""))
        var dieRef = findById(dies, valueOr(bend, "dieId", ""))
        var materialRef = findById(materials, valueOr(bend, "materialId", ""))
        // Exact BendCalculator parity when tooling resolves; else fall back to stored/heuristic.
        var calc = calcBendParity(bend, punchRef, dieRef, materialRef)
        var tonnage = calc ? calc.bendTonnage
            : valueOr(bend, "tonnage", width > 0 && thickness > 0 ? Number(width) * Number(thickness) * 0.08 : 0)
        var finalPosition = calc ? calc.inUseFinalBendPosition
            : valueOr(bend, "overriddenFinalBendPosition", valueOr(bend, "finalPosition", -2.0))
        var startPosition = calc ? calc.startSafetyClearance
            : Number(finalPosition) + Number(valueOr(bend, "punchToMaterialClearance", 0.03))
        var retractPosition = calc ? calc.retractAfterBend
            : Number(startPosition) + Number(valueOr(bend, "additionalRetractAfterBend", 0))
        return Object.assign({}, bend || {}, {
            id: valueOr(bend, "id", ""),
            punchId: valueOr(bend, "punchId", punchRef ? punchRef.id : ""),
            dieId: valueOr(bend, "dieId", dieRef ? dieRef.id : ""),
            materialId: valueOr(bend, "materialId", materialRef ? materialRef.id : ""),
            name: normalizeName(bend, "Storage Bend"),
            date: valueOr(bend, "dateCreated", "-"),
            angle: formatNumber(angle, 1, "90.0"),
            compensation: formatNumber(compensation, 1, "0.0"),
            state: valueOr(bend, "angleCompensationReversed", false) ? "UNDERBENT" : "OVERBENT",
            x: formatNumber(x, 4, "0.0000"),
            r: formatNumber(r, 4, "0.0000"),
            speed: formatNumber(speed, 3, "100.000"),
            tonnage: formatNumber(tonnage, 3, "0.000"),
            thickness: formatNumber(thickness, 4, "0.0000"),
            material: valueOr(bend, "material", valueOr(bend, "materialName", materialRef ? materialRef.name : "UNDEFINED")),
            punch: valueOr(bend, "punch", valueOr(bend, "punchName", punchRef ? punchRef.name : "UNDEFINED")),
            die: valueOr(bend, "die", valueOr(bend, "dieName", dieRef ? dieRef.name : "UNDEFINED")),
            vdieValue: finiteNumber(valueOr(bend, "vdieValue", valueOr(bend, "vdieOpeningInch", dieRef ? dieRef.vdieOpeningInch : 0)), 0),
            vdie: valueOr(bend, "vdie", ""),
            toolingPhaseIndex: finiteNumber(valueOr(bend, "toolingPhaseIndex", 0), 0),
            punchSegmentWidths: valueOr(bend, "punchSegmentWidths", []),
            dieSegmentWidths: valueOr(bend, "dieSegmentWidths", []),
            punchSegmentStartIn: finiteNumber(valueOr(bend, "punchSegmentStartIn", NaN), NaN),
            dieSegmentStartIn: finiteNumber(valueOr(bend, "dieSegmentStartIn", NaN), NaN),
            toolingRackIndex: finiteNumber(valueOr(bend, "toolingRackIndex", NaN), NaN),
            toolingStationOffsetIn: finiteNumber(valueOr(bend, "toolingStationOffsetIn", 0), 0),
            toolingCoStations: valueOr(bend, "toolingCoStations", []),
            toolingBendCenterIn: valueOr(bend, "toolingBendCenterIn", null),
            punchInventoryShortage: valueOr(bend, "punchInventoryShortage", false) === true,
            dieInventoryShortage: valueOr(bend, "dieInventoryShortage", false) === true,
            width: formatNumber(width, 3, "0.000"),
            startPosition: formatNumber(startPosition, 4, "0.0000"),
            clampPosition: formatNumber(calc ? calc.clampPosition
                : Number(finalPosition) + 0.036, 4, "0.0000"),
            finalPosition: formatNumber(finalPosition, 4, "0.0000"),
            retractPosition: formatNumber(retractPosition, 4, "0.0000"),
            materialThickness: finiteNumber(thickness, 0),
            desiredBendAngle: finiteNumber(angle, 90),
            angleCompensation: finiteNumber(compensation, 0),
            angleCompensationReversed: valueOr(bend, "angleCompensationReversed",
                                                String(valueOr(bend, "state", "")).toUpperCase() === "UNDERBENT") === true,
            punchToMaterialClearance: finiteNumber(valueOr(bend, "punchToMaterialClearance", 0.05), 0.05),
            additionalRetractAfterBend: finiteNumber(valueOr(bend, "additionalRetractAfterBend", 0), 0),
            bendWidth: finiteNumber(width, 0.1),
            backGaugeRefEdgeStop: String(valueOr(bend, "backGaugeRefEdgeStop", "G54")),
            backGaugeRefEdgeStopEnabled: valueOr(bend, "backGaugeRefEdgeStopEnabled",
                                                  isFinite(Number(x)) || isFinite(Number(r))) !== false,
            backGaugeXPosition: finiteNumber(x, 0),
            backGaugeRPosition: finiteNumber(r, 0),
            backGaugeJogSpeed: finiteNumber(speed, 100),
            // Missing key = automatic formula (calcBendParity already treats it
            // as false). Defaulting to true showed MANUAL RAM OVERRIDE active
            // for every stored bend and would freeze the final depth on save.
            overrideFinalBendPositionEnabled: valueOr(bend, "overrideFinalBendPositionEnabled", false) === true,
            overriddenFinalBendPosition: finiteNumber(valueOr(bend, "overriddenFinalBendPosition", finalPosition), finalPosition),
            valid: valueOr(bend, "valid", true)
        })
    }

    function setAllBends(bends, punches, dies, materials) {
        var mapped = []
        for (var i = 0; bends && i < bends.length; i++)
            mapped.push(bendFromStorage(bends[i], punches, dies, materials))
        allBends = mapped
        if (selectedAddBendIndex >= mapped.length)
            selectedAddBendIndex = mapped.length - 1
        if (selectedAddBendIndex < 0 && mapped.length > 0)
            selectedAddBendIndex = 0
    }

    function validateProgramBend(bend) {
        var messages = []
        var tonnageValue = finiteNumber(bend.tonnage, 0)
        var finalPosition = finiteNumber(bend.finalPosition, 0)
        var xPosition = finiteNumber(bend.x, 0)
        if (Math.abs(xPosition) > 24.0)
            messages.push("OUT_OF_TRAVEL_LIMIT: back gauge X " + formatNumber(xPosition, 4, "0.0000") + " in")
        if (tonnageValue > 25.0)
            messages.push("TONNAGE_ERROR: bend tonnage " + formatNumber(tonnageValue, 3, "0.000") + " tons")
        if (finalPosition < -4.0 || finalPosition > -0.05)
            messages.push("FINAL_BEND_POS_OUT_RANGE: final position " + formatNumber(finalPosition, 4, "0.0000") + " in")
        return messages
    }

    function openAddBendPopup(bends, punches, dies, materials) {
        if (bends)
            setAllBends(bends, punches, dies, materials)
        addBendPopupVisible = true
        addBendStatus = allBends.length > 0 ? "ADD BEND MOVE" : "NO BEND MOVES AVAILABLE"
        log("RUN", "Add Bend popup opened with " + String(allBends.length) + " storage bends")
    }

    function closeAddBendPopup() {
        addBendPopupVisible = false
        addBendStatus = "Select a bend to add to the active program"
    }

    function selectAddBend(index) {
        if (index < 0 || index >= allBends.length)
            return
        selectedAddBendIndex = index
        addBendStatus = allBends[index].name
    }

    function addSelectedBendToProgram() {
        if (selectedAddBendIndex < 0 || selectedAddBendIndex >= allBends.length) {
            showAlarm("ADD BEND", "Select a bend before pressing ADD BEND.")
            return
        }
        var candidate = allBends[selectedAddBendIndex]
        var validation = validateProgramBend(candidate)
        runValidationMessages = validation
        if (validation.length > 0) {
            addBendStatus = validation.join("\n")
            showNextAddBendError(validation)
            return
        }
        var bend = appendBendToProgram(candidate)
        recordSandboxWrite("program-bends", "add-storage-bend", bend.name)
        closeAddBendPopup()
        showPopup("ADD BEND", bend.name + " added to " + activeProgram + " as bend " + String(bend.seq) + ".", 1)
    }

    function showNextAddBendError(validation) {
        var first = validation.length > 0 ? validation[0] : ""
        if (first.indexOf("OUT_OF_TRAVEL_LIMIT") >= 0)
            showAlarm("BEND OUT OF TRAVEL LIMIT", first)
        else if (first.indexOf("FINAL_BEND_POS_OUT_RANGE") >= 0)
            showAlarm("FINAL BEND DEPTH POSITION NOT IN RANGE", first)
        else if (first.indexOf("TONNAGE_ERROR") >= 0)
            showAlarm("HIGH TONNAGE", first)
        else
            showAlarm("ADD BEND MOVE", first)
    }

    function openRunConfirmation() {
        if (programBends.length === 0) {
            showAlarm("PROGRAM INVALID", "NO BEND MOVES AVAILABLE")
            return
        }
        if (!runProgramAllowed) {
            showAlarm("CAN'T RUN PROGRAM", "No bend move is selected.")
            return
        }
        if (licenseBlocksPhysicalRun())
            return
        if (measuredThicknessOverrideActive) {
            var executing = executingBendsForRun()
            for (var overrideIndex = 0; overrideIndex < executing.length; overrideIndex++) {
                if (executing[overrideIndex].measuredThicknessOverride !== "APPLIED") {
                    showAlarm("MEASURED THICKNESS OVERRIDE",
                              "Bend " + String(executing[overrideIndex].seq || overrideIndex + 1)
                              + " cannot be recalculated for the measured thickness. Turn the"
                              + " override off or fix its punch, die and material.")
                    return
                }
            }
        }
        if (runProgramGrayed) {
            if (!machineConnected)
                showAlarm("PRESS BRAKE NOT CONNECTED", "Connect the press brake before running the program.")
            else if (!offlineSimulationEnabled && machineControl && !machineControl.pressHomed)
                showAlarm("PRESS BRAKE NOT HOMED", "Home the press brake before running the program.")
            else if (!offlineSimulationEnabled && machineControl
                    && (!machineControl.pressReady || !machineControl.pressTelemetryFresh))
                showAlarm("PRESS BRAKE NOT READY", "Wait for fresh idle press-brake telemetry before running the program.")
            else if (!moduleConnected)
                showAlarm("BACK GAUGE NOT CONNECTED", "BACK GAUGE NOT CONNECTED")
            else if (!backGaugeHomed)
                showAlarm("BACK GAUGE NOT HOMED", "BACK GAUGE NOT HOMED")
            else if (!offlineSimulationEnabled && machineControl
                    && (!machineControl.moduleTelemetryFresh
                        || machineControl.moduleState !== "IDLE"
                        || machineControl.moduleOperationActive))
                showAlarm("BACK GAUGE NOT READY", "Wait for fresh idle Back Gauge telemetry before running the program.")
            else if (!backGaugeReady)
                showAlarm("BACK GAUGE NOT IN IDLE STATE", "BACK GAUGE NOT IN IDLE STATE")
            else
                showAlarm("CAN'T RUN PROGRAM", "Machine is not idle.")
            return
        }
        runConfirmationVisible = true
        log("RUN", "Run confirmation opened for " + activeProgram)
    }

    function closeRunConfirmation() {
        runConfirmationVisible = false
        log("RUN", "Run confirmation closed")
    }

    function confirmRunProgram() {
        runConfirmationVisible = false
        hidePopup()
        if (licenseBlocksPhysicalRun())
            return false
        if (!offlineSimulationEnabled) {
            if (!machineControl) {
                showMachineRejection("RUN PROGRAM")
                return false
            }
            if (runProgramGrayed) {
                showAlarm("CAN'T RUN PROGRAM", "Machine or Back Gauge readiness changed before dispatch.")
                return false
            }
            if (machineControl.setRunPedalMode && !machineControl.setRunPedalMode(runPedalMode)) {
                showAlarm("CAN'T RUN PROGRAM", "RUN pedal mode could not be sent to the press controller.")
                return false
            }
            if (!machineControl.beginProgramRun())
                return false
        } else if (runProgramGrayed) {
            showAlarm("CAN'T RUN PROGRAM", "Machine or Back Gauge readiness changed before dispatch.")
            return false
        }
        // Java closes the confirmation into the active Run view. Keep the
        // modern renderer, but move it to its live projection before any
        // execution phase is exposed to the operator.
        runSceneMode = "LIVE"
        runBendListVisible = false
        runActive = true
        if (offlineSimulationEnabled)
            machineStatus = "RUNNING"
        // Initialize the ported execution state machine for this run.
        beginExecutionStateMachine()
        var startToolChange = runStartAtToolChange
            ? toolChangeBeforeBend(programBends, selectedRunBend) : null
        runStartAtToolChange = false
        if (startToolChange)
            return enterRunToolChange(startToolChange)
        runProgressTitle = "Bend #" + String(selectedRunBend + 1) + " in Progress"
        runProgressSubtitle = currentRunPhaseLabel()
        if (!offlineSimulationEnabled && !dispatchPhysicalRunPhase()) {
            resetRunPresentationState()
            machineControl.endProgramRun()
            return false
        }
        return true
    }

    function finiteRunValue(value, fallback) {
        var parsed = Number(value)
        return isFinite(parsed) ? parsed : fallback
    }

    function physicalRunRamTarget(value, ramToTableOpening) {
        var target = finiteRunValue(value, NaN)
        if (target >= -4 && target <= -0.05)
            return target
        var opening = finiteRunValue(ramToTableOpening, NaN)
        if (!isFinite(target) || !(opening > 0))
            return NaN
        return target - opening
    }

    function authoritativeRamToTableOpening() {
        if (machineControl) {
            const controllerOpening = finiteRunValue(machineControl.ramToTableOpening, NaN)
            if (controllerOpening > 0)
                return controllerOpening
        }
        // Offline simulation has no controller EEPROM. Use the persisted
        // desktop opening only there; hardware mode must never substitute a
        // local/mock value for missing controller authority.
        const desktopOpening = finiteRunValue(desktopRamToTableOpening, NaN)
        return offlineSimulationEnabled && desktopOpening > 0 ? desktopOpening : NaN
    }

    function runRamTarget(field) {
        var bend = selectedBend || ({})
        if (field === "retractPosition") {
            // Match the validated retract plane sent by dispatchPhysicalRunPhase:
            // convert START to machine coordinates before applying the offset.
            var startPosition = physicalRunRamTarget(valueOr(bend, "startPosition", NaN),
                                                      authoritativeRamToTableOpening())
            return isFinite(startPosition) ? Math.min(-0.05,
                startPosition + finiteRunValue(bend.additionalRetractAfterBend, 0)) : NaN
        }
        return physicalRunRamTarget(valueOr(bend, field, NaN),
                                    authoritativeRamToTableOpening())
    }

    function runRamTargetText(field, unit) {
        var target = runRamTarget(field)
        if (!isFinite(target))
            return "UNAVAILABLE"
        return metricUnits ? Units.len(target, true) : target.toFixed(4) + (unit || "")
    }

    function runBendUsesBackGauge() {
        var ref = String(selectedBend.backGaugeRefEdgeStop || backGaugeCoordinateSystem || "G54").toUpperCase()
        return /^G5[4-9]$/.test(ref)
    }

    function dispatchPhysicalRunPhase() {
        if (!runActive || !machineControl || physicalRunCommandPending)
            return false
        if (runToolChangeActive)
            return true
        if (physicalRunWaitAction === "NEXT_BEND_PEDAL_TAP")
            return true
        if (!machineControl.pressConnected || !machineControl.pressReady
                || !machineControl.pressHomed || !machineControl.pressTelemetryFresh) {
            failPhysicalRun("PRESS_NOT_READY")
            return false
        }
        var P = ExecutionModel.BendPhase
        var operation = ""
        var accepted = false
        var speed = finiteRunValue(selectedBend.speed, jogSpeed)
        var ramToTableOpening = machineControl
            ? finiteRunValue(machineControl.ramToTableOpening, 0) : 0
        if (!(ramToTableOpening > 0)) {
            failPhysicalRun("RAM_TO_TABLE_OPENING_UNAVAILABLE")
            return false
        }
        if (measuredThicknessOverrideActive
                && selectedBend.measuredThicknessOverride !== "APPLIED") {
            failPhysicalRun("MEASURED_THICKNESS_OVERRIDE_UNRESOLVED")
            return false
        }
        var startPosition = physicalRunRamTarget(selectedBend.startPosition, ramToTableOpening)
        var clampPosition = physicalRunRamTarget(selectedBend.clampPosition, ramToTableOpening)
        var finalPosition = physicalRunRamTarget(selectedBend.finalPosition, ramToTableOpening)
        physicalRunBackGaugeSpeed = speed
        physicalRunUsesBackGauge = runBendUsesBackGauge()
        if (physicalRunUsesBackGauge && (!machineControl.moduleConnected
                || !machineControl.moduleReady || !machineControl.moduleHomed
                || !machineControl.moduleTelemetryFresh)) {
            failPhysicalRun("BACK_GAUGE_NOT_READY")
            return false
        }
        if (!isFinite(rawRamControlPosition)) {
            failPhysicalRun("RAM_TARGET_POSITION_UNAVAILABLE")
            return false
        }
        if (!isFinite(startPosition) || !isFinite(clampPosition) || !isFinite(finalPosition)
                || startPosition < -4 || startPosition > -0.05
                || clampPosition < -4 || clampPosition > -0.05
                || finalPosition < -4 || finalPosition > -0.05
                || speed < 1 || speed > 2500) {
            failPhysicalRun("INVALID_BEND_PARAMETERS")
            return false
        }
        if (executionPhase === P.STARTING.name) {
            physicalRunRetractPlane = runRamTarget("retractPosition")
            operation = "set-retract-plane"
            accepted = machineControl.setPressRetractPlane(physicalRunRetractPlane)
        } else if (executionPhase === P.BACK_GAUGE_MOVE.name) {
            if (!physicalRunUsesBackGauge)
                return advancePhysicalRunPhase()
            var coordinate = String(selectedBend.backGaugeRefEdgeStop
                                    || backGaugeCoordinateSystem || "G54").toUpperCase()
            if (coordinate !== backGaugeCoordinateSystem) {
                operation = "select-coordinate"
                accepted = machineControl.selectModuleCoordinateSystem(coordinate)
                if (accepted)
                    backGaugeCoordinateSystem = coordinate
            } else {
                operation = "move"
                accepted = machineControl.moveModule(finiteRunValue(selectedBend.x, 0),
                    finiteRunValue(selectedBend.r, 0)
                        + backGaugeDieCompensationR(coordinate, selectedBend), speed)
            }
        } else if (executionPhase === P.SAFETY_CLEARANCE_POSITION_MOVE.name) {
            if (leftSafetyJog || rightSafetyJog) {
                physicalRunWaitAction = "RELEASE_PALM_SWITCHES"
                runProgressSubtitle = runOperatorPrompt()
                return true
            }
            // Auto measure on the reference block: the sheet sits on the block, so
            // the safety opening must be raised by the block thickness (+0.1 in)
            // or the block cannot be placed under the punch.
            if (autoMeasureOnClampEnabled && !runAutoMeasureDone
                    && !autoMeasureDirectViable(selectedBend)
                    && autoMeasureReferenceBlockThickness > 0)
                // Cap 0.1 in below the Home plane: an idle stop at -0.05 drifts into
                // the firmware PANEL_RETRACT_HARD_LIMIT (-0.049) -> home-plane fault.
                startPosition = Math.min(-0.15,
                    startPosition + autoMeasureReferenceBlockThickness + 0.1)
            // Java MachineJogModel.jogToSafetyClearancePosition(): RETRACT only
            // when the clearance is above the controller position, else the
            // palm-held SAFETY jog. Compare at the 0.0001 in frame resolution:
            // float noise made an equal -2.5986 pick "retract" (2026-11-01).
            var retractToClearance = Math.round(startPosition * 10000)
                    > Math.round(rawRamControlPosition * 10000)
            operation = retractToClearance ? "jog-retract" : "jog-safety"
            accepted = machineControl.jogPress(startPosition, jogRamSpeed,
                                               retractToClearance ? "retract" : "safety")
        } else if (executionPhase === P.CLAMP_MATERIAL_MOVE.name) {
            // Read the backend pedal bit directly: the QML mirror can lag the
            // completion of a pedal-driven SAFETY jog (clamp rejected NOT READY).
            if (bendJogPedal || (machineControl && machineControl.bendPedal)) {
                physicalRunWaitAction = "RELEASE_PEDAL"
                runProgressSubtitle = runOperatorPrompt()
                return true
            }
            if (autoMeasureOnClampEnabled && !runAutoMeasureDone)
                return beginRunAutoMeasure()
            operation = "jog-clamp"
            accepted = machineControl.jogPress(clampPosition, bendRamSpeed, "clamp")
        } else if (executionPhase === P.BACK_GAUGE_BUMP_MOVE.name) {
            if (!physicalRunUsesBackGauge)
                return advancePhysicalRunPhase()
            operation = "increment"
            accepted = machineControl.incrementModule("X", backGaugeBumpOffDistanceInch, speed)
        } else if (executionPhase === P.DWELL_TIMER_WAIT.name) {
            return tickPhysicalRunDwell()
        } else if (executionPhase === P.BEND_MOVE.name) {
            // AUTO CLAMP TO BEND off: stop after the clamp; the operator must
            // release and press the pedal again. Read the backend bit too: the
            // QML mirror can lag the clamp completion and let the bend run on.
            if (!autoClampEnabled && !bendRepressDone) {
                bendRepressReleased = !(dwellPedalHeld() || bendJogPedal)
                physicalRunWaitAction = "BEND_PEDAL_REPRESS"
                runProgressSubtitle = runOperatorPrompt()
                return true
            }
            bendRepressDone = false
            operation = "jog-bend"
            accepted = machineControl.jogPress(finalPosition, bendRamSpeed, "bend")
        } else if (executionPhase === P.BACK_GAUGE_AND_RAM_RETRACT_MOVE.name) {
            if (!physicalRunUsesBackGauge || !backGaugeRetractBetweenBendsEnabled
                    || !(backGaugeRetractBetweenBendsInch > 0))
                return advancePhysicalRunPhase()
            operation = "increment"
            accepted = machineControl.incrementModule("X", backGaugeRetractBetweenBendsInch, speed)
        }
        if (!accepted) {
            failPhysicalRun(machineControl.lastRejectReason || "COMMAND_REJECTED")
            return false
        }
        physicalRunPendingOperation = operation
        physicalRunWaitAction = ""
        physicalRunPendingDevice = executionPhase === P.BACK_GAUGE_MOVE.name
            || executionPhase === P.BACK_GAUGE_BUMP_MOVE.name
            || executionPhase === P.BACK_GAUGE_AND_RAM_RETRACT_MOVE.name
            ? "module" : "press"
        physicalRunPendingOperationId = machineControl.operationId
        physicalRunCommandPending = true
        log("RUN", "Dispatched " + physicalRunPendingDevice + " " + operation
            + " operation #" + String(physicalRunPendingOperationId)
            + " for " + executionPhase)
        runProgressSubtitle = currentRunPhaseLabel()
        return true
    }

    function handlePhysicalRunOperationFinished(operation, state, error) {
        if (!runActive || !physicalRunCommandPending || operation !== physicalRunPendingOperation)
            return
        physicalRunCommandPending = false
        physicalRunPendingOperation = ""
        physicalRunPendingDevice = ""
        physicalRunPendingOperationId = undefined
        if (state !== "COMPLETED") {
            failPhysicalRun(error || state || "CONTROLLER_OPERATION_FAILED")
            return
        }
        if (executionPhase === ExecutionModel.BendPhase.BACK_GAUGE_MOVE.name
                && physicalRunUsesBackGauge && operation === "select-coordinate") {
            dispatchPhysicalRunPhase()
            return
        }
        advancePhysicalRunPhase()
    }

    function advancePhysicalRunPhase() {
        if (!runActive)
            return false
        advanceExecutionPhase()
        if (!runActive)
            return true
        return dispatchPhysicalRunPhase()
    }

    // Dwell pedal hold follows the BEND gesture of runBendPermit() (r36e16):
    // modes 1/2 single tap (pedal down), modes 0/3 double-tap latch.
    function runBendSingleTap() {
        return runPedalMode === 1 || runPedalMode === 2 || runPedalMode === 4
    }
    function dwellPedalHeld() {
        return runBendSingleTap() ? physicalPedalActive : bendJogPedal
    }

    function tickPhysicalRunDwell() {
        if (!runActive)
            return false
        if (!autoClampEnabled || !autoClampDwellEnabled || autoClampDwellSec <= 0)
            return advancePhysicalRunPhase()
        if (!dwellPedalHeld()) {
            // Lifting the pedal during the countdown pauses it; the full
            // dwell restarts when the pedal is held again (no cancel).
            if (dwellStartedForBend) {
                dwellStartedForBend = false
                dwellRemainingSec = autoClampDwellSec
                log("RUN", "Dwell reset by pedal lift; hold pedal to restart")
            }
            dwellPausedForPedal = true
            runProgressSubtitle = runOperatorPrompt()
            return true
        }
        dwellPausedForPedal = false
        if (!dwellStartedForBend) {
            // Use the current setting so edits made after RUN started apply.
            dwellTimerState = DwellAndBailOut.createDwellTimer(autoClampDwellSec)
            DwellAndBailOut.startDwellTimer(dwellTimerState)
            dwellStartedForBend = true
            dwellRemainingSec = autoClampDwellSec
            runProgressSubtitle = runOperatorPrompt()
            return true
        }
        var dwellState = DwellAndBailOut.tickDwellTimer(dwellTimerState, dwellPedalHeld())
        dwellRemainingSec = Number(dwellTimerState.remainingSec || 0)
        runProgressSubtitle = runOperatorPrompt()
        if (dwellState === DwellAndBailOut.DwellTimerState.FINISHED)
            return advancePhysicalRunPhase()
        return true
    }

    // Bending tonnage stored with the bend (width, thickness, tensile and V
    // already applied). Direct measurement on the V is viable only when the
    // part needs well over the measuring force to yield.
    function autoMeasureDirectViable(bend) {
        var tonnage = finiteNumber(valueOr(bend || {}, "tonnage", NaN), NaN)
        return isFinite(tonnage) && tonnage
            >= manualMeasurementTonnageMinimum * autoMeasureViabilityMargin
    }

    function beginRunAutoMeasure() {
        var bend = selectedBend || ({})
        if (!manualDieTopCalibrationValid) {
            failPhysicalRun("AUTO_MEASURE_CALIBRATION_REQUIRED")
            return false
        }
        var record = userSettingsModel.manualDieTopCalibration || ({})
        if ((record.punchId && String(bend.punchId || "") !== String(record.punchId))
                || (record.dieId && String(bend.dieId || "") !== String(record.dieId))) {
            failPhysicalRun("AUTO_MEASURE_TOOLING_NOT_CALIBRATED")
            return false
        }
        runAutoMeasureOnBlock = !autoMeasureDirectViable(bend)
        if (runAutoMeasureOnBlock && !runAutoMeasureBlockConfirmed) {
            if (!(autoMeasureReferenceBlockThickness > 0)) {
                failPhysicalRun("AUTO_MEASURE_REFERENCE_BLOCK_THICKNESS_NOT_SET")
                return false
            }
            physicalRunWaitAction = "AUTO_MEASURE_PLACE_BLOCK"
            runProgressSubtitle = runOperatorPrompt()
            showConfirmation("USE REFERENCE BLOCK",
                "Bend tonnage " + finiteNumber(bend.tonnage, 0).toFixed(2) + " T is too low to measure on the V at "
                + manualMeasurementTonnageMinimum.toFixed(2) + " T without deforming the part. Place the sheet on the "
                + autoMeasureReferenceBlockThickness.toFixed(4) + " in reference block and press YES to measure.",
                function() {
                    runAutoMeasureBlockConfirmed = true
                    physicalRunWaitAction = ""
                    dispatchPhysicalRunPhase()
                },
                function() { failPhysicalRun("AUTO_MEASURE_CANCELLED") })
            return true
        }
        manualMeasurementMode = "MEASUREMENT"
        manualMeasurementOnReferencePiece = false
        runAutoMeasureActive = true
        physicalRunWaitAction = "AUTO_MEASURE"
        resetManualMeasurementAcquisition("")
        clearManualMeasurementAcceptedSnapshot()
        manualMeasurementResult = NaN
        manualMeasurementStackResult = NaN
        manualMeasurementStatus = "WAITING FOR CONTACT"
        if (!startTonnageHoldProfile(manualMeasurementTonnageMinimum, "RUN_AUTO_MEASURE", false)) {
            failPhysicalRun("AUTO_MEASURE_PROFILE_REJECTED")
            return false
        }
        log("RUN", "Auto measure started" + (runAutoMeasureOnBlock
            ? " on " + autoMeasureReferenceBlockThickness.toFixed(4) + " in reference block" : "")
            + " at " + manualMeasurementTonnageMinimum.toFixed(2) + " T")
        runProgressSubtitle = runOperatorPrompt()
        return true
    }

    function handleRunAutoMeasureFinished(completed, reason) {
        if (!runActive || !runAutoMeasureActive)
            return
        runAutoMeasureActive = false
        var stack = Number(manualMeasurementStackResult)
        if (!completed || !isFinite(stack)) {
            failPhysicalRun("AUTO_MEASURE_FAILED " + String(reason || manualMeasurementStatus))
            return
        }
        var measured = stack - (runAutoMeasureOnBlock ? autoMeasureReferenceBlockThickness : 0)
        var bend = (storedProgramBends || [])[selectedRunBend] || selectedBend || ({})
        var programT = finiteNumber(valueOr(bend, "materialThickness", valueOr(bend, "thickness", NaN)), NaN)
        runAutoMeasureResult = measured
        log("RUN", "Auto measure stack=" + stack.toFixed(4) + " measured=" + measured.toFixed(4)
            + " program=" + (isFinite(programT) ? programT.toFixed(4) : "n/a"))
        if (!(measured > 0) || (programT > 0
                && Math.abs(measured - programT) / programT > autoMeasureMaximumDeviation)) {
            failPhysicalRun("AUTO_MEASURE_OUT_OF_BAND " + measured.toFixed(4) + " IN VS PROGRAM "
                            + (isFinite(programT) ? programT.toFixed(4) : "?") + " IN")
            return
        }
        persistUserSetting("measuredMaterialThickness", {
            value: measured, unit: "INCH", valid: true,
            onReferencePiece: runAutoMeasureOnBlock,
            referenceThickness: runAutoMeasureOnBlock ? autoMeasureReferenceBlockThickness : null,
            source: "RUN_AUTO_MEASURE",
            measuredAt: new Date().toISOString()
        })
        userSettingsModel = Object.assign({}, userSettingsModel)
        // Safe point: the ram is back at clearance and the clamp is not sent,
        // so the run targets may be recalculated for the measured thickness.
        measuredThicknessOverrideEnabled = true
        syncActiveProgramState()
        if (measuredThicknessOverrideUnresolvedCount > 0) {
            failPhysicalRun("MEASURED_THICKNESS_OVERRIDE_UNRESOLVED")
            return
        }
        runAutoMeasureDone = true
        if (runAutoMeasureOnBlock) {
            physicalRunWaitAction = "AUTO_MEASURE_REMOVE_BLOCK"
            runProgressSubtitle = runOperatorPrompt()
            showConfirmation("REMOVE REFERENCE BLOCK",
                "Measured " + measured.toFixed(4) + " in. Remove the reference block, position the sheet against the back gauge and press YES to clamp.",
                function() { physicalRunWaitAction = ""; dispatchPhysicalRunPhase() },
                function() { failPhysicalRun("AUTO_MEASURE_CANCELLED") })
            return
        }
        physicalRunWaitAction = ""
        dispatchPhysicalRunPhase()
    }

    function failPhysicalRun(reason) {
        if (runAutoMeasureActive) {
            runAutoMeasureActive = false
            if (contactProfileActive && contactProfileOwner === "RUN_AUTO_MEASURE")
                cancelTonnageHoldProfile()
        }
        physicalRunCommandPending = false
        physicalRunPendingOperation = ""
        physicalRunPendingDevice = ""
        physicalRunPendingOperationId = undefined
        physicalRunWaitAction = ""
        dwellRemainingSec = 0
        dwellPausedForPedal = false
        abortRunToolChange()
        resetRunPresentationState()
        if (machineControl) {
            if (machineControl.pressOperationActive)
                machineControl.abortPress()
            if (machineControl.moduleOperationActive)
                machineControl.stopModule()
            machineControl.endProgramRun()
        }
        showAlarm("RUN PROGRAM FAILED", String(reason || "FAILED").replace(/_/g, " "))
        log("RUN", "Physical run failed: " + String(reason || "FAILED"))
    }

    // --- Execution state machine (ExecutionStateModel + DwellAndBailOut parity) ---

    // Bends that would execute given the current bend mode, using ExecutionStateModel
    // slicing semantics (program+loop -> all; program -> from selected index; single -> selected).
    function executionStateFor(index) {
        var state = ExecutionModel.createExecution()
        state.mode = ExecutionModel.BendMode[bendMode] || ExecutionModel.BendMode.PROGRAM_BEND_MODE
        ExecutionModel.setSelectedProgram(state, { name: activeProgram, bends: programBends || [] })
        state.selectedBendIndex = Math.max(0, index)
        return state
    }

    function executingBendsForRun() {
        return ExecutionModel.executingBends(executionStateFor(selectedRunBend))
    }

    function beginExecutionStateMachine() {
        executionPhaseIndex = 0
        executionPhase = ExecutionModel.BendPhase.STARTING.name
        // Dwell timer mirrors autoClampBendDwellSec; created fresh per run.
        dwellTimerState = DwellAndBailOut.createDwellTimer(autoClampDwellSec)
        bailOutState = DwellAndBailOut.createBailOut()
        lastBailOutReason = ""
        dwellStartedForBend = false
        dwellRemainingSec = 0
        dwellPausedForPedal = false
        physicalRunWaitAction = ""
        runAutoMeasureDone = false
        runAutoMeasureActive = false
        runAutoMeasureBlockConfirmed = false
        runAutoMeasureResult = NaN
    }

    // Per-bend run phase order presented to the UI. Mirrors BendProgramModel.runProgram:
    // the STARTING marker, the 6 ExecutionModel.BEND_PHASE_SEQUENCE move phases, with the
    // DWELL_TIMER_WAIT inserted between CLAMP_MATERIAL_MOVE and BEND_MOVE (only honored
    // when auto-clamp is enabled — otherwise it's a passthrough phase).
    function runPhaseSequence() {
        var P = ExecutionModel.BendPhase
        return [
            P.STARTING.name,
            P.BACK_GAUGE_MOVE.name,
            P.SAFETY_CLEARANCE_POSITION_MOVE.name,
            P.CLAMP_MATERIAL_MOVE.name,
            P.BACK_GAUGE_BUMP_MOVE.name,
            P.DWELL_TIMER_WAIT.name,
            P.BEND_MOVE.name,
            P.BACK_GAUGE_AND_RAM_RETRACT_MOVE.name
        ]
    }

    // Advance one step through the run phase sequence. executionPhaseIndex points at the
    // CURRENT phase (seq[index] === executionPhase). When the dwell phase is current and
    // auto-clamp is enabled, the dwell timer must finish (gracefully) before progressing.
    // Returns the new phase name. Called by RunView's 100ms run Timer.
    function advanceExecutionPhase() {
        if (!runActive)
            return executionPhase
        if (runToolChangeActive)
            return executionPhase
        if (!offlineSimulationEnabled && physicalRunCommandPending)
            return executionPhase
        var seq = runPhaseSequence()
        var current = (executionPhaseIndex >= 0 && executionPhaseIndex < seq.length) ? seq[executionPhaseIndex] : null
        // Dwell gate: hold on DWELL_TIMER_WAIT (auto-clamp on) until timer finishes/cancels.
        // A freshly created timer is FINISHED, so we gate on dwellStartedForBend to ensure
        // the countdown actually runs before progressing.
        if (current === ExecutionModel.BendPhase.DWELL_TIMER_WAIT.name
            && autoClampEnabled && autoClampDwellEnabled && dwellTimerState) {
            if (!dwellStartedForBend) {
                DwellAndBailOut.startDwellTimer(dwellTimerState)
                dwellStartedForBend = true
                dwellRemainingSec = autoClampDwellSec
            }
            if (DwellAndBailOut.isDwellRunning(dwellTimerState)) {
                if (!dwellPedalHeld()) {
                    dwellPausedForPedal = true
                    executionPhase = ExecutionModel.BendPhase.DWELL_TIMER_WAIT.name
                    runProgressSubtitle = currentRunPhaseLabel()
                    return executionPhase
                }
                dwellPausedForPedal = false
                var st = DwellAndBailOut.tickDwellTimer(dwellTimerState, true)
                dwellRemainingSec = Number(dwellTimerState.remainingSec || 0)
                executionPhase = ExecutionModel.BendPhase.DWELL_TIMER_WAIT.name
                runProgressSubtitle = currentRunPhaseLabel()
                if (st !== DwellAndBailOut.DwellTimerState.FINISHED)
                    return executionPhase   // still dwelling — hold this phase
            }
        }
        executionPhaseIndex = executionPhaseIndex + 1
        if (executionPhaseIndex >= seq.length) {
            completeCurrentBendExecution()
            return executionPhase
        }
        executionPhase = seq[executionPhaseIndex]
        // SEAT AGAIN is retired once the next bend clamps material.
        if (executionPhase === ExecutionModel.BendPhase.CLAMP_MATERIAL_MOVE.name
                && toolChangeSeatAgainAvailable && !runToolChangeActive)
            endToolChange()
        runProgressSubtitle = currentRunPhaseLabel()
        return executionPhase
    }

    // Reached end of a bend's phase sequence: advance to next bend (program mode) or
    // finish the run. Mirrors ExecutionStateModel.nextBend semantics.
    function completeCurrentBendExecution() {
        var state = executionStateFor(selectedRunBend)
        var hasNext = ExecutionModel.nextBend(state)
        if (hasNext && bendModeIsProgramMode()) {
            selectRunBend(state.selectedBendIndex, true)
            var toolChange = toolChangeBeforeBend(programBends, state.selectedBendIndex)
            if (toolChange) {
                executionPhaseIndex = 0
                dwellTimerState = DwellAndBailOut.createDwellTimer(autoClampDwellSec)
                dwellStartedForBend = false
                dwellRemainingSec = 0
                dwellPausedForPedal = false
                enterRunToolChange(toolChange)
                return
            }
            executionPhaseIndex = 0
            executionPhase = ExecutionModel.BendPhase.STARTING.name
            dwellTimerState = DwellAndBailOut.createDwellTimer(autoClampDwellSec)
            dwellStartedForBend = false
            dwellRemainingSec = 0
            dwellPausedForPedal = false
            physicalRunWaitAction = ""
            runProgressTitle = "Bend #" + String(selectedRunBend + 1) + " in Progress"
            runProgressSubtitle = currentRunPhaseLabel()
            awaitNextBendPedalTap()
        } else if (bendModeIsRepeatable()) {
            // Loop/repeat: restart sequence at the first executing bend.
            if (bendModeIsProgramMode())
                selectRunBend(0, true)
            executionPhaseIndex = 0
            executionPhase = ExecutionModel.BendPhase.STARTING.name
            dwellTimerState = DwellAndBailOut.createDwellTimer(autoClampDwellSec)
            dwellStartedForBend = false
            dwellRemainingSec = 0
            dwellPausedForPedal = false
            physicalRunWaitAction = ""
            runProgressSubtitle = currentRunPhaseLabel()
            awaitNextBendPedalTap()
        } else {
            // PROGRAM BEND: the part is done; park on sequence 1 for the next
            // part. SINGLE BEND keeps the active sequence.
            if (bendModeIsProgramMode() && programBends.length > 0)
                selectRunBend(0, true)
            finishRunExecution()
        }
    }

    function finishRunExecution() {
        physicalRunCommandPending = false
        physicalRunPendingOperation = ""
        physicalRunPendingDevice = ""
        physicalRunPendingOperationId = undefined
        if (offlineSimulationEnabled)
            machineStatus = "IDLE"
        else if (machineControl)
            machineControl.endProgramRun()
        executionPhase = ExecutionModel.BendPhase.FINISHING_PROGRAM.name
        resetRunPresentationState()
        log("RUN", "Program finished: " + activeProgram)
    }

    // Bail out of the current run with a reason (debounced by DwellAndBailOut).
    function triggerBailOut(reason) {
        if (!bailOutState)
            bailOutState = DwellAndBailOut.createBailOut()
        var fired = DwellAndBailOut.onBailOut(bailOutState, reason, Date.now())
        if (!fired)
            return false
        lastBailOutReason = String(reason)
        physicalRunCommandPending = false
        physicalRunPendingOperation = ""
        physicalRunPendingDevice = ""
        physicalRunPendingOperationId = undefined
        if (offlineSimulationEnabled)
            machineStatus = "IDLE"
        else if (machineControl)
            machineControl.endProgramRun()
        resetRunPresentationState()
        var alarm = DwellAndBailOut.bailOutIsMachineAlarm(reason)
        if (alarm)
            showAlarm("MACHINE ALARM", "Bail out: " + String(reason))
        else
            showPopup("PROGRAM BAILED OUT", activeProgram + "\nReason: " + String(reason), 1)
        log("RUN", "Bail out: " + String(reason))
        return true
    }

    function bendModeIsProgramMode() {
        return bendMode === "PROGRAM_BEND_MODE" || bendMode === "PROGRAM_BEND_LOOP"
    }

    function bendModeIsRepeatable() {
        return bendMode === "SINGLE_BEND_REPEAT" || bendMode === "PROGRAM_BEND_LOOP"
    }

    function bendModeLabel(mode) {
        if (mode === "SINGLE_BEND_MODE")
            return "SINGLE BEND MODE"
        if (mode === "SINGLE_BEND_REPEAT")
            return "SINGLE BEND REPEAT"
        if (mode === "PROGRAM_BEND_LOOP")
            return "PROGRAM BEND LOOP"
        return "PROGRAM BEND MODE"
    }

    function setBendMode(mode) {
        if ((mode === "PROGRAM_BEND_MODE" || mode === "PROGRAM_BEND_LOOP") && !multipleBendsProgram)
            mode = "SINGLE_BEND_MODE"
        bendMode = mode
        bendModePopupVisible = false
        persistLocalSetting("lastBendMode", bendMode)
        log("RUN", "Bend mode " + bendModeLabel(bendMode))
    }

    function enforceBendModeForProgram() {
        if (!multipleBendsProgram && bendModeIsProgramMode())
            bendMode = "SINGLE_BEND_MODE"
    }

    function toggleBendModePopup() {
        if (programBends.length === 0 || selectedRunBend < 0)
            return
        bendModePopupVisible = !bendModePopupVisible
    }

    function currentRunPhaseLabel() {
        if (!runActive)
            return ""
        return runOperatorPrompt()
    }

    // Java parity for MachineJogModel's wait-for-release stage,
    // SwitchControlHintView, and DwellTimerView. This is presentation and
    // dispatch gating only; raw controller telemetry remains authoritative.
    function runOperatorPrompt() {
        if (!runActive)
            return ""
        if (runToolChangeActive)
            return runToolChangePhaseLabel()
        if (physicalRunWaitAction === "RELEASE_PALM_SWITCHES")
            return "RELEASE SAFETY PALM SWITCHES TO CONTINUE"
        if (physicalRunWaitAction === "RELEASE_PEDAL")
            return "RELEASE FOOT PEDAL TO CONTINUE"
        if (physicalRunWaitAction === "BEND_PEDAL_REPRESS")
            return bendRepressReleased ? "PRESS FOOT PEDAL TO BEND"
                : "CLAMPED — RELEASE FOOT PEDAL, THEN PRESS TO BEND"
        if (physicalRunWaitAction === "NEXT_BEND_PEDAL_TAP")
            return !nextBendTapReleased ? "RELEASE FOOT PEDAL, REMOVE PART"
                : nextBendTapPressed ? "RELEASE FOOT PEDAL FOR NEXT BEND"
                : "REMOVE PART — TAP FOOT PEDAL FOR NEXT BEND"
        if (physicalRunWaitAction === "AUTO_MEASURE_PLACE_BLOCK")
            return "PLACE SHEET ON REFERENCE BLOCK " + autoMeasureReferenceBlockThickness.toFixed(4) + " IN"
        if (physicalRunWaitAction === "AUTO_MEASURE_REMOVE_BLOCK")
            return "REMOVE REFERENCE BLOCK AND POSITION SHEET"
        if (physicalRunWaitAction === "AUTO_MEASURE")
            return "AUTO MEASURE " + (runAutoMeasureOnBlock ? "ON BLOCK " : "")
                + "\u2014 " + manualMeasurementStatus
        if (executionPhase === "DWELL_TIMER_WAIT")
            return dwellPausedForPedal
                ? "DWELL PAUSED — " + pedalGesturePrompt(!runBendSingleTap()) + " TO CONTINUE — "
                    + Number(dwellRemainingSec).toFixed(1) + " SECONDS"
                : "DWELL — KEEP FOOT PEDAL DOWN — "
                    + Number(dwellRemainingSec).toFixed(1) + " SECONDS"
        // Only the SAFETY jog is palm-gated; the RETRACT to clearance is automatic.
        if (executionPhase === "SAFETY_CLEARANCE_POSITION_MOVE"
                && physicalRunCommandPending
                && physicalRunPendingOperation === "jog-safety")
            // runPedalMode: 0 BTN/2TAP, 1 BTN/1TAP, 2 2TAP/1TAP, 3 1TAP/2TAP (jog/bend).
            // Firmware r36e16 runJogPermit(): 2 = double-tap latch, 3 = pedal down.
            // r36e19: modes 0/1/2 accept palm switches OR the pedal double tap.
            return (runPedalMode === 3 || runPedalMode === 4) ? pedalGesturePrompt(false)
                : bendJogPedal ? "HOLD FOOT PEDAL"
                : (leftSafetyJog || rightSafetyJog)
                ? "HOLD SAFETY PALM SWITCHES"
                : "HOLD PALM SWITCHES OR DOUBLE-TAP AND HOLD PEDAL"
        if ((executionPhase === "CLAMP_MATERIAL_MOVE"
                || executionPhase === "BEND_MOVE")
                && physicalRunCommandPending)
            // Firmware runBendPermit() gates BOTH clamp and bend (jog types 4/5):
            // modes 1/2 single tap (pedal down), modes 0/3 double-tap latch.
            return pedalGesturePrompt(!runBendSingleTap())
        return executionPhaseDisplayName(executionPhase)
    }

    // Double-tap gestures are satisfied by the controller latch (field 10);
    // single-tap gestures by the raw pedal-down input. Show HOLD only when
    // the bit the firmware actually checks is set.
    function pedalGesturePrompt(doubleTap) {
        if (doubleTap)
            return bendJogPedal ? "HOLD FOOT PEDAL"
                : physicalPedalActive ? "RELEASE, THEN DOUBLE-TAP AND HOLD FOOT PEDAL"
                : "DOUBLE-TAP AND HOLD FOOT PEDAL"
        return physicalPedalActive ? "HOLD FOOT PEDAL" : "PRESS AND HOLD FOOT PEDAL"
    }

    function processPhysicalRunOperatorGate() {
        if (!runActive || physicalRunCommandPending || physicalRunWaitAction === "")
            return false
        if (physicalRunWaitAction === "RELEASE_PALM_SWITCHES"
                && (leftSafetyJog || rightSafetyJog)) {
            runProgressSubtitle = runOperatorPrompt()
            return true
        }
        if (physicalRunWaitAction === "RELEASE_PEDAL"
                && (bendJogPedal || (machineControl && machineControl.bendPedal))) {
            runProgressSubtitle = runOperatorPrompt()
            return true
        }
        if (physicalRunWaitAction === "BEND_PEDAL_REPRESS") {
            // AUTO CLAMP TO BEND off: release after the clamp, then press to bend.
            // Bend gesture follows RUN Pedal Mode (1TAP = pedal down, 2TAP = latch).
            var held = dwellPedalHeld()
            if (!bendRepressReleased) {
                if (!held && !bendJogPedal)
                    bendRepressReleased = true
            } else if (held) {
                physicalRunWaitAction = ""
                bendRepressDone = true
                runProgressSubtitle = "PROCEEDING..."
                log("RUN", "Pedal re-pressed: bending")
                return dispatchPhysicalRunPhase()
            }
            runProgressSubtitle = runOperatorPrompt()
            return true
        }
        if (physicalRunWaitAction === "NEXT_BEND_PEDAL_TAP") {
            // Tap = released (from the bend), pressed, then released again.
            var down = physicalPedalActive || bendJogPedal
            if (!nextBendTapReleased) {
                if (!down)
                    nextBendTapReleased = true
            } else if (down) {
                nextBendTapPressed = true
            } else if (nextBendTapPressed) {
                physicalRunWaitAction = ""
                runProgressSubtitle = "PROCEEDING..."
                log("RUN", "Pedal tap: advancing to bend #" + String(selectedRunBend + 1))
                return dispatchPhysicalRunPhase()
            }
            runProgressSubtitle = runOperatorPrompt()
            return true
        }
        // Auto measure waits are released by their own handlers.
        if (physicalRunWaitAction.indexOf("AUTO_MEASURE") === 0) {
            runProgressSubtitle = runOperatorPrompt()
            return true
        }
        physicalRunWaitAction = ""
        runProgressSubtitle = "PROCEEDING..."
        return dispatchPhysicalRunPhase()
    }

    // Original manual "Sequence of Bending Operations" (6 steps). Dwell belongs to step 5.
    readonly property var runSequenceStepNames: ["BACKGAUGE MOVE", "SAFETY START POSITION",
        "CLAMP MATERIAL", "BACKGAUGE BUMP", "BEND MOVE", "BACKGAUGE & RAM RETRACT"]
    function runSequenceStep(phaseName) {
        switch (phaseName) {
        case "BACK_GAUGE_MOVE": return 1
        case "SAFETY_CLEARANCE_POSITION_MOVE": return 2
        case "CLAMP_MATERIAL_MOVE": return 3
        case "BACK_GAUGE_BUMP_MOVE": return 4
        case "DWELL_TIMER_WAIT":
        case "BEND_MOVE": return 5
        case "BACK_GAUGE_AND_RAM_RETRACT_MOVE": return 6
        default: return 0
        }
    }

    // Map ExecutionModel.BendPhase names to display labels for the Run UI.
    function executionPhaseDisplayName(phaseName) {
        switch (phaseName) {
        case "STARTING": return "STARTING"
        case "BACK_GAUGE_MOVE": return "BACKGAUGE MOVE"
        case "SAFETY_CLEARANCE_POSITION_MOVE": return "SAFETY START POSITION"
        case "CLAMP_MATERIAL_MOVE": return "CLAMP MATERIAL"
        case "BACK_GAUGE_BUMP_MOVE": return "BACKGAUGE BUMP"
        case "DWELL_TIMER_WAIT": return "DWELL"
        case "BEND_MOVE": return "BEND MOVE"
        case "BACK_GAUGE_AND_RAM_RETRACT_MOVE": return "BACKGAUGE & RAM RETRACT"
        case "FINISHING_PROGRAM": return "FINISHING"
        default: return phaseName ? String(phaseName) : "STARTING"
        }
    }

    function deleteProgramBend(index) {
        if (programs.length === 0 || index < 0)
            return
        var nextPrograms = programs.slice(0)
        var program = nextPrograms[selectedProgramIndex]
        var bends = cloneBends(program.bends || [])
        if (index >= bends.length)
            return
        var removed = bends.splice(index, 1)[0]
        nextPrograms[selectedProgramIndex] = Object.assign({}, program, { name: program.name || activeProgram, source: program.source || "qml", bends: bends, cadPreviewJson: program.cadPreviewJson || activeProgramCadPreviewJson, updatedAt: programTimestamp() })
        programs = nextPrograms
        selectedRunBend = Math.min(index, bends.length - 1)
        syncActiveProgramState()
        enforceBendModeForProgram()
        recordSandboxWrite("program-bends", "delete", removed.name || ("Bend " + String(index + 1)))
        showAlarm("DELETE PROGRAM BEND", "Delete requested for " + (removed.name || "bend") + ". Stored as sandbox action only.")
    }

    function formatNumber(value, digits, fallback) {
        if (value === undefined || value === null || isNaN(Number(value)))
            return fallback || "0"
        return Number(value).toFixed(digits)
    }

    function fileNameFromUrl(fileUrl) {
        var value = String(fileUrl || "")
        var slash = Math.max(value.lastIndexOf("/"), value.lastIndexOf("\\"))
        var name = slash >= 0 ? value.substring(slash + 1) : value
        try { name = decodeURIComponent(name) } catch (error) {}
        return name
    }

    function fileNameWithoutExtension(name) {
        var trimmed = String(name || "").trim()
        if (trimmed.length === 0)
            return "Imported Part"
        var dot = trimmed.lastIndexOf(".")
        return dot > 0 ? trimmed.substring(0, dot) : trimmed
    }

    function readableFileUrl(fileUrl) {
        var value = String(fileUrl || "")
        try {
            if (value.indexOf("%") !== -1)
                value = decodeURI(value)
        } catch (e) {}
        if (/^[A-Za-z]:[\\/]/.test(value))
            return encodeURI("file:///" + value.replace(/\\/g, "/"))
        if (value.indexOf("file:") === 0 || value.indexOf("qrc:") === 0)
            return encodeURI(value)
        if (value.indexOf("/") === 0)
            return encodeURI("file://" + value)
        return encodeURI(value)
    }

    function valueOr(object, key, fallback) {
        return object && object[key] !== undefined && object[key] !== null ? object[key] : fallback
    }

    function finiteNumber(value, fallback) {
        var number = Number(value)
        return isFinite(number) ? number : fallback
    }

    function findClosestMaterial(materialName, materials) {
        if (!materials || materials.length === 0)
            return null
        function normalizeMaterialName(value) {
            return String(value || "").toLowerCase()
                .replace(/[^a-z0-9]+/g, " ").replace(/\s+/g, " ").trim()
        }
        function materialScore(material, targetName) {
            var candidate = normalizeMaterialName(material && material.name)
            var score = material && material.stock === true ? 5 : 0
            if (targetName.length > 0) {
                if (candidate === targetName)
                    score += 1000
                if (candidate.indexOf(targetName) >= 0 || targetName.indexOf(candidate) >= 0)
                    score += 300
                if (targetName.indexOf("stainless") >= 0 && candidate.indexOf("stainless") >= 0)
                    score += 250
                if (targetName.indexOf("aluminum") >= 0 && candidate.indexOf("aluminum") >= 0)
                    score += 250
                if (targetName.indexOf("steel") >= 0 && candidate.indexOf("steel") >= 0)
                    score += 150
                if (targetName.indexOf("steel") >= 0
                        && targetName.indexOf("stainless") < 0
                        && candidate.indexOf("stainless") >= 0)
                    score -= 500
            }
            score -= Math.round(Math.abs(finiteNumber(
                material && material.materialTensileStrengthPsi, cadTensileStrength)
                - cadTensileStrength) / 1000)
            score -= Math.round(Math.abs(finiteNumber(
                material && material.materialSpringback, cadSpringBack)
                - cadSpringBack) * 10)
            return score
        }
        var normalized = normalizeMaterialName(materialName)
        var best = materials[0]
        var bestScore = materialScore(best, normalized)
        for (var i = 0; i < materials.length; i++) {
            var score = materialScore(materials[i], normalized)
            if (score > bestScore) {
                best = materials[i]
                bestScore = score
            }
        }
        return best
    }

    function findById(items, id) {
        if (!items || !id)
            return null
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === id)
                return items[i]
        }
        return null
    }

    function chooseTooling(material, punches, dies, thickness, entry) {
        // 1:1 tooling selection via the ported ToolingPlanningEngine per-bend scorer.
        // Mirrors the Java engine's deterministic penalty model (rule-of-8 opening,
        // predicted radius, profile/angle support, clearance need, preferences).
        var e = entry || {}
        var bendInput = {
            angleDeg: finiteNumber(e.angleValue, finiteNumber(e.angle, 90)),
            lengthIn: finiteNumber(e.widthValue, finiteNumber(e.width, 0)),
            thicknessIn: finiteNumber(thickness, 0),
            chainDepth: finiteNumber(e.chainDepth, 0),
            processBgPositionIn: finiteNumber(e.processBgPosition, 0),
            parentBendId: finiteNumber(e.parentBendId, 0) > 0 ? e.parentBendId : null,
            referenceType: e.refType !== undefined ? e.refType : (e.referenceType !== undefined ? e.referenceType : null),
            thicknessLabel: e.thicknessLabel !== undefined ? e.thicknessLabel : null
        }
        var selection = ToolingEngine.selectToolingForBend(material, bendInput, punches, dies)
        if (selection)
            return { punch: selection.punch, die: selection.die, warnings: selection.warnings }
        // Fallback (insufficient data): first available tooling.
        return {
            punch: punches && punches.length > 0 ? punches[0] : null,
            die: dies && dies.length > 0 ? dies[0] : null,
            warnings: []
        }
    }

    function copyCadRow(row) {
        var copy = {}
        for (var key in row)
            copy[key] = row[key]
        copy.errors = row.errors ? row.errors.slice(0) : []
        copy.warnings = row.warnings ? row.warnings.slice(0) : []
        copy.notes = row.notes ? row.notes.slice(0) : []
        copy.punchSegmentWidths = row.punchSegmentWidths
            ? row.punchSegmentWidths.slice(0) : []
        copy.dieSegmentWidths = row.dieSegmentWidths
            ? row.dieSegmentWidths.slice(0) : []
        return copy
    }

    function applyCadAssignedSegmentPlan(rows) {
        var plan = ToolingEngine.assignedSegmentPlan(
            rows, cadPunchCatalog, cadDieCatalog, punchCoverageSideToleranceIn)
        var recommendationById = ({})
        for (var recommendationIndex = 0;
                recommendationIndex < plan.recommendations.length; recommendationIndex++) {
            var recommendation = plan.recommendations[recommendationIndex]
            recommendationById[String(recommendation.bendId)] = recommendation
        }
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
            var row = rows[rowIndex]
            var rowRecommendation = recommendationById[String(row.id)]
            if (!rowRecommendation)
                continue
            var phase = plan.phases[rowRecommendation.phaseIndex]
            row.toolingPhaseIndex = rowRecommendation.phaseIndex
            row.punchSegmentWidths = phase.punchWidths.slice(0)
            row.dieSegmentWidths = phase.dieWidths.slice(0)
            row.punchSegmentStartIn = phase.punchStartIn
            row.dieSegmentStartIn = phase.dieStartIn
            row.toolingRackIndex = phase.rackIndex
            row.toolingStationOffsetIn = phase.stationOffsetIn
            row.toolingBendCenterIn = null
            row.toolingCoStations = JSON.parse(JSON.stringify(phase.coStations || []))
            UnfoldPlan.orderLayoutLargestOutward(row, "punchSegmentWidths", "punchSegmentStartIn")
            UnfoldPlan.orderLayoutLargestOutward(row, "dieSegmentWidths", "dieSegmentStartIn")
            row.punchInventoryShortage = phase.punchInventoryShortage
            row.dieInventoryShortage = phase.dieInventoryShortage
            row.punchUnsupported = phase.punchUnsupported
            row.dieUnsupported = phase.dieUnsupported
            row.chg = rowRecommendation.changeLabel
            while (row.notes.length < 5)
                row.notes.push("")
            row.notes[4] = "Tooling change: " + row.chg
        }
        return rows
    }

    // Catalog punch outline (same DXF the Run canvas draws) for sequencing
    // collision checks. Cached per file; null falls back to a generic envelope.
    property var cadPunchSilhouetteCache: ({})
    function cadPunchSilhouette(punchToken) {
        var file = ToolingEngine.punchDxfFileForId(punchToken)
        if (file.length === 0)
            return null
        if (cadPunchSilhouetteCache[file] !== undefined)
            return cadPunchSilhouetteCache[file]
        var silhouette = ToolingEngine.punchSilhouetteFromDxf(cadToolDxfText("Punches", file))
        cadPunchSilhouetteCache[file] = silhouette
        if (!silhouette)
            log("CAD IMPORT", "Punch outline not found for " + file + "; using generic envelope")
        return silhouette
    }

    function cadToolDxfText(folder, file) {
        if (!file)
            return ""
        var relative = "../../assets/" + folder + "/" + file
        var text = ""
        try {
            if (typeof fileIo !== "undefined" && fileIo !== null && typeof fileIo.appDir === "function") {
                var packaged = fileIo.appDir() + "/assets/" + folder + "/" + file
                if (typeof fileIo.exists !== "function" || fileIo.exists(packaged))
                    text = fileIo.read(packaged) || ""
            }
        } catch (ioError) {}
        if (!text) {
            try {
                var xhr = new XMLHttpRequest()
                xhr.open("GET", Qt.resolvedUrl(relative), false)
                xhr.send()
                if (xhr.status === 0 || (xhr.status >= 200 && xhr.status < 300))
                    text = xhr.responseText || ""
            } catch (xhrError) {}
        }
        return text
    }

    function orderCadBendsForSetupReuse(rows) {
        return ToolingEngine.orderBendsForSetupReuse(rows)
    }

    // unfold (PC only) plans with 3D meshes; the press uses the embedded plan.
    // Operator "RE-RUN 3D PLANNER": replans the loaded file ignoring the cache
    // and any embedded plan (e.g. after tooling/material changes).
    function rerunCadUnfoldPlan() {
        if (!cadUnfoldFileUrl || cadUnfoldState === "planning")
            return false
        log("CAD PLAN", "Re-running 3D planner (cache bypassed)")
        cadForcedOrderTemplates = cadManualSequenceOverride ? cadOrderTemplates(cadBends) : null
        return requestCadUnfoldPlan(cadUnfoldFileUrl, true)
    }

    // Planner operation templates fixing the current row order (each stroke
    // requires the previous one done). null when rows lack planner stages.
    function cadOrderTemplates(rows) {
        if (!cadUnfoldPlan || !Array.isArray(cadUnfoldPlan.stages))
            return null
        var byId = ({})
        for (var s = 0; s < cadUnfoldPlan.stages.length; s++)
            byId[cadUnfoldPlan.stages[s].id] = cadUnfoldPlan.stages[s]
        var templates = [], previous = null
        for (var i = 0; i < rows.length; i++) {
            var stage = byId[rows[i].unfoldStageId]
            if (!stage)
                return null
            var rel = stage.relationId || stage.bendId
            var t = { operationId: stage.id, bendId: rel,
                      fromAmount: Number(stage.from[stage.bendId]) || 0,
                      toAmount: Number(stage.to[stage.bendId]) || 1 }
            if (previous) {
                t.requires = ({})
                t.requires[previous.bendId] = previous.toAmount
            }
            templates.push(t)
            previous = t
        }
        return templates
    }

    // Manual order: re-plan tooling/stations for exactly this order (the
    // suggested plan's tooling is only valid for the suggested order).
    function requestCadForcedOrderPlan() {
        if (!cadUnfoldPlannerAvailable || !cadUnfoldFileUrl)
            return false
        cadForcedOrderTimer.restart()
        return true
    }

    function startCadForcedOrderPlan() {
        if (!cadUnfoldPlannerAvailable || !cadUnfoldFileUrl)
            return false
        var templates = cadOrderTemplates(cadBends)
        if (!templates)
            return false
        cadForcedOrderTemplates = templates
        log("CAD PLAN", "Planning tooling for manual order "
            + templates.map(function(t) { return t.operationId.split(":")[0] }).join(" "))
        return requestCadUnfoldPlan(cadUnfoldFileUrl, true)
    }

    function requestCadUnfoldPlan(fileUrl, force) {
        if (!cadUnfoldPlannerAvailable) {
            cadUnfoldState = "unavailable"
            log("CAD PLAN", "3D planner unavailable: " + (typeof unfoldPlanner !== "undefined" && unfoldPlanner
                ? unfoldPlanner.unavailableReason() : "not built in"))
            return false
        }
        cadUnfoldState = "planning"
        cadUnfoldFileUrl = String(fileUrl)
        cadUnfoldRequestId = String(Date.now()) + ":" + String(fileUrl)
        cadStatusMessage = "Planning 3D collision-free sequence..."
        var request = cadUnfoldPlanRequest()
        cadUnfoldRequestKey = request.key
        log("CAD PLAN", "Planner engine: " + unfoldPlanner.engineLabel)
        return unfoldPlanner.start(String(fileUrl), cadUnfoldRequestId, request.preference, force === true)
    }

    // Planner request: dies/punches are pre-filtered by the CAD sheet-metal rule
    // (inside radius, thickness, angle); the Material > thickness preference is
    // planned first only when it matches that design, then up to 3 alternatives.
    function cadUnfoldPlanRequest() {
        var prefs = ToolingEngine.resolveMaterialPreferences(cadSelectedMaterial, null, cadThicknessValue)
        var preference = ({})
        if (prefs.preferredPunchId)
            preference.preferredPunchId = String(prefs.preferredPunchId)
        if (prefs.preferredDieId)
            preference.preferredDieId = String(prefs.preferredDieId)
        var tensilePsi = finiteNumber(valueOr(cadSelectedMaterial, "materialTensileStrengthPsi", NaN), cadTensileStrength)
        var rule = finiteNumber(valueOr(cadSelectedMaterial, "insideRadiusRuleOfThumb", NaN), NaN)
        var selection = ({ maxPlans: 3 })
        if (rule > 0 && tensilePsi > 0)
            selection.radiusToOpeningRatio = rule * tensilePsi / 60000.0
        if (tensilePsi > 0)
            selection.tensileMpa = tensilePsi * 0.00689476
        preference.toolingSelection = selection
        log("CAD PLAN", "Tooling preference " + (prefs.thicknessOutOfTolerance
                ? "none (thickness " + formatNumber(cadThicknessValue, 4, "0") + " in outside profile tolerance)"
                : (prefs.thicknessLabel || "-")) + ": punch="
            + (preference.preferredPunchId || "auto") + " die=" + (preference.preferredDieId || "auto")
            + " r/V=" + (selection.radiusToOpeningRatio ? selection.radiusToOpeningRatio.toFixed(3) : "default"))
        var orderKey = ""
        if (cadForcedOrderTemplates && cadForcedOrderTemplates.length > 0) {
            preference.operationTemplates = cadForcedOrderTemplates
            orderKey = "|order:" + cadForcedOrderTemplates.map(function(t) { return t.operationId }).join(",")
            // Several strokes on one CAD bend (7S1/7): the plan used the
            // split-hinge model, so the replan must import the same model.
            var bendNumbers = ({})
            for (var ti = 0; ti < cadForcedOrderTemplates.length; ti++) {
                var number = String(cadForcedOrderTemplates[ti].bendId).split(":")[0]
                if (bendNumbers[number])
                    preference.splitHinges = true
                bendNumbers[number] = true
            }
            // Tooling setups accepted by the previous plan are verified first.
            var seeds = [], seen = ({})
            var stages = cadUnfoldPlanFull && Array.isArray(cadUnfoldPlanFull.stages) ? cadUnfoldPlanFull.stages : []
            for (var s = 0; s < stages.length; s++) {
                if (!stages[s].config)
                    continue
                var config = Object.assign({}, stages[s].config)
                delete config.flip
                var configKey = JSON.stringify(config)
                if (seen[configKey])
                    continue
                seen[configKey] = true
                seeds.push(config)
            }
            if (seeds.length > 0)
                preference.seedSetups = seeds
        }
        preference.punchCoverageSideToleranceIn = punchCoverageSideToleranceIn
        // Same key format as the Fusion add-in embeds: a mismatch forces a replan.
        return { preference: preference,
                 key: "tooling-v1|" + (preference.preferredPunchId || "") + "|" + (preference.preferredDieId || "") + orderKey }
    }

    function cadEmbeddedPlanIsCurrent(plan) {
        if (!plan || !Array.isArray(plan.stages))
            return false
        if (!plan.planRequestKey)
            return true
        var current = cadUnfoldPlanRequest().key
        if (plan.planRequestKey === current)
            return true
        log("CAD PLAN", "Embedded plan tooling key " + plan.planRequestKey + " != " + current + " - replanning")
        return false
    }

    function selectCadToolingAlternative(index) {
        // Swap on the full plan when available so the chosen alternative keeps
        // its transfers, access paths and validations.
        var full = cadUnfoldPlanFull ? UnfoldPlan.selectAlternative(cadUnfoldPlanFull, index) : null
        var next = full ? UnfoldPlan.compactPlan(full) : UnfoldPlan.selectAlternative(cadUnfoldPlan, index)
        if (!next)
            return false
        if (!applyCadUnfoldPlan(next, full))
            return false
        embedCadUnfoldPlan(full || next)
        log("CAD PLAN", "Operator selected tooling alternative " + index)
        return true
    }

    // Persist the PC-computed plan into the .bend so the press (no unfold) reuses it.
    function embedCadUnfoldPlan(plan) {
        if (!cadUnfoldFileUrl || typeof fileIo === "undefined" || fileIo === null)
            return false
        try {
            var json = JSON.parse(fileIo.read(cadUnfoldFileUrl))
            json.unfoldPlan = plan
            // Keep the file's own format: compressed .bend stays compressed.
            var ok = fileIo.isCompressed(cadUnfoldFileUrl)
                    ? fileIo.writeCompressed(cadUnfoldFileUrl, JSON.stringify(json))
                    : fileIo.write(cadUnfoldFileUrl, JSON.stringify(json, null, 2))
            log("CAD PLAN", ok ? "3D plan embedded in .bend" : "Could not embed 3D plan in .bend")
            return ok
        } catch (error) {
            log("CAD PLAN", "Embed failed: " + String(error))
            return false
        }
    }

    function cadDieSilhouette(token, profiles) {
        var file = ToolingEngine.dieDxfFileForId(token)
        if (!file)
            return null
        if (profiles && Object.prototype.hasOwnProperty.call(profiles, file))
            return profiles[file]
        var text = cadToolDxfText("Dies", file)
        var silhouette = text ? ToolingEngine.dieSilhouetteFromDxf(text) : null
        if (profiles)
            profiles[file] = silhouette
        return silhouette
    }

    function cadApplyUnfoldTooling(row, profiles) {
        var punch = findById(cadPunchCatalog, row.unfoldPunchId || "")
        var die = findById(cadDieCatalog, row.unfoldDieId || "")
        if (punch) {
            row.punchId = punch.id
            row.punchName = punch.name
            row.punch = punchLabel(punch.name)
            row.punchSilhouette = cadPunchSilhouette(punch.id)
        }
        // Co-station tokens are planner ids (press catalog: UUIDs); the 3D DXF
        // lookup needs the catalog label with its [vendor code].
        var co = row.toolingCoStations || []
        for (var c = 0; c < co.length; c++) {
            var coPunch = findById(cadPunchCatalog, co[c].punchToken || "")
            if (coPunch)
                co[c].punchToken = coPunch.name
        }
        if (die) {
            row.dieId = die.id
            row.dieName = die.name
            row.die = die.name
            row.vdieValue = finiteNumber(die.vdieOpeningInch, row.vdieValue)
            row.vdie = dieLabel(die.name, row.vdieValue)
            row.dieSilhouette = cadDieSilhouette(die.id, profiles)
        }
        row.tonnageValue = row.vdieValue > 0
            ? Math.pow(cadThicknessValue * 25.4, 2.0) * cadTensileStrength
                * 1.099644E-6 * row.widthValue / row.vdieValue : 0
        row.tonnage = formatNumber(row.tonnageValue, 3, "0.000")
        row.warnings = row.warnings.filter(function(w) {
            return w !== "Formed flange may hit the punch in this order"
        })
        if (!punch || !die)
            row.warnings.push("Planned tooling not in catalog: "
                              + (punch ? row.unfoldDieId : row.unfoldPunchId))
        row.status = row.errors.length > 0 ? "ERROR" : (row.warnings.length > 0 ? "WARN" : "OK")
        while (row.notes.length < 5)
            row.notes.push("")
        row.notes[2] = "Suggested punch: " + row.punchName
        row.notes[3] = "Suggested die: " + row.dieName
        row.notes[4] = "Tooling change: " + row.chg
        return row
    }

    function applyCadUnfoldPlan(plan, full, sourceRows, profiles) {
        var base = sourceRows || cadBends
        var mapped = UnfoldPlan.stageRows(base, plan, copyCadRow)
        if (mapped.error.length > 0) {
            if (sourceRows)
                return false  // The normal import builds the fallback and reports the mapping error.
            cadUnfoldState = "failed"
            cadStatusMessage = "3D plan rejected (" + mapped.error + ") - heuristic order kept"
            log("CAD PLAN", cadStatusMessage)
            return false
        }
        var rows = mapped.rows
        profiles = profiles || ({})
        var ids = []
        var errorCount = 0
        for (var r = 0; r < rows.length; r++) {
            rows[r].seq = r + 1
            rows[r].fix = rows[r].locked ? "LOCK" : "AUTO"
            cadApplyUnfoldTooling(rows[r], profiles)
            ids.push(rows[r].id)
            errorCount += rows[r].errors.length > 0 ? 1 : 0
        }
        cadUnfoldPlanFull = full || null
        cadUnfoldPlan = plan
        var forced = !!(cadForcedOrderTemplates && cadForcedOrderTemplates.length > 0)
        cadForcedOrderTemplates = null
        if (!forced)
            cadSuggestedOrderIds = ids
        cadManualSequenceOverride = forced
        cadBends = rows
        cadBendCount = rows.length
        cadHasErrors = errorCount > 0
        updateCadPreviewExecutionOrder()
        var verified = plan.completeGeometricRouteSampleClear
        cadStatusMessage = "3D plan: " + rows.length + " strokes"
            + (verified ? ", collision-free route" : ", NOT fully verified (" + plan.status + ")")
            + (plan.backgaugeSampleClear ? "" : ", review backgauge")
            + (plan.toolingPreference
               ? (plan.toolingPreference.applied ? ", preferred tooling"
                  : ", preferred tooling not viable (" + ((plan.toolingPreference.preferredResult || {}).status || "?")
                    + "), best tooling used")
               : "")
            + (plan.toolingSelection
               ? (plan.toolingSelection.designMatch
                  ? ", " + plan.toolingSelection.alternatives.filter(function(a) { return a.clear }).length
                    + " tooling option(s) for R" + Number(plan.toolingSelection.designInsideRadiusMm).toFixed(2) + " mm"
                  : ", no tooling reproduces design R" + Number(plan.toolingSelection.designInsideRadiusMm).toFixed(2)
                    + " mm - flat pattern may not match")
               : "")
            + (errorCount > 0 ? ", " + errorCount + " with errors" : "")
        log("CAD PLAN", cadStatusMessage + " order " + ids.join(" "))
        cadUnfoldState = "applied"
        return true
    }

    // Plan tooling/stations stay valid only while the planned order is kept.
    function cadRowsFollowUnfoldPlan(rows) {
        if (!cadUnfoldPlan || rows.length !== cadUnfoldPlan.stages.length)
            return false
        for (var i = 0; i < rows.length; i++)
            if (rows[i].unfoldStageId !== cadUnfoldPlan.stages[i].id)
                return false
        return true
    }

    function updateCadPreviewExecutionOrder() {
        if (!cadLoadedJson || typeof cadLoadedJson !== "object")
            return
        var source = cadLoadedJson
        // Geometry and STEP stay read-only when the operator reorders strokes.
        var preview = Object.assign({}, source)
        var bendsById = ({})
        for (var sourceIndex = 0; preview.bends && sourceIndex < preview.bends.length; sourceIndex++)
            bendsById[String(preview.bends[sourceIndex].id)] = Object.assign({}, preview.bends[sourceIndex])
        var ordered = []
        var partialRows = 0
        for (var rowIndex = 0; rowIndex < cadBends.length; rowIndex++) {
            var row = cadBends[rowIndex]
            // A pre-bend stroke has no own preview bend: the source bend keeps
            // its final stroke's sequence; stagePlan carries the fold progress.
            if (row.partialOf !== undefined) {
                partialRows++
                continue
            }
            var bend = bendsById[String(row.id)]
            if (!bend)
                continue
            bend.sequence = rowIndex + 1
            bend.sequenceHint = rowIndex + 1
            bend.direction = row.dir
            bend.angle_deg = row.angleValue
            bend.bgRPosition_in = row.bgrValue
            ordered.push(bend)
        }
        if (ordered.length + partialRows !== cadBends.length)
            throw new Error("CAD bend order could not be synchronized by bend id")
        preview.bends = ordered
        var stagePlan = UnfoldPlan.previewStagePlan(cadBends)
        if (stagePlan.length > 0 && cadUnfoldPlan) {
            preview.stagePlan = stagePlan
            preview.unfoldPlan = cadUnfoldPlan
        } else {
            delete preview.stagePlan
            delete preview.unfoldPlan
        }
        var graph = preview.sheetMetalGraph
        if (graph && Number(graph.schemaVersion) >= 5 && graph.bendEdges) {
            graph = Object.assign({}, graph, { bendEdges: graph.bendEdges.slice() })
            preview.sheetMetalGraph = graph
            var sequenceById = ({})
            for (var orderedIndex = 0; orderedIndex < ordered.length; orderedIndex++)
                sequenceById[String(ordered[orderedIndex].id)] = ordered[orderedIndex].sequence
            for (var edgeIndex = 0; edgeIndex < graph.bendEdges.length; edgeIndex++) {
                var edge = graph.bendEdges[edgeIndex]
                var sequence = sequenceById[String(edge.sourceBendId)]
                if (sequence !== undefined)
                    graph.bendEdges[edgeIndex] = Object.assign({}, edge, { sequenceHint: sequence })
            }
        }
        cadLoadedJson = preview
    }

    function isDeclaredSchemaV5(payload) {
        if (!payload)
            return false
        var topologyVersion = parseFloat(String(payload.topologySchemaVersion || 0))
        var graphVersion = payload.sheetMetalGraph
                ? Number(payload.sheetMetalGraph.schemaVersion || 0) : 0
        return topologyVersion >= 5 || graphVersion >= 5
    }

    function validateCadSchemaV5(payload) {
        if (!isDeclaredSchemaV5(payload))
            return ""
        if (!payload.sheetMetalGraph)
            return "missing-sheet-metal-graph"
        return SheetMetalPoseGraph.validateAuthoritativePreview(
            payload,
            "com.bendcnc.export",
            "1.1.0",
            acceptedCadExporterRevisions)
    }

    // Must match GENERATOR_REVISION in fusion360-addin/BendCNCExport.py.
    readonly property string currentCadExporterRevision: "2026-08-06-compound-operation-relations-v5"
    readonly property var acceptedCadExporterRevisions: [currentCadExporterRevision,
                                                         "2026-08-03-cyclic-loop-graph-v4"]
    // Header metadata only; keyed by length + head so the large preview
    // strings are parsed once per load, not every time the menu opens.
    property var cadExportHeaderCache: ({})

    function cadExportHeader(cadPreviewJson) {
        var key = cadPreviewJson.length + ":" + cadPreviewJson.substring(0, 640)
        var cached = cadExportHeaderCache[key]
        if (cached)
            return cached
        var header = { parsed: false, schemaV5: false, topologyVersion: "", revision: "" }
        try {
            var payload = JSON.parse(cadPreviewJson)
            var graphVersion = payload.sheetMetalGraph ? payload.sheetMetalGraph.schemaVersion : ""
            header = {
                parsed: true,
                schemaV5: isDeclaredSchemaV5(payload),
                topologyVersion: String(payload.topologySchemaVersion || graphVersion || ""),
                revision: payload.generator ? String(payload.generator.revision || "") : ""
            }
        } catch (error) {
        }
        cadExportHeaderCache[key] = header
        return header
    }

    // Worst problem wins: unreadable/legacy topology, then bends saved
    // without width (zero tonnage/springback, see canonicalCadProgramBend),
    // then an older exporter revision.
    function programCompatibility(program) {
        var cadPreviewJson = program ? String(program.cadPreviewJson || "") : ""
        if (cadPreviewJson.length === 0)
            return { status: "manual", label: "MANUAL", detail: "Manual program, no CAD export" }
        var header = cadExportHeader(cadPreviewJson)
        if (!header.parsed)
            return { status: "invalid", label: "CAD ERROR", detail: "CAD export data cannot be read" }
        if (!header.schemaV5) {
            var major = Math.floor(parseFloat(header.topologyVersion) || 0)
            return { status: "legacy", label: "LEGACY V" + (major > 0 ? major : "?"),
                     detail: "Topology schema " + (header.topologyVersion || "unknown")
                             + "; re-export with the current Fusion add-in" }
        }
        var zeroWidthBends = 0
        var bends = program.bends || []
        for (var index = 0; index < bends.length; index++) {
            if (finiteNumber(valueOr(bends[index], "bendWidth", valueOr(bends[index], "width", 0)), 0) <= 0)
                zeroWidthBends++
        }
        if (zeroWidthBends > 0)
            return { status: "degraded", label: "REGENERATE",
                     detail: zeroWidthBends + " bend(s) without width or springback; regenerate from CAD" }
        if (header.revision !== currentCadExporterRevision)
            return { status: "old-revision", label: "REGENERATE",
                     detail: "Exporter revision " + (header.revision || "unknown") }
        return { status: "current", label: "", detail: "Current Fusion exporter revision" }
    }

    function recalculateCadOrder() {
        var rows = []
        var errorCount = 0
        var warningCount = 0
        for (var index = 0; index < cadBends.length; index++) {
            var entry = copyCadRow(cadBends[index])
            entry.seq = index + 1
            entry.fix = entry.locked ? "LOCK" : "AUTO"
            entry.setup = determineSuggestedSetup(entry)
            entry.setupLabel = setupLabel(entry.setup)
            var tooling = chooseTooling(cadSelectedMaterial, cadPunchCatalog,
                                        cadDieCatalog, cadThicknessValue, entry)
            entry.punchName = tooling.punch ? tooling.punch.name : "No punch"
            entry.dieName = tooling.die ? tooling.die.name : "No die"
            entry.punchId = tooling.punch ? tooling.punch.id : ""
            entry.dieId = tooling.die ? tooling.die.id : ""
            if (tooling.die)
                entry.vdieValue = finiteNumber(tooling.die.vdieOpeningInch, entry.vdieValue)
            entry.punch = punchLabel(entry.punchName)
            entry.die = entry.dieName
            entry.vdie = dieLabel(entry.dieName, entry.vdieValue)
            entry.tonnageValue = entry.vdieValue > 0
                ? Math.pow(cadThicknessValue * 25.4, 2.0) * cadTensileStrength
                    * 1.099644E-6 * entry.widthValue / entry.vdieValue : 0
            entry.tonnage = formatNumber(entry.tonnageValue, 3, "0.000")
            var validation = validateCadEntry(entry, tooling.warnings || [])
            entry.errors = validation.errors
            entry.warnings = validation.warnings
            entry.status = entry.errors.length > 0 ? "ERROR"
                : (entry.warnings.length > 0 ? "WARN" : "OK")
            var stageNotes = entry.notes.slice(5)
            entry.notes = [
                entry.ref === "EDGE"
                    ? "Back gauge references blank edge with " + entry.bg + "\" offset"
                    : "Back gauge references bend " + entry.parentBendId + " with " + entry.bg + "\" offset",
                "Suggested setup: " + entry.setup,
                "Suggested punch: " + entry.punchName,
                "Suggested die: " + entry.dieName,
                "Tooling change: " + entry.chg
            ].concat(stageNotes)
            errorCount += entry.errors.length > 0 ? 1 : 0
            warningCount += entry.warnings.length > 0 ? 1 : 0
            rows.push(entry)
        }
        if (cadRowsFollowUnfoldPlan(rows)) {
            for (var planIndex = 0; planIndex < rows.length; planIndex++)
                cadApplyUnfoldTooling(rows[planIndex])
        } else {
            // Manual order: keep each stroke's planner placement and fold
            // delta for the 3D preview, re-accumulated in the new order.
            // Each stroke also keeps its planner tooling/station: the part
            // placement (placementOrigin at stationYmm) is only valid with
            // that station; the heuristic stack would shift notched bends.
            if (UnfoldPlan.resequenceStageRows(rows)) {
                for (var keepIndex = 0; keepIndex < rows.length; keepIndex++) {
                    var kept = rows[keepIndex], prior = keepIndex > 0 ? rows[keepIndex - 1] : null
                    cadApplyUnfoldTooling(kept)
                    kept.chg = !prior ? "START"
                        : (prior.toolingRackIndex !== kept.toolingRackIndex ? "CHANGE"
                           : (Math.abs(finiteNumber(prior.toolingStationOffsetIn, 0)
                                       - finiteNumber(kept.toolingStationOffsetIn, 0)) > 1e-6 ? "STATION" : "SAME"))
                    if (kept.notes.length > 4)
                        kept.notes[4] = "Tooling change: " + kept.chg
                }
            } else {
                for (var dropIndex = 0; dropIndex < rows.length; dropIndex++)
                    delete rows[dropIndex].unfoldFrom
                rows = applyCadAssignedSegmentPlan(rows)
            }
        }
        cadBends = rows
        cadBendCount = rows.length
        cadHasErrors = errorCount > 0
        var lockedCount = 0
        for (var lockIndex = 0; lockIndex < rows.length; lockIndex++)
            lockedCount += rows[lockIndex].locked ? 1 : 0
        cadStatusMessage = "Loaded " + rows.length + " bends - "
            + (lockedCount > 0 ? lockedCount + " locked, current order preserved"
                               : "automatic order")
            + (errorCount > 0 ? ", " + errorCount + " with errors"
                              : (warningCount > 0 ? ", " + warningCount + " with warnings"
                                                  : ", ready to generate"))
        updateCadPreviewExecutionOrder()
    }

    function moveCadBend(fromIndex, toIndex) {
        if (fromIndex < 0 || fromIndex >= cadBends.length
                || toIndex < 0 || toIndex >= cadBends.length
                || fromIndex === toIndex)
            return false
        var rows = []
        for (var index = 0; index < cadBends.length; index++)
            rows.push(copyCadRow(cadBends[index]))
        var moved = rows.splice(fromIndex, 1)[0]
        moved.locked = true
        rows.splice(toIndex, 0, moved)
        cadBends = rows
        cadManualSequenceOverride = true
        recalculateCadOrder()
        log("CAD IMPORT", "Moved bend " + String(moved.id) + " from "
            + String(fromIndex + 1) + " to " + String(toIndex + 1))
        requestCadForcedOrderPlan()
        return true
    }

    function cadOrderDiffersFromSuggested() {
        if (!cadSuggestedOrderIds || cadSuggestedOrderIds.length !== cadBends.length)
            return cadBends.length > 0
        for (var index = 0; index < cadBends.length; index++) {
            if (String(cadBends[index].id) !== String(cadSuggestedOrderIds[index]))
                return true
        }
        return false
    }

    function restoreCadSuggestedOrder() {
        if (!cadSuggestedOrderIds || cadSuggestedOrderIds.length !== cadBends.length)
            return false
        var rowsById = ({})
        for (var index = 0; index < cadBends.length; index++)
            rowsById[String(cadBends[index].id)] = copyCadRow(cadBends[index])
        var restored = []
        for (var orderIndex = 0; orderIndex < cadSuggestedOrderIds.length; orderIndex++) {
            var row = rowsById[String(cadSuggestedOrderIds[orderIndex])]
            if (!row)
                return false
            row.locked = false
            restored.push(row)
        }
        cadBends = restored
        cadManualSequenceOverride = false
        recalculateCadOrder()
        log("CAD IMPORT", "Restored automatic suggested bend order")
        // The current plan may be a manual-order plan: reload the free one (cached).
        if (!cadRowsFollowUnfoldPlan(cadBends) && cadUnfoldPlannerAvailable && cadUnfoldFileUrl
                && cadUnfoldState !== "planning") {
            cadForcedOrderTemplates = null
            requestCadUnfoldPlan(cadUnfoldFileUrl, false)
        }
        return true
    }

    function toggleCadBendLock(index) {
        if (index < 0 || index >= cadBends.length)
            return false
        var rows = []
        for (var rowIndex = 0; rowIndex < cadBends.length; rowIndex++)
            rows.push(copyCadRow(cadBends[rowIndex]))
        rows[index].locked = !rows[index].locked
        cadBends = rows
        cadManualSequenceOverride = cadOrderDiffersFromSuggested()
            || rows.some(function(row) { return row.locked === true })
        recalculateCadOrder()
        return true
    }

    function updateCadBendR(index, value) {
        if (index < 0 || index >= cadBends.length)
            return false
        var normalized = String(value).trim()
        if (normalized.length === 0)
            return false
        var parsed = Number(normalized)
        if (!isFinite(parsed))
            return false
        var rows = []
        for (var rowIndex = 0; rowIndex < cadBends.length; rowIndex++)
            rows.push(copyCadRow(cadBends[rowIndex]))
        rows[index].bgrValue = parsed
        rows[index].bgr = formatNumber(parsed, 4, "0.0000")
        rows[index].locked = true
        cadBends = rows
        cadManualSequenceOverride = true
        recalculateCadOrder()
        return true
    }

    function setupLabel(setup) {
        var value = String(setup || "").toLowerCase()
        if (value.indexOf("extended") >= 0)
            return "EXT44"
        if (value.indexOf("follow-on") >= 0)
            return "FOLLOW"
        if (value.indexOf("clearance") >= 0)
            return "CLR"
        return "STD"
    }

    function punchLabel(punchName) {
        var value = String(punchName || "").toLowerCase()
        if (value.indexOf("gooseneck 88") >= 0)
            return "GN88"
        if (value.indexOf("extreme gooseneck") >= 0)
            return "XGN"
        if (value.indexOf("gooseneck") >= 0)
            return "GN"
        if (value.indexOf("standard 35") >= 0)
            return "STD35"
        if (value.indexOf("standard 30") >= 0)
            return "STD30"
        if (value.indexOf("acute") >= 0)
            return "ACUTE"
        return "AUTO"
    }

    function dieLabel(dieName, opening) {
        var value = String(dieName || "").toLowerCase()
        if (value.indexOf("8mm") >= 0)
            return "8mm"
        if (value.indexOf("0.288") >= 0 || value.indexOf("2288") >= 0)
            return "0.288\""
        if (value.indexOf("0.315") >= 0 || value.indexOf("5623") >= 0)
            return "0.315\""
        if (value.indexOf("acute") >= 0)
            return "A " + formatNumber(opening, 3, "0.315") + "\""
        if (value.indexOf("standard 30") >= 0 || value.indexOf("std30") >= 0)
            return "STD30"
        if (value.indexOf("standard 35") >= 0 || value.indexOf("std35") >= 0)
            return "STD35"
        return formatNumber(opening, 3, "0.315") + "\""
    }

    function pointInLoop(loop, x, y) {
        var inside = false
        for (var i = 0, j = loop.length - 1; i < loop.length; j = i++) {
            var xi = Number(loop[i].x_in), yi = Number(loop[i].y_in)
            var xj = Number(loop[j].x_in), yj = Number(loop[j].y_in)
            if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi)
                inside = !inside
        }
        return inside
    }

    function pointInFlatMaterial(boundary, x, y) {
        if (!pointInLoop(boundary.outerLoop, x, y))
            return false
        var holes = boundary.holeLoops || []
        for (var h = 0; h < holes.length; h++)
            if (holes[h] && holes[h].length > 2 && pointInLoop(holes[h], x, y))
                return false
        return true
    }

    // Widest centered punch stack that touches only this bend: past each end
    // of the bend line, the free gap (cutout/relief) before material that
    // crosses the same line would be pressed too. Infinity when the line
    // runs off the part.
    function cadBendPunchWidthCap(json, source, thickness) {
        var boundary = json && json.sheetMetalGraph ? json.sheetMetalGraph.materialBoundary : null
        if (!boundary || !boundary.outerLoop || boundary.outerLoop.length < 3)
            return Infinity
        var x0 = finiteNumber(valueOr(source, "hinge_start_x_in", valueOr(source, "start_x_in", NaN)), NaN)
        var y0 = finiteNumber(valueOr(source, "hinge_start_y_in", valueOr(source, "start_y_in", NaN)), NaN)
        var x1 = finiteNumber(valueOr(source, "hinge_end_x_in", valueOr(source, "end_x_in", NaN)), NaN)
        var y1 = finiteNumber(valueOr(source, "hinge_end_y_in", valueOr(source, "end_y_in", NaN)), NaN)
        var length = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
        if (!isFinite(length) || length <= 0)
            return Infinity
        var ux = (x1 - x0) / length, uy = (y1 - y0) / length
        var off = Math.max(0.02, finiteNumber(thickness, 0.06))
        var step = 0.02, start = 0.05, limit = 40.0
        // Line probes (crossings sorted once) replace per-sample polygon tests.
        var probes = [
            ToolingEngine.lineMaterialProbe(boundary, x0, y0, ux, uy),
            ToolingEngine.lineMaterialProbe(boundary, x0 - uy * off, y0 + ux * off, ux, uy),
            ToolingEngine.lineMaterialProbe(boundary, x0 + uy * off, y0 - ux * off, ux, uy)
        ]
        function materialAt(t) {
            return probes[0](t) || probes[1](t) || probes[2](t)
        }
        // Any material along the line past the bend end (even right at a
        // small relief) would be pressed by a longer stack, so it caps it.
        function gap(t0, sign) {
            for (var d = start; d <= limit; d += step)
                if (materialAt(t0 + sign * d))
                    return Math.max(0, d - step)
            return Infinity
        }
        var gapStart = gap(0, -1)
        var gapEnd = gap(length, 1)
        var side = Math.min(gapStart, gapEnd)
        return isFinite(side) ? length + 2 * side : Infinity
    }

    function determineSuggestedSetup(entry) {
        if (entry.chainDepth > 0)
            return "Follow-on flange setup from bend " + String(entry.parentBendId)
        if (entry.widthValue > 44.0)
            return "Extended segmented 44in setup"
        if (entry.processBgPosition >= 5.0)
            return "Short-center clearance setup"
        return "Standard segmented setup"
    }

    function validateCadEntry(entry, plannerWarnings) {
        var errors = []
        var warnings = []
        if (!isFinite(cadThicknessValue) || cadThicknessValue <= 0)
            errors.push("Material thickness is missing or invalid")
        if (!isFinite(entry.widthValue) || entry.widthValue <= 0)
            errors.push("Bend length is missing or invalid")
        if (entry.tonnageValue > 25.0)
            errors.push("Tonnage " + formatNumber(entry.tonnageValue, 1, "0.0") + "T exceeds machine max 25.0T")
        else if (entry.tonnageValue > 12.5)
            warnings.push("Tonnage " + formatNumber(entry.tonnageValue, 1, "0.0") + "T exceeds single ram 12.5T - ensure centered")
        if (entry.widthValue > 44.0)
            errors.push("Bend width " + formatNumber(entry.widthValue, 2, "0.00") + "\" exceeds segmented tooling span 44\"")
        else if (entry.widthValue > 29.0)
            warnings.push("Bend width " + formatNumber(entry.widthValue, 2, "0.00") + "\" exceeds standard frame width 29\"")
        if (entry.angleValue < 15.0 || entry.angleValue > 170.0)
            errors.push("Bend angle " + formatNumber(entry.angleValue, 1, "0.0") + "° outside valid range 15°-170°")
        for (var i = 0; plannerWarnings && i < plannerWarnings.length; i++)
            warnings.push(plannerWarnings[i])
        return { errors: errors, warnings: warnings }
    }

    function cadLoadFile(fileUrl, punches, dies, materials, userSettings) {
        try {
            var rawText = ""
            if (typeof fileIo !== "undefined" && fileIo && typeof fileIo.read === "function") {
                rawText = fileIo.read(String(fileUrl))
            }
            if (!rawText || rawText.length === 0) {
                var request = new XMLHttpRequest()
                request.open("GET", readableFileUrl(fileUrl), false)
                request.send()
                rawText = request.responseText
            }
            if (!rawText || rawText.length === 0)
                throw new Error("Unable to read CAD file contents from " + String(fileUrl))
            cadLoadSequence++
            cadLoadContext = { requestId: cadLoadSequence, fileUrl: fileUrl, punches: punches,
                               dies: dies, materials: materials, userSettings: userSettings,
                               startedAt: Date.now() }
            cadLoadBusy = true
            setCadLoadProgress(0.05, "Validating part geometry...")
            cadLoadWorker.sendMessage({ requestId: cadLoadSequence, text: rawText,
                                        baseUrl: String(Qt.resolvedUrl("core/")),
                                        acceptedRevisions: acceptedCadExporterRevisions })
            return true
        } catch (error) {
            cadLoadFailed(error)
            return false
        }
    }

    // ---- Staged CAD import: worker thread validates, then the GUI thread
    // builds rows in short steps so the progress overlay keeps repainting.
    signal cadLoadFinished(bool ok)
    property bool cadLoadBusy: false
    property real cadLoadProgress: 0
    property string cadLoadStage: ""
    property int cadLoadSequence: 0
    property var cadLoadContext: null
    property WorkerScript cadLoadWorker: WorkerScript {
        source: "core/CadLoadWorker.js"
        onMessage: function(reply) { appState.cadLoadWorkerReply(reply) }
    }

    function setCadLoadProgress(fraction, stage) {
        cadLoadProgress = fraction
        cadLoadStage = stage
    }

    function cadLoadWorkerReply(reply) {
        var ctx = cadLoadContext
        if (!ctx || reply.requestId !== ctx.requestId)
            return
        log("CAD IMPORT", "Geometry validated in " + String(Date.now() - ctx.startedAt) + " ms (worker)")
        if (reply.error.length > 0) {
            cadLoadFailed(reply.error)
            return
        }
        ctx.json = reply.json
        // Canvases re-validate the same geometry on the GUI thread; hand
        // them the worker's verdict (identical validator source).
        if (isDeclaredSchemaV5(reply.json) && reply.json.sheetMetalGraph)
            SheetMetalPoseGraph.rememberValidation(reply.json, "com.bendcnc.export",
                                                   "1.1.0", acceptedCadExporterRevisions, "")
        setCadLoadProgress(0.35, "Selecting tooling and section model...")
        cadLoadNext(cadLoadStageRows, ctx)
    }

    // Lets the scene graph paint the progress update before the next step.
    function cadLoadNext(step, ctx) {
        Qt.callLater(function() {
            if (cadLoadContext !== ctx)
                return
            try {
                step(ctx)
            } catch (error) {
                cadLoadFailed(error)
            }
        })
    }

    function cadLoadFailed(error) {
        cadLoadBusy = false
        cadLoadContext = null
        setCadLoadProgress(0, "")
        cadImported = false
        cadHasErrors = true
        cadBends = []
        cadBendCount = 0
        cadSuggestedOrderIds = []
        cadStatusMessage = "Error: " + String(error)
        showAlarm("CAD IMPORT FAILED", cadStatusMessage)
        cadLoadFinished(false)
    }

    function cadLoadStageRows(ctx) {
            var json = ctx.json, fileUrl = ctx.fileUrl, punches = ctx.punches, dies = ctx.dies
            var materials = ctx.materials, userSettings = ctx.userSettings
            cadLoadedJson = json
            cadPunchCatalog = punches || []
            cadDieCatalog = dies || []
            cadMaterialCatalog = materials || []
            cadManualSequenceOverride = false
            cadSuggestedOrderIds = []
            var importedFileName = fileNameFromUrl(fileUrl)
            var importedPartName = fileNameWithoutExtension(importedFileName)
            var part = json.part || {}
            var materialJson = json.material || {}
            var flat = json.flatPattern || {}
            cadFileName = importedFileName
            cadPartName = importedPartName
            cadProgramName = importedPartName
            cadMaterial = valueOr(materialJson, "name", valueOr(part, "material", "Unknown"))
            cadThicknessValue = finiteNumber(valueOr(materialJson, "thickness_in", 0), 0)
            cadTensileStrength = finiteNumber(valueOr(materialJson, "tensile_psi", 60000), 60000)
            cadSpringBack = finiteNumber(valueOr(materialJson, "springBack_deg", 0), 0)
            cadKFactor = finiteNumber(valueOr(materialJson, "kFactor", 0.44), 0.44)
            cadFlatWidth = finiteNumber(valueOr(flat, "width_in", 0), 0)
            cadFlatLength = finiteNumber(valueOr(flat, "length_in", 0), 0)
            cadThickness = formatNumber(cadThicknessValue, 4, "0.0000") + " in"
            cadFlatPattern = formatNumber(cadFlatWidth, 3, "0.000") + " x " + formatNumber(cadFlatLength, 3, "0.000") + " in"
            cadLoadedFilePath = String(fileUrl)
            var selectedMaterial = findClosestMaterial(cadMaterial, materials)
            cadSelectedMaterial = selectedMaterial
            var defaultR = userSettings && userSettings.defaultBackGaugeRPositionInch !== undefined ? finiteNumber(userSettings.defaultBackGaugeRPositionInch, -0.25) : -0.25
            var rows = []
            if (!Array.isArray(json.bends))
                throw new Error("No bend operation array was found at the top-level 'bends' field")
            if (json.bends.length === 0)
                throw new Error("The imported file contains no bend operations")
            var sourceBends = json.bends
            var importedIds = ({})
            for (var i = 0; i < sourceBends.length; i++) {
                var source = sourceBends[i] || {}
                var sourceId = valueOr(source, "id", i + 1)
                var id = String(sourceId).trim().length > 0 ? sourceId : i + 1
                if (importedIds[String(id)] === true)
                    throw new Error("Duplicate bend id '" + String(id) + "' is not allowed")
                importedIds[String(id)] = true
                var angle = finiteNumber(valueOr(source, "angle_deg", 90), 90)
                var width = finiteNumber(valueOr(source, "length_in", 0), 0)
                var dist = finiteNumber(valueOr(source, "distanceFromEdge_in", 0), 0)
                var refDistance = finiteNumber(valueOr(source, "referenceDistance_in", dist), dist)
                var chainDepth = finiteNumber(valueOr(source, "chainDepth", 0), 0)
                var sequenceHint = finiteNumber(valueOr(source, "sequenceHint", id), id)
                var entry = {
                    id: id,
                    seq: i + 1,
                    locked: false,
                    angleValue: angle,
                    angle: formatNumber(angle, 1, "90.0"),
                    radius: finiteNumber(valueOr(source, "radius_in", cadThicknessValue), cadThicknessValue),
                    widthValue: width,
                    width: formatNumber(width, 3, "0.000"),
                    distanceFromEdge: dist,
                    referenceDistance: refDistance,
                    processBgPosition: refDistance > 0 ? refDistance : dist,
                    bgrValue: finiteNumber(valueOr(source, "bgRPosition_in", defaultR), defaultR),
                    refType: valueOr(source, "referenceType", "EDGE"),
                    parentBendId: valueOr(source, "parentBendId", 0),
                    chainDepth: chainDepth,
                    sequenceHint: sequenceHint,
                    dir: valueOr(source, "direction", "UP"),
                    axis: valueOr(source, "axis", "X"),
                    closestSide: valueOr(source, "closest_side", "POS"),
                    startXIn: finiteNumber(valueOr(source, "start_x_in", NaN), NaN),
                    startYIn: finiteNumber(valueOr(source, "start_y_in", NaN), NaN),
                    endXIn: finiteNumber(valueOr(source, "end_x_in", NaN), NaN),
                    endYIn: finiteNumber(valueOr(source, "end_y_in", NaN), NaN)
                }
                entry.maxPunchWidthIn = cadBendPunchWidthCap(json, source, cadThicknessValue)
                var tmm = cadThicknessValue * 25.4
                var vdie = cadThicknessValue * 8.0
                entry.vdieValue = vdie > 0 ? vdie : 0.315
                entry.tonnageValue = entry.vdieValue > 0 ? Math.pow(tmm, 2.0) * cadTensileStrength * 1.099644E-6 * width / entry.vdieValue : 0
                entry.setup = determineSuggestedSetup(entry)
                var tooling = chooseTooling(selectedMaterial, punches, dies, cadThicknessValue, entry)
                entry.punchName = tooling.punch ? tooling.punch.name : "No punch"
                entry.dieName = tooling.die ? tooling.die.name : "No die"
                entry.punchId = tooling.punch ? tooling.punch.id : ""
                entry.dieId = tooling.die ? tooling.die.id : ""
                if (tooling.die)
                    entry.vdieValue = finiteNumber(tooling.die.vdieOpeningInch, entry.vdieValue)
                entry.tonnageValue = entry.vdieValue > 0
                    ? Math.pow(tmm, 2.0) * cadTensileStrength
                        * 1.099644E-6 * width / entry.vdieValue : 0
                entry.fix = entry.locked ? "LOCK" : "AUTO"
                entry.tonnage = formatNumber(entry.tonnageValue, 3, "0.000")
                entry.vdie = dieLabel(entry.dieName, entry.vdieValue)
                entry.ref = entry.refType === "PREVIOUS_BEND" && entry.parentBendId > 0 ? "B" + String(entry.parentBendId) : "EDGE"
                entry.setupLabel = setupLabel(entry.setup)
                entry.punch = punchLabel(entry.punchName)
                entry.die = entry.dieName
                entry.chg = i === 0 ? "START" : "SAME"
                entry.bg = formatNumber(entry.processBgPosition, 4, "0.0000")
                entry.bgr = formatNumber(entry.bgrValue, 4, "0.0000")
                var validation = validateCadEntry(entry, [])
                entry.errors = validation.errors
                entry.warnings = validation.warnings
                entry.notes = [
                    entry.ref === "EDGE" ? "Back gauge references blank edge with " + entry.bg + "\" offset" : "Back gauge references bend " + entry.parentBendId + " with " + entry.bg + "\" offset",
                    "Suggested setup: " + entry.setup,
                    "Suggested punch: " + entry.punchName,
                    "Suggested die: " + entry.dieName,
                    "Tooling change: " + entry.chg
                ]
                entry.status = entry.errors.length > 0 ? "ERROR" : (entry.warnings.length > 0 ? "WARN" : "OK")
                rows.push(entry)
            }
            ctx.dieProfiles = ({})
            for (var si = 0; si < rows.length; si++)
            {
                rows[si].punchSilhouette = cadPunchSilhouette(rows[si].punchId || rows[si].punchName)
                rows[si].dieSilhouette = cadDieSilhouette(rows[si].dieId || rows[si].dieName, ctx.dieProfiles)
            }
            ToolingEngine.attachSectionModel(rows,
                json.sheetMetalGraph ? json.sheetMetalGraph.materialBoundary : null)
            ctx.rows = rows
            ctx.importedFileName = importedFileName
            setCadLoadProgress(0.6, "Planning collision-safe bend order...")
            cadLoadNext(cadLoadStageOrder, ctx)
    }

    function cadLoadStageOrder(ctx) {
            // A fully checked, current embedded route already specifies the
            // order, partials, tools, segments and transfers. Map every source
            // bend before accepting it. Keep the heuristic available on failure.
            var embedded = ctx.json.unfoldPlan
            if (embedded && embedded.completeGeometricRouteSampleClear === true
                    && embedded.stages && embedded.stages.length > 0
                    && !(cadForcedOrderTemplates && cadForcedOrderTemplates.length)
                    && cadEmbeddedPlanIsCurrent(embedded)) {
                var full = UnfoldPlan.isCompactPlan(embedded) ? null : embedded
                if (applyCadUnfoldPlan(UnfoldPlan.compactPlan(embedded), full, ctx.rows, ctx.dieProfiles)) {
                    ToolingEngine.setStationPartClearance(Math.max(cadFlatWidth, cadFlatLength))
                    cadUnfoldRequestId = ""
                    cadUnfoldFileUrl = String(ctx.fileUrl)
                    cadImported = true
                    popupVisible = false
                    log("CAD IMPORT", cadStatusMessage + " from " + ctx.importedFileName
                        + " in " + String(Date.now() - ctx.startedAt) + " ms")
                    cadLoadComplete()
                    return
                }
            }
            var rows = orderCadBendsForSetupReuse(ctx.rows)
            var orderedById = ({})
            for (var oi = 0; oi < rows.length; oi++)
                if (rows[oi].partialOf === undefined)
                    orderedById[String(rows[oi].id)] = rows[oi]
            var doneIds = ({})
            for (var ci = 0; ci < rows.length; ci++) {
                if (ToolingEngine.sectionPunchCollision(rows[ci], doneIds, orderedById)) {
                    rows[ci].warnings.push("Formed flange may hit the punch in this order")
                    if (rows[ci].status === "OK")
                        rows[ci].status = "WARN"
                }
                ToolingEngine.markFormed(doneIds, rows[ci])
            }
            ctx.rows = rows
            setCadLoadProgress(0.85, "Assigning tool stations and preview...")
            cadLoadNext(cadLoadStageFinish, ctx)
    }

    function cadLoadStageFinish(ctx) {
            var fileUrl = ctx.fileUrl, importedFileName = ctx.importedFileName, json = ctx.json
            ToolingEngine.setStationPartClearance(Math.max(cadFlatWidth, cadFlatLength))
            var rows = applyCadAssignedSegmentPlan(ctx.rows)
            for (var r = 0; r < rows.length; r++) {
                rows[r].seq = r + 1
                cadSuggestedOrderIds.push(rows[r].id)
            }
            cadBends = rows
            cadBendCount = rows.length
            updateCadPreviewExecutionOrder()
            var errorCount = 0
            for (var e = 0; e < rows.length; e++) {
                if (rows[e].errors.length > 0)
                    errorCount++
            }
            cadHasErrors = errorCount > 0
            cadImported = true
            cadStatusMessage = errorCount > 0
                ? "Loaded " + rows.length + " bends - " + errorCount + " with errors"
                : "Loaded " + rows.length + " bends - ready to generate"
            popupVisible = false
            log("CAD IMPORT", cadStatusMessage + " from " + importedFileName
                + " in " + String(Date.now() - ctx.startedAt) + " ms")
            cadUnfoldPlan = null
            cadUnfoldPlanFull = null
            cadUnfoldRequestId = ""
            cadUnfoldFileUrl = String(fileUrl)
            if (cadEmbeddedPlanIsCurrent(json.unfoldPlan)) {
                // Fusion add-in and V6 Qt embed the full planner output (bendId "3:FACE:...");
                // old Qt files hold only the compact view.
                var embedded = json.unfoldPlan
                var embeddedFull = UnfoldPlan.isCompactPlan(embedded) ? null : embedded
                applyCadUnfoldPlan(UnfoldPlan.compactPlan(embedded), embeddedFull, undefined, ctx.dieProfiles)
            }
            else
                requestCadUnfoldPlan(fileUrl)
            cadLoadComplete()
    }

    function cadLoadComplete() {
        cadLoadBusy = false
        cadLoadContext = null
        setCadLoadProgress(1, "")
        cadLoadFinished(true)
    }

    function bendFromCreateDraft(bendName, bend, punch, die, material, finalPosition, tonnage) {
        var materialName = material && material.name ? material.name : "Material"
        var punchName = punch && punch.name ? punch.name : "Punch"
        var dieName = die && die.name ? die.name : "Die"
        var calculation = calcBendParity(bend || {}, punch, die, material)
        var effectiveFinalPosition = calculation
            ? calculation.inUseFinalBendPosition : Number(finalPosition || 0)
        var effectiveTonnage = calculation ? calculation.bendTonnage : Number(tonnage || 0)
        var result = Object.assign({}, bend || {}, {
            id: valueOr(bend, "id", "bend-" + String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000000))),
            name: bendName || (bend && bend.name) || "Created Bend",
            punchId: punch && punch.id ? punch.id : valueOr(bend, "punchId", ""),
            dieId: die && die.id ? die.id : valueOr(bend, "dieId", ""),
            materialId: material && material.id ? material.id : valueOr(bend, "materialId", ""),
            materialThickness: Number(valueOr(bend, "materialThickness", 0)),
            desiredBendAngle: Number(valueOr(bend, "desiredBendAngle", 90)),
            angleCompensation: Number(valueOr(bend, "angleCompensation", 0)),
            angleCompensationReversed: valueOr(bend, "angleCompensationReversed", false) === true,
            punchToMaterialClearance: Number(valueOr(bend, "punchToMaterialClearance", 0.05)),
            additionalRetractAfterBend: Number(valueOr(bend, "additionalRetractAfterBend", 0)),
            bendWidth: Number(valueOr(bend, "bendWidth", 0.1)),
            backGaugeRefEdgeStop: String(valueOr(bend, "backGaugeRefEdgeStop", "G54")),
            backGaugeRefEdgeStopEnabled: valueOr(bend, "backGaugeRefEdgeStopEnabled", false) === true,
            backGaugeXPosition: Number(valueOr(bend, "backGaugeXPosition", 0)),
            backGaugeRPosition: Number(valueOr(bend, "backGaugeRPosition", 0)),
            backGaugeJogSpeed: Number(valueOr(bend, "backGaugeJogSpeed", 100)),
            overrideFinalBendPositionEnabled: valueOr(bend, "overrideFinalBendPositionEnabled", false) === true,
            overriddenFinalBendPosition: Number(valueOr(bend, "overriddenFinalBendPosition", effectiveFinalPosition)),
            xAxisNotes: String(valueOr(bend, "xAxisNotes", "")),
            rAxisNotes: String(valueOr(bend, "rAxisNotes", "")),
            notes: String(valueOr(bend, "notes", "")),
            stock: false,
            angle: formatNumber(bend ? bend.desiredBendAngle : 90, 1, "90.0"),
            compensation: formatNumber(bend ? bend.angleCompensation : 0, 1, "0.0"),
            state: bend && bend.angleCompensationReversed ? "UNDERBENT" : "OVERBENT",
            x: formatNumber(bend ? bend.backGaugeXPosition : 0, 4, "0.0000"),
            r: formatNumber(bend ? bend.backGaugeRPosition : 0, 4, "0.0000"),
            speed: formatNumber(bend ? bend.backGaugeJogSpeed : 100, 3, "100.000"),
            tonnage: formatNumber(effectiveTonnage, 3, "0.000"),
            thickness: formatNumber(bend ? bend.materialThickness : 0, 4, "0.0000"),
            material: materialName,
            punch: punchName,
            die: dieName,
            width: formatNumber(bend ? bend.bendWidth : 0, 3, "0.000"),
            startPosition: formatNumber(calculation ? calculation.startSafetyClearance : effectiveFinalPosition + Number(bend ? bend.punchToMaterialClearance || 0 : 0), 4, "0.0000"),
            clampPosition: formatNumber(calculation ? calculation.clampPosition : effectiveFinalPosition + 0.036, 4, "0.0000"),
            finalPosition: formatNumber(effectiveFinalPosition, 4, "0.0000"),
            retractPosition: formatNumber(calculation ? calculation.retractAfterBend : effectiveFinalPosition + Number(bend ? bend.additionalRetractAfterBend || 0 : 0), 4, "0.0000"),
            totalStroke: formatNumber(calculation ? (calculation.overrideFinalBendPositionEnabled ? calculation.overriddenTotalBendStroke : calculation.totalBendStroke) : 0, 4, "0.0000"),
            predictedInsideBendRadius: formatNumber(calculation ? calculation.predictedInsideBendRadius : 0, 4, "0.0000")
        })
        return result
    }

    function timestamp() {
        var now = new Date()
        return Qt.formatTime(now, "HH:mm:ss")
    }

    function log(scope, message) {
        latestLog = timestamp() + " " + scope + " - " + message
        var next = logEntries.slice(0)
        next.unshift(latestLog)
        if (next.length > 80)
            next.length = 80
        logEntries = next
        console.log(latestLog)
    }

    // Epoch ms when the most recent RUN started (debug report "LAST RUN" scope).
    property double lastRunStartedMs: 0

    function machineLogBody(sinceMs) {
        var lines = []
        var since = Number(sinceMs || 0)
        for (var index = 0; index < machineLogModel.count; index++) {
            var entry = machineLogModel.get(index)
            if (since > 0 && Number(entry.ms || 0) < since)
                continue
            lines.push(entry.formatted)
        }
        return lines.join("\n")
    }

    function appendMachineLog(source, content) {
        var text = String(content === undefined || content === null ? "" : content)
        while (text.length > 0 && (text.charAt(text.length - 1) === "\n"
                                  || text.charAt(text.length - 1) === "\r"))
            text = text.substring(0, text.length - 1)
        if (text.length === 0)
            return false
        var isStatus = text.charAt(0) === "<" && text.charAt(text.length - 1) === ">"
        if (isStatus && !machineLogStatusReportsEnabled)
            return false
        var now = new Date()
        var timestampWithMilliseconds = Qt.formatTime(now, "HH:mm:ss")
            + "." + String(1000 + now.getMilliseconds()).substring(1)
        var normalizedSource = String(source || "MACHINE").toUpperCase()
        var formatted = "[" + timestampWithMilliseconds + "] [" + normalizedSource + "]: " + text
        machineLogModel.append({ ms: now.getTime(),
                                 timestamp: timestampWithMilliseconds,
                                 source: normalizedSource,
                                 content: text,
                                 formatted: formatted })
        while (machineLogModel.count > machineLogMaximumEntries)
            machineLogModel.remove(0)
        return true
    }

    function clearMachineLog() {
        machineLogModel.clear()
    }

    function copyMachineLog() {
        var copied = hostSystem && hostSystem.copyTextToClipboard(machineLogBody())
        if (!copied)
            showAlarm("MACHINE LOG COPY FAILED", hostSystem
                ? String(hostSystem.lastError || "Clipboard unavailable.")
                : "System service unavailable.")
        else
            log("MACHINE LOG", "Copied all entries")
        return copied
    }

    function exportMachineLog() {
        var exported = hostSystem && hostSystem.exportMachineLog(machineLogBody(), "")
        if (!exported)
            showAlarm("MACHINE LOG EXPORT FAILED", hostSystem
                ? String(hostSystem.lastError || "Export failed.")
                : "System service unavailable.")
        else
            showPopup("MACHINE LOG EXPORTED",
                      String(hostSystem.lastResult || "Export complete."),
                      1, "message", "CLOSE")
        return exported
    }

    function inferPopupKind(title, progress) {
        var normalized = String(title || "").toUpperCase()
        if (normalized.indexOf("WIFI") >= 0 || normalized.indexOf("WI-FI") >= 0)
            return "wifi"
        if (normalized.indexOf("INFO") >= 0 || normalized.indexOf("LOG") >= 0 || normalized.indexOf("BACKUPS") >= 0)
            return "info"
        if (normalized.indexOf("WARNING") >= 0 || normalized.indexOf("CAUTION") >= 0 || normalized.indexOf("NOTICE") >= 0)
            return "caution"
        if ((Number(progress) > 0 && Number(progress) < 1)
                || normalized.indexOf("HOMING") >= 0
                || normalized.indexOf("UPDATING") >= 0
                || normalized.indexOf("RESTARTING") >= 0
                || normalized.indexOf("BLEED") >= 0
                || normalized.indexOf("WAITING") >= 0)
            return "blur"
        return "message"
    }

    function showPopup(title, body, progress, kind, buttonText) {
        popupAction = ""
        popupPrimaryHandler = null
        popupCancelHandler = null
        popupImageSource = ""
        popupTitle = title
        popupBody = body
        popupProgress = progress === undefined ? 0 : progress
        popupKind = kind === undefined || String(kind).length === 0 ? inferPopupKind(title, popupProgress) : kind
        popupButtonText = buttonText !== undefined && String(buttonText).length > 0
            ? String(buttonText)
            : (popupKind === "blur" ? "CANCEL" : (popupKind === "caution" ? "OK" : "CLOSE"))
        popupCancelButtonText = "CANCEL"
        popupVisible = true
        log("POPUP", title + ": " + body)
    }

    function showImagePopup(title, body, imageSource) {
        showPopup(title, body, 1, "info", "CLOSE")
        popupImageSource = String(imageSource || "")
    }

    function showCadGenerationResult(saved) {
        var resultRows = []
        for (var index = 0; index < cadBends.length; index++) {
            var bend = cadBends[index]
            resultRows.push({
                seq: bend.seq,
                angle: bend.angle,
                setup: bend.setupLabel,
                tooling: bend.punch + " / " + bend.vdie,
                bg: bend.bg,
                reference: bend.ref,
                status: bend.status
            })
        }
        popupResultData = {
            programName: cadProgramName,
            partName: cadPartName,
            material: cadMaterial,
            thickness: cadThickness,
            bendCount: cadBends.length,
            saved: saved,
            storageLabel: saved ? "SAVED · backup-guarded write" : "SESSION ONLY · not persisted",
            rows: resultRows
        }
        showPopup("BEND PROGRAM READY",
                  saved
                    ? "Program generated and saved safely."
                    : "Program generated in Run, but persistent storage is unavailable.",
                  1, "cad-result", "VIEW IN RUN")
    }

    function hidePopup() {
        popupVisible = false
        popupAction = ""
        popupImageSource = ""
        popupPrimaryHandler = null
        popupCancelHandler = null
        log("POPUP", "Closed")
    }

    function performPopupPrimaryAction() {
        var action = popupAction
        var handler = popupPrimaryHandler
        popupPrimaryHandler = null
        popupCancelHandler = null
        if (handler) {
            hidePopup()
            handler()
            return
        }
        if (action === "back-gauge-home-confirm") {
            startBackGaugeHome()
            return
        }
        if (action === "back-gauge-home-cancel") {
            cancelBackGaugeHome()
            return
        }
        if (action === "press-home-cancel") {
            cancelPressHome()
            return
        }
        hidePopup()
    }

    function cancelPopupAction() {
        var handler = popupCancelHandler
        popupPrimaryHandler = null
        popupCancelHandler = null
        hidePopup()
        if (handler)
            handler()
    }

    // "[LS-BEND v1.3]" -> "BEND 1.3"; falls back to the raw id when unknown.
    function friendlyFirmwareName(expected, fallback) {
        var s = String(expected || "").replace(/[\[\]]/g, "").replace(/LS-/g, "").replace(/\sv(?=\d)/, " ").trim()
        return s.length > 0 ? s : String(fallback || "")
    }

    function showConfirmation(title, body, primaryHandler, cancelHandler) {
        showPopup(title, body, 0, "caution", "YES")
        popupPrimaryHandler = primaryHandler || null
        popupCancelHandler = cancelHandler || null
        popupAction = "confirmation"
    }

    function showAlarm(title, body) {
        alarmTitle = title
        alarmBody = body
        alarmVisible = true
        log("ALARM", title + ": " + body)
    }

    function clearAlarm() {
        alarmVisible = false
        log("ALARM", "Cleared")
    }

    function toolbarAction(action) {
        if (action === "power-off") {
            if (runActive) {
                log("SYSTEM", "Power off rejected: run active")
                return false
            }
            var ok = typeof hostSystem !== "undefined" && hostSystem && hostSystem.powerOff(true)
            log("SYSTEM", ok ? "Power off requested" : "Power off unavailable on this host")
            showPopup(ok ? "SHUTTING DOWN" : "POWER OFF UNAVAILABLE",
                      ok ? "The controller is powering off. Wait for the screen to go dark before cutting main power."
                         : "Software power-off is only available on the Linux controller.",
                      ok ? 0.35 : 1, "message", "CLOSE")
            return ok
        } else if (action === "restart") {
            if (runActive) {
                log("SYSTEM", "Restart rejected: run active")
                return false
            }
            var rebootOk = typeof hostSystem !== "undefined" && hostSystem && hostSystem.reboot(true)
            log("SYSTEM", rebootOk ? "Restart requested" : "Restart unavailable: " + (hostSystem ? hostSystem.lastError : ""))
            showPopup(rebootOk ? "RESTARTING SYSTEM" : "RESTART UNAVAILABLE",
                      rebootOk ? "The controller is restarting."
                               : "Software restart is only available on the Linux controller.",
                      rebootOk ? 0.35 : 1, "message", "CLOSE")
            return rebootOk
        } else if (action === "check-updates") {
            log("UPDATE", "Manual application update check requested")
            if (hostSystem) hostSystem.checkForApplicationUpdates()
            showPopup("CHECKING FOR UPDATES", "Querying the update server. If a newer release exists, UPDATE APP will appear in the toolbar.", 0.35, "message", "CLOSE")
            return true
        } else if (action === "update-app") {
            if (!applicationUpdateAvailable) {
                log("UPDATE", "Application update action rejected: no verified newer release")
                return false
            }
            var notes = String(hostSystem.applicationUpdateNotes || "")
            showConfirmation("UPDATE APP TO " + applicationUpdateVersion,
                      "Installed: " + applicationVersion + "\n\n" + (notes.length > 0 ? notes + "\n\n" : "")
                      + "The update is downloaded, verified and installed. The screen restarts; "
                      + "if the new version fails to start, the previous version is restored.",
                      function() {
                if (runActive || runToolChangeActive) {
                    showPopup("UPDATE BLOCKED", "Stop the run before updating.", 1, "message", "CLOSE")
                    return
                }
                if (!hostSystem.installApplicationUpdate(true))
                    showPopup("UPDATE UNAVAILABLE", String(hostSystem.lastError), 1, "message", "CLOSE")
                else
                    showPopup("UPDATING APPLICATION", "Downloading " + applicationUpdateVersion + "...",
                              0.5, "message", "CLOSE")
            })
        } else if (action === "update-module") {
            if (!moduleUpdateAvailable)
                return false
        } else if (action === "update-machine") {
            if (!machineUpdateAvailable)
                return false
            var fw = remoteFirmwareImage
            // Customer-facing: "BEND 1.3", never the internal build id (v53-r36e34-...).
            var newName = friendlyFirmwareName(fw.expectedVersion, fw.version)
            var installedRaw = machineControl && machineControl.pressFirmwareVersion
                ? String(machineControl.pressFirmwareVersion) : ""
            var notes = String(fw.description || "").replace(/^[A-Za-z0-9._-]+:\s*/, "")
            showConfirmation("MACHINE FIRMWARE UPDATE",
                      "Installed: " + (installedRaw.length > 0 ? friendlyFirmwareName("[LS-BEND " + installedRaw + "]", installedRaw) : "unknown")
                      + "\nNew: " + newName
                      + (notes.length > 0 ? "\n\nWhat's new: " + notes : "")
                      + "\n\nTurn hydraulics off first. Installation takes about 1 minute; "
                      + "if the check fails, the previous firmware is restored automatically. "
                      + "Home the press afterwards.",
                      function() {
                var reason = machineFirmware.machineBlockReason()
                if (!machineFirmwareUiGateClear || String(reason).length > 0) {
                    showPopup("UPDATE BLOCKED", String(reason).length > 0 ? reason : "Stop the run before updating.",
                              1, "message", "CLOSE")
                    return
                }
                log("UPDATE", "MACHINE FIRMWARE INSTALL " + fw.id)
                machineFirmware.startFlash(fw.id, true, machineFirmwareUiGateClear)
            })
        } else if (action === "bleed") {
            startBleedHydraulics()
        } else if (action === "log") {
            showPopup("MACHINE LOG", "", 1, "machine-log")
        } else if (action === "backup") {
            showPopup("BACKUP & RESTORE", "", 1, "backup")
        } else if (action === "wifi") {
            showPopup("WIFI CONNECTION", "CONNECTED NETWORK", 0, "wifi")
            Qt.callLater(refreshWifiNetworks)
        } else {
            log("ACTION", action)
        }
    }

    function setBleedPending(operation, state) {
        bleedPendingOperation = operation
        bleedPendingOperationId = machineControl ? machineControl.operationId : undefined
        bleedState = state
    }

    function failBleedHydraulics(reason) {
        bleedPendingOperation = ""
        bleedPendingOperationId = undefined
        bleedState = "IDLE"
        if (machineControl && machineConnected && machineControl.primingModeEnabled)
            machineControl.setPrimingEnabled(false)
        showAlarm("BLEED HYDRAULICS FAILED",
                  String(reason || "CONTROLLER_CONFIRMATION_FAILED").replace(/_/g, " "))
        return false
    }

    function startBleedHydraulics() {
        if (bleedActive)
            return false
        if (!offlineSimulationEnabled && (!machineControl || !machineConnected
                || !machineControl.pressTelemetryFresh
                || machineControl.pressOperationActive)) {
            showMachineRejection("BLEED HYDRAULICS")
            return false
        }
        if (!offlineSimulationEnabled && (leftSafetyJog || rightSafetyJog)) {
            showAlarm(qsTr("BLEED HYDRAULICS"),
                      qsTr("Release both palm safety switches before enabling bleed mode."))
            return false
        }
        showPopup("BLEED HYDRAULICS",
                  "Preparing the controller for hydraulic priming.", 0.15,
                  "blur", "CANCEL")
        if (offlineSimulationEnabled) {
            bleedState = "PRIMING"
            showBleedProcedure()
            return true
        }
        if (machineControl.pressMachineState === "HYDRAULIC_SHUTDOWN"
                || machineControl.pressMachineState === "STARTUP_HOMING_REQUIRED") {
            if (!machineControl.setPrimingEnabled(true))
                return failBleedHydraulics(machineControl.lastRejectReason)
            setBleedPending("priming-enable", "ENABLING")
            return true
        }
        if (!machineControl.killHydraulics())
            return failBleedHydraulics(machineControl.lastRejectReason)
        setBleedPending("kill-hydraulics", "SHUTTING_DOWN")
        return true
    }

    function handleBleedOperationFinished(operation, state, error) {
        bleedPendingOperation = ""
        bleedPendingOperationId = undefined
        if (state !== "COMPLETED")
            return failBleedHydraulics(error || operation.toUpperCase() + "_FAILED")
        if (operation === "kill-hydraulics") {
            if (!machineControl || (machineControl.pressMachineState !== "HYDRAULIC_SHUTDOWN"
                    && machineControl.pressMachineState !== "STARTUP_HOMING_REQUIRED"))
                return failBleedHydraulics("HYDRAULIC_SHUTDOWN_NOT_CONFIRMED")
            if (!machineControl.setPrimingEnabled(true))
                return failBleedHydraulics(machineControl.lastRejectReason)
            setBleedPending("priming-enable", "ENABLING")
            popupBody = "Hydraulics are off. Waiting for priming mode confirmation."
            popupProgress = 0.45
            return true
        }
        if (operation === "priming-enable") {
            if (!machineControl || !machineControl.primingModeEnabled
                    || machineControl.pressMachineState !== "PRIMING_MODE")
                return failBleedHydraulics("PRIMING_MODE_NOT_CONFIRMED")
            bleedState = "PRIMING"
            showBleedProcedure()
            return true
        }
        if (operation === "priming-disable") {
            bleedState = "IDLE"
            hidePopup()
            showPopup("BLEED HYDRAULICS COMPLETE",
                      "Priming mode is disabled and hydraulic power remains off.",
                      1, "message", "CLOSE")
            return true
        }
        return false
    }

    function showBleedProcedure() {
        showPopup("BLEED HYDRAULICS",
                  "", 1, "bleed-procedure", "COMPLETE")
        popupAction = "confirmation"
        popupPrimaryHandler = function() { finishBleedHydraulics() }
        popupCancelHandler = function() { finishBleedHydraulics() }
    }

    function setBleedAxisLatch(axis, enabled) {
        if (offlineSimulationEnabled || !machineControl || !bleedLatchSupported
                || bleedState !== "PRIMING") {
            showAlarm("BLEED HYDRAULICS", qsTr("Per-axis UI latching is unavailable. Hold the physical palm switch to prime."))
            return false
        }
        if (!machineControl.setPrimingLatch(axis, enabled)) {
            showAlarm("BLEED HYDRAULICS", String(machineControl.lastRejectReason || "LATCH_REJECTED").replace(/_/g, " "))
            return false
        }
        // State remains controller-authoritative: TEMP updates the UI.
        return true
    }

    function finishBleedHydraulics() {
        if (offlineSimulationEnabled) {
            bleedState = "IDLE"
            hidePopup()
            return true
        }
        if (!machineControl || !machineControl.setPrimingEnabled(false))
            return failBleedHydraulics(machineControl
                ? machineControl.lastRejectReason : "CONTROLLER_UNAVAILABLE")
        setBleedPending("priming-disable", "DISABLING")
        showPopup("BLEED HYDRAULICS", "Disabling priming mode.", 0.9,
                  "blur", "CANCEL")
        return true
    }

    function setConnection(kind, connected) {
        if (!offlineSimulationEnabled) {
            if (!machineControl) {
                showMachineRejection(kind.toUpperCase() + " CONNECTION")
                return false
            }
            lastConnectionFailureDevice = ""
            lastConnectionFailureReason = ""
            return kind === "module"
                ? (connected ? machineControl.connectModule() : machineControl.disconnectModule())
                : (connected ? machineControl.connectPress() : machineControl.disconnectPress())
        }
        if (kind === "module") {
            moduleConnected = connected
            if (!connected) {
                backGaugeHomingTimer.stop()
                backGaugeResetTimer.stop()
                backGaugeBusy = false
                backGaugeHomed = false
                backGaugeActiveDirection = ""
                backGaugeStatus = "UNKNOWN"
                backGaugeMachineX = 0
                backGaugeMachineR = 0
                updateBackGaugeWorkPosition()
            } else if (backGaugeStatus === "UNKNOWN") {
                backGaugeStatus = "IDLE"
            }
        } else {
            machineConnected = connected
        }
        log("CONNECTION", kind + (connected ? " connected" : " disconnected"))
        return true
    }

    function resetConnection(kind) {
        if (!offlineSimulationEnabled) {
            if (!machineControl) {
                showMachineRejection(kind.toUpperCase() + " RESET")
                return false
            }
            return kind === "module" ? machineControl.resetModule() : machineControl.resetPress()
        }
        log("CONNECTION", kind + " reset requested")
        showPopup(kind.toUpperCase() + " RESET", "Reset command sent to the " + kind + " connection model.", 0.25)
        return true
    }

    function showMachineRejection(title) {
        var reason = machineControl && machineControl.lastRejectReason.length > 0
            ? machineControl.lastRejectReason : "TRANSPORT_UNAVAILABLE"
        showAlarm(title + " REJECTED", "Command was not dispatched: " + reason.replace(/_/g, " ") + ".")
    }

    function deviceDisplayName(device) {
        return String(device || "").toLowerCase() === "module" ? "BACK GAUGE" : "MACHINE"
    }

    function readableMachineReason(reason) {
        return String(reason || "UNKNOWN").replace(/_/g, " ")
    }

    function showBackendFailure(device, reason) {
        showAlarm(deviceDisplayName(device) + " CONNECTION FAILED",
                  "The serial connection could not be initialized: "
                  + readableMachineReason(reason) + ".")
    }

    function showBackendRejection(device, operation, reason) {
        showAlarm(deviceDisplayName(device) + " "
                  + String(operation || "command").replace(/-/g, " ").toUpperCase()
                  + " REJECTED",
                  "Command was not dispatched: " + readableMachineReason(reason) + ".")
    }

    function backGaugeCoordinateDisplayName(system) {
        var key = String(system || backGaugeCoordinateSystem)
        return backGaugeCoordinateNames[key] || defaultBackGaugeCoordinateNames[key] || key
    }

    function openOnScreenKeyboard(target, numericOnly, title, commitHandler, cancelHandler,
                                  requiredForOperation) {
        if (!target || (virtualInputMode === "NEVER" && requiredForOperation !== true))
            return false
        onScreenKeyboardTarget = target
        onScreenKeyboardKind = numericOnly ? "numeric" : "text"
        onScreenKeyboardTitle = String(title || (numericOnly ? "ENTER VALUE" : "ENTER TEXT"))
        onScreenKeyboardValue = String(target.text === undefined || target.text === null ? "" : target.text)
        onScreenKeyboardCursor = onScreenKeyboardValue.length
        onScreenKeyboardOriginalValue = numericOnly
        onScreenKeyboardShiftState = "NONE"
        onScreenKeyboardSymbols = false
        onScreenKeyboardCommitHandler = commitHandler || null
        onScreenKeyboardCancelHandler = cancelHandler || null
        onScreenKeyboardVisible = true
        return true
    }

    function insertOnScreenKeyboardText(text) {
        var value = String(onScreenKeyboardValue || "")
        var insert = String(text || "")
        if (onScreenKeyboardKind === "numeric" && onScreenKeyboardOriginalValue) {
            onScreenKeyboardValue = insert
            onScreenKeyboardCursor = insert.length
            onScreenKeyboardOriginalValue = false
            return
        }
        var position = Math.max(0, Math.min(onScreenKeyboardCursor, value.length))
        onScreenKeyboardValue = value.substring(0, position) + insert + value.substring(position)
        onScreenKeyboardCursor = position + insert.length
    }

    function backspaceOnScreenKeyboard() {
        if (onScreenKeyboardKind === "numeric" && onScreenKeyboardOriginalValue) {
            clearOnScreenKeyboard()
            return
        }
        var value = String(onScreenKeyboardValue || "")
        var position = Math.max(0, Math.min(onScreenKeyboardCursor, value.length))
        if (position <= 0)
            return
        onScreenKeyboardValue = value.substring(0, position - 1) + value.substring(position)
        onScreenKeyboardCursor = position - 1
    }

    function clearOnScreenKeyboard() {
        onScreenKeyboardValue = ""
        onScreenKeyboardCursor = 0
        onScreenKeyboardOriginalValue = false
    }

    function moveOnScreenKeyboardCursor(delta) {
        onScreenKeyboardCursor = Math.max(0, Math.min(
            String(onScreenKeyboardValue || "").length,
            onScreenKeyboardCursor + Number(delta || 0)))
    }

    function toggleOnScreenKeyboardNegative() {
        var value = String(onScreenKeyboardValue || "")
        if (onScreenKeyboardOriginalValue) {
            onScreenKeyboardValue = "-"
            onScreenKeyboardCursor = 1
            onScreenKeyboardOriginalValue = false
            return
        }
        onScreenKeyboardValue = value.indexOf("-") === 0 ? value.substring(1) : "-" + value
        onScreenKeyboardCursor = onScreenKeyboardValue.length
    }

    function cycleOnScreenKeyboardShift() {
        onScreenKeyboardShiftState = onScreenKeyboardShiftState === "NONE"
            ? "SHIFT" : (onScreenKeyboardShiftState === "SHIFT" ? "CAPS" : "NONE")
    }

    function commitOnScreenKeyboard() {
        if (!onScreenKeyboardVisible)
            return false
        var value = String(onScreenKeyboardValue || "")
        if (onScreenKeyboardKind === "numeric") {
            var trimmed = value.trim()
            if (trimmed.length === 0 || !isFinite(Number(trimmed)))
                return false
            value = trimmed
        }
        var target = onScreenKeyboardTarget
        var handler = onScreenKeyboardCommitHandler
        if (target && target.text !== undefined)
            target.text = value
        closeOnScreenKeyboardState()
        if (handler)
            handler(value)
        value = ""
        return true
    }

    function cancelOnScreenKeyboard() {
        if (!onScreenKeyboardVisible)
            return false
        var handler = onScreenKeyboardCancelHandler
        closeOnScreenKeyboardState()
        if (handler)
            handler()
        return true
    }

    function closeOnScreenKeyboardState() {
        onScreenKeyboardVisible = false
        onScreenKeyboardValue = ""
        onScreenKeyboardCursor = 0
        onScreenKeyboardTarget = null
        onScreenKeyboardCommitHandler = null
        onScreenKeyboardCancelHandler = null
        onScreenKeyboardOriginalValue = false
        onScreenKeyboardShiftState = "NONE"
        onScreenKeyboardSymbols = false
    }

    function selectBackGaugeCoordinateSystem(system) {
        var key = String(system || "G54")
        if (backGaugeCoordinateSystems.indexOf(key) < 0)
            return false
        if (backGaugeStatus !== "IDLE" && backGaugeStatus !== "HOMED")
            return false
        if (!offlineSimulationEnabled) {
            if (!machineControl)
                return false
            if (!machineControl.selectModuleCoordinateSystem(key))
                return false
        }
        backGaugeCoordinateSystem = key
        log("BACK GAUGE", "Coordinate system " + key + " selected")
        return true
    }

    function renameBackGaugeCoordinateSystem(name) {
        if (backGaugeStatus !== "IDLE" && backGaugeStatus !== "HOMED")
            return false
        var names = Object.assign({}, backGaugeCoordinateNames)
        var clean = String(name || "").trim()
        if (clean.length > 0)
            names[backGaugeCoordinateSystem] = clean
        else
            delete names[backGaugeCoordinateSystem]
        backGaugeCoordinateNames = names
        var result = SettingsModel.saveCoordinateSystemNames(
            writableCurrentDataPath("coordinate-system-names.json"), names, settingsIo(), {})
        if (!storageBackendReady)
            recordSandboxWrite("settings", "coordinateSystemNames", names)
        log("BACK GAUGE", "Coordinate name " + backGaugeCoordinateSystem + " = " + (clean || "default"))
        return result.ok === true || !storageBackendReady
    }

    function backGaugeOffset() {
        return backGaugeCoordinateOffsets[backGaugeCoordinateSystem] || { x: 0, r: 0 }
    }

    function updateBackGaugeWorkPosition() {
        var offset = backGaugeOffset()
        backGaugeX = backGaugeMachineX - Number(offset.x || 0)
        backGaugeR = backGaugeMachineR - Number(offset.r || 0)
    }

    function setBackGaugeWorkPosition(axis, value) {
        if (!backGaugeCanOperate)
            return false
        var target = Number(value)
        if (!isFinite(target))
            return false
        if (!offlineSimulationEnabled) {
            if (!machineControl)
                return false
            var accepted = machineControl.setModuleWorkPosition(
                backGaugeCoordinateSystem, axis, target)
            if (accepted && axis === "R")
                recordBackGaugeCalibrationDie(backGaugeCoordinateSystem)
            return accepted
        }
        if (axis === "R")
            recordBackGaugeCalibrationDie(backGaugeCoordinateSystem)
        var offsets = Object.assign({}, backGaugeCoordinateOffsets)
        var current = Object.assign({}, backGaugeOffset())
        if (axis === "X")
            current.x = backGaugeMachineX - target
        else if (axis === "R")
            current.r = backGaugeMachineR - target
        else
            return false
        offsets[backGaugeCoordinateSystem] = current
        backGaugeCoordinateOffsets = offsets
        updateBackGaugeWorkPosition()
        log("BACK GAUGE", "Set " + axis + " work position " + target.toFixed(4))
        return true
    }

    function setBackGaugeJogStep(value, continuous) {
        var numeric = Number(value)
        if (!continuous && !isFinite(numeric))
            return false
        backGaugeContinuousJog = continuous === true
        if (!backGaugeContinuousJog)
            jogStep = Math.max(backGaugeMinJogStep, Math.min(backGaugeMaxJogStep, numeric))
        var inchValue = backGaugeUnit === "INCH" ? jogStep : jogStep / 25.4
        var mmValue = backGaugeUnit === "MILLIMETER" ? jogStep : jogStep * 25.4
        persistLocalSetting("backGaugeJogStep", { millimetersValue: mmValue, inchesValue: inchValue })
        persistLocalSetting("backGaugeContinuousJog", backGaugeContinuousJog)
        log("BACK GAUGE", backGaugeContinuousJog ? "Continuous jog enabled" : "Jog step " + jogStep.toFixed(4))
        return true
    }

    function setBackGaugeJogSpeed(value) {
        var numeric = Number(value)
        if (!isFinite(numeric))
            return false
        jogSpeed = Math.max(backGaugeMinJogSpeed, Math.min(backGaugeMaxJogSpeed, numeric))
        var inchValue = backGaugeUnit === "INCH" ? jogSpeed : jogSpeed / 25.4
        var mmValue = backGaugeUnit === "MILLIMETER" ? jogSpeed : jogSpeed * 25.4
        persistLocalSetting("backGaugeJogSpeed", { millimetersValue: mmValue, inchesValue: inchValue })
        log("BACK GAUGE", "Jog speed " + jogSpeed.toFixed(3))
        return true
    }

    function requestBackGaugeHome() {
        if (moduleConnectionState !== "READY") {
            showAlarm("HOMING NOT ALLOWED", "Back gauge connection is "
                      + moduleConnectionState.replace(/_/g, " ") + ".")
            return false
        }
        if (moduleControllerAlarm && backGaugeStatus !== "ALARM") {
            showAlarm("BACK GAUGE ALARM", "The serial connection is ready, but the controller is in "
                      + backGaugeStatus.replace(/_/g, " ") + ". Clear the controller condition before homing.")
            return false
        }
        if (!backGaugeReady || backGaugeBusy) {
            showAlarm("HOMING NOT ALLOWED", "Back gauge telemetry is not ready for homing.")
            return false
        }
        var activeLimits = []
        if (backGaugeLimitX1) activeLimits.push("X1")
        if (backGaugeLimitX2) activeLimits.push("X2")
        if (backGaugeLimitR1) activeLimits.push("R1")
        if (backGaugeLimitR2) activeLimits.push("R2")
        if (activeLimits.length > 0) {
            showAlarm("LIMIT SWITCHES ACTIVE", "Release " + activeLimits.join(", ") + " before homing.")
            return false
        }
        showPopup("HOME BACK GAUGE", "Confirm that both axes can move safely to machine zero.", 0, "caution", "HOME")
        popupAction = "back-gauge-home-confirm"
        popupCancelButtonText = "CLOSE"
        return true
    }

    function backGaugeHome() {
        return requestBackGaugeHome()
    }

    function startBackGaugeHome() {
        if (!offlineSimulationEnabled) {
            if (!machineControl) {
                showMachineRejection("BACK GAUGE HOME")
                return false
            }
            var accepted = machineControl.homeModule()
            if (accepted) {
                backGaugeHomeOperationId = machineControl.operationId
                showPopup("BACK GAUGE HOMING",
                          "Homing was dispatched. Keep the physical emergency stop within reach.",
                          0, "blur", "CLOSE")
                popupAction = ""
            }
            return accepted
        }
        backGaugeBusy = true
        backGaugeHomed = false
        backGaugeStatus = "HOMING"
        backGaugeLastCommands = [BackGauge.homingCommand()]
        showPopup("BACK GAUGE HOMING", "Back gauge axes are moving to machine zero.", 0.5, "blur", "CANCEL")
        popupAction = "back-gauge-home-cancel"
        backGaugeHomingTimer.restart()
    }

    function completeBackGaugeHome() {
        backGaugeMachineX = 0
        backGaugeMachineR = 0
        updateBackGaugeWorkPosition()
        backGaugeHomed = true
        backGaugeBusy = false
        backGaugeStatus = "IDLE"
        popupAction = ""
        showPopup("BACK GAUGE HOMED", "Back gauge axes homed to machine zero.", 1, "message", "CLOSE")
    }

    function cancelBackGaugeHome() {
        backGaugeHomingTimer.stop()
        backGaugeLastCommands = [BackGauge.softResetCommand()]
        backGaugeBusy = false
        backGaugeStatus = "IDLE"
        popupAction = ""
        hidePopup()
        log("BACK GAUGE", "Homing cancelled")
    }

    function requestPressHome() {
        if (!offlineSimulationEnabled && !pressCanHome) {
            showAlarm("HOMING NOT ALLOWED", "Press telemetry is not ready for homing.")
            return false
        }
        showConfirmation("HOME MACHINE",
                         "The ram will move through its homing cycle. Keep the physical emergency stop within reach.",
                         function() { appState.startPressHome() })
        popupButtonText = "HOME"
        popupCancelButtonText = "CLOSE"
        return true
    }

    function startPressHome() {
        if (!offlineSimulationEnabled) {
            if (!machineControl || !machineControl.homePress())
                return false
            pressHomeOperationId = machineControl.operationId
        } else {
            machineStatus = "HOMING"
        }
        showPopup("HOMING MACHINE",
                  "Press brake homing is in progress. This window closes automatically when telemetry confirms completion.",
                  0, "blur", "CANCEL")
        popupAction = "press-home-cancel"
        return true
    }

    function startCombinedHome() {
        if (offlineSimulationEnabled) {
            machineStatus = "HOMING"
            backGaugeHomed = false
            backGaugeStatus = "HOMING"
            combinedHomeBackGaugePending = true
            combinedHomeTimer.restart()
            log("MACHINE", "Combined press and back gauge home started")
            return true
        }
        if (!machineControl || !pressCanHome || moduleConnectionState !== "READY"
                || !backGaugeReady || backGaugeBusy) {
            showAlarm("COMBINED HOME NOT ALLOWED",
                      "Press and Back Gauge must both be connected, ready, and idle.")
            return false
        }
        // Press and Back Gauge home simultaneously; both report with the same id.
        if (!machineControl.homeAll())
            return false
        pressHomeOperationId = machineControl.operationId
        backGaugeHomeOperationId = machineControl.operationId
        log("MACHINE", "Simultaneous press and back gauge home started")
        showPopup("HOMING MACHINE",
                  "Press and Back Gauge are homing simultaneously. This window closes when both are confirmed homed.",
                  0, "blur", "CANCEL")
        popupAction = "press-home-cancel"
        return true
    }

    property Timer combinedHomeTimer: Timer {
        interval: 450
        repeat: false
        onTriggered: {
            appState.machineStatus = "IDLE"
            appState.backGaugeHomed = true
            appState.backGaugeStatus = "IDLE"
            appState.combinedHomeBackGaugePending = false
            appState.log("MACHINE", "Combined press and back gauge home completed")
        }
    }

    function cancelPressHome() {
        if (!offlineSimulationEnabled && machineControl && machineControl.pressOperationActive)
            machineControl.abortPress()
        pressHomeOperationId = undefined
        combinedHomeBackGaugePending = false
        hidePopup()
        log("MACHINE", "Homing cancelled")
        return true
    }

    function beginBackGaugeJog(axis, direction) {
        if (!backGaugeCanOperate || backGaugeActiveDirection.length > 0)
            return false
        if ((axis !== "X" && axis !== "R") || (direction !== -1 && direction !== 1))
            return false
        if (!offlineSimulationEnabled) {
            if (!machineControl) {
                showMachineRejection("BACK GAUGE JOG")
                return false
            }
            var accepted = machineControl.jogModule(
                axis, direction, jogStep, jogSpeed, backGaugeContinuousJog)
            if (accepted && backGaugeContinuousJog)
                backGaugeActiveDirection = axis + (direction > 0 ? "+" : "-")
            return accepted
        }
        backGaugeActiveDirection = axis + (direction > 0 ? "+" : "-")
        backGaugeStatus = "JOG"
        backGaugeLastCommands = [backGaugeContinuousJog
            ? BackGauge.jogCommand(backGaugeUnit, backGaugeCoordinateSystem,
                axis === "X" ? "X" : "Y", direction * jogStep, jogSpeed)
            : BackGauge.bumpCommand(backGaugeUnit, backGaugeCoordinateSystem,
                axis === "X" ? "X" : "Y", direction * jogStep, jogSpeed)]
        applyBackGaugeJogIncrement(axis, direction)
        log("BACK GAUGE", backGaugeActiveDirection + (backGaugeContinuousJog ? " continuous jog" : " jog step " + jogStep.toFixed(4)))
        return true
    }

    function applyBackGaugeJogIncrement(axis, direction) {
        if (axis === "X")
            backGaugeMachineX += direction * jogStep
        else
            backGaugeMachineR += direction * jogStep
        updateBackGaugeWorkPosition()
    }

    function continueBackGaugeJog() {
        if (!backGaugeContinuousJog || backGaugeActiveDirection.length !== 2)
            return false
        var axis = backGaugeActiveDirection.charAt(0)
        var direction = backGaugeActiveDirection.charAt(1) === "+" ? 1 : -1
        // Production continuous jog is advanced ACK-by-ACK by the native
        // backend, as Java ContinuousJogOperation does. This helper remains
        // only for deterministic offline animation/tests.
        if (!offlineSimulationEnabled)
            return false
        var commands = backGaugeLastCommands.slice()
        commands.push(BackGauge.jogCommand(backGaugeUnit, backGaugeCoordinateSystem,
            axis === "X" ? "X" : "Y", direction * jogStep, jogSpeed))
        backGaugeLastCommands = commands
        applyBackGaugeJogIncrement(axis, direction)
        return true
    }

    function releaseBackGaugeJog(axis, direction) {
        var expected = axis + (direction > 0 ? "+" : "-")
        if (backGaugeContinuousJog && backGaugeActiveDirection !== expected)
            return false
        // Pointer/key release owns the UI repeat state. Clear it before asking the
        // controller to leave JOG so the 120 ms repeat timer cannot dispatch a new
        // segment while the native operation is awaiting Idle.
        backGaugeActiveDirection = ""
        if (!offlineSimulationEnabled) {
            if (!machineControl) {
                showMachineRejection("BACK GAUGE STOP")
                return false
            }
            if (!backGaugeContinuousJog)
                return true
            return machineControl.stopModule()
        }
        if (backGaugeContinuousJog) {
            var commands = backGaugeLastCommands.slice()
            commands.push(BackGauge.jogCancelCommand())
            backGaugeLastCommands = commands
        }
        backGaugeStatus = "IDLE"
        log("BACK GAUGE", expected + " released")
        return true
    }

    function backGaugeJog(axis, direction) {
        if (!beginBackGaugeJog(axis, direction))
            return false
        return releaseBackGaugeJog(axis, direction)
    }

    function backGaugeMoveTo(xValue, rValue) {
        if (!backGaugeCanOperate) {
            showAlarm("BACK GAUGE MOVE NOT ALLOWED", "Home the connected back gauge and wait for IDLE before moving.")
            return false
        }
        var targetX = Number(xValue)
        var targetR = Number(rValue)
        if (!isFinite(targetX) || !isFinite(targetR)) {
            showAlarm("INVALID BACK GAUGE TARGET", "Enter finite numeric X and R positions.")
            return false
        }
        if (!offlineSimulationEnabled) {
            if (!machineControl) {
                showMachineRejection("BACK GAUGE MOVE")
                return false
            }
            return machineControl.moveModule(targetX, targetR, jogSpeed)
        }
        backGaugeLastCommands = BackGauge.moveToCommands(backGaugeUnit, backGaugeCoordinateSystem,
            backGaugeX, targetX, targetR, jogSpeed)
        var offset = backGaugeOffset()
        backGaugeMachineX = targetX + Number(offset.x || 0)
        backGaugeMachineR = targetR + Number(offset.r || 0)
        updateBackGaugeWorkPosition()
        backGaugeStatus = "MOVE"
        showPopup("BACK GAUGE MOVE", "Move-to command: X " + backGaugeX.toFixed(4) + ", R " + backGaugeR.toFixed(4), 0.6)
        backGaugeStatus = "IDLE"
        return true
    }

    function backGaugeStop() {
        if (!offlineSimulationEnabled) {
            if (!machineControl) {
                showMachineRejection("BACK GAUGE STOP")
                return false
            }
            return machineControl.stopModule()
        }
        backGaugeHomingTimer.stop()
        backGaugeActiveDirection = ""
        backGaugeBusy = true
        backGaugeHomed = false
        backGaugeStatus = "RESETTING"
        backGaugeLastCommands = [BackGauge.feedHoldCommand(), BackGauge.softResetCommand()]
        showAlarm("BACK GAUGE STOP", "Feed hold and controller reset issued. Waiting for Back Gauge initialization.")
        backGaugeResetTimer.restart()
        return true
    }

    function completeBackGaugeReset() {
        if (!moduleConnected)
            return false
        backGaugeBusy = false
        backGaugeHomed = true
        backGaugeStatus = "IDLE"
        clearAlarm()
        log("BACK GAUGE", "Controller initialized after stop")
        return true
    }

    function resetBackGaugeStop() {
        backGaugeResetTimer.stop()
        return completeBackGaugeReset()
    }

    function ingestBackGaugeStatus(line) {
        var status = BackGauge.decodeStatus(line)
        if (!status)
            return false
        if (status.mpos) {
            if (isFinite(Number(status.mpos.x)))
                backGaugeMachineX = Number(status.mpos.x)
            if (isFinite(Number(status.mpos.y)))
                backGaugeMachineR = Number(status.mpos.y)
        }
        if (status.wco) {
            var offsets = Object.assign({}, backGaugeCoordinateOffsets)
            var currentOffset = Object.assign({}, backGaugeOffset())
            if (isFinite(Number(status.wco.x)))
                currentOffset.x = Number(status.wco.x)
            if (isFinite(Number(status.wco.y)))
                currentOffset.r = Number(status.wco.y)
            offsets[backGaugeCoordinateSystem] = currentOffset
            backGaugeCoordinateOffsets = offsets
        }
        if (status.wpos) {
            if (isFinite(Number(status.wpos.x)))
                backGaugeX = Number(status.wpos.x)
            if (isFinite(Number(status.wpos.y)))
                backGaugeR = Number(status.wpos.y)
        } else if (status.mpos) {
            updateBackGaugeWorkPosition()
        }
        var state = String(status.state || "UNKNOWN").toUpperCase()
        backGaugeStatus = state === "IDLE" ? "IDLE" : state
        backGaugeBusy = state !== "IDLE" && state !== "ALARM" && state !== "UNKNOWN"
        var pins = status.fields && status.fields.Pn ? String(status.fields.Pn) : ""
        backGaugeLimitX1 = pins.indexOf("X") >= 0
        backGaugeLimitX2 = pins.indexOf("Z") >= 0
        backGaugeLimitR1 = pins.indexOf("Y") >= 0
        backGaugeLimitR2 = pins.indexOf("A") >= 0
        return true
    }

    function machineAction(action) {
        // During a RUN tool change the ADVANCE (jog-down) button drives TOUCH.
        if (runToolChangeActive) {
            if (action === "advance-jog")
                return runToolChangeJogDown(true)
            if (action === "advance-jog-release")
                return runToolChangeJogDown(false)
            if (action === "retract-jog" || action === "retract-jog-release")
                return false
        }
        if (!offlineSimulationEnabled && action !== "jog-speed") {
            if (!machineControl) {
                showMachineRejection("MACHINE " + action.toUpperCase())
                return false
            }
            var accepted = false
            if (action === "home") {
                return requestPressHome()
            }
            else if (action === "abort") accepted = machineControl.abortPress()
            else if (action === "kill-hydraulics") accepted = machineControl.killHydraulics()
            else if (action === "retract-jog")
                accepted = machineControl.startRetractJog(jogRamSpeed)
            else if (action === "advance-jog")
                accepted = machineControl.startAdvanceJog(jogRamSpeed)
            else if (action === "retract-jog-release"
                     || action === "advance-jog-release")
                accepted = machineControl.releasePanelJog()
            return accepted
        }
        if (action === "home") {
            return requestPressHome()
        } else if (action === "abort") {
            machineStatus = "ABORTED"
            commandedJogSpeed = 0
            showAlarm("MACHINE ABORT", "Abort command issued to the press brake.")
        } else if (action === "kill-hydraulics") {
            machineStatus = "HYDRAULICS OFF"
            commandedJogSpeed = 0
            showAlarm("HYDRAULIC POWER OFF", "Hydraulic power kill command issued.")
        } else if (action === "retract-jog") {
            machineStatus = "RETRACT JOG"
            ramPosition += 0.05
            commandedJogPosition = ramPosition
            commandedJogSpeed = jogRamSpeed
            distanceToGo = Math.max(0, distanceToGo - 0.05)
            log("MACHINE", "Retract jog at " + jogRamSpeed.toFixed(1) + " IPM")
        } else if (action === "advance-jog") {
            machineStatus = "SAFETY JOG"
            ramPosition = Math.max(-4.0, ramPosition - 0.05)
            commandedJogPosition = ramPosition
            commandedJogSpeed = jogRamSpeed
            distanceToGo = Math.max(0, distanceToGo - 0.05)
            log("MACHINE", "Advance jog at " + jogRamSpeed.toFixed(1) + " IPM")
        } else if (action === "retract-jog-release"
                   || action === "advance-jog-release") {
            machineStatus = "IDLE"
            commandedJogSpeed = 0
        } else if (action === "jog-speed") {
            showPopup("JOG SPEED SETTINGS", "Bend ram " + bendRamSpeed.toFixed(1) + " IPM\nJog ram " + jogRamSpeed.toFixed(1) + " IPM", 1)
        }
    }

    function toggleLed(name) {
        if (!offlineSimulationEnabled) {
            log("INPUT", name + " is read-only controller telemetry")
            return false
        }
        if (name === "left")
            leftSafetyJog = !leftSafetyJog
        else if (name === "right")
            rightSafetyJog = !rightSafetyJog
        else if (name === "pedal")
            bendJogPedal = !bendJogPedal
        else if (name === "anti-bind")
            antiBindSwitch = !antiBindSwitch
        log("INPUT", name + " = " + (name === "left" ? leftSafetyJog : name === "right" ? rightSafetyJog : name === "pedal" ? bendJogPedal : antiBindSwitch))
        return true
    }

    function runAction(action) {
        if (action === "run") {
            if (runActive) {
                if (offlineSimulationEnabled) {
                    machineStatus = "IDLE"
                    resetRunPresentationState()
                    showPopup("PROGRAM PAUSED", activeProgram + "\nBend " + String(selectedRunBend + 1), 1)
                } else {
                    stopPhysicalRunByOperator()
                }
            } else {
                openRunConfirmation()
            }
        } else if (action === "new") {
            var nextPrograms = programs.slice(0)
            var newStamp = programTimestamp()
            nextPrograms.push({ id: uniqueEntityId("program", [nextPrograms]), name: "UNTITLED PROGRAM", source: "qml", bends: [], cadPreviewJson: "",
                                folder: "", createdAt: newStamp, updatedAt: newStamp })
            programs = nextPrograms
            selectedProgramIndex = nextPrograms.length - 1
            selectedRunBend = -1
            syncActiveProgramState()
            runProgramEditing = true
            runProgramNameDraft = "UNTITLED PROGRAM"
            enforceBendModeForProgram()
            recordSandboxWrite("programs", "create", "UNTITLED PROGRAM")
            log("RUN", "New program edit mode")
        } else if (action === "save") {
            runProgramEditing = false
            if (runProgramNameDraft.length > 0) {
                activeProgram = runProgramNameDraft
                if (selectedProgramIndex >= 0 && selectedProgramIndex < programs.length) {
                    var renamed = programs.slice(0)
                    renamed[selectedProgramIndex] = Object.assign({}, renamed[selectedProgramIndex], { name: runProgramNameDraft, updatedAt: programTimestamp() })
                    programs = renamed
                }
            }
            recordSandboxWrite("programs", "save", activeProgram)
            if (persistPrograms("save", activeProgram))
                return
            showPopup("SAVE PROGRAM", "Program save queued in QML sandbox.", 1)
        } else if (action === "duplicate") {
            var copyName = activeProgram + " COPY"
            if (selectedProgramIndex >= 0 && selectedProgramIndex < programs.length) {
                var dupPrograms = programs.slice(0)
                var sourceProgram = programs[selectedProgramIndex] || {}
                var dupStamp = programTimestamp()
                dupPrograms.push(Object.assign({}, sourceProgram, { id: uniqueEntityId("program", [dupPrograms]), name: copyName, bends: cloneBends(sourceProgram.bends || []),
                                                                    createdAt: dupStamp, updatedAt: dupStamp }))
                programs = dupPrograms
                selectedProgramIndex = dupPrograms.length - 1
                syncActiveProgramState()
            }
            runProgramEditing = true
            runProgramNameDraft = copyName
            recordSandboxWrite("programs", "duplicate", activeProgram)
            if (persistPrograms("duplicate", copyName))
                return
            showPopup("DUPLICATE PROGRAM", activeProgram + " duplicated in QML sandbox.", 1)
        } else if (action === "edit") {
            runProgramEditing = true
            runProgramNameDraft = activeProgram
            log("RUN", "Program edit mode")
        } else if (action === "delete") {
            recordSandboxWrite("programs", "delete", activeProgram)
            if (selectedProgramIndex >= 0 && selectedProgramIndex < programs.length && storageBackendReady) {
                var afterDelete = programs.slice(0)
                var deletedName = activeProgram
                afterDelete.splice(selectedProgramIndex, 1)
                programs = afterDelete
                selectedProgramIndex = afterDelete.length > 0 ? Math.max(0, selectedProgramIndex - 1) : -1
                syncActiveProgramState()
                if (persistPrograms("delete", deletedName))
                    return
            }
            showAlarm("DELETE PROGRAM", "Delete requested for " + activeProgram + ". Stored as sandbox action only.")
        } else if (action === "cancel") {
            runProgramEditing = false
            runProgramNameDraft = activeProgram
            log("RUN", "Program edit cancelled")
        } else if (action === "add-bend") {
            openAddBendPopup(allBends)
        } else if (action === "auto-clamp") {
            autoClampEnabled = !autoClampEnabled
            autoClampToBendEnabled = autoClampEnabled
            persistUserSetting("autoClampToBendEnabled", autoClampEnabled)
            log("RUN", "Auto clamp-to-bend " + (autoClampEnabled ? "enabled" : "disabled"))
        } else if (action === "auto-dwell") {
            // Original parity: no separate dwell switch; OFF = 0 sec (persisted).
            if (autoClampDwellSec > 0) {
                lastNonZeroDwellSec = autoClampDwellSec
                setApplicationNumericSetting("autoClampToBendDwellSec", 0)
            } else {
                setApplicationNumericSetting("autoClampToBendDwellSec",
                                             lastNonZeroDwellSec > 0 ? lastNonZeroDwellSec : 3.0)
            }
            log("RUN", "Auto clamp dwell = " + autoClampDwellSec.toFixed(1) + " sec")
        } else if (action === "bend-mode") {
            toggleBendModePopup()
        }
    }

    function stopPhysicalRunByOperator() {
        if (!runActive)
            return false
        physicalRunCommandPending = false
        physicalRunPendingOperation = ""
        physicalRunPendingDevice = ""
        physicalRunPendingOperationId = undefined
        resetRunPresentationState()
        if (machineControl) {
            if (machineControl.pressOperationActive)
                machineControl.abortPress()
            if (machineControl.moduleOperationActive)
                machineControl.stopModule()
            machineControl.endProgramRun()
        }
        showPopup("PROGRAM STOPPED", activeProgram + "\nBend " + String(selectedRunBend + 1), 1)
        log("RUN", "Program stopped by operator")
        return true
    }

    function resetRunPresentationState() {
        abortRunToolChange()
        if (runAutoMeasureActive) {
            runAutoMeasureActive = false
            if (contactProfileActive && contactProfileOwner === "RUN_AUTO_MEASURE")
                cancelTonnageHoldProfile()
        }
        runActive = false
        runSimulatedRun = false
        runBendListVisible = false
        runSceneMode = "LIVE"
        runProgressTitle = ""
        runProgressSubtitle = ""
        executionPhaseIndex = 0
        executionPhase = ExecutionModel.BendPhase.STARTING.name
        dwellStartedForBend = false
        dwellTimerState = DwellAndBailOut.createDwellTimer(autoClampDwellSec)
        dwellRemainingSec = 0
        dwellPausedForPedal = false
        physicalRunWaitAction = ""
    }

    function replaceProgramBend(index, bend) {
        if (selectedProgramIndex < 0 || selectedProgramIndex >= programs.length
                || index < 0 || index >= programBends.length)
            return false
        var nextPrograms = programs.slice(0)
        var program = Object.assign({}, nextPrograms[selectedProgramIndex])
        var bends = cloneBends(program.bends || [])
        var replacement = Object.assign({}, bend || {})
        replacement.seq = index + 1
        bends[index] = replacement
        program.bends = bends
        program.updatedAt = programTimestamp()
        nextPrograms[selectedProgramIndex] = program
        if (storageBackendReady && !persistEntities("programs", nextPrograms))
            return false
        programs = nextPrograms
        selectedRunBend = index
        syncActiveProgramState()
        return true
    }

    function appendProgramBend(bend) {
        if (selectedProgramIndex < 0 || selectedProgramIndex >= programs.length)
            return false
        var nextPrograms = programs.slice(0)
        var program = Object.assign({}, nextPrograms[selectedProgramIndex])
        var bends = cloneBends(program.bends || [])
        var appended = Object.assign({}, bend || {})
        appended.seq = bends.length + 1
        bends.push(appended)
        program.bends = bends
        program.updatedAt = programTimestamp()
        nextPrograms[selectedProgramIndex] = program
        if (storageBackendReady && !persistEntities("programs", nextPrograms))
            return false
        programs = nextPrograms
        selectedRunBend = bends.length - 1
        syncActiveProgramState()
        return true
    }

    function removeProgramBend(index) {
        if (selectedProgramIndex < 0 || selectedProgramIndex >= programs.length
                || index < 0 || index >= programBends.length)
            return false
        var nextPrograms = programs.slice(0)
        var program = Object.assign({}, nextPrograms[selectedProgramIndex])
        var bends = cloneBends(program.bends || [])
        bends.splice(index, 1)
        for (var bendIndex = 0; bendIndex < bends.length; bendIndex++)
            bends[bendIndex].seq = bendIndex + 1
        program.bends = bends
        program.updatedAt = programTimestamp()
        nextPrograms[selectedProgramIndex] = program
        if (storageBackendReady && !persistEntities("programs", nextPrograms))
            return false
        programs = nextPrograms
        selectedRunBend = bends.length > 0 ? Math.min(index, bends.length - 1) : -1
        syncActiveProgramState()
        return true
    }

    // LIST: selecting a TOOL CHANGE row selects the following bend and makes
    // the next RUN start with that tooling sequence (fast tool-change testing).
    property bool runStartAtToolChange: false
    function selectRunToolChange(index) {
        if (!toolChangeBeforeBend(programBends, index) || !selectRunBend(index))
            return false
        runStartAtToolChange = true
        log("RUN", "Next RUN starts with the tool change before bend " + String(index + 1))
        return true
    }

    function selectRunBend(index, executionOwned) {
        if (index < 0 || index >= programBends.length)
            return false
        // Operator selection must not replace the bend or targets owned by an
        // admitted physical/simulated execution. The execution state machine
        // passes executionOwned only when advancing its completed sequence.
        if (runActive && executionOwned !== true) {
            log("RUN", "Bend selection ignored while execution is active")
            return false
        }
        selectedRunBend = index
        selectedBend = programBends[index]
        if (executionOwned !== true)
            runStartAtToolChange = false
        runProgressTitle = runActive ? "Bend #" + String(index + 1) + " in Progress" : ""
        runProgressSubtitle = currentRunPhaseLabel()
        log("RUN", "Selected bend " + String(index + 1) + ": " + (selectedBend.name || "Bend"))
        return true
    }

    function runSimulationAction(action) {
        if (action === "placement") {
            runSceneMode = "PLACEMENT"
            runSimulatedRun = false
        } else if (action === "live") {
            runSceneMode = "LIVE"
        } else if (action === "guides") {
            runShowMachineGuides = !runShowMachineGuides
            runSceneMode = "LIVE"
        } else if (action === "sim-run") {
            runSimulatedRun = !runSimulatedRun
            if (runSimulatedRun)
                runSceneMode = "LIVE"
        } else if (action === "toggle-list") {
            runBendListVisible = !runBendListVisible
        } else if (action === "previous") {
            selectRunBend(selectedRunBend - 1)
        } else if (action === "next") {
            selectRunBend(selectedRunBend + 1)
        }
        log("RUN", "Simulation " + action)
    }

    function setRunLiveProjectionMode(mode) {
        return false
    }

    function normalizeRunLiveCameraOrientation(value) {
        var normalized = String(value || "").toUpperCase()
        var allowed = [
            "ISO_TOP_LEFT", "ISO_TOP_RIGHT", "ISO_BOTTOM_LEFT", "ISO_BOTTOM_RIGHT",
            "ISO_TOP", "ISO_BOTTOM", "ISO_LEFT", "ISO_RIGHT", "ISO_FRONT", "ISO_BACK"
        ]
        return allowed.indexOf(normalized) >= 0 ? normalized : "ISO_TOP_LEFT"
    }

    function setRunLiveCameraOrientation(orientation) {
        runLiveCameraOrientation = normalizeRunLiveCameraOrientation(orientation)
        persistLocalSetting("runLiveCameraOrientation", runLiveCameraOrientation)
        log("RUN", "LIVE camera orientation " + runLiveCameraOrientation)
    }

    function setRunToolingAppearance(appearance) {
        var normalized = String(appearance || "").toUpperCase()
        runToolingAppearance = normalized === "TRANSLUCENT" ? "TRANSLUCENT" : "SOLID"
        persistLocalSetting("runToolingAppearance", runToolingAppearance)
        log("RUN", "Tooling appearance " + runToolingAppearance)
    }

    function compactPunchName(name) {
        var text = String(name || "UNDEFINED").replace(/\u00C2\u00B0|°/g, "°")
        var match = /\[([^\]]+)\]/.exec(text)
        if (text === "UNDEFINED")
            return text
        var cleaned = text.replace(/\[[^\]]+\]/g, "")
            .replace(/\bPUNCH\b/ig, "").replace(/\s+/g, " ").trim()
        var words = cleaned.split(" ")
        var shortName = words.slice(0, 3).join(" ").toUpperCase()
        return (shortName.length > 0 ? shortName : "PUNCH")
            /* omit long catalog in single-line header */
    }

    function compactDieName(name, bend) {
        var text = String(name || "UNDEFINED").replace(/\u00C2\u00B0|°/g, "°")
        if (text === "UNDEFINED")
            return text
        var match = /\[([^\]]+)\]/.exec(text)
        var opening = runDieOpeningText(bend)
        var is4Way = text.toUpperCase().indexOf("4 WAY") >= 0 || text.toUpperCase().indexOf("4-WAY") >= 0
        var cleaned = text.replace(/\[[^\]]+\]/g, "")
            .replace(/\bDIE\b/ig, "").replace(/\s+/g, " ").trim()
        var words = cleaned.split(" ")
        var shortName = words.slice(0, 3).join(" ").toUpperCase()
        if (shortName.length === 0)
            shortName = is4Way ? "4-WAY" : "DIE"
        var result = shortName
        if (opening.length > 0 && result.indexOf(opening) === -1)
            result += " · " + opening
        if (match && match[1])
            result += " [" + match[1] + "]"
        return result
    }

    // V opening of the bend's resolved die (bendFromStorage/CAD set vdieValue
    // from the die catalog). Empty when unknown: never invent an opening.
    function runDieOpeningText(bend) {
        var opening = finiteNumber(valueOr(bend, "vdieValue", NaN), NaN)
        if (!(opening > 0))
            opening = finiteNumber(valueOr(bend, "dieOpening", valueOr(bend, "vOpening", NaN)), NaN)
        return opening > 0 ? "V " + (metricUnits ? (opening * 25.4).toFixed(2) + " mm" : formatNumber(opening, 3, "0.000") + "\"") : ""
    }

    function runBendRPosition(bend) {
        return finiteNumber(valueOr(bend, "r", valueOr(bend, "backGaugeRPosition",
                                                     defaultBackGaugeRPositionInch)),
                            defaultBackGaugeRPositionInch)
    }

    function runBendDirection(bend) {
        var value = String(valueOr(bend, "direction", valueOr(bend, "bendDirection", valueOr(bend, "flangeDirection", "UP"))))
        return value.length > 0 ? value.toUpperCase() : "UP"
    }

    function runDieFaceStatus(bend) {
        var face = String(valueOr(bend, "dieFace", valueOr(bend, "face", "TOP"))).toUpperCase()
        var opening = valueOr(bend, "dieOpening", valueOr(bend, "vOpening", ""))
        if (opening !== "")
            return "FACE " + face + "  |  V " + (metricUnits && isFinite(Number(opening)) ? (Number(opening) * 25.4).toFixed(2) + " mm" : opening + "\"")
        return "FACE " + face
    }

    function runSceneInfoText() {
        var bend = selectedBend || ({})
        return "Placement / Live preview\n" +
            "X0 = die centerline\n" +
            "R0 = active die work surface\n" +
            "Punch: " + String(valueOr(bend, "punch", "UNDEFINED")) + "\n" +
            "Die: " + String(valueOr(bend, "die", "UNDEFINED")) + "\n" +
            "Start: " + runRamTargetText("startPosition", " in") + "\n" +
            "Clamp: " + runRamTargetText("clampPosition", " in") + "\n" +
            "Final: " + runRamTargetText("finalPosition", " in") + "\n" +
            "Retract: " + runRamTargetText("retractPosition", " in") + "\n\n" +
            "Use GUIDES in Live for hard stop, home, ram-to-table, stroke, travel, and table references.\n" +
            "SIM RUN auto-switches to Live."
    }

    function runSimulationHeader1() {
        if (programBends.length === 0 || selectedRunBend < 0)
            return "NO BENDS"
        var bend = selectedBend
        return "B" + String(selectedRunBend + 1) + "/" + String(programBends.length) + "  |  " + (bend.angle || "90.0") + "°  |  " + compactPunchName(bend.punch) + "  |  " + compactDieName(bend.die, bend)
    }

    function runSimulationHeader2() {
        if (programBends.length === 0 || selectedRunBend < 0)
            return "Select or create a bend program"
        var bend = selectedBend
        return "BG X " + (metricUnits ? (Number(bend.x || 0) * 25.4).toFixed(2) + " mm" : (bend.x || "0.0000") + "\"") + "  |  R "
            + (metricUnits ? (runBendRPosition(bend) * 25.4).toFixed(2) + " mm" : runBendRPosition(bend).toFixed(4) + "\"")
            + "  |  DIR " + runBendDirection(bend) + "  |  " + runDieFaceStatus(bend)
    }

    // createBendAction: optional `allBendRecords` is the full library bends array
    // (dataStore.bends). When present + FileIo available, create/save/duplicate/delete
    // persist the updated bends.json (backup-guarded); otherwise the existing sandbox
    // behavior is preserved unchanged.
    function createBendAction(action, bendName, bend, punch, die, material, finalPosition, tonnage, allBendRecords) {
        log("CREATE BEND", action + " " + bendName)
        if (action === "load") {
            var loadDraft = bendFromCreateDraft(bendName, bend, punch, die, material, finalPosition, tonnage)
            var validationMessages = validateProgramBend(loadDraft)
            if (validationMessages.length > 0) {
                showAlarm("LOAD BEND INTO PROGRAM", validationMessages.join("\n"))
                return { ok: false, reason: "validation", messages: validationMessages }
            }
            var loadedBend = appendBendToProgram(loadDraft)
            var programPersisted = storageBackendReady ? persistEntities("programs", programs) : false
            if (storageBackendReady && !programPersisted) {
                showAlarm("LOAD BEND INTO PROGRAM", "Could not write programs.json safely. The bend remains in the current session.")
                return { ok: false, reason: "persistence", bend: loadedBend }
            }
            recordSandboxWrite("bends", "load-into-program", loadedBend.name)
            showPopup("LOAD BEND INTO PROGRAM", loadedBend.name + " added to " + activeProgram + " as bend " + String(loadedBend.seq) + (programPersisted ? " and saved safely." : "."), 1, "message", "CLOSE")
            return { ok: true, bend: loadedBend, persisted: programPersisted }
        }
        if (action === "save" || action === "create" || action === "duplicate")
            recordSandboxWrite("bends", action, bendName)
        // Real persistence path (packaged app with FileIo + records provided).
        var canPersist = storageBackendReady && allBendRecords !== undefined && allBendRecords !== null
        if (canPersist && (action === "save" || action === "create" || action === "duplicate" || action === "delete")) {
            var nextBends = updatedBendLibrary(action, bendName, allBendRecords, bend, punch, die, material, finalPosition, tonnage)
            var ok = persistEntities("bends", nextBends)
            if (ok) {
                var verb = action === "delete" ? "deleted from" : "saved to"
                showPopup(action.toUpperCase() + " BEND", bendName + " " + verb + " bends.json (backup-guarded).", 1, "message", "CLOSE")
                return { ok: true, records: nextBends, persisted: true }
            }
            showAlarm(action.toUpperCase() + " BEND", "Could not write bends.json safely. No changes were made to production storage.")
            return { ok: false, records: allBendRecords, persisted: false }
        }
        if (action === "save" || action === "create" || action === "duplicate" || action === "delete") {
            var sandboxRecords = updatedBendLibrary(action, bendName, allBendRecords || [], bend, punch, die, material, finalPosition, tonnage)
            showAlarm(action.toUpperCase() + " BEND", "Persistent storage is unavailable. The bend was not saved.")
            return { ok: false, records: sandboxRecords, persisted: false, reason: "storage-unavailable" }
        }
        showPopup("CREATE BEND", action.toUpperCase() + " requested for " + bendName, 1)
        return { ok: true }
    }

    // Produces the updated library bends array for a create/save/duplicate/delete action,
    // matching by name (create-bend identity in the legacy app is the bend name).
    function updatedBendLibrary(action, bendName, records, bend, punch, die, material, finalPosition, tonnage) {
        var next = (records || []).slice(0)
        var draft = bendFromCreateDraft(bendName, bend, punch, die, material, finalPosition, tonnage)
        var matchIndex = -1
        var draftId = String(draft.id || "")
        for (var i = 0; i < next.length; i++) {
            if ((draftId.length > 0 && String(next[i].id || "") === draftId)
                    || (draftId.length === 0 && String(next[i].name || "") === String(bendName)))
                { matchIndex = i; break }
        }
        if (action === "delete") {
            if (matchIndex >= 0)
                next.splice(matchIndex, 1)
            return next
        }
        if (action === "duplicate") {
            var dupName = nextUnusedBendName(String(bendName) + " COPY", next)
            next.push(Object.assign({}, draft, {
                id: "bend-" + String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000000)),
                name: dupName,
                dateCreated: new Date().toISOString()
            }))
            return next
        }
        // save / create: upsert by name
        if (matchIndex >= 0)
            next[matchIndex] = Object.assign({}, next[matchIndex], draft)
        else
            next.push(draft)
        return next
    }

    function nextUnusedBendName(base, records) {
        var taken = {}
        for (var i = 0; i < (records || []).length; i++)
            taken[String(records[i].name || "")] = true
        if (!taken[base]) return base
        for (var n = 1; n < 1000; n++) {
            var candidate = base + " " + n
            if (!taken[candidate]) return candidate
        }
        return base + " " + Date.now()
    }

    function recordSandboxWrite(domain, action, detail) {
        var entry = { time: timestamp(), domain: domain, action: action, detail: detail }
        var next = sandboxWrites.slice(0)
        next.unshift(entry)
        if (next.length > 80)
            next.length = 80
        sandboxWrites = next
        log("SANDBOX", domain + " " + action + " " + detail)
    }

    function sandboxJson() {
        var lines = ["{"]
        lines.push("  \"updatedAt\": \"" + timestamp() + "\",")
        lines.push("  \"writes\": [")
        for (var i = 0; i < sandboxWrites.length; i++) {
            var write = sandboxWrites[i]
            lines.push("    {\"time\": \"" + write.time + "\", \"domain\": \"" + write.domain + "\", \"action\": \"" + write.action + "\", \"detail\": \"" + String(write.detail).replace(/\"/g, "'") + "\"}" + (i === sandboxWrites.length - 1 ? "" : ","))
        }
        lines.push("  ]")
        lines.push("}")
        return lines.join("\n")
    }

    function exportSandbox() {
        try {
            var request = new XMLHttpRequest()
            request.open("PUT", Qt.resolvedUrl("data/sandbox/qml-sandbox-actions.json"), false)
            request.send(sandboxJson())
            showPopup("SANDBOX SAVED", "QML sandbox actions saved to data/sandbox/qml-sandbox-actions.json", 1)
        } catch (error) {
            showAlarm("SANDBOX SAVE FAILED", String(error))
        }
    }

    // Maps a Tools module "kind" to the storage file key used by persistEntities/loadEntities.
    function toolStorageKind(kind) {
        var k = String(kind || "").toLowerCase()
        if (k === "punch") return "punches"
        if (k === "die") return "dies"
        if (k === "material") return "materials"
        return k
    }

    function showHostFailure(title) {
        var detail = hostSystem && String(hostSystem.lastError || "").length > 0
            ? String(hostSystem.lastError) : "Host service is unavailable."
        showAlarm(title, detail)
    }

    function refreshWifiNetworks() {
        if (!hostSystem)
            return false
        hostSystem.refreshWifi()
        if (String(hostSystem.lastError || "").length > 0) {
            if (hostOperationsAvailable)
                showHostFailure("WIFI REFRESH")
            return false
        }
        return true
    }

    function connectWifiNetwork(ssid, password) {
        if (!hostOperationsAvailable || !hostSystem
                || !hostSystem.connectWifi(String(ssid || ""), String(password || ""))) {
            showHostFailure("WIFI CONNECTION")
            return false
        }
        popupBody = "CONNECTING TO " + String(ssid || "") + "…"
        return true
    }

    function disconnectWifiNetwork(ssid) {
        if (!hostOperationsAvailable || !hostSystem
                || !hostSystem.disconnectWifi(String(ssid || ""))) {
            showHostFailure("WIFI DISCONNECT")
            return false
        }
        popupBody = "NOT CONNECTED"
        return true
    }

    function refreshSystemLogs() {
        if (!hostSystem)
            return false
        hostSystem.refreshSystemLogs()
        if (hostOperationsAvailable && String(hostSystem.lastError || "").length > 0) {
            showHostFailure("REFRESH SYSTEM LOGS")
            return false
        }
        return true
    }

    function exportSystemLogs() {
        if (!hostOperationsAvailable || !hostSystem || !hostSystem.exportSystemLogs("")) {
            showHostFailure("EXPORT SYSTEM LOGS")
            return false
        }
        showPopup("SYSTEM LOGS EXPORTED", String(hostSystem.lastResult || "Export complete."), 1, "message", "CLOSE")
        return true
    }

    function createHostBackup() {
        if (!hostOperationsAvailable || !hostSystem || !hostSystem.createBackup("")) {
            showHostFailure("CREATE BACKUP")
            return false
        }
        showPopup("BACKUP COMPLETE", String(hostSystem.lastResult || "Backup created."), 1, "message", "CLOSE")
        return true
    }

    function stageSelectedSoftwareUpdate() {
        if (!hostOperationsAvailable || !hostSystem) {
            showHostFailure("UPDATE SOFTWARE")
            return false
        }
        if (String(selectedUpdatePackage || "").trim().length === 0) {
            showAlarm("UPDATE SOFTWARE", "Select an update package from USB before staging it.")
            return false
        }
        showConfirmation("STAGE SOFTWARE UPDATE",
            "Stage the selected package? This does not apply or restart the application.",
            function() {
                if (!hostSystem.stageSoftwareUpdate(selectedUpdatePackage, true)) {
                    showHostFailure("UPDATE SOFTWARE")
                    return
                }
                showPopup("UPDATE STAGED", String(hostSystem.lastResult || "Package staged."), 1, "message", "CLOSE")
            })
        return true
    }

    // toolAction now accepts the current records array so SAVE/NEW/DUPLICATE/DELETE can be
    // persisted (backup-guarded) when a real FileIo backend is present. Without FileIo
    // (e.g. running under qml.exe) it falls back to the existing sandbox behavior and never
    // mutates production JSON.
    function toolAction(kind, action, records, selectedIndex) {
        log("TOOLS", kind + " " + action)
        recordSandboxWrite(kind, action.toLowerCase(), kind)
        var persistableAction = (action === "SAVE" || action === "NEW" || action === "DUPLICATE" || action === "DELETE")
        if (persistableAction && records !== undefined && records !== null && storageBackendReady) {
            var storageKind = toolStorageKind(kind)
            var nextRecords = JSON.parse(JSON.stringify(records || []))
            var index = Math.max(0, Math.min(Number(selectedIndex || 0), Math.max(0, nextRecords.length - 1)))
            var selected = nextRecords.length > 0 ? nextRecords[index] : null
            if (action === "NEW") {
                var newName = nextUnusedName("NEW " + kind.toUpperCase(), nextRecords)
                selected = kind === "material"
                    ? { id: uniqueEntityId(kind, [nextRecords]), name: newName, stock: false,
                        materialTensileStrengthPsi: 0, insideRadiusRuleOfThumb: 0,
                        materialSpringback: 0, thicknessToolingPreferences: [] }
                    : { id: uniqueEntityId(kind, [nextRecords]), name: newName, stock: false,
                        heightInch: 0, segmentCount16In: 0, segmentCount8In: 0,
                        segmentCount4In: 0, segmentCount2In: 0, segmentCount1In: 0 }
                nextRecords.push(selected)
                index = nextRecords.length - 1
            } else if (action === "DUPLICATE" && selected) {
                selected = Object.assign({}, selected, {
                    id: uniqueEntityId(kind, [nextRecords]),
                    name: nextUnusedName(String(selected.name || kind.toUpperCase()) + " COPY", nextRecords),
                    stock: false
                })
                nextRecords.push(selected)
                index = nextRecords.length - 1
            } else if (action === "DELETE" && selected) {
                if (selected.stock === true) {
                    showAlarm("DELETE " + kind.toUpperCase(), "Stock records cannot be deleted.")
                    return { ok: false, records: records, selectedIndex: index, reason: "stock-record" }
                }
                var references = entityReferences(toolStorageKind(kind), selected.id)
                if (references.length > 0) {
                    showAlarm("DELETE " + kind.toUpperCase(), "Record is used by " + references.join(", ") + ". Replace those references before deleting it.")
                    return { ok: false, records: records, selectedIndex: index, reason: "referenced-record" }
                }
                nextRecords.splice(index, 1)
                index = Math.max(0, Math.min(index, nextRecords.length - 1))
            }
            var ok = persistEntities(storageKind, nextRecords)
            if (ok) {
                showPopup("SAVE " + kind.toUpperCase(), kind.toUpperCase() + " saved to storage (backup-guarded).", 1)
                return { ok: true, records: nextRecords, selectedIndex: index, persisted: true }
            }
            showAlarm("SAVE " + kind.toUpperCase(), "Could not write " + storageKind + ".json safely. No changes were made to production storage.")
            return { ok: false, records: records, selectedIndex: index, persisted: false }
        }
        if (persistableAction) {
            showAlarm(action + " " + kind.toUpperCase(), "Persistent storage is unavailable. No changes were saved.")
            return { ok: false, records: records || [], selectedIndex: selectedIndex || 0,
                persisted: false, reason: "storage-unavailable" }
        }
        return { ok: true, records: records || [], selectedIndex: selectedIndex || 0, persisted: false }
    }

    function entityReferences(storageKind, entityId) {
        var references = []
        var id = String(entityId || "")
        if (id.length === 0)
            return references
        var storedBends = loadEntities("bends")
        for (var bendIndex = 0; bendIndex < storedBends.length; bendIndex++) {
            var bend = storedBends[bendIndex] || {}
            var referenced = (storageKind === "punches" && String(bend.punchId || "") === id)
                || (storageKind === "dies" && String(bend.dieId || "") === id)
                || (storageKind === "materials" && String(bend.materialId || "") === id)
            if (referenced)
                references.push(String(bend.name || bend.id || "stored bend"))
        }
        for (var programIndex = 0; programIndex < programs.length; programIndex++) {
            var program = programs[programIndex] || {}
            var bends = program.bends || []
            for (var inlineIndex = 0; inlineIndex < bends.length; inlineIndex++) {
                var inlineBend = bends[inlineIndex] || {}
                var inlineReferenced = (storageKind === "punches" && String(inlineBend.punchId || "") === id)
                    || (storageKind === "dies" && String(inlineBend.dieId || "") === id)
                    || (storageKind === "materials" && String(inlineBend.materialId || "") === id)
                if (inlineReferenced) {
                    references.push(String(program.name || "program"))
                    break
                }
            }
        }
        return references
    }

    function settingsAction(action) {
        log("SETTINGS", action)
        if (action === "REFRESH WIFI") {
            refreshWifiNetworks()
            return
        }
        if (action === "REFRESH LOGS") {
            refreshSystemLogs()
            return
        }
        if (action === "UPDATE SOFTWARE") {
            stageSelectedSoftwareUpdate()
            return
        }
        if (action === "FLASH MODULE") {
            showAlarm(action, "Firmware flashing remains disabled until the machine command lifecycle is authoritative.")
            return
        }
        if (action === "Legacy Run UI") {
            legacyRunUiEnabled = !legacyRunUiEnabled
            runBendListVisible = false
            runSimulatedRun = false
            persistLegacyRunUiSetting()
            recordSandboxWrite("settings", "legacyRunUiEnabled", legacyRunUiEnabled)
            return
        }
        if (action === "Run Preview Debug Logs") {
            runPreviewDebugLogsEnabled = !runPreviewDebugLogsEnabled
            persistLocalSetting("runPreviewDebugLogsEnabled", runPreviewDebugLogsEnabled)
            recordSandboxWrite("settings", "runPreviewDebugLogsEnabled", runPreviewDebugLogsEnabled)
            return
        }
        if (action === "Run Preview Debug Overlays") {
            runPreviewDebugOverlaysEnabled = !runPreviewDebugOverlaysEnabled
            persistLocalSetting("runPreviewDebugOverlaysEnabled", runPreviewDebugOverlaysEnabled)
            recordSandboxWrite("settings", "runPreviewDebugOverlaysEnabled", runPreviewDebugOverlaysEnabled)
            return
        }
        if (action === "Flat Pattern Contours") {
            runFlatPatternContourRenderer = runFlatPatternContourRenderer === "classic" ? "canonical" : (runFlatPatternContourRenderer === "canonical" ? "overlay" : "classic")
            persistLocalSetting("runFlatPatternContourRenderer", runFlatPatternContourRenderer)
            recordSandboxWrite("settings", "runFlatPatternContourRenderer", runFlatPatternContourRenderer)
            log("SETTINGS", "Flat Pattern Contours " + runFlatPatternContourRenderer)
            return
        }
        if (action === "Tooling Appearance") {
            setRunToolingAppearance(runToolingAppearance === "SOLID" ? "TRANSLUCENT" : "SOLID")
            return
        }
        // Phase 5.3: application/controller toggles bound to the validated models.
        // Each routes through persistLocalSetting (backup-guarded FileIo or sandbox).
        if (action === "Safety Warnings") {
            safetyPopupsEnabled = !safetyPopupsEnabled
            persistLocalSetting("safetyPopupsEnabled", safetyPopupsEnabled)
            return
        }
        if (action === "Frame Deflection Compensation") {
            // Firmware-owned ($1): the controller adds tonnage-proportional
            // travel per ram (0.0028 in/t). The host only toggles it.
            const fwComp = machineControl ? Number(machineControl.deflectionCompensation) : -1
            const current = fwComp >= 0 ? fwComp === 1 : desktopFrameDeflectionCompensationEnabled
            const next = !current
            if (machineControl && typeof machineControl.setDeflectionCompensation === "function"
                    && fwComp >= 0) {
                if (!machineControl.setDeflectionCompensation(next)) {
                    log("SETTINGS", "Frame deflection compensation write rejected (press must be IDLE and connected)")
                    return
                }
                log("SETTINGS", "Frame deflection compensation -> " + (next ? "ON" : "OFF") + " ($1 sent)")
            } else {
                log("SETTINGS", "Frame deflection compensation stored offline; press not connected")
            }
            desktopFrameDeflectionCompensationEnabled = next
            persistLocalSetting("desktopFrameDeflectionCompensationEnabled", next)
            return
        }
        if (action === "Auto Measure On Clamp") {
            autoMeasureOnClampEnabled = !autoMeasureOnClampEnabled
            persistLocalSetting("autoMeasureOnClampEnabled", autoMeasureOnClampEnabled)
            log("SETTINGS", "Auto measure on clamp " + (autoMeasureOnClampEnabled ? "enabled" : "disabled"))
            return
        }
        if (action === "Calibration Convergence") {
            manualCalibrationConvergenceEnabled = !manualCalibrationConvergenceEnabled
            persistLocalSetting("manualCalibrationConvergenceEnabled", manualCalibrationConvergenceEnabled)
            log("SETTINGS", "Calibration convergence " + (manualCalibrationConvergenceEnabled
                ? "enabled (accept when stable)" : "disabled (fixed "
                  + manualMeasurementRequiredSamples + " samples)"))
            return
        }
        if (action === "Measurement Convergence") {
            manualMeasurementConvergenceEnabled = !manualMeasurementConvergenceEnabled
            persistLocalSetting("manualMeasurementConvergenceEnabled", manualMeasurementConvergenceEnabled)
            log("SETTINGS", "Measurement convergence " + (manualMeasurementConvergenceEnabled
                ? "enabled (accept when stable)" : "disabled (fixed "
                  + manualMeasurementRequiredSamples + " samples)"))
            return
        }
        if (action === "Tonnage Protection") {
            tonnageProtectionEnabled = !tonnageProtectionEnabled
            recordSandboxWrite("settings", "tonnageProtectionEnabled", tonnageProtectionEnabled)
            log("SETTINGS", "Tonnage Protection " + (tonnageProtectionEnabled ? "enabled" : "disabled"))
            return
        }
        if (action === "RESTORE DEFAULTS") {
            localSettingsModel = SettingsModel.defaultLocalSettings()
            userSettingsModel = SettingsModel.defaultUserSettings()
            applyLocalSettings(localSettingsModel)
            applyUserSettings(userSettingsModel)
            var localSaved = storageBackendReady && SettingsModel.save(
                writableCurrentDataPath("local-settings.json"), localSettingsModel, settingsIo(), {}).ok
            var userSaved = storageBackendReady && SettingsModel.save(
                writableCurrentDataPath("user-settings.json"), userSettingsModel, settingsIo(), {}).ok
            if (localSaved && userSaved)
                showPopup("RESTORE DEFAULTS", "Factory defaults restored and saved.", 1, "message", "CLOSE")
            else
                showAlarm("RESTORE DEFAULTS", "Defaults were loaded in memory but could not be saved safely.")
            return
        }
        if (action === "CANCEL") {
            editedRamToTableOpening = NaN
            return
        }
        if (action === "SAVE") {
            var requestedOpening = Number(editedRamToTableOpening)
            if (!isFinite(requestedOpening))
                return
            requestedOpening = Math.max(7.950, Math.min(8.750, requestedOpening))
            if (offlineSimulationEnabled) {
                desktopRamToTableOpening = requestedOpening
                persistLocalSetting("desktopRamToTableOpening", requestedOpening)
                editedRamToTableOpening = NaN
                return
            }
            if (!machineControl || !machineControl.setRamToTableOpening(requestedOpening))
                return
            ramToTableSaveOperationId = Number(machineControl.operationId)
            return
        }
        if (action === "SAVE" || action === "RESET" || action === "RESTORE DEFAULTS" || action.indexOf("DIRECT INPUT") === 0)
            recordSandboxWrite("settings", action.toLowerCase(), action)
    }

    function setManualPending(operation, action, stateText) {
        manualPendingOperation = operation
        manualPendingOperationId = !offlineSimulationEnabled && machineControl
                ? Number(machineControl.operationId) : undefined
        manualPendingAction = action
        manualModeState = stateText
    }

    function clearManualPending() {
        manualPendingOperation = ""
        manualPendingOperationId = undefined
        manualPendingAction = ""
        manualPendingPreviousSetting = undefined
        manualModeState = manualModeEnabled ? "ENABLED" : "DISABLED"
    }

    function failManualLifecycle() {
        if (manualPendingOperation.length === 0 && !manualActivationPending
                && !manualLeavePending && !tonnageHoldActive
                && !contactProfileActive)
            return
        manualActivationPending = false
        manualLeavePending = false
        manualModeArmed = false
        tonnageHoldActive = false
        finishTonnageHoldProfile(false, "MANUAL_LIFECYCLE_FAILED")
        manualRepeatStroke = false
        manualRepeatJog = false
        clearManualPending()
        manualModeState = "DISABLED"
    }
    function activateManualMode() {
        if (offlineSimulationEnabled) {
            manualModeArmed = true
            manualModeState = "ENABLED"
            return true
        }
        // The controller may already be in Manual after an API commissioning
        // cycle or a retained temporary-status update. Re-entering the menu is
        // idempotent: refresh its bounded tonnage limit instead of asking the
        // backend to reject a duplicate ManualEnable as INVALID_ARGUMENT.
        if (manualModeEnabled) {
            if (!machineControl
                    || !machineControl.setManualModeMaxTonnage(manualModeMaxTonnagePerRam))
                return false
            manualActivationPending = true
            setManualPending("manual-max-tonnage", "activate", "ENABLING")
            return true
        }
        if (!machineControl || !machineControl.setManualModeEnabled(true))
            return false
        manualActivationPending = true
        setManualPending("manual-enable", "activate", "ENABLING")
        return true
    }

    function deactivateManualMode() {
        manualRepeatStroke = false
        manualRepeatJog = false
        if (offlineSimulationEnabled) {
            tonnageHoldActive = false
            manualModeArmed = false
            manualModeState = "DISABLED"
            return true
        }
        if (manualPendingOperation.length > 0
            || (machineControl && machineControl.pressOperationActive)) {
            showAlarm("MANUAL MODE BUSY",
                      "Stop the active Manual operation and wait for controller confirmation before leaving Manual mode.")
            return false
        }
        if (!machineControl || (!manualModeEnabled && !manualActivationPending)) {
            manualModeState = "DISABLED"
            return true
        }
        if (!machineControl.setManualModeEnabled(false))
            return false
        manualLeavePending = true
        setManualPending("manual-disable", "deactivate", "DISABLING")
        return true
    }

    function rollbackFailedManualActivation(failureText) {
        manualActivationPending = false
        manualModeArmed = false
        tonnageHoldActive = false
        manualRepeatStroke = false
        manualRepeatJog = false
        clearManualPending()
        if (machineControl && machineControl.setManualModeEnabled(false)) {
            manualLeavePending = true
            setManualPending("manual-disable", "activation-failure",
                             "DISABLING AFTER ACTIVATION FAILURE")
            showAlarm("MANUAL ACTIVATION FAILED",
                      failureText + " Manual mode is being disabled and remains unavailable until controller confirmation.")
            return
        }
        manualLeavePending = false
        manualModeState = "DISABLE REQUIRED"
        showAlarm("MANUAL ACTIVATION FAILED",
                  failureText + " Automatic Manual disable was not admitted. Manual controls remain locked; retry leaving Manual mode or disconnect the controller safely.")
    }

    function handleManualOperationFinished(operation, state, error) {
        if (manualPendingOperation.length === 0 || operation !== manualPendingOperation)
            return false
        if (state !== "COMPLETED") {
            var failedAction = manualPendingAction
            if (operation === "manual-max-tonnage"
                    && manualPendingPreviousSetting !== undefined) {
                var previousSetting = manualPendingPreviousSetting
                userSettingsModel.manualModeMaxTonnagePerRam = previousSetting
                userSettingsModel = Object.assign({}, userSettingsModel)
                manualModeMaxTonnagePerRam = Number(previousSetting)
                persistUserSetting("manualModeMaxTonnagePerRam", previousSetting)
            }
            var failureText = operation.replace(/-/g, " ").toUpperCase() + ": "
                    + String(error || state).replace(/_/g, " ") + "."
            if (operation === "manual-enable"
                    || (operation === "manual-max-tonnage" && failedAction === "activate")) {
                rollbackFailedManualActivation(failureText)
                return true
            }
            if (operation === "manual-disable") {
                manualActivationPending = false
                manualLeavePending = false
                manualModeArmed = false
                tonnageHoldActive = false
                manualRepeatStroke = false
                manualRepeatJog = false
                clearManualPending()
                manualModeState = "DISABLE REQUIRED"
                showAlarm("MANUAL DISABLE FAILED",
                          failureText + " Manual controls remain locked. Retry leaving Manual mode or disconnect the controller safely.")
                return true
            }
            manualActivationPending = false
            manualLeavePending = false
            tonnageHoldActive = false
            manualRepeatStroke = false
            manualRepeatJog = false
            clearManualPending()
            var thStopRequested = tonnageHoldStopRequested
            tonnageHoldStopRequested = false
            if (operation === "tonnage-hold" && thStopRequested) {
                // Operator STOP of an armed/active pedal hold: the controller
                // ends it as an abort; that is the requested outcome, not a fault.
                log("TONNAGE HOLD", "Stopped by operator (" + String(error || state) + ")")
                return true
            }
            if (operation === "tonnage-hold"
                    && String(error || "").indexOf("FORCE_TIMEOUT") >= 0) {
                // Firmware still fails closed, revokes motion and confirms
                // IDLE. Pedal TH treats acquisition timeout as a quiet end;
                // AUTO keeps its dedicated timeout alarm unchanged.
                log("TONNAGE HOLD", "Pedal force acquisition ended before qualification")
                return true
            }
            showAlarm("MANUAL OPERATION FAILED",
                      failureText)
            return true
        }
        if (operation === "manual-enable") {
            if (!machineControl.setManualModeMaxTonnage(manualModeMaxTonnagePerRam)) {
                rollbackFailedManualActivation(
                            "The temporary tonnage limit command was rejected.")
                return true
            }
            setManualPending("manual-max-tonnage", "activate", "ENABLING")
            return true
        }
        if (operation === "manual-disable") {
            manualLeavePending = false
            manualModeArmed = false
            clearManualPending()
            return true
        }
        if (operation === "manual-max-tonnage") {
            if (manualPendingAction === "activate") {
                manualActivationPending = false
                manualModeArmed = true
            }
            clearManualPending()
            return true
        }
        if (operation === "tonnage-hold") {
            tonnageHoldActive = false
            tonnageHoldStopRequested = false
            clearManualPending()
            return true
        }

        var repeatAction = manualPendingAction
        clearManualPending()
        if (repeatAction === "stroke" && manualRepeatStroke)
            Qt.callLater(function() { manualAction("stroke") })
        else if (repeatAction === "jog-down" && manualRepeatJog
                 && ramPositionY1 - manualJogStep >= -4.0)
            Qt.callLater(function() { manualAction("jog-down") })
        else if (repeatAction === "jog-down" && manualRepeatJog) {
            manualRepeatJog = false
            showAlarm("MANUAL JOG TRAVEL LIMIT", "The next -Y jog step would exceed machine travel.")
        }
        return true
    }

    function manualAction(action, value) {
        if (action === "automatic-tonnage-hold") {
            if (contactProfileActive)
                return cancelTonnageHoldProfile()
            return startTonnageHoldProfile(value !== undefined && isFinite(Number(value))
                                           ? Number(value) : Number(tonnageHoldTarget),
                                           "MANUAL", true)
        }
        if (action === "toggle-repeat-stroke") {
            if (!offlineSimulationEnabled && !pressCanOperate)
                return false
            manualRepeatStroke = !manualRepeatStroke
            log("MANUAL", "Repeat stroke " + (manualRepeatStroke ? "enabled" : "disabled"))
            return true
        }
        if (action === "toggle-repeat-jog") {
            if (!offlineSimulationEnabled && !pressCanOperate)
                return false
            manualRepeatJog = !manualRepeatJog
            log("MANUAL", "Repeat jog " + (manualRepeatJog ? "enabled" : "disabled"))
            return true
        }
        if (action === "jog-step")
            return setManualSetting("jogStep", value)

        if (!offlineSimulationEnabled) {
            if (!machineControl) {
                showMachineRejection("MANUAL " + action.toUpperCase())
                return false
            }
            if (!pressCanOperate) {
                showAlarm("MANUAL MODE NOT ENABLED",
                          manualModeState === "DISABLE REQUIRED"
                          ? "Manual disable was not confirmed. Motion remains locked until disable succeeds or the controller is disconnected safely."
                          : "Confirm Manual mode activation before dispatching machine motion.")
                return false
            }
            var currentPosition = ramPositionY1
            if (action === "jog-up") {
                if (machineControl.jogPress(currentPosition + manualJogStep, jogRamSpeed, "retract")) {
                    setManualPending("jog-retract", action, "MANUAL JOG STEP RUNNING")
                    return true
                }
                return false
            }
            if (action === "jog-down") {
                if (machineControl.jogPress(currentPosition - manualJogStep, jogRamSpeed, "safety")) {
                    setManualPending("jog-safety", action, "MANUAL JOG STEP RUNNING")
                    return true
                }
                return false
            }
            if (action === "move-to") {
                var target = Number(value)
                // More-negative targets retain the physical safety-button
                // hold-to-run gate; more-positive targets use the dedicated
                // automatic Move To retract path. Standalone panel controls
                // continue to use their host-held panel-* command types.
                var moveType = target > currentPosition ? "move-retract" : "safety"
                if (machineControl.jogPress(target, jogRamSpeed, moveType)) {
                    setManualPending("jog-" + moveType, action,
                                     "MANUAL MOVE TO POSITION RUNNING")
                    return true
                }
                return false
            }
            if (action === "continuous-down") {
                if (machineControl.jogPress(-4.0, jogRamSpeed, "safety")) {
                    setManualPending("jog-safety", action,
                                     "MANUAL CONTINUOUS JOG RUNNING")
                    return true
                }
                return false
            }
            if (action === "stroke") {
                if (machineControl.startManualStroke(manualSafetyPlaneClearance
                        + manualStartRamPosition, manualEndRamPosition,
                        jogRamSpeed, bendRamSpeed)) {
                    setManualPending("manual-stroke", action, "MANUAL STROKE RUNNING")
                    return true
                }
                return false
            }
            if (action === "tonnage-hold") {
                if (tonnageHoldActive) {
                    if (!machineControl.stopTonnageHold())
                        return false
                    tonnageHoldStopRequested = true
                    setManualPending("tonnage-hold", action,
                                     "CONSTANT TONNAGE HOLD STOPPING")
                    return true
                }
                var holdTarget = value !== undefined && isFinite(Number(value))
                    ? Number(value) : tonnageHoldTarget
                if (!machineControl.startTonnageHold(holdTarget, bendRamSpeed, jogRamSpeed))
                    return false
                tonnageHoldActiveTarget = holdTarget
                tonnageHoldActive = true
                setManualPending("tonnage-hold", action,
                                 "CONSTANT TONNAGE HOLD ARMED")
                return true
            }
            return false
        }
        if (action === "stroke") {
            manualModeState = manualRepeatStroke ? "REPEAT STROKE" : "STROKE"
            machineStatus = "MANUAL STROKE"
            commandedJogPosition = 1
            commandedJogSpeed = bendRamSpeed
            distanceToGo = 1
            liveTonnage = 2.4
            showPopup("MANUAL STROKE", "Manual stroke operation armed. Safety plane 0.5000 in, end position 1.0000 in.", 0.45)
        } else if (action === "jog-up" || action === "jog-down") {
            var direction = action === "jog-up" ? 1 : -1
            manualModeState = "JOG"
            machineStatus = "MANUAL JOG"
            ramPosition += direction * manualJogStep
            commandedJogPosition = ramPosition
            commandedJogSpeed = jogRamSpeed
            distanceToGo = manualRepeatJog ? manualJogStep : 0
            log("MANUAL", (direction > 0 ? "Y up" : "Y down") + " " + manualJogStep.toFixed(4) + " in")
        } else if (action === "move-to") {
            manualModeState = "MOVE TO"
            machineStatus = "MANUAL MOVE"
            commandedJogPosition = Number(value)
            distanceToGo = Math.abs(commandedJogPosition - ramPosition)
            showPopup("MANUAL MOVE TO", "Move Y axis to " + commandedJogPosition.toFixed(4) + " in machine coordinate.", 0.5)
        } else if (action === "continuous-down") {
            manualModeState = "CONTINUOUS JOG"
            machineStatus = "MANUAL JOG"
            commandedJogSpeed = jogRamSpeed
            log("MANUAL", "Continuous Y down jog requested")
        } else if (action === "tonnage-hold") {
            var offlineHoldTarget = value !== undefined && isFinite(Number(value))
                ? Number(value) : tonnageHoldTarget
            if (!tonnageHoldActive)
                tonnageHoldActiveTarget = offlineHoldTarget
            tonnageHoldActive = !tonnageHoldActive
            manualModeState = tonnageHoldActive
                ? "CONSTANT TONNAGE HOLD RUNNING" : "ENABLED"
            liveTonnage = tonnageHoldActive ? offlineHoldTarget : 0
            showPopup("TONNAGE HOLD", tonnageHoldActive
                ? "Constant tonnage hold started at " + offlineHoldTarget.toFixed(2) + " T target."
                : "Constant tonnage hold stopped.", tonnageHoldActive ? 0.35 : 1)
        }
    }

    function cadAction(action) {
        if (action === "import") {
            cadImported = true
            cadFileName = "Fusion360_Enclosure_Box.json"
            cadPartName = "Enclosure Box"
            cadProgramName = "Enclosure Box - CAD Import"
            cadMaterial = "Cold Rolled Steel"
            cadThickness = "0.1250 in"
            cadFlatPattern = "14.000 x 8.000 in"
            cadBends = [
                { seq: "1", angle: "90.0", width: "6.000", flange: "1.000", tool: "Gooseneck / 4 Way", warning: "OK" },
                { seq: "2", angle: "90.0", width: "6.000", flange: "2.000", tool: "Gooseneck / 4 Way", warning: "OK" },
                { seq: "3", angle: "45.0", width: "3.500", flange: "0.750", tool: "Acute / V Die", warning: "CHECK" }
            ]
            cadBendCount = cadBends.length
            popupVisible = false
            log("CAD IMPORT", "Fusion 360 sheet metal design imported. " + cadBendCount + " bends detected.")
        } else if (action === "generate") {
            if (!cadImported) {
                showAlarm("CAD IMPORT REQUIRED", "Import a Fusion 360 sheet metal design before generating a program.")
                return
            }
            if (!cadBends || cadBends.length === 0) {
                showAlarm("NO BENDS DETECTED", "The imported file has no bend operations. Import a valid .bcbend file before generating a program.")
                return
            }
            if (cadHasErrors) {
                showAlarm("CAD IMPORT HAS ERRORS", "Fix the import errors before generating a program.")
                return
            }
            var normalizedProgramName = String(cadProgramName || "").trim()
            if (normalizedProgramName.length === 0)
                normalizedProgramName = String(cadPartName || "Imported Part").trim()
            if (normalizedProgramName.length === 0)
                normalizedProgramName = "Imported Part"
            cadProgramName = normalizedProgramName
            var generatedBends = []
            var storedBends = storageBackendReady ? loadEntities("bends") : []
            for (var i = 0; i < cadBends.length; i++) {
                var cadBend = cadBends[i]
                var selectedPunch = findById(cadPunchCatalog, cadBend.punchId || "")
                var selectedDie = findById(cadDieCatalog, cadBend.dieId || "")
                var bendCalculation = calcBendParity({
                    materialThickness: cadThicknessValue,
                    bendWidth: cadBend.widthValue,
                    desiredBendAngle: cadBend.angleValue,
                    angleCompensation: cadSpringBack,
                    punchToMaterialClearance: 0.0306
                }, selectedPunch, selectedDie, cadSelectedMaterial)
                if (!bendCalculation) {
                    showAlarm("CAD GENERATION FAILED", "Bend " + String(i + 1)
                        + " cannot be calculated with the selected punch, die, material, and thickness.")
                    return
                }
                generatedBends.push({
                    id: uniqueEntityId("bend", [storedBends, generatedBends]),
                    seq: i + 1,
                    name: cadProgramName + "-#" + String(cadBend.seq || i + 1),
                    angle: cadBend.angle || formatNumber(cadBend.angleValue, 1, "90.0"),
                    compensation: formatNumber(cadSpringBack, 1, "0.0"),
                    state: "CAD",
                    // Canonical editable inputs, identical to the calculation
                    // above, so CREATE BEND can edit/save and reloads keep
                    // the same START/FINAL depths.
                    materialThickness: cadThicknessValue,
                    desiredBendAngle: cadBend.angleValue,
                    angleCompensation: cadSpringBack,
                    angleCompensationReversed: false,
                    punchToMaterialClearance: 0.0306,
                    additionalRetractAfterBend: 0,
                    bendWidth: cadBend.widthValue,
                    width: formatNumber(cadBend.widthValue, 3, "0.000"),
                    backGaugeXPosition: finiteNumber(cadBend.processBgPosition, 0),
                    backGaugeRPosition: finiteNumber(cadBend.bgrValue, 0),
                    // Collision-checked unfold plan: side of the die the part
                    // enters from (flip) and the gauged edge distance.
                    unfoldFlip: cadBend.unfoldFlip === true,
                    // Planner tool frame is +X toward the backgauge; LIVE is
                    // +X toward the operator, so planned punches are drawn
                    // X-reflected unless the planner mounted them reversed.
                    unfoldPlanned: cadBend.unfoldStageId !== undefined,
                    unfoldPunchMirror: cadBend.unfoldPunchMirror === true,
                    unfoldGaugeIn: finiteNumber(cadBend.unfoldGaugeIn, NaN),
                    backGaugeJogSpeed: 100,
                    x: formatNumber(cadBend.processBgPosition, 4, "0.0000"),
                    r: formatNumber(cadBend.bgrValue, 4, "0.0000"),
                    speed: "100.000",
                    tonnage: cadBend.tonnage || formatNumber(cadBend.tonnageValue, 3, "0.000"),
                    thickness: cadThickness.replace(" in", ""),
                    material: cadMaterial,
                    materialId: cadSelectedMaterial && cadSelectedMaterial.id
                        ? cadSelectedMaterial.id : "",
                    punch: cadBend.punchName || cadBend.punch || "Punch",
                    die: cadBend.dieName || cadBend.die || "Die",
                    punchId: cadBend.punchId || "",
                    dieId: cadBend.dieId || "",
                    vdieValue: cadBend.vdieValue || 0,
                    vdie: cadBend.vdie || "",
                    toolingPhaseIndex: finiteNumber(cadBend.toolingPhaseIndex, 0),
                    punchSegmentWidths: cadBend.punchSegmentWidths
                        ? cadBend.punchSegmentWidths.slice(0) : [],
                    dieSegmentWidths: cadBend.dieSegmentWidths
                        ? cadBend.dieSegmentWidths.slice(0) : [],
                    punchSegmentStartIn: finiteNumber(cadBend.punchSegmentStartIn, NaN),
                    dieSegmentStartIn: finiteNumber(cadBend.dieSegmentStartIn, NaN),
                    toolingRackIndex: finiteNumber(cadBend.toolingRackIndex, NaN),
                    toolingStationOffsetIn: finiteNumber(cadBend.toolingStationOffsetIn, 0),
                    toolingCoStations: cadBend.toolingCoStations || [],
            toolingBendCenterIn: cadBend.toolingBendCenterIn !== undefined ? cadBend.toolingBendCenterIn : null,
                    punchInventoryShortage: cadBend.punchInventoryShortage === true,
                    dieInventoryShortage: cadBend.dieInventoryShortage === true,
                    startPosition: formatNumber(bendCalculation.startSafetyClearance, 4, "0.0000"),
                    clampPosition: formatNumber(bendCalculation.clampPosition, 4, "0.0000"),
                    finalPosition: formatNumber(bendCalculation.inUseFinalBendPosition, 4, "0.0000"),
                    notes: "Imported from CAD (" + cadPartName + ", " + (cadBend.dir || "UP") + ")\nSuggested sequence: " + String(cadBend.seq || i + 1) + "\nReference: " + (cadBend.ref || "EDGE") + " " + (cadBend.bg || "0.0000") + "\nSuggested setup: " + (cadBend.setup || "") + "\nSuggested punch: " + (cadBend.punchName || "") + "\nSuggested die: " + (cadBend.dieName || "")
                })
            }
            var previousPrograms = programs.slice(0)
            var previousSelectedProgramIndex = selectedProgramIndex
            var previousSelectedRunBend = selectedRunBend
            var replacedCadBendIds = ({})
            for (var existingProgramIndex = 0;
                    existingProgramIndex < previousPrograms.length;
                    existingProgramIndex++) {
                var existingCadProgram = previousPrograms[existingProgramIndex] || {}
                if (String(existingCadProgram.name || "").trim().toLowerCase()
                        !== cadProgramName.toLowerCase())
                    continue
                var existingCadBends = existingCadProgram.bends || []
                for (var existingBendIndex = 0;
                        existingBendIndex < existingCadBends.length;
                        existingBendIndex++) {
                    replacedCadBendIds[String(existingCadBends[existingBendIndex].id || "")] = true
                }
                break
            }
            setActiveProgram(cadProgramName, generatedBends, "cad", JSON.stringify(cadLoadedJson))
            cadProgramName = activeProgram
            recordSandboxWrite("cad", "generate-program", cadProgramName + " (" + cadBendCount + " bends)")
            var generatedSummary = "Generated program \"" + cadProgramName + "\" with "
                + String(generatedBends.length) + " bends"
            if (storageBackendReady) {
                var retainedStoredBends = []
                for (var storedBendIndex = 0;
                        storedBendIndex < storedBends.length;
                        storedBendIndex++) {
                    if (!replacedCadBendIds[String(storedBends[storedBendIndex].id || "")])
                        retainedStoredBends.push(storedBends[storedBendIndex])
                }
                var nextStoredBends = retainedStoredBends.concat(generatedBends)
                if (persistEntityTransaction([
                    { kind: "bends", items: nextStoredBends },
                    { kind: "programs", items: programs }
                ])) {
                    lastProgramPersistenceSucceeded = true
                    cadStatusMessage = generatedSummary + " and saved"
                    showCadGenerationResult(true)
                    return
                }
                programs = previousPrograms
                selectedProgramIndex = previousSelectedProgramIndex
                selectedRunBend = previousSelectedRunBend
                syncActiveProgramState()
                showAlarm("GENERATE PROGRAM", "Could not save bends.json and programs.json as one transaction. Previous files and in-memory program state were restored.")
                cadStatusMessage = generatedSummary + " failed to save"
                return
            }
            cadStatusMessage = generatedSummary + " for this session only (not saved)"
            showCadGenerationResult(false)
        }
    }
}
