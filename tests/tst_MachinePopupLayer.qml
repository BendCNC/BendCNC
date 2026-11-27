import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 1366
    height: 768

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
        popupVisible: true
        popupKind: "cad-result"
        popupTitle: "BEND PROGRAM READY"
        popupBody: "Program generated and saved safely."
        popupButtonText: "VIEW IN RUN"
        popupResultData: ({
            programName: "Battery Plate N1",
            partName: "Battery Plate N1",
            material: "Steel",
            thickness: "0.0600 in",
            bendCount: 2,
            saved: true,
            storageLabel: "SAVED · backup protected",
            rows: [
                { seq: 1, angle: "90.0", setup: "STD", tooling: "GN88 / 8mm", bg: "0.9494", reference: "EDGE", status: "OK" },
                { seq: 2, angle: "90.0", setup: "STD", tooling: "GN88 / 8mm", bg: "0.9494", reference: "EDGE", status: "OK" }
            ]
        })
    }

    BendCNC.MachinePopupLayer {
        id: layer
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "MachinePopupLayerTests"
        when: windowShown

        function init() {
            state.popupVisible = false
            state.popupKind = "message"
            state.popupAction = ""
            state.popupPrimaryHandler = null
            state.popupCancelHandler = null
            wait(0)
        }

        function test_cadResultPopupIsVisibleAndStructured() {
            state.popupKind = "cad-result"
            state.popupVisible = true
            wait(0)
            wait(50)
            let popup = findChild(layer, "cad-result-popup")
            verify(popup !== null)
            verify(popup.visible)
            compare(popup.width, 950)
            compare(popup.height, 600)
        }

        function test_messageProgressAndConfirmationFamilies() {
            state.showPopup("SAVE PROGRAM", "Program saved successfully.", 1)
            wait(0)
            compare(state.popupKind, "message")
            let message = findChild(layer, "message-popup")
            verify(message && message.visible)
            compare(message.width, 550)
            compare(message.height, 300)

            state.showPopup("UPDATING MACHINE", "Firmware update in progress.", 0.45)
            wait(0)
            compare(state.popupKind, "blur")
            let progress = findChild(layer, "blur-popup")
            verify(progress && progress.visible)
            compare(progress.width, 550)
            compare(progress.height, 300)

            state.showConfirmation("DELETE PROGRAM", "Delete this program?", function() {}, null)
            wait(0)
            compare(state.popupKind, "caution")
            compare(state.popupAction, "confirmation")
            let confirmation = findChild(layer, "caution-popup")
            verify(confirmation && confirmation.visible)
            compare(confirmation.width, 550)
            compare(confirmation.height, 300)
        }

        function test_showPopupClearsStaleCallbacks() {
            state.showConfirmation("DELETE", "Confirm deletion", function() {}, function() {})
            verify(state.popupPrimaryHandler !== null)
            verify(state.popupCancelHandler !== null)
            state.showPopup("COMPLETE", "Operation complete", 1)
            compare(state.popupAction, "")
            compare(state.popupPrimaryHandler, null)
            compare(state.popupCancelHandler, null)
        }

        function test_bleedProcedureShowsIndependentLiveAxisCards() {
            state.bleedState = "PRIMING"
            state.leftSafetyJog = true
            state.rightSafetyJog = false
            state.showBleedProcedure()
            wait(0)

            compare(state.popupKind, "bleed-procedure")
            let popup = findChild(layer, "bleed-procedure-popup")
            let y1 = findChild(layer, "bleed-y1-card")
            let y2 = findChild(layer, "bleed-y2-card")
            verify(popup && popup.visible)
            compare(popup.width, 950)
            compare(popup.height, 600)
            verify(popup.y >= 0)
            verify(popup.y + popup.height <= layer.height)
            verify(y1 && !y1.held)
            verify(y2 && !y2.held)
            verify(!popup.latchSupported)
            let completeButton = findChild(layer, "bleed-complete-button")
            let cancelButton = findChild(layer, "bleed-cancel-button")
            verify(completeButton !== null)
            verify(cancelButton !== null)
            verify(completeButton.mapToItem(popup, 0, completeButton.height).y <= popup.height)
            verify(cancelButton.mapToItem(popup, 0, cancelButton.height).y <= popup.height)
        }

        function test_backGaugeHomeUsesJavaConfirmationContract() {
            state.moduleConnected = true
            state.backGaugeBusy = false
            state.backGaugeLimitX1 = false
            state.backGaugeLimitX2 = false
            state.backGaugeLimitR1 = false
            state.backGaugeLimitR2 = false
            verify(state.requestBackGaugeHome())
            compare(state.popupKind, "caution")
            compare(state.popupAction, "back-gauge-home-confirm")
            compare(state.popupButtonText, "HOME")
            compare(state.popupCancelButtonText, "CLOSE")
        }
    }
}