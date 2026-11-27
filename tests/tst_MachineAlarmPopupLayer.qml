import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 1366
    height: 768

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
        alarmVisible: true
        alarmTitle: "BACK GAUGE ALARM"
        alarmBody: "Release the active limit switch before continuing."
    }

    BendCNC.MachineAlarmPopupLayer {
        id: layer
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "MachineAlarmPopupLayerTests"
        when: windowShown

        function test_alarmUsesJavaMachineGeometry() {
            const container = findChild(layer, "container")
            const clearButton = findChild(layer, "buttonClear")
            verify(container && clearButton)
            compare(container.width, 850)
            compare(container.height, 500)
            compare(clearButton.width, 190)
            compare(clearButton.height, 58)
            verify(layer.visible)
        }

        function test_clearButtonAcknowledgesAlarm() {
            const clearButton = findChild(layer, "buttonClear")
            mouseClick(clearButton)
            verify(!state.alarmVisible)
        }
    }
}