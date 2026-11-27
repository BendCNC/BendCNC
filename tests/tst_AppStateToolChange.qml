import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 640
    height: 480

    QtObject {
        id: backend
        property bool pressConnected: true
        property bool moduleConnected: false
        property string pressConnectionState: "READY"
        property string moduleConnectionState: "DISCONNECTED"
        property string pressMachineState: "IDLE"
        property string moduleState: "UNKNOWN"
        property bool pressTelemetryFresh: true
        property double pressTelemetrySequence: 0
        property string thcCommissioningState: "IDLE"
        property int releaseThcCalls: 0
        property bool moduleTelemetryFresh: false
        property bool pressOperationActive: false
        property bool moduleOperationActive: false
        property bool pressReady: true
        property bool pressHomed: true
        property bool moduleHomed: false
        property bool manualModeEnabled: false
        property real manualModeMaxTonnagePerRam: 12.5
        property bool independentRamTelemetryAvailable: true
        property real ramPositionY1: -1.0
        property real ramPositionY2: -1.0
        property real ramLoadY1: 0
        property real ramLoadY2: 0
        property real ramCommandedJogPosition: -1.0
        property real ramJogSpeed: 0
        property real ramDistanceToGo: 0
        property bool safetyJogLeft: false
        property bool safetyJogRight: false
        property bool bendPedal: false
        property bool antiBind: false
        property string pressFirmwareVersion: "1.2"
        property string moduleFirmwareVersion: ""
        property real moduleWorkX: 0
        property real moduleWorkR: 0
        property real moduleMachineX: 0
        property real moduleMachineR: 0
        property bool moduleLimitX1: false
        property bool moduleLimitX2: false
        property bool moduleLimitR1: false
        property bool moduleLimitR2: false
        property int manualEnableCalls: 0
        property int maxTonnageCalls: 0
        property int jogCalls: 0
        property int strokeCalls: 0
        property int startHoldCalls: 0
        property real lastHoldTarget: 0
        property int stopHoldCalls: 0
        property bool acceptCommands: true
        property bool acceptManualModeCommands: true
        property bool acceptMaxTonnage: true
        property int operationId: 0
        property real lastMaxTonnage: 0
        property real ramToTableOpening: 0
        property bool commandOperationActive: false
        property int ramToTableCalls: 0
        property real lastRamToTableOpening: 0
        property bool lastManualModeRequest: false
        property string lastJogType: ""
        signal commandOperationFinished(int id, string device, string operation,
                                        string state, string error)
        signal connectionFailed(string device, string reason)
        signal operationRejected(string device, string operation, string reason)
        signal telemetryLogLine(string device, string line)
        signal pressSerialLogLine(string source, string content)

        function setManualModeEnabled(enabled) {
            manualEnableCalls += 1
            operationId += 1
            lastManualModeRequest = enabled
            return acceptCommands && acceptManualModeCommands
        }
        function setManualModeMaxTonnage(value) {
            maxTonnageCalls += 1
            operationId += 1
            lastMaxTonnage = value
            return acceptCommands && acceptMaxTonnage
        }
        function jogPress(target, speed, type) {
            jogCalls += 1
            operationId += 1
            lastJogType = type
            return acceptCommands
        }
        function startManualStroke(retract, bend, jogSpeed, bendSpeed) {
            strokeCalls += 1
            operationId += 1
            return acceptCommands
        }
        function startTonnageHold(target, speed) {
            startHoldCalls += 1
            lastHoldTarget = target
            operationId += 1
            return acceptCommands
        }
        function stopTonnageHold() {
            stopHoldCalls += 1
            operationId += 1
            return acceptCommands
        }
        function releaseThcCommissioning() {
            releaseThcCalls += 1
            return acceptCommands
        }
        property int automaticProfileCalls: 0
        property real lastAutomaticTarget: 0
        function startAutomaticThcContactProfile(target) {
            automaticProfileCalls += 1
            lastAutomaticTarget = target
            operationId += 1
            return acceptCommands
        }
        property bool toolChangeSupported: true
        property var calls: []
        signal toolChangeEvent(string event, real position)
        function startToolChangeTouch(b, f) { calls.push("touch:" + b + "," + f.toFixed(4)); return true }
        function heartbeatToolChangeTouch() { return true }
        function cancelThcCommissioning() { calls.push("cancel"); return true }
        function startToolChangeMove(t) { calls.push("move:" + t.toFixed(4)); return true }
        function startToolChangeSeat(b, j, p) { calls.push("seat:" + p.toFixed(4)); return true }
        function setRamToTableOpening(value) {
            ramToTableCalls += 1
            operationId += 1
            lastRamToTableOpening = value
            return acceptCommands
        }
    }

    BendCNC.AppState {
        id: state
        machineControl: backend
    }

    TestCase {
        name: "AppStateToolChangeTests"
        when: windowShown

        function init() { backend.calls = []; state.endToolChange(); state.toolChangeBackoff = 0.125; state.clearAlarm() }
        function finish(op, result, error) {
            backend.commandOperationFinished(1, "press", op, result || "COMPLETED", error || ""); wait(0)
        }

        function test_moveFormulaRaisesForTallerPunch() {
            fuzzyCompare(state.toolChangeMoveTarget(-1.5, 0.125, 3.0, 3.5), -0.875, 1e-9)
            fuzzyCompare(state.toolChangeMoveTarget(-1.5, 0.125, 3.5, 3.0), -1.875, 1e-9)
        }

        function test_missingHeightBlocks() {
            verify(!state.beginToolChange(NaN, 3.0))
            compare(state.toolChangeFailure, "MISSING_TOOLING_HEIGHT")
            verify(!state.toolChangeJogDownPressed(-1.5))
            compare(backend.calls.length, 0)
        }

        function test_differentHeightTouchRemovedMoveSeat() {
            verify(state.beginToolChange(3.0, 3.5))
            verify(state.toolChangeJogDownPressed(-1.5))
            compare(backend.calls[0], "touch:0.125,-1.7500")
            backend.toolChangeEvent("CONTACT", -1.5); wait(0)
            compare(state.toolChangeState, "BACKOFF")
            state.toolChangeJogDownReleased()
            compare(backend.calls.indexOf("cancel"), -1)
            finish("tool-change-touch")
            compare(state.toolChangeState, "AWAIT_TOOLING_REMOVED")
            verify(state.confirmToolingRemoved())
            compare(backend.calls[1], "move:-0.8750")
            finish("tool-change-move")
            compare(state.toolChangeState, "AWAIT_SEAT")
            verify(state.startToolChangeSeat())
            backend.toolChangeEvent("SEAT_PAUSED", NaN); wait(0)
            compare(state.toolChangeState, "SEAT_PAUSED")
            finish("tool-change-seat")
            compare(state.toolChangeState, "DONE")
            verify(state.toolChangeSeatAgainAvailable)
            verify(state.startToolChangeSeat())
        }

        function test_sameHeightSkipsMoveAndReleaseBeforeContactCancels() {
            verify(state.beginToolChange(3.0, 3.0))
            verify(state.toolChangeJogDownPressed(-1.5))
            state.toolChangeJogDownReleased()
            compare(backend.calls[1], "cancel")
            finish("tool-change-touch", "FAILED", "THC_CANCELLED")
            compare(state.toolChangeState, "FAILED")
            verify(state.beginToolChange(3.0, 3.0))
            verify(state.toolChangeJogDownPressed(-1.5))
            backend.toolChangeEvent("CONTACT", -1.5); wait(0)
            finish("tool-change-touch")
            compare(state.toolChangeState, "AWAIT_SEAT")
        }
    }
}
