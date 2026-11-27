import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 864
    height: 638.4

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
    }

    BendCNC.RunView {
        id: view
        anchors.fill: parent
        appState: state
    }

    BendCNC.OnScreenKeyboard {
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "RunTextKeyboardTests"
        when: windowShown

        function init() {
            state.closeOnScreenKeyboardState()
            state.virtualInputMode = "ALWAYS"
            state.runProgramEditing = true
            state.runProgramNameDraft = "TOUCH PROGRAM"
            wait(0)
        }

        function test_programNameOpensFullKeyboardAndCommits() {
            const field = findChild(view, "run-program-name-field")
            const input = findChild(view, "run-program-name-input")
            verify(field && input)

            field.openKeyboard()
            compare(state.onScreenKeyboardKind, "text")
            compare(state.onScreenKeyboardTarget, input)
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("RENAMED BY TOUCH")
            verify(state.commitOnScreenKeyboard())
            compare(state.runProgramNameDraft, "RENAMED BY TOUCH")
        }

        function test_editActionOpensFullKeyboard() {
            state.runProgramEditing = false
            view.beginProgramNameEdit()
            tryCompare(state, "onScreenKeyboardVisible", true)
            compare(state.onScreenKeyboardKind, "text")
            compare(state.onScreenKeyboardTarget, view.programNameField.input)
        }
    }
}