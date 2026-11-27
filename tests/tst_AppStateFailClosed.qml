import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 640
    height: 480

    BendCNC.AppState {
        id: state
        // Intentionally no backend and no simulation opt-in: this is the
        // packaged application's conservative fallback contract.
    }

    TestCase {
        name: "AppStateFailClosedTests"
        when: windowShown

        function init() {
            state.hidePopup()
            state.clearAlarm()
            state.closeRunConfirmation()
        }

        function test_defaultsAreDisconnectedAndUnknown() {
            compare(state.offlineSimulationEnabled, false)
            compare(state.machineConnected, false)
            compare(state.moduleConnected, false)
            compare(state.backGaugeHomed, false)
            compare(state.machineStatus, "UNKNOWN")
            compare(state.backGaugeStatus, "UNKNOWN")
            compare(state.independentRamTelemetryAvailable, false)
        }

        function test_previewDiagnosticsDefaultOffAndRemainExplicitOptIn() {
            state.applyLocalSettings({})
            compare(state.runPreviewDebugLogsEnabled, false)
            compare(state.runPreviewDebugOverlaysEnabled, false)

            state.applyLocalSettings({
                runPreviewDebugLogsEnabled: true,
                runPreviewDebugOverlaysEnabled: true
            })
            compare(state.runPreviewDebugLogsEnabled, true)
            compare(state.runPreviewDebugOverlaysEnabled, true)
        }

        function test_machineCommandRejectsWithoutMutation() {
            compare(state.machineAction("home"), false)
            compare(state.machineStatus, "UNKNOWN")
            compare(state.ramPosition, 0)
            verify(state.alarmVisible)
            compare(state.alarmTitle, "MACHINE HOME REJECTED")
        }

        function test_backGaugeCommandRejectsWithoutMutation() {
            compare(state.backGaugeMoveTo(1.25, 0.5), false)
            compare(state.backGaugeX, 0)
            compare(state.backGaugeR, 0)
            compare(state.backGaugeStatus, "UNKNOWN")
            verify(state.alarmVisible)
        }

        function test_runCannotDispatchOffline() {
            state.runConfirmationVisible = true
            compare(state.confirmRunProgram(), false)
            compare(state.runActive, false)
            compare(state.machineStatus, "UNKNOWN")
            verify(state.alarmVisible)
            compare(state.alarmTitle, "RUN PROGRAM REJECTED")
        }

        function test_safetyTelemetryCannotBeToggled() {
            compare(state.toggleLed("left"), false)
            compare(state.leftSafetyJog, false)
            compare(state.toggleLed("pedal"), false)
            compare(state.bendJogPedal, false)
        }
    }
}
