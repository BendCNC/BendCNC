import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 640
    height: 480

    QtObject {
        id: backend
        property bool pressConnected: true
        property bool moduleConnected: true
        property string pressConnectionState: "READY"
        property string moduleConnectionState: "READY"
        property string pressMachineState: "IDLE"
        property string moduleState: "IDLE"
        property string pressFirmwareVersion: "1.2"
        property string moduleFirmwareVersion: "1.1h"
        property bool pressReady: true
        property bool moduleReady: true
        property bool pressHomed: true
        property bool moduleHomed: true
        property bool pressOperationActive: false
        property bool moduleOperationActive: false
        property bool pressTelemetryFresh: true
        property bool moduleTelemetryFresh: true
        property bool independentRamTelemetryAvailable: true
        property real ramPositionY1: 0.57
        property real ramPositionY2: 0.54
        property real ramTargetPosition: 0
        property real ramCommandedJogPosition: 0
        property real ramDistanceToGo: 0
        property real ramJogSpeed: 0
        property real ramVelocity: 0
        property real ramLoadY1: 0
        property real ramLoadY2: 0
        property bool safetyJogLeft: false
        property bool safetyJogRight: false
        property bool bendPedal: false
        property bool antiBind: false
        property string lastRejectReason: ""
        property int operationId: 0
        property int beginRunCalls: 0
        property int endRunCalls: 0
        property int setRetractCalls: 0
        property int moveCalls: 0
        property int incrementCalls: 0
        property int pressJogCalls: 0
        property int abortPressCalls: 0
        property int stopModuleCalls: 0
        property string lastPressJogType: ""
        property real lastPressTarget: 0
        property real lastRetractTarget: 0
        property real lastIncrement: 0
        property real ramToTableOpening: 8.3
        signal commandOperationFinished(int id, string device, string operation,
                                        string state, string error)
        signal connectionFailed(string device, string reason)
        signal operationRejected(string device, string operation, string reason)
        signal telemetryLogLine(string device, string line)

        function beginProgramRun() { beginRunCalls += 1; return true }
        function setRunPedalMode(mode) { return true }
        function setRemoteRunAllowed(allowed) { }
        function endProgramRun() { endRunCalls += 1 }
        function acceptOperation() { operationId += 1; return true }
        function setPressRetractPlane(value) {
            setRetractCalls += 1
            lastRetractTarget = value
            return acceptOperation()
        }
        function selectModuleCoordinateSystem(system) { return acceptOperation() }
        function moveModule(x, r, speed) { moveCalls += 1; return acceptOperation() }
        function incrementModule(axis, distance, speed) {
            incrementCalls += 1
            lastIncrement = distance
            return acceptOperation()
        }
        function jogPress(target, speed, type) {
            pressJogCalls += 1
            lastPressTarget = target
            lastPressJogType = type
            return acceptOperation()
        }
        function abortPress() { abortPressCalls += 1; return true }
        function stopModule() { stopModuleCalls += 1; return true }
    }

    BendCNC.AppState {
        id: state
        machineControl: backend
    }

    TestCase {
        name: "PhysicalRunRoutingTests"
        when: windowShown

        function init() {
            state.offlineSimulationEnabled = false
            state.bendJogPedal = Qt.binding(function() {
                return state.offlineSimulationEnabled ? false : backend.bendPedal
            })
            backend.beginRunCalls = 0
            backend.endRunCalls = 0
            backend.setRetractCalls = 0
            backend.moveCalls = 0
            backend.incrementCalls = 0
            backend.pressJogCalls = 0
            backend.abortPressCalls = 0
            backend.stopModuleCalls = 0
            backend.lastPressTarget = 0
            backend.lastRetractTarget = 0
            backend.lastIncrement = 0
            backend.ramToTableOpening = 8.3
            backend.ramPositionY1 = 0.57
            backend.ramPositionY2 = 0.54
            backend.ramTargetPosition = 0
            backend.ramCommandedJogPosition = 0
            backend.ramDistanceToGo = 0
            backend.ramJogSpeed = 0
            backend.ramVelocity = 0
            backend.safetyJogLeft = false
            backend.safetyJogRight = false
            backend.bendPedal = false
            backend.pressOperationActive = false
            backend.moduleOperationActive = false
            backend.pressTelemetryFresh = true
            backend.moduleTelemetryFresh = true
            backend.pressReady = true
            backend.moduleReady = true
            backend.pressHomed = true
            backend.moduleHomed = true
            backend.pressMachineState = "IDLE"
            backend.moduleState = "IDLE"
            state.runActive = false
            state.physicalRunCommandPending = false
            state.physicalRunPendingOperation = ""
            state.physicalRunPendingDevice = ""
            state.physicalRunPendingOperationId = undefined
            state.physicalRunWaitAction = ""
            state.dwellRemainingSec = 0
            state.manualPendingOperation = ""
            state.manualPendingAction = ""
            state.autoClampEnabled = false
            state.selectedRunBend = 0
            state.selectRunBend(0)
            state.hidePopup()
            state.clearAlarm()
            wait(0)
        }

        function complete(device, operation) {
            backend.commandOperationFinished(backend.operationId, device, operation, "COMPLETED", "")
            wait(0)
        }

        function test_physicalRunAdvancesOnlyOnMatchingControllerCompletion() {
            verify(state.confirmRunProgram())
            compare(state.popupVisible, false)
            verify(state.runProgressTitle.length > 0)
            verify(state.runProgressSubtitle.length > 0)
            compare(backend.beginRunCalls, 1)
            compare(backend.setRetractCalls, 1)
            fuzzyCompare(backend.lastRetractTarget, -1.7890, 0.0001)
            compare(state.executionPhase, "STARTING")
            state.advanceExecutionPhase()
            compare(state.executionPhase, "STARTING")
            compare(backend.moveCalls, 0)

            complete("press", "other-operation")
            compare(state.executionPhase, "STARTING")
            compare(backend.moveCalls, 0)
            backend.commandOperationFinished(backend.operationId, "module",
                                             "set-retract-plane", "COMPLETED", "")
            wait(0)
            compare(state.executionPhase, "STARTING")
            backend.commandOperationFinished(backend.operationId - 1, "press",
                                             "set-retract-plane", "COMPLETED", "")
            wait(0)
            compare(state.executionPhase, "STARTING")
            complete("press", "set-retract-plane")
            compare(state.executionPhase, "BACK_GAUGE_MOVE")
            compare(backend.moveCalls, 1)
            complete("module", "move")
            compare(state.executionPhase, "SAFETY_CLEARANCE_POSITION_MOVE")
            compare(backend.pressJogCalls, 1)
            fuzzyCompare(backend.lastPressTarget, -1.7890, 0.0001)
            verify(backend.lastPressJogType === "safety" || backend.lastPressJogType === "retract")
            complete("press", backend.lastPressJogType === "safety" ? "jog-safety" : "jog-retract")
            compare(state.executionPhase, "CLAMP_MATERIAL_MOVE")
            compare(backend.lastPressJogType, "clamp")
            complete("press", "jog-clamp")
            compare(state.executionPhase, "BACK_GAUGE_BUMP_MOVE")
            compare(backend.lastIncrement, state.backGaugeBumpOffDistanceInch)
            complete("module", "increment")
            compare(state.executionPhase, "BEND_MOVE")
            compare(backend.lastPressJogType, "bend")
            complete("press", "jog-bend")
            compare(state.executionPhase, "BACK_GAUGE_AND_RAM_RETRACT_MOVE")
            compare(backend.lastIncrement, state.backGaugeRetractBetweenBendsInch)
        }

        function test_displayTargetsEqualDispatchedControllerCoordinates() {
            state.selectedBend = Object.assign({}, state.selectedBend, {
                startPosition: "5.6726",
                clampPosition: "5.6402",
                finalPosition: "5.5194"
            })
            fuzzyCompare(state.runRamTarget("startPosition"), -2.6274, 0.0001)
            fuzzyCompare(state.runRamTarget("clampPosition"), -2.6598, 0.0001)
            fuzzyCompare(state.runRamTarget("finalPosition"), -2.7806, 0.0001)
            compare(state.runRamTargetText("startPosition", " in"), "-2.6274 in")

            verify(state.confirmRunProgram())
            complete("press", "set-retract-plane")
            complete("module", "move")
            fuzzyCompare(backend.lastPressTarget,
                         state.runRamTarget("startPosition"), 0.0001)
        }

        function test_operatorCannotChangeBendDuringActiveRun() {
            verify(state.programBends.length > 1)
            const originalIndex = state.selectedRunBend
            const originalBendId = state.selectedBend.id
            const originalStartTarget = state.runRamTarget("startPosition")

            verify(state.confirmRunProgram())
            verify(!state.selectRunBend(originalIndex + 1))
            compare(state.selectedRunBend, originalIndex)
            compare(state.selectedBend.id, originalBendId)
            fuzzyCompare(state.runRamTarget("startPosition"), originalStartTarget, 0.0001)

            complete("press", "set-retract-plane")
            complete("module", "move")
            fuzzyCompare(backend.lastPressTarget, originalStartTarget, 0.0001)
        }

        function test_negativeControllerCoordinatesAreNeverDoubleConverted() {
            state.selectedBend = Object.assign({}, state.selectedBend, {
                startPosition: "-2.6274",
                clampPosition: "-2.6598",
                finalPosition: "-2.7806"
            })
            fuzzyCompare(state.runRamTarget("startPosition"), -2.6274, 0.0001)
            fuzzyCompare(state.runRamTarget("clampPosition"), -2.6598, 0.0001)
            fuzzyCompare(state.runRamTarget("finalPosition"), -2.7806, 0.0001)
        }

        function test_hardwareDisplayFailsClosedWithoutControllerOpening() {
            state.selectedBend = Object.assign({}, state.selectedBend, {
                startPosition: "5.6726"
            })
            backend.ramToTableOpening = 0
            state.desktopRamToTableOpening = 8.3
            compare(state.runRamTargetText("startPosition", " in"), "UNAVAILABLE")
            verify(isNaN(state.runRamTarget("startPosition")))
        }

        function test_sharedJogCompletionIsNotConsumedByManualRouter() {
            verify(state.confirmRunProgram())
            complete("press", "set-retract-plane")
            complete("module", "move")
            compare(state.executionPhase, "SAFETY_CLEARANCE_POSITION_MOVE")
            const operation = backend.lastPressJogType === "safety"
                ? "jog-safety" : "jog-retract"
            complete("press", operation)
            compare(state.executionPhase, "CLAMP_MATERIAL_MOVE")
            compare(state.manualPendingOperation, "")
        }

        function test_safetyDispatchWaitsForPreHeldPalmSwitchesToRelease() {
            backend.safetyJogLeft = true
            verify(state.confirmRunProgram())
            complete("press", "set-retract-plane")
            complete("module", "move")

            compare(state.executionPhase, "SAFETY_CLEARANCE_POSITION_MOVE")
            compare(state.physicalRunWaitAction, "RELEASE_PALM_SWITCHES")
            compare(backend.pressJogCalls, 0)
            verify(state.runOperatorPrompt().indexOf("RELEASE") >= 0)

            backend.safetyJogLeft = false
            verify(state.processPhysicalRunOperatorGate())
            compare(state.physicalRunWaitAction, "")
            compare(backend.pressJogCalls, 1)
            verify(state.runOperatorPrompt().indexOf("PALM SWITCHES") >= 0)
        }

        function test_clampDispatchWaitsForPreHeldPedalToRelease() {
            verify(state.confirmRunProgram())
            complete("press", "set-retract-plane")
            complete("module", "move")
            backend.bendPedal = true
            complete("press", backend.lastPressJogType === "safety" ? "jog-safety" : "jog-retract")
            compare(state.physicalRunWaitAction, "RELEASE_PEDAL")
            compare(backend.pressJogCalls, 1)

            backend.bendPedal = false
            verify(state.processPhysicalRunOperatorGate())
            compare(backend.pressJogCalls, 2)
            compare(backend.lastPressJogType, "clamp")
        }

        function test_noAutoClampRequiresPedalReleaseBeforeBend() {
            verify(state.confirmRunProgram())
            complete("press", "set-retract-plane")
            complete("module", "move")
            complete("press", backend.lastPressJogType === "safety" ? "jog-safety" : "jog-retract")
            backend.bendPedal = true
            complete("press", "jog-clamp")
            complete("module", "increment")

            compare(state.executionPhase, "BEND_MOVE")
            compare(state.physicalRunWaitAction, "RELEASE_PEDAL")
            compare(backend.lastPressJogType, "clamp")
            backend.bendPedal = false
            verify(state.processPhysicalRunOperatorGate())
            compare(backend.lastPressJogType, "bend")
        }

        function test_autoClampDwellPausesAndResumesWhenPedalReleased() {
            state.autoClampEnabled = true
            state.autoClampDwellSec = 0.3
            verify(state.confirmRunProgram())
            complete("press", "set-retract-plane")
            complete("module", "move")
            complete("press", backend.lastPressJogType === "safety" ? "jog-safety" : "jog-retract")
            backend.bendPedal = true
            complete("press", "jog-clamp")
            complete("module", "increment")

            compare(state.executionPhase, "DWELL_TIMER_WAIT")
            fuzzyCompare(state.dwellRemainingSec, 0.3, 0.0001)
            verify(state.tickPhysicalRunDwell())
            fuzzyCompare(state.dwellRemainingSec, 0.2, 0.0001)
            verify(state.runOperatorPrompt().indexOf("DWELLING") >= 0)
            verify(state.runOperatorPrompt().indexOf("0.2 SECONDS") >= 0)

            backend.bendPedal = false
            verify(state.tickPhysicalRunDwell())
            compare(state.runActive, true)
            compare(state.dwellPausedForPedal, true)
            fuzzyCompare(state.dwellRemainingSec, 0.2, 0.0001)
            compare(state.physicalRunCommandPending, false)
            compare(backend.pressJogCalls, 2)
            compare(backend.endRunCalls, 0)
            verify(state.runOperatorPrompt().indexOf("DWELL PAUSED") >= 0)
            verify(state.runOperatorPrompt().indexOf("DOUBLE-TAP AND HOLD") >= 0)

            // Additional timer ticks while released remain paused and never
            // dispatch, retract, fail, or advance the bend.
            verify(state.tickPhysicalRunDwell())
            fuzzyCompare(state.dwellRemainingSec, 0.2, 0.0001)
            compare(state.executionPhase, "DWELL_TIMER_WAIT")
            compare(backend.pressJogCalls, 2)

            backend.bendPedal = true
            verify(state.tickPhysicalRunDwell())
            compare(state.dwellPausedForPedal, false)
            fuzzyCompare(state.dwellRemainingSec, 0.1, 0.0001)
            compare(state.runActive, true)
            compare(backend.endRunCalls, 0)
        }

        function test_offlineDwellAlsoPausesWithoutAdvancing() {
            state.offlineSimulationEnabled = true
            state.autoClampEnabled = true
            state.autoClampDwellSec = 0.3
            state.runActive = true
            state.beginExecutionStateMachine()
            state.executionPhaseIndex = 5
            state.executionPhase = "DWELL_TIMER_WAIT"

            state.advanceExecutionPhase()
            fuzzyCompare(state.dwellRemainingSec, 0.3, 0.0001)
            state.advanceExecutionPhase()
            compare(state.executionPhase, "DWELL_TIMER_WAIT")
            compare(state.dwellPausedForPedal, true)
            fuzzyCompare(state.dwellRemainingSec, 0.3, 0.0001)
            compare(state.selectedRunBend, 0)
            compare(backend.pressJogCalls, 0)
            compare(backend.endRunCalls, 0)

            verify(state.toggleLed("pedal"))
            state.advanceExecutionPhase()
            compare(state.dwellPausedForPedal, false)
            fuzzyCompare(state.dwellRemainingSec, 0.2, 0.0001)
            compare(state.executionPhase, "DWELL_TIMER_WAIT")
            state.offlineSimulationEnabled = false
            state.bendJogPedal = Qt.binding(function() {
                return state.offlineSimulationEnabled ? false : backend.bendPedal
            })
        }

        function test_failedNativePhaseEndsRunAndRaisesAlarm() {
            verify(state.confirmRunProgram())
            backend.commandOperationFinished(backend.operationId, "press", "set-retract-plane", "FAILED", "SETTING_REJECTED")
            wait(0)
            compare(state.runActive, false)
            compare(state.alarmTitle, "RUN PROGRAM FAILED")
            verify(state.alarmBody.indexOf("SETTING REJECTED") >= 0)
            compare(backend.endRunCalls, 1)
        }

        function test_missingRamToTableOpeningFailsBeforeAnyPhysicalDispatch() {
            backend.ramToTableOpening = 0
            verify(!state.confirmRunProgram())
            compare(backend.setRetractCalls, 0)
            compare(backend.moveCalls, 0)
            compare(backend.pressJogCalls, 0)
            compare(state.alarmTitle, "RUN PROGRAM FAILED")
            verify(state.alarmBody.indexOf("RAM TO TABLE OPENING UNAVAILABLE") >= 0)
        }

        function test_toolSpacePositionsUseEepromOpeningBeforeDispatch() {
            state.selectedBend = {
                startPosition: 5.6726,
                clampPosition: 5.6402,
                finalPosition: 5.5194,
                speed: 100,
                x: -1,
                r: 0,
                backGaugeRefEdgeStop: "G54",
                additionalRetractAfterBend: 0
            }

            verify(state.confirmRunProgram())
            fuzzyCompare(backend.lastRetractTarget, -2.6274, 0.0001)
            complete("press", "set-retract-plane")
            complete("module", "move")
            fuzzyCompare(backend.lastPressTarget, -2.6274, 0.0001)
        }

        function test_clearanceDirectionUsesControllerTrajectoryWhileDroUsesEncoders() {
            state.selectedBend = {
                startPosition: 5.6726,
                clampPosition: 5.6402,
                finalPosition: 5.5194,
                speed: 100,
                x: -1,
                r: 0,
                backGaugeRefEdgeStop: "G54",
                additionalRetractAfterBend: 0
            }
            backend.ramPositionY1 = 0.5726
            backend.ramPositionY2 = 0.5402
            backend.ramTargetPosition = -2.7806

            verify(state.confirmRunProgram())
            complete("press", "set-retract-plane")
            complete("module", "move")

            compare(state.executionPhase, "SAFETY_CLEARANCE_POSITION_MOVE")
            compare(backend.lastPressJogType, "retract")
            fuzzyCompare(backend.lastPressTarget, -2.6274, 0.0001)
            fuzzyCompare(state.rawRamControlPosition, -2.7806, 0.0001)
            fuzzyCompare(state.rawRamPosition, 0.5564, 0.0001)
        }

        function test_droRetainsLastValidValuesWhenTelemetryBecomesStale() {
            backend.pressTelemetryFresh = true
            backend.ramTargetPosition = -2.7806
            backend.ramCommandedJogPosition = -2.6274
            backend.ramDistanceToGo = 0.1532
            wait(0)
            fuzzyCompare(state.rawRamPosition, 0.555, 0.0001)
            fuzzyCompare(state.commandedJogPosition, -2.6274, 0.0001)
            fuzzyCompare(state.distanceToGo, 0.1532, 0.0001)

            backend.pressTelemetryFresh = false
            backend.ramTargetPosition = 0
            backend.ramCommandedJogPosition = 0
            backend.ramDistanceToGo = 0
            wait(0)
            fuzzyCompare(state.rawRamPosition, 0.555, 0.0001)
            fuzzyCompare(state.commandedJogPosition, -2.6274, 0.0001)
            fuzzyCompare(state.distanceToGo, 0.1532, 0.0001)
        }

        function test_secondBendClearanceUsesUpdatedControllerTarget() {
            const firstBend = {
                id: "first",
                name: "First",
                startPosition: 5.6726,
                clampPosition: 5.6402,
                finalPosition: 5.5194,
                speed: 100,
                x: -1,
                r: 0,
                backGaugeRefEdgeStop: "G54",
                additionalRetractAfterBend: 0
            }
            const secondBend = {
                id: "second",
                name: "Second",
                startPosition: 5.7000,
                clampPosition: 5.6600,
                finalPosition: 5.5000,
                speed: 100,
                x: -1.5,
                r: 0,
                backGaugeRefEdgeStop: "G54",
                additionalRetractAfterBend: 0
            }
            state.bendMode = "PROGRAM_BEND_MODE"
            state.programBends = [firstBend, secondBend]
            state.selectedRunBend = 0
            state.selectedBend = firstBend
            backend.ramTargetPosition = -2.7806

            verify(state.confirmRunProgram())
            complete("press", "set-retract-plane")
            complete("module", "move")
            complete("press", "jog-retract")
            complete("press", "jog-clamp")
            complete("module", "increment")
            complete("press", "jog-bend")
            complete("module", "increment")

            compare(state.selectedRunBend, 1)
            compare(state.executionPhase, "STARTING")
            backend.ramTargetPosition = -2.8000
            complete("press", "set-retract-plane")
            complete("module", "move")

            compare(state.executionPhase, "SAFETY_CLEARANCE_POSITION_MOVE")
            compare(backend.lastPressJogType, "retract")
            fuzzyCompare(backend.lastPressTarget, -2.6000, 0.0001)
        }

        function test_operatorStopCancelsActiveControllersAndReleasesAdmission() {
            verify(state.confirmRunProgram())
            backend.pressOperationActive = true
            backend.moduleOperationActive = true

            state.runAction("run")

            compare(state.runActive, false)
            compare(state.physicalRunCommandPending, false)
            compare(state.physicalRunPendingOperation, "")
            compare(backend.abortPressCalls, 1)
            compare(backend.stopModuleCalls, 1)
            compare(backend.endRunCalls, 1)
            compare(state.runSimulatedRun, false)
            compare(state.runBendListVisible, false)
            compare(state.runSceneMode, "PLACEMENT")
            compare(state.runProgressTitle, "")
            compare(state.runProgressSubtitle, "")
        }
    }
}
