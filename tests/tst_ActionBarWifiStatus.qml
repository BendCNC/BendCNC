import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 1024
    height: 80

    QtObject {
        id: host
        property var wifiNetworks: []
        function checkForApplicationUpdates() {}
    }

    BendCNC.AppState {
        id: state
        hostSystem: host
    }

    BendCNC.ActionBarView {
        id: actionBar
        width: parent.width
        appState: state
    }

    TestCase {
        name: "ActionBarWifiStatusTests"
        when: windowShown

        function wifiButton() {
            return findChild(actionBar,
                             "button wifi-connection-button WifiConnectionView.fxml wifi-connection-view")
        }

        function init() {
            host.wifiNetworks = []
            wait(0)
        }

        function test_wifiButtonIsRedWhenDisconnected() {
            var button = wifiButton()
            verify(button !== null)
            compare(state.wifiConnected, false)
            compare(button.color, "#a82011")
        }

        function test_wifiButtonIsGreenWhenAnyNetworkConnected() {
            host.wifiNetworks = [
                { ssid: "offline", connected: false },
                { ssid: "press", connected: true }
            ]
            wait(0)

            var button = wifiButton()
            verify(button !== null)
            compare(state.wifiConnected, true)
            compare(button.color, "#59a60c")
        }
    }
}
