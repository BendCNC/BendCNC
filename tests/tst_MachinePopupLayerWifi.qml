import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 1366
    height: 768

    QtObject {
        id: hostStub
        readonly property bool offlineValidation: false
        property var wifiNetworks: [{
            connected: false,
            ssid: "SECURE TEST",
            signal: 80,
            security: "WPA2"
        }]
        readonly property string systemSummary: "test"
        readonly property var systemLogs: []
        property string lastError: ""
        property bool operationActive: false
        readonly property real operationProgress: 0
        property int connectCount: 0
        property int refreshCount: 0
        property string connectedSsid: ""
        property string connectedPassword: ""

        function connectWifi(ssid, password) {
            connectCount += 1
            connectedSsid = String(ssid || "")
            connectedPassword = String(password || "")
            return true
        }

        function refreshWifi() {
            refreshCount += 1
        }

        function checkForApplicationUpdates() {
        }
    }

    BendCNC.AppState {
        id: state
        hostSystem: hostStub
    }

    BendCNC.MachinePopupLayer {
        id: popupLayer
        anchors.fill: parent
        appState: state
    }

    BendCNC.OnScreenKeyboard {
        id: keyboard
        anchors.fill: parent
        appState: state
        z: 10000
    }

    TestCase {
        name: "MachinePopupLayerWifiTests"
        when: windowShown

        function init() {
            state.cancelOnScreenKeyboard()
            state.hidePopup()
            state.virtualInputMode = "ALWAYS"
            hostStub.connectCount = 0
            hostStub.refreshCount = 0
            hostStub.connectedSsid = ""
            hostStub.connectedPassword = ""
            hostStub.operationActive = false
            hostStub.wifiNetworks = [{
                connected: false,
                ssid: "SECURE TEST",
                signal: 80,
                security: "WPA2"
            }]
            state.showPopup("WIFI CONNECTION", "CONNECTED NETWORK", 0, "wifi")
            wait(0)
        }

        function test_toolbarOpenDoesNotBlockOnAutomaticRefresh() {
            state.hidePopup()
            state.toolbarAction("wifi")
            compare(hostStub.refreshCount, 0)
            compare(state.popupKind, "wifi")
        }

        function test_secureNetworkOpensTouchKeyboard() {
            const wifiPopup = findChild(popupLayer, "wifi-connection-view")
            verify(wifiPopup)
            const connectButton = findChild(wifiPopup, "wifi-connect-SECURE TEST")
            verify(connectButton)
            mouseClick(connectButton)
            tryVerify(function() { return state.onScreenKeyboardVisible })
            compare(state.onScreenKeyboardKind, "text")
            const field = findChild(wifiPopup, "wifi-password-field")
            verify(field)
            compare(state.onScreenKeyboardTarget, field)
            verify(keyboard.visible)
        }

        function test_secureNetworkOpensRequiredKeyboardWhenVirtualInputDisabled() {
            state.virtualInputMode = "NEVER"
            const wifiPopup = findChild(popupLayer, "wifi-connection-view")
            const connectButton = findChild(wifiPopup, "wifi-connect-SECURE TEST")
            mouseClick(connectButton)
            tryVerify(function() { return state.onScreenKeyboardVisible })
            compare(state.onScreenKeyboardTarget.objectName, "wifi-password-field")
        }

        function test_networkRowOpensSameConnectionFlowAsButton() {
            const wifiPopup = findChild(popupLayer, "wifi-connection-view")
            const listCell = findChild(wifiPopup, "list-cell")
            verify(listCell)
            mouseClick(listCell, 40, listCell.height / 2)
            tryVerify(function() { return state.onScreenKeyboardVisible })
            compare(state.onScreenKeyboardTarget.objectName, "wifi-password-field")
        }

        function test_keyboardCancelClosesPasswordDialog() {
            const wifiPopup = findChild(popupLayer, "wifi-connection-view")
            const connectButton = findChild(wifiPopup, "wifi-connect-SECURE TEST")
            mouseClick(connectButton)
            tryVerify(function() { return state.onScreenKeyboardVisible })
            state.insertOnScreenKeyboardText("discard-me")
            verify(state.cancelOnScreenKeyboard())
            tryVerify(function() { return !state.onScreenKeyboardVisible })
            compare(hostStub.connectCount, 0)
            compare(state.onScreenKeyboardValue, "")
        }

        function test_keyboardCommitConnectsWithoutModalDialog() {
            const wifiPopup = findChild(popupLayer, "wifi-connection-view")
            const connectButton = findChild(wifiPopup, "wifi-connect-SECURE TEST")
            mouseClick(connectButton)
            tryVerify(function() { return state.onScreenKeyboardVisible })
            state.insertOnScreenKeyboardText("test-password")
            verify(state.commitOnScreenKeyboard())
            tryVerify(function() { return !state.onScreenKeyboardVisible })
            compare(hostStub.connectCount, 1)
            compare(hostStub.connectedSsid, "SECURE TEST")
            compare(hostStub.connectedPassword, "test-password")
            compare(state.onScreenKeyboardValue, "")
        }

        function test_activeHostOperationDisablesNetworkSelection() {
            hostStub.operationActive = true
            wait(0)
            const wifiPopup = findChild(popupLayer, "wifi-connection-view")
            const connectButton = findChild(wifiPopup, "wifi-connect-SECURE TEST")
            compare(connectButton.enabled, false)
            const listCell = findChild(wifiPopup, "list-cell")
            mouseClick(listCell, 40, listCell.height / 2)
            compare(state.onScreenKeyboardVisible, false)
            wifiPopup.activateNetwork(hostStub.wifiNetworks[0])
            compare(state.onScreenKeyboardVisible, false)
        }

        function test_nmcliOpenMarkerUsesOpenNetworkFlow() {
            hostStub.wifiNetworks = [{
                connected: false,
                ssid: "OPEN TEST",
                signal: 65,
                security: "--"
            }]
            wait(0)
            const wifiPopup = findChild(popupLayer, "wifi-connection-view")
            const connectButton = findChild(wifiPopup, "wifi-connect-OPEN TEST")
            verify(connectButton)
            mouseClick(connectButton)
            tryCompare(state, "popupAction", "confirmation")
            compare(state.onScreenKeyboardVisible, false)
            state.performPopupPrimaryAction()
            compare(hostStub.connectCount, 1)
            compare(hostStub.connectedSsid, "OPEN TEST")
            compare(hostStub.connectedPassword, "")
        }
    }
}