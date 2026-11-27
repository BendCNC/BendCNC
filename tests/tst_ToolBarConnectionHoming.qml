import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 1366
    height: 50

    QtObject {
        id: control
        property bool pressHomed: false
    }

    QtObject {
        id: state
        property string moduleToolbarState: "READY"
        property string machineToolbarState: "READY"
        property string backGaugeStatus: "IDLE"
        property string machineStatus: "STARTUP_HOMING_REQUIRED"
        property string moduleName: "BACK GAUGE 1.2"
        property string machineName: "LS-BEND 1.3"
        property bool backGaugeHomed: false
        property bool machineConnected: true
        property bool moduleConnected: true
        property bool offlineSimulationEnabled: false
        property var machineControl: control
        property string lastAction: ""
        function setConnection(role, connected) { lastAction = role + ":" + connected }
    }

    BendCNC.ToolBarView {
        id: toolbar
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "ToolBarConnectionHomingTests"
        when: windowShown

        function test_eachConnectionRequiresItsOwnHoming() {
            const bg = findChild(toolbar, "device-connection-view module-connection-view")
            const bend = findChild(toolbar, "device-connection-view machine-connection-view")
            verify(bg !== null)
            verify(bend !== null)
            state.backGaugeHomed = false
            control.pressHomed = false
            compare(bg.baseColor.toString(), "#a82011")
            compare(bend.baseColor.toString(), "#a82011")
            state.backGaugeHomed = true
            compare(bg.baseColor.toString(), "#167a00")
            compare(bend.baseColor.toString(), "#a82011")
            control.pressHomed = true
            compare(bend.baseColor.toString(), "#167a00")
            state.backGaugeHomed = false
            compare(bg.baseColor.toString(), "#a82011")
            compare(bend.baseColor.toString(), "#167a00")
        }

        function test_firmwareNameNeverBecomesControllerError() {
            const bg = findChild(toolbar, "device-connection-view module-connection-view")
            const bend = findChild(toolbar, "device-connection-view machine-connection-view")
            state.moduleToolbarState = "READY_WITH_ALARM"
            state.machineToolbarState = "READY_WITH_ALARM"
            state.backGaugeStatus = "DOOR_OPEN"
            state.machineStatus = "TRACKING_ERROR"
            compare(bg.labelText, "BACK GAUGE 1.2")
            compare(bend.labelText, "LS-BEND 1.3")
            compare(bg.baseColor.toString(), "#a82011")
            compare(bend.baseColor.toString(), "#a82011")
            state.moduleToolbarState = "DISCONNECTED"
            state.machineToolbarState = "FAULTED"
            compare(bg.labelText, "CONNECT")
            compare(bend.baseColor.toString(), "#a82011")
            state.moduleToolbarState = "READY"
            state.machineToolbarState = "READY"
        }
    }
}