import QtQuick
import QtTest
import "../qml" as BendCNC
import "../qml/modal-previews/v7" as V7

// Production CREATE BEND (V7) dropdowns must close when their field is
// tapped again; CloseOnPressOutside used to close and the click reopened.
Item {
    width: 1280
    height: 800

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
    }

    V7.V7CreateBendLeftView {
        id: view
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "CreateBendDropdownToggleTests"
        when: windowShown

        function bend(id, name) {
            return { id: id, name: name, desiredBendAngle: 90, materialThickness: 0.06,
                     bendWidth: 4, backGaugeRefEdgeStop: "G55", backGaugeRefEdgeStopEnabled: true }
        }

        function init() {
            state.setProgramsFromStorage([{ id: "p1", name: "DROPDOWN PROGRAM", source: "storage",
                bends: [bend("b1", "BEND ONE"), bend("b2", "BEND TWO")] }], [], [], [], [], null)
            state.selectedProgramIndex = 0
            state.syncActiveProgramState()
            view.cancelEditing()
            view.syncWorkingBends()
            // Not the first entry, so an accidental first-item pick is visible.
            view.selectedBendIndex = 1
            wait(0)
            compare(view.currentBend.backGaugeRefEdgeStop, "G55")
        }

        function verifyToggle(objectName) {
            const field = findChild(view, objectName)
            verify(field, objectName)
            verify(field.visible, objectName + " visible")
            compare(field.menuOpen, false, objectName)
            const selectionBefore = view.selectedBendIndex
            const stopBefore = view.currentBend.backGaugeRefEdgeStop
            mouseClick(field)
            tryCompare(field, "menuOpen", true)
            // Near the left edge: a menu opened over the field would catch this.
            mouseClick(field, 6, field.height / 2)
            tryCompare(field, "menuOpen", false)
            wait(100)
            compare(field.menuOpen, false, objectName + " stays closed")
            compare(view.selectedBendIndex, selectionBefore, objectName + " no item picked")
            compare(view.currentBend.backGaugeRefEdgeStop, stopBefore, objectName + " no stop picked")
            mouseClick(field)
            tryCompare(field, "menuOpen", true)
            keyClick(Qt.Key_Escape)
            tryCompare(field, "menuOpen", false)
        }

        function test_bendSelectorToggles() { verifyToggle("create-bend-selector-field") }
        function test_punchSelectorToggles() { verifyToggle("create-bend-tool-selector-punch") }
        function test_dieSelectorToggles() { verifyToggle("create-bend-tool-selector-die") }
        function test_materialSelectorToggles() { verifyToggle("create-bend-tool-selector-material") }
        function test_stopDatumToggles() { verifyToggle("create-bend-stop-datum-field") }
    }
}
