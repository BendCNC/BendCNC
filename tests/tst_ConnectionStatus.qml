import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 900
    height: 100

    QtObject {
        id: backend
        property bool pressConnected: false
        property bool moduleConnected: false
        property string pressConnectionState: "DISCONNECTED"
        property string moduleConnectionState: "DISCONNECTED"
        property string pressMachineState: "UNKNOWN"
        property string moduleState: "UNKNOWN"
        property string pressFirmwareVersion: ""
        property string moduleFirmwareVersion: ""
        property bool pressReady: false
        property bool moduleReady: false
        property bool pressHomed: false
        property bool moduleHomed: false
        property bool pressOperationActive: false
        property bool moduleOperationActive: false
        property bool pressTelemetryFresh: false
        property bool moduleTelemetryFresh: false
        property bool moduleLimitX1: false
        property bool moduleLimitX2: false
        property bool moduleLimitR1: false
        property bool moduleLimitR2: false
        property real ramTargetPosition: 0
        property real ramCommandedJogPosition: 0
        property real ramDistanceToGo: 0
        property real ramJogSpeed: 0
        property string lastRejectReason: ""
        property int connectPressCalls: 0
        property int connectModuleCalls: 0
        property int homePressCalls: 0
        property int homeModuleCalls: 0
        property int abortPressCalls: 0
        property int operationId: 0
        signal connectionFailed(string device, string reason)
        signal operationRejected(string device, string operation, string reason)
        signal commandOperationFinished(int id, string device, string operation,
                        string state, string error)
        signal telemetryLogLine(string device, string line)
        signal pressSerialLogLine(string source, string content)

        function connectPress() { connectPressCalls += 1; return true }
        function connectModule() { connectModuleCalls += 1; return true }
        function disconnectPress() { return true }
        function disconnectModule() { return true }
        function homePress() {
            homePressCalls += 1
            operationId += 1
            pressOperationActive = true
            return true
        }
        function homeModule() {
            homeModuleCalls += 1
            operationId += 1
            moduleOperationActive = true
            return true
        }
        function abortPress() { abortPressCalls += 1; pressOperationActive = false; return true }
    }

    BendCNC.AppState {
        id: state
        machineControl: backend
    }

    BendCNC.ToolBarView {
        id: toolbar
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "ConnectionStatusTests"
        when: windowShown

        function init() {
            backend.pressConnected = false
            backend.moduleConnected = false
            backend.pressConnectionState = "DISCONNECTED"
            backend.moduleConnectionState = "DISCONNECTED"
            backend.pressMachineState = "UNKNOWN"
            backend.moduleState = "UNKNOWN"
            backend.pressFirmwareVersion = ""
            backend.moduleFirmwareVersion = ""
            backend.connectPressCalls = 0
            backend.connectModuleCalls = 0
            backend.homePressCalls = 0
            backend.homeModuleCalls = 0
            backend.abortPressCalls = 0
            backend.operationId = 0
            backend.pressOperationActive = false
            backend.moduleOperationActive = false
            state.clearMachineLog()
            state.machineLogStatusReportsEnabled = false
            state.clearAlarm()
            wait(0)
        }

        function test_authoritativeStatesAndControllerAlarms() {
            compare(state.machineToolbarState, "DISCONNECTED")
            compare(state.moduleToolbarState, "DISCONNECTED")

            backend.pressConnected = true
            backend.pressConnectionState = "INITIALIZING"
            backend.moduleConnected = true
            backend.moduleConnectionState = "CONNECTING"
            wait(0)
            compare(state.machineToolbarState, "INITIALIZING")
            compare(state.moduleToolbarState, "CONNECTING")

            backend.pressConnectionState = "READY"
            backend.pressMachineState = "HYDRAULIC_SHUTDOWN"
            backend.pressFirmwareVersion = "1.1"
            backend.moduleConnectionState = "READY"
            backend.moduleState = "ALARM"
            backend.moduleFirmwareVersion = "1.1BG"
            wait(0)
            compare(state.machineToolbarState, "READY_WITH_ALARM")
            compare(state.moduleToolbarState, "READY_WITH_ALARM")
            compare(state.machineName, "LS-BEND 1.1")
            compare(state.moduleName, "BACK GAUGE 1.1BG")
        }

        function test_readyAndInitializingPillsDoNotDispatchResetOrConnect() {
            const machineElement = findChild(toolbar, "device-connection-view machine-connection-view")
            verify(machineElement)
            const primaryAction = findChild(machineElement, "connection-primary-action")
            verify(primaryAction)

            backend.pressConnected = true
            backend.pressConnectionState = "INITIALIZING"
            wait(0)
            verify(!primaryAction.enabled)
            mouseClick(primaryAction)
            compare(backend.connectPressCalls, 0)

            backend.pressConnectionState = "READY"
            backend.pressMachineState = "IDLE"
            wait(0)
            verify(!primaryAction.enabled)
            mouseClick(primaryAction)
            compare(backend.connectPressCalls, 0)
        }

        function test_disconnectedPillConnects() {
            const machineElement = findChild(toolbar, "device-connection-view machine-connection-view")
            const primaryAction = findChild(machineElement, "connection-primary-action")
            verify(primaryAction.enabled)
            mouseClick(primaryAction)
            compare(backend.connectPressCalls, 1)
        }

        function test_connectionFailureAndPairedRejectionShowOneAlarm() {
            backend.connectionFailed("press", "INITIALIZATION_TIMEOUT")
            compare(state.alarmTitle, "MACHINE CONNECTION FAILED")
            const firstLogCount = state.logEntries.length
            backend.operationRejected("press", "connect", "INITIALIZATION_TIMEOUT")
            compare(state.logEntries.length, firstLogCount)
            compare(state.alarmTitle, "MACHINE CONNECTION FAILED")
        }

        function test_nonConnectRejectionIsSurfaced() {
            backend.operationRejected("module", "home", "COMMAND_DISABLED")
            compare(state.alarmTitle, "BACK GAUGE HOME REJECTED")
            verify(state.alarmBody.indexOf("COMMAND DISABLED") >= 0)
        }

        function test_nativeCallerDoesNotDuplicateSynchronousRejection() {
            backend.pressConnected = true
            backend.pressConnectionState = "READY"
            backend.pressReady = true
            backend.pressTelemetryFresh = true
            backend.pressMachineState = "IDLE"
            wait(0)
            verify(state.machineAction("home"))
            compare(backend.homePressCalls, 0)
            compare(state.popupTitle, "HOME MACHINE")
            state.performPopupPrimaryAction()
            compare(backend.homePressCalls, 1)
            compare(state.popupTitle, "HOMING MACHINE")
            compare(state.popupAction, "press-home-cancel")
            backend.commandOperationFinished(backend.operationId, "press", "home", "COMPLETED", "")
            compare(state.popupVisible, false)
            compare(backend.moduleHomed, false)
        }

        function test_expectedModuleAlarmAllowsManualHomeConfirmation() {
            backend.moduleConnected = true
            backend.moduleConnectionState = "READY"
            backend.moduleReady = true
            backend.moduleTelemetryFresh = true
            backend.moduleState = "ALARM"
            wait(0)
            verify(state.requestBackGaugeHome())
            compare(state.popupAction, "back-gauge-home-confirm")
            state.performPopupPrimaryAction()
            compare(backend.homeModuleCalls, 1)
            compare(state.popupTitle, "BACK GAUGE HOMING")
            compare(state.backGaugeHomeOperationId, backend.operationId)
            backend.commandOperationFinished(backend.operationId, "module", "home", "COMPLETED", "")
            compare(state.popupVisible, false)
            compare(state.backGaugeHomeOperationId, undefined)
        }

        function test_homeCompletionAndFailureUseNativeLifecycle() {
            state.hidePopup()
            backend.commandOperationFinished(1, "module", "home", "COMPLETED", "")
            compare(state.popupVisible, false)
            verify(state.logEntries[0].indexOf("homing completed") >= 0)
            backend.pressConnected = true
            backend.pressConnectionState = "READY"
            backend.pressReady = true
            backend.pressTelemetryFresh = true
            backend.pressMachineState = "IDLE"
            wait(0)
            verify(state.requestPressHome())
            state.performPopupPrimaryAction()
            backend.commandOperationFinished(backend.operationId, "press", "home", "FAILED", "HOMING_TIMEOUT")
            compare(state.alarmTitle, "MACHINE HOMING FAILED")
            verify(state.alarmBody.indexOf("HOMING TIMEOUT") >= 0)
        }

        function test_homeRefusalMessages() {
            verify(state.homeFailureMessage("HOME_RECOVERY_NOT_SETTLED").indexOf("No Home is queued") >= 0)
            verify(state.homeFailureMessage("CONTROLLER_ALARM_ACTIVE").indexOf("retained safety fault") >= 0)
        }

        function test_backGaugeHomePopupRequiresMatchingOperationId() {
            backend.moduleConnected = true
            backend.moduleConnectionState = "READY"
            backend.moduleReady = true
            backend.moduleTelemetryFresh = true
            backend.moduleState = "IDLE"
            wait(0)
            verify(state.requestBackGaugeHome())
            state.performPopupPrimaryAction()
            const homeId = backend.operationId
            backend.commandOperationFinished(homeId + 1, "module", "home", "COMPLETED", "")
            verify(state.popupVisible)
            backend.commandOperationFinished(homeId, "module", "home", "FAILED", "HOMING_TIMEOUT")
            compare(state.popupVisible, false)
            compare(state.alarmTitle, "BACK GAUGE HOMING FAILED")
            verify(state.alarmBody.indexOf("HOMING TIMEOUT") >= 0)
        }

        function test_pressHomePopupIgnoresOtherOperationAndCanCancel() {
            backend.pressConnected = true
            backend.pressConnectionState = "READY"
            backend.pressReady = true
            backend.pressTelemetryFresh = true
            backend.pressMachineState = "IDLE"
            wait(0)
            verify(state.requestPressHome())
            state.performPopupPrimaryAction()
            verify(state.popupVisible)
            backend.commandOperationFinished(backend.operationId + 1, "press", "home", "COMPLETED", "")
            verify(state.popupVisible)
            state.performPopupPrimaryAction()
            compare(backend.abortPressCalls, 1)
            compare(state.popupVisible, false)
        }

        function test_machineLogUsesRawPressIoAndStatusFilter() {
            backend.pressSerialLogLine("SOFTWARE", "<VER>")
            compare(state.machineLogModel.count, 0)
            backend.pressSerialLogLine("SOFTWARE", "Byte 0x85")
            compare(state.machineLogModel.count, 1)
            verify(state.machineLogModel.get(0).formatted.indexOf("[SOFTWARE]: Byte 0x85") >= 0)
            backend.pressSerialLogLine("MACHINE", "<Idle|Y1:-0.0500>")
            compare(state.machineLogModel.count, 1)
            backend.pressSerialLogLine("MACHINE", "<Idle|Y1:-0.0500>\r\n")
            compare(state.machineLogModel.count, 1)
            state.machineLogStatusReportsEnabled = true
            backend.pressSerialLogLine("MACHINE", "<Idle|Y1:-0.0500>\r\n")
            compare(state.machineLogModel.count, 2)
            compare(state.machineLogModel.get(1).content, "<Idle|Y1:-0.0500>")
            state.toolbarAction("log")
            compare(state.popupTitle, "MACHINE LOG")
            compare(state.popupKind, "machine-log")
        }
    }
}